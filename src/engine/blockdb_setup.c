/* Vortex engine - first-launch block database discovery and generation.
 *
 * The executable owns this path: it scans local Minecraft installations,
 * invokes their Java data generator, validates the reports and atomically
 * writes VBLKDB01. No scripting runtime or source-tree helper is required.
 */
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  include <direct.h>
#else
#  include <dirent.h>
#  include <errno.h>
#  include <sys/stat.h>
#  include <sys/types.h>
#  include <sys/wait.h>
#  include <unistd.h>
#endif

#define VT_SETUP_PATH 4096
#define VT_SETUP_BLOCKS 4096
#define VT_SETUP_STATES (1 << 20)
#define VT_SETUP_TARGET_PROTOCOL 777
#define VT_SETUP_TARGET_VERSION "26.3"
/* One block state can hold this many properties, each as "key=value" text.
 * No vanilla state has more than a handful, so a fixed row is cheaper than a
 * growable one for the tens of thousands of states parsed per run. */
#define VT_SETUP_PROPERTIES 16
#define VT_SETUP_PROPERTY_TEXT 160

typedef struct {
    char* data;
    size_t length;
    size_t capacity;
} VtText;

typedef struct {
    const char* data;
    size_t length;
    size_t position;
} VtJson;

typedef struct {
    const char* name;
    size_t name_length;
    uint32_t first;
    uint32_t count;
    uint32_t protocol;
    uint32_t flags;
} VtBlockRecord;

typedef struct {
    VtBlockRecord* records;
    size_t count;
    unsigned char* states;
    /* The Anvil name table: "B <state id> <name>[props]" rows from blocks.json
     * followed by "I <protocol id> <name>" rows from registries.json. */
    VtText registry;
} VtReport;

typedef struct {
    char jar[VT_SETUP_PATH];
    char json[VT_SETUP_PATH];
    char libraries[VT_SETUP_PATH];
    char protocol[32];
    int protocol_number;
} VtInstallation;

static int vt_text_reserve(VtText* text, size_t extra) {
    size_t needed;
    char* grown;
    if (extra > SIZE_MAX - text->length - 1) return 0;
    needed = text->length + extra + 1;
    if (needed <= text->capacity) return 1;
    if (text->capacity == 0) text->capacity = 256;
    while (text->capacity < needed) {
        if (text->capacity > SIZE_MAX / 2) return 0;
        text->capacity *= 2;
    }
    grown = (char*)realloc(text->data, text->capacity);
    if (grown == NULL) return 0;
    text->data = grown;
    return 1;
}

static int vt_text_add(VtText* text, const char* value, size_t length) {
    if (!vt_text_reserve(text, length)) return 0;
    memcpy(text->data + text->length, value, length);
    text->length += length;
    text->data[text->length] = 0;
    return 1;
}

static int vt_text_str(VtText* text, const char* value) {
    return vt_text_add(text, value, strlen(value));
}

static void vt_text_clear(VtText* text) {
    text->length = 0;
    if (text->data != NULL) text->data[0] = 0;
}

static void vt_text_free(VtText* text) {
    free(text->data);
    text->data = NULL;
    text->length = 0;
    text->capacity = 0;
}

static int vt_read_text(const char* path, VtText* out) {
    FILE* file = fopen(path, "rb");
    char buffer[16384];
    size_t count;
    if (file == NULL) return 0;
    while ((count = fread(buffer, 1, sizeof(buffer), file)) != 0) {
        if (!vt_text_add(out, buffer, count)) {
            fclose(file);
            return 0;
        }
    }
    if (ferror(file)) {
        fclose(file);
        return 0;
    }
    fclose(file);
    if (out->data == NULL && !vt_text_reserve(out, 0)) return 0;
    return 1;
}

static int vt_path_join(char* out, size_t capacity, const char* left, const char* right) {
    int count;
#ifdef _WIN32
    count = snprintf(out, capacity, "%s\\%s", left, right);
#else
    count = snprintf(out, capacity, "%s/%s", left, right);
#endif
    return count >= 0 && (size_t)count < capacity;
}

static int vt_file_exists(const char* path) {
#ifdef _WIN32
    DWORD attributes = GetFileAttributesA(path);
    return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
#else
    struct stat info;
    return stat(path, &info) == 0 && S_ISREG(info.st_mode);
#endif
}

static int vt_directory_exists(const char* path) {
#ifdef _WIN32
    DWORD attributes = GetFileAttributesA(path);
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY);
#else
    struct stat info;
    return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
#endif
}

static int vt_make_directory(const char* path) {
    char copy[VT_SETUP_PATH];
    size_t i;
    if (strlen(path) >= sizeof(copy)) return 0;
    strcpy(copy, path);
    if (vt_directory_exists(copy)) return 1;
    for (i = 1; copy[i] != 0; i++) {
        if (copy[i] != '/' && copy[i] != '\\') continue;
        copy[i] = 0;
        if (copy[0] != 0 && !vt_directory_exists(copy)) {
#ifdef _WIN32
            if (_mkdir(copy) != 0 && !vt_directory_exists(copy)) return 0;
#else
            if (mkdir(copy, 0700) != 0 && errno != EEXIST) return 0;
#endif
        }
        copy[i] =
#ifdef _WIN32
            '\\';
#else
            '/';
#endif
    }
#ifdef _WIN32
    return _mkdir(copy) == 0 || vt_directory_exists(copy);
#else
    return mkdir(copy, 0700) == 0 || vt_directory_exists(copy);
#endif
}

static int vt_parent_directory(const char* path, char* out, size_t capacity) {
    const char* slash = strrchr(path, '/');
    const char* backslash = strrchr(path, '\\');
    size_t length;
    if (backslash != NULL && (slash == NULL || backslash > slash)) slash = backslash;
    if (slash == NULL) {
        if (capacity < 2) return 0;
        strcpy(out, ".");
        return 1;
    }
    length = (size_t)(slash - path);
    if (length == 0) length = 1;
    if (length >= capacity) return 0;
    memcpy(out, path, length);
    out[length] = 0;
    return 1;
}

static void vt_json_space(VtJson* json) {
    while (json->position < json->length) {
        char c = json->data[json->position];
        if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
        json->position++;
    }
}

static int vt_json_hex(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int vt_json_string(VtJson* json, VtText* out) {
    vt_json_space(json);
    if (json->position >= json->length || json->data[json->position++] != '"') return 0;
    if (out != NULL) vt_text_clear(out);
    while (json->position < json->length) {
        unsigned char c = (unsigned char)json->data[json->position++];
        char replacement[4];
        size_t replacement_length = 1;
        if (c == '"') return 1;
        if (c < 0x20) return 0;
        replacement[0] = (char)c;
        if (c == '\\') {
            unsigned int code;
            int digit;
            if (json->position >= json->length) return 0;
            c = (unsigned char)json->data[json->position++];
            if (c == '"' || c == '\\' || c == '/') replacement[0] = (char)c;
            else if (c == 'b') replacement[0] = '\b';
            else if (c == 'f') replacement[0] = '\f';
            else if (c == 'n') replacement[0] = '\n';
            else if (c == 'r') replacement[0] = '\r';
            else if (c == 't') replacement[0] = '\t';
            else if (c == 'u') {
                code = 0;
                for (digit = 0; digit < 4; digit++) {
                    int value;
                    if (json->position >= json->length) return 0;
                    value = vt_json_hex(json->data[json->position++]);
                    if (value < 0) return 0;
                    code = (code << 4) | (unsigned int)value;
                }
                if (code >= 0xD800 && code <= 0xDBFF) {
                    unsigned int low = 0;
                    if (json->position + 6 > json->length || json->data[json->position++] != '\\' ||
                        json->data[json->position++] != 'u') return 0;
                    for (digit = 0; digit < 4; digit++) {
                        int value = vt_json_hex(json->data[json->position++]);
                        if (value < 0) return 0;
                        low = (low << 4) | (unsigned int)value;
                    }
                    if (low < 0xDC00 || low > 0xDFFF) return 0;
                    code = 0x10000 + ((code - 0xD800) << 10) + low - 0xDC00;
                } else if (code >= 0xDC00 && code <= 0xDFFF) return 0;
                if (code < 0x80) replacement[0] = (char)code;
                else if (code < 0x800) {
                    replacement[0] = (char)(0xC0 | (code >> 6));
                    replacement[1] = (char)(0x80 | (code & 0x3F));
                    replacement_length = 2;
                } else if (code < 0x10000) {
                    replacement[0] = (char)(0xE0 | (code >> 12));
                    replacement[1] = (char)(0x80 | ((code >> 6) & 0x3F));
                    replacement[2] = (char)(0x80 | (code & 0x3F));
                    replacement_length = 3;
                } else {
                    replacement[0] = (char)(0xF0 | (code >> 18));
                    replacement[1] = (char)(0x80 | ((code >> 12) & 0x3F));
                    replacement[2] = (char)(0x80 | ((code >> 6) & 0x3F));
                    replacement[3] = (char)(0x80 | (code & 0x3F));
                    replacement_length = 4;
                }
            } else return 0;
        }
        if (out != NULL && !vt_text_add(out, replacement, replacement_length)) return 0;
    }
    return 0;
}

static int vt_json_uint(VtJson* json, uint32_t* out) {
    uint64_t value = 0;
    vt_json_space(json);
    if (json->position >= json->length || json->data[json->position] < '0' ||
        json->data[json->position] > '9') return 0;
    while (json->position < json->length) {
        char c = json->data[json->position];
        if (c < '0' || c > '9') break;
        value = value * 10 + (unsigned int)(c - '0');
        if (value > UINT32_MAX) return 0;
        json->position++;
    }
    *out = (uint32_t)value;
    return 1;
}

static int vt_json_expect_colon(VtJson* json);

static int vt_json_skip(VtJson* json, unsigned int depth) {
    char close;
    vt_json_space(json);
    if (depth > 128 || json->position >= json->length) return 0;
    close = json->data[json->position];
    if (close == '"') return vt_json_string(json, NULL);
    if (close != '{' && close != '[') {
        while (json->position < json->length) {
            char c = json->data[json->position];
            if (c == ',' || c == '}' || c == ']' || c == ' ' || c == '\t' || c == '\r' || c == '\n') break;
            json->position++;
        }
        return 1;
    }
    json->position++;
    close = close == '{' ? '}' : ']';
    vt_json_space(json);
    if (json->position < json->length && json->data[json->position] == close) {
        json->position++;
        return 1;
    }
    while (json->position < json->length) {
        if (close == '}' && (!vt_json_string(json, NULL) || !vt_json_expect_colon(json))) return 0;
        if (!vt_json_skip(json, depth + 1)) return 0;
        vt_json_space(json);
        if (json->position >= json->length) return 0;
        if (json->data[json->position] == close) {
            json->position++;
            return 1;
        }
        if (json->data[json->position++] != ',') return 0;
    }
    return 0;
}

static int vt_json_expect_colon(VtJson* json) {
    vt_json_space(json);
    if (json->position >= json->length || json->data[json->position++] != ':') return 0;
    return 1;
}

static int vt_json_open(VtJson* json, char kind) {
    vt_json_space(json);
    if (json->position >= json->length || json->data[json->position++] != kind) return 0;
    return 1;
}

static int vt_json_next(VtJson* json, char close, int* first) {
    vt_json_space(json);
    if (json->position >= json->length) return 0;
    if (json->data[json->position] == close) {
        json->position++;
        return 0;
    }
    if (!*first) {
        if (json->data[json->position++] != ',') return -1;
    }
    *first = 0;
    return 1;
}

static int vt_name_is(const char* name, size_t length, const char* wanted) {
    return strlen(wanted) == length && memcmp(name, wanted, length) == 0;
}

static int vt_name_suffix(const char* name, size_t length, const char* suffix) {
    size_t wanted = strlen(suffix);
    return wanted <= length && memcmp(name + length - wanted, suffix, wanted) == 0;
}

static uint32_t vt_classify(const char* name, size_t length) {
    static const char* const translucent[] = {
        "glass", "tinted_glass", "ice", "packed_ice", "blue_ice", "frosted_ice",
        "slime_block", "honey_block", "water", "lava", "beacon", "sea_lantern",
        "copper_grate", "exposed_copper_grate", "weathered_copper_grate", "oxidized_copper_grate",
        "waxed_copper_grate", "waxed_exposed_copper_grate", "waxed_weathered_copper_grate",
        "waxed_oxidized_copper_grate"
    };
    static const char* const crosses[] = {
        "short_grass", "tall_grass", "fern", "large_fern", "dead_bush", "short_dry_grass",
        "tall_dry_grass", "firefly_bush", "bush", "dandelion", "poppy", "blue_orchid",
        "allium", "azure_bluet", "red_tulip", "orange_tulip", "white_tulip", "pink_tulip",
        "oxeye_daisy", "cornflower", "lily_of_the_valley", "wither_rose", "torchflower",
        "sunflower", "lilac", "rose_bush", "peony", "wheat", "carrots", "potatoes",
        "beetroots", "torchflower_crop", "pitcher_crop", "melon_stem", "pumpkin_stem",
        "attached_melon_stem", "attached_pumpkin_stem", "sweet_berry_bush", "nether_wart",
        "crimson_roots", "warped_roots", "nether_sprouts", "seagrass", "tall_seagrass",
        "kelp", "kelp_plant", "sugar_cane", "bamboo", "bamboo_sapling", "cocoa", "vine",
        "cave_vines", "cave_vines_plant", "twisting_vines", "weeping_vines", "hanging_roots",
        "glow_lichen", "sculk_vein", "pink_petals", "wildflowers", "leaf_litter", "torch",
        "wall_torch", "soul_torch", "soul_wall_torch", "redstone_torch", "redstone_wall_torch",
        "copper_torch", "copper_wall_torch", "cobweb", "fire", "soul_fire"
    };
    static const char* const cross_suffixes[] = {"_sapling", "_coral", "_coral_fan", "_coral_wall_fan"};
    static const char* const attached_suffixes[] = {
        "_slab", "_stairs", "_fence", "_fence_gate", "_wall", "_door", "_trapdoor", "_button",
        "_pressure_plate", "_carpet", "_pane", "_bars", "_chain", "_lantern", "_sign", "_banner",
        "_bed", "_candle", "_candles", "_cake", "_plant", "_flower", "_tulip", "_orchid", "_bluet",
        "_daisy", "_poppy", "_rose", "_lily", "_grass", "_fern", "_bush", "_vine", "_stem", "_rail",
        "_repeater", "_comparator", "_lever", "_wire", "_hook", "_tripwire", "_scaffolding",
        "_campfire", "_anvil", "_cauldron", "_composter", "_hopper", "_lectern", "_brewing_stand",
        "_conduit", "_chest", "_shulker_box", "_skull", "_head", "_egg", "_pickle", "_frogspawn",
        "_portal", "_fire", "_bud", "_cluster", "_spawner", "_piston_head", "_dragon_egg",
        "_amethyst", "_wall_hanging_sign", "_hanging_sign", "_cocoa"
    };
    static const char* const attached[] = {
        "moving_piston", "flower_pot", "decorated_pot", "composter", "hopper", "lectern",
        "brewing_stand", "beacon", "conduit", "chest", "trapped_chest", "ender_chest", "barrel",
        "scaffolding", "campfire", "soul_campfire", "anvil", "chipped_anvil", "damaged_anvil",
        "cauldron", "water_cauldron", "lava_cauldron", "powder_snow_cauldron", "enchanting_table",
        "stonecutter", "grindstone", "smithing_table", "cartography_table", "fletching_table",
        "loom", "bell", "lantern", "soul_lantern", "twisted_vines", "nether_portal", "end_portal",
        "end_gateway", "piston_head"
    };
    size_t i;
    if (vt_name_is(name, length, "air") || vt_name_is(name, length, "cave_air") ||
        vt_name_is(name, length, "void_air")) return 1;
    if (vt_name_is(name, length, "water") || vt_name_is(name, length, "lava")) return 22;
    if (vt_name_is(name, length, "mangrove_roots") || vt_name_suffix(name, length, "_leaves")) return 36;
    for (i = 0; i < sizeof(crosses) / sizeof(crosses[0]); i++)
        if (vt_name_is(name, length, crosses[i])) return 64;
    for (i = 0; i < sizeof(cross_suffixes) / sizeof(cross_suffixes[0]); i++)
        if (vt_name_suffix(name, length, cross_suffixes[i])) return 64;
    for (i = 0; i < sizeof(translucent) / sizeof(translucent[0]); i++)
        if (vt_name_is(name, length, translucent[i])) return 20;
    for (i = 0; i < sizeof(attached) / sizeof(attached[0]); i++)
        if (vt_name_is(name, length, attached[i])) return 0;
    for (i = 0; i < sizeof(attached_suffixes) / sizeof(attached_suffixes[0]); i++)
        if (vt_name_suffix(name, length, attached_suffixes[i])) return 0;
    return 12;
}

static char* vt_dup_n(const char* text, size_t length) {
    char* out = (char*)malloc(length + 1);
    if (out == NULL) return NULL;
    memcpy(out, text, length);
    out[length] = 0;
    return out;
}

/* The reports key blocks by their full name (minecraft:stone); the database
 * stores and classifies the bare name, matching tools/gen_blockdb.py. */
static void vt_bare_name(const char* name, size_t length, const char** bare, size_t* bare_length) {
    const char* colon = (const char*)memchr(name, ':', length);
    if (colon != NULL) {
        *bare = colon + 1;
        *bare_length = length - (size_t)(colon + 1 - name);
    } else {
        *bare = name;
        *bare_length = length;
    }
}

/* One property value: the quoted strings the report uses, plus bare numbers or
 * words, so a hand-written report still yields a table. Objects and arrays
 * cannot be property values and are rejected. */
static int vt_json_value_text(VtJson* json, VtText* out) {
    vt_json_space(json);
    if (json->position >= json->length) return 0;
    if (json->data[json->position] == '"') return vt_json_string(json, out);
    if (json->data[json->position] == '{' || json->data[json->position] == '[') return 0;
    vt_text_clear(out);
    while (json->position < json->length) {
        char c = json->data[json->position];
        if (c == ',' || c == '}' || c == ']' || c == ' ' || c == '\t' ||
            c == '\r' || c == '\n') break;
        if (!vt_text_add(out, &c, 1)) return 0;
        json->position++;
    }
    return out->length > 0;
}

static int vt_property_compare(const void* left, const void* right) {
    return strcmp((const char*)left, (const char*)right);
}

static int vt_property_add(char (*rows)[VT_SETUP_PROPERTY_TEXT], size_t* count,
                           const VtText* name, const VtText* value) {
    if (*count >= VT_SETUP_PROPERTIES) return 0;
    if (name->length == 0 || name->length + value->length + 2 >= VT_SETUP_PROPERTY_TEXT) return 0;
    memcpy(rows[*count], name->data, name->length);
    rows[*count][name->length] = '=';
    memcpy(rows[*count] + name->length + 1, value->data, value->length);
    rows[*count][name->length + 1 + value->length] = 0;
    (*count)++;
    return 1;
}

/* Appends `B <state id> <namespaced name>[key=value,...]`. The properties are
 * sorted because the Anvil reader builds the same text from a saved palette
 * compound, and the two have to match byte for byte. */
static int vt_registry_state_row(VtText* registry, uint32_t id, const VtText* name,
                                 char (*rows)[VT_SETUP_PROPERTY_TEXT], size_t count) {
    char head[32];
    size_t i;
    if (snprintf(head, sizeof(head), "B %u ", id) < 0) return 0;
    if (!vt_text_str(registry, head) || !vt_text_add(registry, name->data, name->length)) return 0;
    if (count > 0) {
        qsort(rows, count, VT_SETUP_PROPERTY_TEXT, vt_property_compare);
        if (!vt_text_str(registry, "[")) return 0;
        for (i = 0; i < count; i++) {
            if (i > 0 && !vt_text_str(registry, ",")) return 0;
            if (!vt_text_str(registry, rows[i])) return 0;
        }
        if (!vt_text_str(registry, "]")) return 0;
    }
    return vt_text_str(registry, "\n");
}

static int vt_parse_blocks(const VtText* text, VtReport* report) {
    VtJson json = {text->data, text->length, 0};
    VtText key = {0};
    VtText full = {0};
    VtText value = {0};
    int first = 1;
    int result = 0;
    if (!vt_json_open(&json, '{')) goto done;
    while (1) {
        VtJson entry;
        VtBlockRecord* record;
        const char* bare;
        size_t bare_length;
        uint32_t minimum = UINT32_MAX;
        uint32_t maximum = 0;
        uint32_t count = 0;
        int next = vt_json_next(&json, '}', &first);
        if (next < 0) goto done;
        if (next == 0) break;
        if (!vt_json_string(&json, &key) || !vt_json_expect_colon(&json)) goto done;
        if (report->count >= VT_SETUP_BLOCKS) goto done;
        /* The inner passes reuse `key`, so the namespaced name the Anvil table
         * needs is copied aside before anything else is read. */
        vt_text_clear(&full);
        if (!vt_text_add(&full, key.data, key.length)) goto done;
        record = &report->records[report->count];
        vt_bare_name(key.data, key.length, &bare, &bare_length);
        record->name = vt_dup_n(bare, bare_length);
        if (record->name == NULL) goto done;
        record->name_length = bare_length;
        record->first = 0;
        record->count = 0;
        record->protocol = UINT32_MAX;
        record->flags = vt_classify(bare, bare_length);
        entry = json;
        if (!vt_json_open(&entry, '{')) goto done;
        first = 1;
        while (1) {
            int field = vt_json_next(&entry, '}', &first);
            if (field < 0) goto done;
            if (field == 0) break;
            if (!vt_json_string(&entry, &key) || !vt_json_expect_colon(&entry)) goto done;
            if (!vt_name_is(key.data, key.length, "states")) {
                if (!vt_json_skip(&entry, 0)) goto done;
                continue;
            }
            if (!vt_json_open(&entry, '[')) goto done;
            first = 1;
            while (1) {
                VtJson state;
                char rows[VT_SETUP_PROPERTIES][VT_SETUP_PROPERTY_TEXT];
                size_t property_count = 0;
                uint32_t id = UINT32_MAX;
                int element = vt_json_next(&entry, ']', &first);
                if (element < 0) goto done;
                if (element == 0) break;
                state = entry;
                if (!vt_json_open(&state, '{')) goto done;
                first = 1;
                while (1) {
                    int item = vt_json_next(&state, '}', &first);
                    if (item < 0) goto done;
                    if (item == 0) break;
                    if (!vt_json_string(&state, &key) || !vt_json_expect_colon(&state)) goto done;
                    if (vt_name_is(key.data, key.length, "id")) {
                        if (!vt_json_uint(&state, &id)) goto done;
                    } else if (vt_json_value_text(&state, &value)) {
                        if (!vt_property_add(rows, &property_count, &key, &value)) goto done;
                    } else if (!vt_json_skip(&state, 0)) goto done;
                }
                if (id == UINT32_MAX || id >= VT_SETUP_STATES || report->states[id] != 0) goto done;
                report->states[id] = 1;
                if (id < minimum) minimum = id;
                if (id > maximum) maximum = id;
                count++;
                if (!vt_registry_state_row(&report->registry, id, &full,
                                          rows, property_count)) goto done;
                if (!vt_json_skip(&entry, 0)) goto done;
            }
        }
        if (count == 0 || count > UINT16_MAX || maximum - minimum + 1 != count) goto done;
        record->first = minimum;
        record->count = count;
        report->count++;
        if (!vt_json_skip(&json, 0)) goto done;
    }
    result = 1;
done:
    vt_text_free(&key);
    vt_text_free(&full);
    vt_text_free(&value);
    return result;
}

/* One `I <protocol id> <name>` row. */
static int vt_registry_biome_row(VtText* registry, uint32_t id, const VtText* name) {
    char head[32];
    if (snprintf(head, sizeof(head), "I %u ", id) < 0) return 0;
    if (!vt_text_str(registry, head) || !vt_text_add(registry, name->data, name->length)) return 0;
    return vt_text_str(registry, "\n");
}

/* The `minecraft:worldgen/biome` registry holds the ids a saved biome palette
 * uses, so every entry becomes one `I <protocol id> <name>` row. Like the
 * block protocol pass, the entry object is scanned with a cursor copy and the
 * real one then skips it, which keeps the two loops independent. */
static int vt_registry_biome_rows(VtJson* json, VtReport* report) {
    VtText key = {0};
    VtText name = {0};
    int first = 1;
    int result = 0;
    if (!vt_json_open(json, '{')) return 0;
    first = 1;
    while (1) {
        int field = vt_json_next(json, '}', &first);
        if (field < 0) goto done;
        if (field == 0) break;
        if (!vt_json_string(json, &key) || !vt_json_expect_colon(json)) goto done;
        if (!vt_name_is(key.data, key.length, "entries")) {
            if (!vt_json_skip(json, 0)) goto done;
            continue;
        }
        if (!vt_json_open(json, '{')) goto done;
        first = 1;
        while (1) {
            VtJson entry;
            uint32_t protocol = UINT32_MAX;
            int item = vt_json_next(json, '}', &first);
            if (item < 0) goto done;
            if (item == 0) break;
            if (!vt_json_string(json, &key) || !vt_json_expect_colon(json)) goto done;
            if (!vt_text_add(&name, key.data, key.length)) goto done;
            entry = *json;
            if (!vt_json_open(&entry, '{')) goto done;
            first = 1;
            while (1) {
                int value = vt_json_next(&entry, '}', &first);
                if (value < 0) goto done;
                if (value == 0) break;
                if (!vt_json_string(&entry, &key) || !vt_json_expect_colon(&entry)) goto done;
                if (vt_name_is(key.data, key.length, "protocol_id")) {
                    if (!vt_json_uint(&entry, &protocol)) goto done;
                } else if (!vt_json_skip(&entry, 0)) goto done;
            }
            if (protocol == UINT32_MAX) goto done;
            if (!vt_json_skip(json, 0)) goto done;
            if (!vt_registry_biome_row(&report->registry, protocol, &name)) goto done;
            vt_text_clear(&name);
        }
    }
    result = 1;
done:
    vt_text_free(&key);
    vt_text_free(&name);
    return result;
}

static int vt_parse_registry(const VtText* text, VtReport* report) {
    VtJson json = {text->data, text->length, 0};
    VtText key = {0};
    VtText block = {0};
    int first = 1;
    int result = 0;
    if (!vt_json_open(&json, '{')) goto done;
    while (1) {
        int next = vt_json_next(&json, '}', &first);
        if (next < 0) goto done;
        if (next == 0) break;
        if (!vt_json_string(&json, &key) || !vt_json_expect_colon(&json)) goto done;
        if (vt_name_is(key.data, key.length, "minecraft:worldgen/biome")) {
            if (!vt_registry_biome_rows(&json, report)) goto done;
            continue;
        }
        if (!vt_name_is(key.data, key.length, "minecraft:block")) {
            if (!vt_json_skip(&json, 0)) goto done;
            continue;
        }
        if (!vt_json_open(&json, '{')) goto done;
        first = 1;
        while (1) {
            int field = vt_json_next(&json, '}', &first);
            if (field < 0) goto done;
            if (field == 0) break;
            if (!vt_json_string(&json, &key) || !vt_json_expect_colon(&json)) goto done;
            if (!vt_name_is(key.data, key.length, "entries")) {
                if (!vt_json_skip(&json, 0)) goto done;
                continue;
            }
            if (!vt_json_open(&json, '{')) goto done;
            first = 1;
            while (1) {
                VtJson entry;
                size_t i;
                const char* bare;
                size_t bare_length;
                uint32_t protocol = UINT32_MAX;
                int item = vt_json_next(&json, '}', &first);
                if (item < 0) goto done;
                if (item == 0) break;
                if (!vt_json_string(&json, &key) || !vt_json_expect_colon(&json)) goto done;
                vt_bare_name(key.data, key.length, &bare, &bare_length);
                vt_text_clear(&block);
                if (!vt_text_add(&block, bare, bare_length)) goto done;
                entry = json;
                if (!vt_json_open(&entry, '{')) goto done;
                first = 1;
                while (1) {
                    int value = vt_json_next(&entry, '}', &first);
                    if (value < 0) goto done;
                    if (value == 0) break;
                    if (!vt_json_string(&entry, &key) || !vt_json_expect_colon(&entry)) goto done;
                    if (vt_name_is(key.data, key.length, "protocol_id")) {
                        if (!vt_json_uint(&entry, &protocol)) goto done;
                    } else if (!vt_json_skip(&entry, 0)) goto done;
                }
                for (i = 0; i < report->count; i++) {
                    if (report->records[i].name_length == block.length &&
                        memcmp(report->records[i].name, block.data, block.length) == 0) {
                        report->records[i].protocol = protocol;
                        break;
                    }
                }
                if (!vt_json_skip(&json, 0)) goto done;
            }
        }
    }
    result = 1;
done:
    vt_text_free(&key);
    vt_text_free(&block);
    return result;
}

static int vt_record_compare(const void* left, const void* right) {
    const VtBlockRecord* a = (const VtBlockRecord*)left;
    const VtBlockRecord* b = (const VtBlockRecord*)right;
    if (a->first < b->first) return -1;
    if (a->first > b->first) return 1;
    return 0;
}

static void vt_u32(unsigned char* out, uint32_t value) {
    out[0] = (unsigned char)value;
    out[1] = (unsigned char)(value >> 8);
    out[2] = (unsigned char)(value >> 16);
    out[3] = (unsigned char)(value >> 24);
}

static void vt_u16(unsigned char* out, uint16_t value) {
    out[0] = (unsigned char)value;
    out[1] = (unsigned char)(value >> 8);
}

static int vt_write_reports(VtReport* report, const char* destination) {
    char temporary[VT_SETUP_PATH];
    char directory[VT_SETUP_PATH];
    unsigned char* names;
    size_t name_bytes = 0;
    size_t i;
    uint32_t expected = 0;
    FILE* file;
    int result = 0;
    qsort(report->records, report->count, sizeof(report->records[0]), vt_record_compare);
    for (i = 0; i < report->count; i++) {
        VtBlockRecord* record = &report->records[i];
        if (record->first != expected || record->protocol == UINT32_MAX || record->name_length > UINT16_MAX) goto done;
        expected += record->count;
        name_bytes += record->name_length;
    }
    if (expected > VT_SETUP_STATES || name_bytes > UINT32_MAX) goto done;
    names = (unsigned char*)malloc(name_bytes + 1);
    if (names == NULL) goto done;
    if (!vt_parent_directory(destination, directory, sizeof(directory)) || !vt_make_directory(directory) ||
        snprintf(temporary, sizeof(temporary), "%s.tmp", destination) < 0 ||
        strlen(destination) + 5 >= sizeof(temporary)) {
        free(names);
        goto done;
    }
    file = fopen(temporary, "wb");
    if (file == NULL) {
        free(names);
        goto done;
    }
    if (fwrite("VBLKDB01", 1, 8, file) != 8) goto file_failed;
    {
        unsigned char header[12];
        vt_u32(header, expected);
        vt_u32(header + 4, (uint32_t)report->count);
        vt_u32(header + 8, (uint32_t)name_bytes);
        if (fwrite(header, 1, sizeof(header), file) != sizeof(header)) goto file_failed;
    }
    name_bytes = 0;
    for (i = 0; i < report->count; i++) {
        VtBlockRecord* record = &report->records[i];
        unsigned char row[20];
        vt_u32(row, record->protocol);
        vt_u32(row + 4, record->first);
        vt_u16(row + 8, (uint16_t)record->count);
        vt_u16(row + 10, (uint16_t)record->flags);
        vt_u32(row + 12, (uint32_t)name_bytes);
        vt_u16(row + 16, (uint16_t)record->name_length);
        vt_u16(row + 18, 0);
        if (fwrite(row, 1, sizeof(row), file) != sizeof(row)) goto file_failed;
        memcpy(names + name_bytes, record->name, record->name_length);
        name_bytes += record->name_length;
    }
    if (fwrite(names, 1, name_bytes, file) != name_bytes) goto file_failed;
    if (fclose(file) != 0) {
        file = NULL;
        goto file_failed;
    }
    file = NULL;
#ifdef _WIN32
    if (MoveFileExA(temporary, destination, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) == 0) goto file_failed;
#else
    if (rename(temporary, destination) != 0) goto file_failed;
#endif
    result = 1;
    free(names);
    goto done;
file_failed:
    if (file != NULL) fclose(file);
    free(names);
    remove(temporary);
done:
    return result;
}

/* generated/registry.txt sits beside the database. The Anvil codec reads it to
 * turn the numeric palettes the engine holds into the named form a saved chunk
 * has to use, so without it a written world is not readable by the game. */
static int vt_write_registry(const VtReport* report, const char* destination) {
    static const char header[] =
        "# Anvil palette names: `B <block state id> <name>[key=value,...]` and\n"
        "# `I <biome id> <name>`, taken from the game's own reports.\n";
    char directory[VT_SETUP_PATH];
    char path[VT_SETUP_PATH];
    char temporary[VT_SETUP_PATH];
    FILE* file;
    if (report->registry.length == 0) return 0;
    if (!vt_parent_directory(destination, directory, sizeof(directory)) ||
        !vt_path_join(path, sizeof(path), directory, "registry.txt") ||
        strlen(path) + 5 >= sizeof(temporary) ||
        snprintf(temporary, sizeof(temporary), "%s.tmp", path) < 0) return 0;
    if (!vt_make_directory(directory)) return 0;
    file = fopen(temporary, "wb");
    if (file == NULL) return 0;
    if (fwrite(header, 1, sizeof(header) - 1, file) != sizeof(header) - 1 ||
        fwrite(report->registry.data, 1, report->registry.length, file) != report->registry.length) {
        fclose(file);
        remove(temporary);
        return 0;
    }
    if (fclose(file) != 0) {
        remove(temporary);
        return 0;
    }
#ifdef _WIN32
    if (MoveFileExA(temporary, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) == 0) {
        remove(temporary);
        return 0;
    }
#else
    if (rename(temporary, path) != 0) {
        remove(temporary);
        return 0;
    }
#endif
    return 1;
}

int vt_blockdb_build_reports(const char* blocks_path, const char* registries_path, const char* destination) {
    VtText blocks = {0};
    VtText registries = {0};
    VtReport report = {0};
    size_t i;
    int result = 0;
    report.records = (VtBlockRecord*)calloc(VT_SETUP_BLOCKS, sizeof(report.records[0]));
    report.states = (unsigned char*)calloc(VT_SETUP_STATES, 1);
    if (report.records == NULL || report.states == NULL) goto done;
    if (!vt_read_text(blocks_path, &blocks) || !vt_read_text(registries_path, &registries) ||
        !vt_parse_blocks(&blocks, &report) || !vt_parse_registry(&registries, &report) ||
        !vt_write_reports(&report, destination) || !vt_write_registry(&report, destination)) goto done;
    result = 1;
done:
    for (i = 0; i < report.count; i++) free((void*)report.records[i].name);
    free(report.records);
    free(report.states);
    vt_text_free(&report.registry);
    vt_text_free(&blocks);
    vt_text_free(&registries);
    return result;
}

static int vt_json_find_uint(const VtText* text, const char* field, uint32_t* out) {
    VtJson json = {text->data, text->length, 0};
    VtText key = {0};
    int first = 1;
    int result = 0;
    if (!vt_json_open(&json, '{')) goto done;
    while (1) {
        int next = vt_json_next(&json, '}', &first);
        if (next < 0) goto done;
        if (next == 0) break;
        if (!vt_json_string(&json, &key) || !vt_json_expect_colon(&json)) goto done;
        if (vt_name_is(key.data, key.length, field)) {
            result = vt_json_uint(&json, out);
            goto done;
        }
        if (!vt_json_skip(&json, 0)) goto done;
    }
done:
    vt_text_free(&key);
    return result;
}

/* --- ZIP entry extraction -------------------------------------------------- */
/* The jar's version.json is deflated, so discovery inflates just that entry.
 * Sizes come from the central directory (authoritative even when a local
 * header carries a data descriptor), and only the needed ranges are read so
 * scanning many installations never loads a whole multi-megabyte jar. */

static uint16_t vt_zip_u16(const unsigned char* p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t vt_zip_u32(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static unsigned char* vt_read_range(FILE* file, long offset, size_t count) {
    unsigned char* buffer = (unsigned char*)malloc(count != 0 ? count : 1);
    if (buffer == NULL) return NULL;
    if (fseek(file, offset, SEEK_SET) != 0 || fread(buffer, 1, count, file) != count) {
        free(buffer);
        return NULL;
    }
    return buffer;
}

static int vt_inflate_raw(const unsigned char* source, size_t source_length,
                          unsigned char* destination, size_t destination_length) {
    z_stream stream;
    int code;
    int ok;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef*)source;
    stream.avail_in = (uInt)source_length;
    stream.next_out = (Bytef*)destination;
    stream.avail_out = (uInt)destination_length;
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return 0;
    code = inflate(&stream, Z_FINISH);
    ok = code == Z_STREAM_END && stream.total_out == destination_length;
    inflateEnd(&stream);
    return ok;
}

static int vt_zip_extract_file(const char* path, const char* wanted, VtText* out) {
    FILE* file;
    long length;
    unsigned char* tail = NULL;
    unsigned char* central = NULL;
    unsigned char* local = NULL;
    unsigned char* compressed = NULL;
    unsigned char* plain = NULL;
    size_t tail_length, i, eocd = 0, central_size, central_offset, position, end;
    size_t wanted_length = strlen(wanted);
    int found = 0, result = 0;
    file = fopen(path, "rb");
    if (file == NULL) return 0;
    if (fseek(file, 0, SEEK_END) != 0 || (length = ftell(file)) < 22) goto done;
    tail_length = (size_t)length > 65557 ? 65557 : (size_t)length;
    tail = vt_read_range(file, length - (long)tail_length, tail_length);
    if (tail == NULL) goto done;
    for (i = 0; i + 22 <= tail_length; i++) {
        if (vt_zip_u32(tail + i) != 0x06054b50U) continue;
        if (i + 22 + vt_zip_u16(tail + i + 20) == tail_length) {
            eocd = i;
            found = 1;
        }
    }
    if (!found) goto done;
    central_size = vt_zip_u32(tail + eocd + 12);
    central_offset = vt_zip_u32(tail + eocd + 16);
    if (central_offset + central_size > (size_t)length || central_size == 0) goto done;
    central = vt_read_range(file, (long)central_offset, central_size);
    if (central == NULL) goto done;
    position = 0;
    end = central_size;
    while (position + 46 <= end && vt_zip_u32(central + position) == 0x02014b50U) {
        uint16_t method = vt_zip_u16(central + position + 10);
        uint32_t compressed_size = vt_zip_u32(central + position + 20);
        uint32_t plain_size = vt_zip_u32(central + position + 24);
        uint16_t name_length = vt_zip_u16(central + position + 28);
        uint16_t extra_length = vt_zip_u16(central + position + 30);
        uint16_t comment_length = vt_zip_u16(central + position + 32);
        uint32_t local_offset = vt_zip_u32(central + position + 42);
        if (position + 46 + name_length > end) break;
        if (name_length == wanted_length && memcmp(central + position + 46, wanted, wanted_length) == 0) {
            uint16_t local_name, local_extra;
            size_t data_start;
            if (local_offset + 30 > (size_t)length) goto done;
            local = vt_read_range(file, (long)local_offset, 30);
            if (local == NULL || vt_zip_u32(local) != 0x04034b50U) goto done;
            local_name = vt_zip_u16(local + 26);
            local_extra = vt_zip_u16(local + 28);
            data_start = (size_t)local_offset + 30 + local_name + local_extra;
            if (data_start + compressed_size > (size_t)length) goto done;
            compressed = vt_read_range(file, (long)data_start, compressed_size);
            if (compressed == NULL) goto done;
            if (method == 0) {
                if (compressed_size != plain_size) goto done;
                result = vt_text_add(out, (const char*)compressed, plain_size);
                goto done;
            }
            if (method == 8) {
                plain = (unsigned char*)malloc(plain_size != 0 ? plain_size : 1);
                if (plain == NULL) goto done;
                if (vt_inflate_raw(compressed, compressed_size, plain, plain_size))
                    result = vt_text_add(out, (const char*)plain, plain_size);
                goto done;
            }
            goto done;
        }
        position += 46 + name_length + extra_length + comment_length;
    }
done:
    free(tail);
    free(central);
    free(local);
    free(compressed);
    free(plain);
    fclose(file);
    return result;
}

static int vt_installation_inspect(const char* jar, VtInstallation* installation) {
    VtText version = {0};
    uint32_t protocol_number = 0;
    int result = 0;
    memset(installation, 0, sizeof(*installation));
    if (strlen(jar) >= sizeof(installation->jar)) goto done;
    strcpy(installation->jar, jar);
    if (vt_zip_extract_file(jar, "version.json", &version) &&
        vt_json_find_uint(&version, "protocol_version", &protocol_number)) {
        snprintf(installation->protocol, sizeof(installation->protocol), "%u", (unsigned int)protocol_number);
        installation->protocol_number = (int)protocol_number;
    }
    if (installation->protocol_number != VT_SETUP_TARGET_PROTOCOL) goto done;
    {
        size_t length = strlen(jar);
        if (length < 4 || length - 4 >= sizeof(installation->json)) goto done;
        memcpy(installation->json, jar, length - 4);
        strcpy(installation->json + length - 4, ".json");
    }
    {
        char current[VT_SETUP_PATH];
        int depth;
        strcpy(current, installation->jar);
        for (depth = 0; depth < 8; depth++) {
            char libraries[VT_SETUP_PATH];
            if (!vt_parent_directory(current, current, sizeof(current))) break;
            if (!vt_path_join(libraries, sizeof(libraries), current, "libraries")) continue;
            if (vt_directory_exists(libraries)) {
                strcpy(installation->libraries, libraries);
                break;
            }
        }
    }
    result = installation->libraries[0] != 0 && vt_file_exists(installation->json);
done:
    vt_text_free(&version);
    return result;
}

static void vt_scan_versions(const char* versions, VtInstallation* found, size_t capacity, size_t* count);

static void vt_scan_root(const char* root, unsigned int depth, VtInstallation* found, size_t capacity, size_t* count) {
    char path[VT_SETUP_PATH];
#ifdef _WIN32
    WIN32_FIND_DATAA entry;
    HANDLE search;
#else
    DIR* directory;
    struct dirent* entry;
#endif
    if (*count >= capacity || depth > 5 || !vt_directory_exists(root)) return;
    if (!vt_path_join(path, sizeof(path), root, "versions")) return;
    if (vt_directory_exists(path)) {
        vt_scan_versions(path, found, capacity, count);
        return;
    }
#ifdef _WIN32
    if (!vt_path_join(path, sizeof(path), root, "*")) return;
    search = FindFirstFileA(path, &entry);
    if (search == INVALID_HANDLE_VALUE) return;
    do {
        if (!(entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || strcmp(entry.cFileName, ".") == 0 ||
            strcmp(entry.cFileName, "..") == 0) continue;
        if (!vt_path_join(path, sizeof(path), root, entry.cFileName)) continue;
        vt_scan_root(path, depth + 1, found, capacity, count);
    } while (*count < capacity && FindNextFileA(search, &entry));
    FindClose(search);
#else
    directory = opendir(root);
    if (directory == NULL) return;
    while (*count < capacity && (entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        if (!vt_path_join(path, sizeof(path), root, entry->d_name) || !vt_directory_exists(path)) continue;
        vt_scan_root(path, depth + 1, found, capacity, count);
    }
    closedir(directory);
#endif
}

static void vt_scan_versions(const char* versions, VtInstallation* found, size_t capacity, size_t* count) {
#ifdef _WIN32
    WIN32_FIND_DATAA entry;
    HANDLE search;
#else
    DIR* directory;
    struct dirent* entry;
#endif
    char pattern[VT_SETUP_PATH];
    char jar[VT_SETUP_PATH];
    if (!vt_path_join(pattern, sizeof(pattern), versions, "*")) return;
#ifdef _WIN32
    search = FindFirstFileA(pattern, &entry);
    if (search == INVALID_HANDLE_VALUE) return;
#else
    directory = opendir(versions);
    if (directory == NULL) return;
#endif
    while (*count < capacity) {
        const char* name;
        char version[VT_SETUP_PATH];
#ifdef _WIN32
        name = entry.cFileName;
#else
        entry = readdir(directory);
        if (entry == NULL) break;
        name = entry->d_name;
#endif
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0 ||
            !vt_path_join(version, sizeof(version), versions, name) || !vt_directory_exists(version) ||
            !vt_path_join(jar, sizeof(jar), version, name)) continue;
        {
            size_t length = strlen(jar);
            if (length + 4 >= sizeof(jar)) continue;
            strcat(jar, ".jar");
        }
        if (vt_file_exists(jar) && vt_installation_inspect(jar, &found[*count])) (*count)++;
#ifdef _WIN32
        if (!FindNextFileA(search, &entry)) break;
#endif
    }
#ifdef _WIN32
    FindClose(search);
#else
    closedir(directory);
#endif
}

static int vt_collect_libraries(const char* json_path, const char* libraries, VtText* classpath, unsigned int depth);

static int vt_maven_path(const char* coordinate, char* out, size_t capacity) {
    const char* group_end = strchr(coordinate, ':');
    const char* artifact_end;
    const char* version_end;
    const char* p;
    VtText path = {0};
    int result = 0;
    if (group_end == NULL) goto done;
    artifact_end = strchr(group_end + 1, ':');
    if (artifact_end == NULL) goto done;
    version_end = strchr(artifact_end + 1, ':');
    if (version_end == NULL) version_end = artifact_end + 1 + strlen(artifact_end + 1);
    for (p = coordinate; p < group_end; p++) {
        char c = *p == '.' ? '/' : *p;
        if (!vt_text_add(&path, &c, 1)) goto done;
    }
    if (!vt_text_str(&path, "/") || !vt_text_add(&path, group_end + 1, (size_t)(artifact_end - group_end - 1)) ||
        !vt_text_str(&path, "/") || !vt_text_add(&path, artifact_end + 1, (size_t)(version_end - artifact_end - 1)) ||
        !vt_text_str(&path, "/") || !vt_text_add(&path, group_end + 1, (size_t)(artifact_end - group_end - 1)) ||
        !vt_text_str(&path, "-") || !vt_text_add(&path, artifact_end + 1, (size_t)(version_end - artifact_end - 1))) goto done;
    if (*version_end == ':') {
        if (!vt_text_str(&path, "-") || !vt_text_str(&path, version_end + 1)) goto done;
    }
    if (!vt_text_str(&path, ".jar") || path.length >= capacity) goto done;
    strcpy(out, path.data);
    result = 1;
done:
    vt_text_free(&path);
    return result;
}

static int vt_library_entry(VtJson* json, const char* libraries, VtText* classpath) {
    VtText key = {0};
    VtText name = {0};
    VtText path = {0};
    int first = 1;
    int result = 0;
    char relative[VT_SETUP_PATH];
    char full[VT_SETUP_PATH];
    if (!vt_json_open(json, '{')) goto done;
    while (1) {
        int next = vt_json_next(json, '}', &first);
        if (next < 0) goto done;
        if (next == 0) break;
        if (!vt_json_string(json, &key) || !vt_json_expect_colon(json)) goto done;
        if (vt_name_is(key.data, key.length, "name")) {
            if (!vt_json_string(json, &name)) goto done;
        } else if (vt_name_is(key.data, key.length, "downloads")) {
            VtJson downloads = *json;
            int outer_first = 1;
            if (!vt_json_open(&downloads, '{')) goto done;
            while (1) {
                int outer = vt_json_next(&downloads, '}', &outer_first);
                if (outer < 0) goto done;
                if (outer == 0) break;
                if (!vt_json_string(&downloads, &key) || !vt_json_expect_colon(&downloads)) goto done;
                if (vt_name_is(key.data, key.length, "artifact")) {
                    VtJson artifact = downloads;
                    int inner_first = 1;
                    if (!vt_json_open(&artifact, '{')) goto done;
                    while (1) {
                        int inner = vt_json_next(&artifact, '}', &inner_first);
                        if (inner < 0) goto done;
                        if (inner == 0) break;
                        if (!vt_json_string(&artifact, &key) || !vt_json_expect_colon(&artifact)) goto done;
                        if (vt_name_is(key.data, key.length, "path")) {
                            if (!vt_json_string(&artifact, &path)) goto done;
                        } else if (!vt_json_skip(&artifact, 0)) goto done;
                    }
                    if (!vt_json_skip(&downloads, 0)) goto done;
                } else if (!vt_json_skip(&downloads, 0)) goto done;
            }
            if (!vt_json_skip(json, 0)) goto done;
        } else if (!vt_json_skip(json, 0)) goto done;
    }
    if (path.length != 0) {
        if (path.length >= sizeof(relative)) goto done;
        strcpy(relative, path.data);
    } else if (name.length != 0) {
        if (!vt_maven_path(name.data, relative, sizeof(relative))) goto done;
    } else goto done;
    if (!vt_path_join(full, sizeof(full), libraries, relative) || !vt_file_exists(full)) {
        result = 1;
        goto done;
    }
#ifdef _WIN32
    if (classpath->length != 0 && !vt_text_str(classpath, ";")) goto done;
#else
    if (classpath->length != 0 && !vt_text_str(classpath, ":")) goto done;
#endif
    result = vt_text_str(classpath, full);
done:
    vt_text_free(&key);
    vt_text_free(&name);
    vt_text_free(&path);
    return result;
}

static int vt_collect_libraries(const char* json_path, const char* libraries, VtText* classpath, unsigned int depth) {
    VtText text = {0};
    VtText key = {0};
    VtText parent = {0};
    VtJson json;
    int first = 1;
    int result = 0;
    if (depth > 4 || !vt_read_text(json_path, &text)) goto done;
    json.data = text.data;
    json.length = text.length;
    json.position = 0;
    if (!vt_json_open(&json, '{')) goto done;
    while (1) {
        int next = vt_json_next(&json, '}', &first);
        if (next < 0) goto done;
        if (next == 0) break;
        if (!vt_json_string(&json, &key) || !vt_json_expect_colon(&json)) goto done;
        if (vt_name_is(key.data, key.length, "inheritsFrom")) {
            if (!vt_json_string(&json, &parent)) goto done;
        } else if (vt_name_is(key.data, key.length, "libraries")) {
            int library_first = 1;
            if (!vt_json_open(&json, '[')) goto done;
            while (1) {
                int library = vt_json_next(&json, ']', &library_first);
                if (library < 0) goto done;
                if (library == 0) break;
                if (!vt_library_entry(&json, libraries, classpath)) goto done;
            }
        } else if (!vt_json_skip(&json, 0)) goto done;
    }
    if (parent.length != 0) {
        char directory[VT_SETUP_PATH];
        char versions[VT_SETUP_PATH];
        char version[VT_SETUP_PATH];
        char inherited[VT_SETUP_PATH];
        if (!vt_parent_directory(libraries, directory, sizeof(directory)) ||
            !vt_path_join(versions, sizeof(versions), directory, "versions") ||
            !vt_path_join(version, sizeof(version), versions, parent.data) ||
            !vt_path_join(inherited, sizeof(inherited), version, parent.data)) goto done;
        {
            size_t length = strlen(inherited);
            if (length + 5 >= sizeof(inherited)) goto done;
            strcat(inherited, ".json");
        }
        if (vt_file_exists(inherited) && !vt_collect_libraries(inherited, libraries, classpath, depth + 1)) goto done;
    }
    result = 1;
done:
    vt_text_free(&text);
    vt_text_free(&key);
    vt_text_free(&parent);
    return result;
}

static int vt_find_java(const VtInstallation* installation, char* java, size_t capacity) {
    const char* home = getenv("JAVA_HOME");
    const char* executable =
#ifdef _WIN32
        "java.exe";
#else
        "java";
#endif
    if (home != NULL) {
        char bin[VT_SETUP_PATH];
        if (vt_path_join(bin, sizeof(bin), home, "bin") && vt_path_join(java, capacity, bin, executable) &&
            vt_file_exists(java)) return 1;
    }
    {
        char runtime[VT_SETUP_PATH];
        char directory[VT_SETUP_PATH];
        if (vt_parent_directory(installation->libraries, directory, sizeof(directory)) &&
            vt_path_join(runtime, sizeof(runtime), directory, "runtime") && vt_directory_exists(runtime)) {
#ifdef _WIN32
            WIN32_FIND_DATAA component;
            char pattern[VT_SETUP_PATH];
            HANDLE search;
            if (!vt_path_join(pattern, sizeof(pattern), runtime, "*")) return 0;
            search = FindFirstFileA(pattern, &component);
            if (search == INVALID_HANDLE_VALUE) return 0;
            do {
                char base[VT_SETUP_PATH];
                char platform[VT_SETUP_PATH];
                WIN32_FIND_DATAA os_entry;
                HANDLE os_search;
                if (!(component.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
                    !vt_path_join(base, sizeof(base), runtime, component.cFileName) ||
                    !vt_path_join(pattern, sizeof(pattern), base, "*")) continue;
                os_search = FindFirstFileA(pattern, &os_entry);
                if (os_search == INVALID_HANDLE_VALUE) continue;
                do {
                    char leaf[VT_SETUP_PATH];
                    char bin[VT_SETUP_PATH];
                    if (!(os_entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
                        !vt_path_join(platform, sizeof(platform), base, os_entry.cFileName) ||
                        !vt_path_join(leaf, sizeof(leaf), platform, component.cFileName) ||
                        !vt_path_join(bin, sizeof(bin), leaf, "bin") ||
                        !vt_path_join(java, capacity, bin, "java.exe")) continue;
                    if (vt_file_exists(java)) {
                        FindClose(os_search);
                        FindClose(search);
                        return 1;
                    }
                } while (FindNextFileA(os_search, &os_entry));
                FindClose(os_search);
            } while (FindNextFileA(search, &component));
            FindClose(search);
#else
            DIR* components = opendir(runtime);
            struct dirent* component;
            if (components == NULL) return 0;
            while ((component = readdir(components)) != NULL) {
                char base[VT_SETUP_PATH];
                DIR* platforms;
                struct dirent* platform;
                if (component->d_name[0] == '.' || !vt_path_join(base, sizeof(base), runtime, component->d_name)) continue;
                platforms = opendir(base);
                if (platforms == NULL) continue;
                while ((platform = readdir(platforms)) != NULL) {
                    char os_path[VT_SETUP_PATH];
                    char leaf[VT_SETUP_PATH];
                    char home_path[VT_SETUP_PATH];
                    char bin[VT_SETUP_PATH];
                    if (platform->d_name[0] == '.' || !vt_path_join(os_path, sizeof(os_path), base, platform->d_name) ||
                        !vt_path_join(leaf, sizeof(leaf), os_path, component->d_name)) continue;
                    if (vt_path_join(bin, sizeof(bin), leaf, "bin") && vt_path_join(java, capacity, bin, "java") && vt_file_exists(java)) {
                        closedir(platforms);
                        closedir(components);
                        return 1;
                    }
#ifdef __APPLE__
                    if (vt_path_join(home_path, sizeof(home_path), leaf, "jre.bundle/Contents/Home") &&
                        vt_path_join(bin, sizeof(bin), home_path, "bin") && vt_path_join(java, capacity, bin, "java") && vt_file_exists(java)) {
                        closedir(platforms);
                        closedir(components);
                        return 1;
                    }
#endif
                }
                closedir(platforms);
            }
            closedir(components);
#endif
        }
    }
#ifdef _WIN32
    return SearchPathA(NULL, "java.exe", NULL, (DWORD)capacity, java, NULL) != 0;
#else
    {
        const char* path = getenv("PATH");
        const char* start = path;
        if (path == NULL) return 0;
        while (start != NULL) {
            const char* end = strchr(start, ':');
            size_t length = end == NULL ? strlen(start) : (size_t)(end - start);
            char directory[VT_SETUP_PATH];
            if (length != 0 && length < sizeof(directory)) {
                memcpy(directory, start, length);
                directory[length] = 0;
                if (vt_path_join(java, capacity, directory, "java") && vt_file_exists(java)) return 1;
            }
            start = end == NULL ? NULL : end + 1;
        }
    }
    return 0;
#endif
}

#ifdef _WIN32
static int vt_run_process(char* command) {
    STARTUPINFOA startup;
    PROCESS_INFORMATION process;
    DWORD code;
    ZeroMemory(&startup, sizeof(startup));
    startup.cb = sizeof(startup);
    if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &startup, &process)) return 0;
    WaitForSingleObject(process.hProcess, INFINITE);
    if (!GetExitCodeProcess(process.hProcess, &code)) code = 1;
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return code == 0;
}
#else
static int vt_run_process(char* const arguments[]) {
    pid_t child = fork();
    int status;
    if (child < 0) return 0;
    if (child == 0) {
        execv(arguments[0], arguments);
        _exit(127);
    }
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) return 0;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
#endif

static int vt_run_generator(const VtInstallation* installation, const char* output) {
    VtText classpath = {0};
    char java[VT_SETUP_PATH];
    int result = 0;
    if (!vt_find_java(installation, java, sizeof(java)) || !vt_text_str(&classpath, installation->jar) ||
#ifdef _WIN32
        !vt_text_str(&classpath, ";") ||
#else
        !vt_text_str(&classpath, ":") ||
#endif
        !vt_collect_libraries(installation->json, installation->libraries, &classpath, 0)) goto done;
    printf("Generating the block database with Minecraft %s (protocol %d)...\n", VT_SETUP_TARGET_VERSION, VT_SETUP_TARGET_PROTOCOL);
#ifdef _WIN32
    {
        VtText command = {0};
        if (!vt_text_str(&command, "\"") || !vt_text_str(&command, java) || !vt_text_str(&command, "\" -cp \"") ||
            !vt_text_str(&command, classpath.data) || !vt_text_str(&command, "\" net.minecraft.data.Main --reports --output \"") ||
            !vt_text_str(&command, output) || !vt_text_str(&command, "\"")) {
            vt_text_free(&command);
            goto done;
        }
        result = vt_run_process(command.data);
        vt_text_free(&command);
    }
#else
    {
        char* arguments[] = {java, "-cp", classpath.data, "net.minecraft.data.Main", "--reports", "--output", (char*)output, NULL};
        result = vt_run_process(arguments);
    }
#endif
done:
    vt_text_free(&classpath);
    return result;
}

int vt_run_blockdb_setup(void) {
    const char* destination = getenv("VORTEX_BLOCK_DB");
    const char* home;
    VtInstallation installations[32];
    size_t count = 0;
    size_t i;
    char generated[VT_SETUP_PATH];
    char output[VT_SETUP_PATH];
    char blocks[VT_SETUP_PATH];
    char registries[VT_SETUP_PATH];
    if (destination == NULL) destination = "generated/blockdb.bin";
    if (!vt_parent_directory(destination, generated, sizeof(generated)) ||
        !vt_path_join(output, sizeof(output), generated, ".blockdb-work") || !vt_make_directory(output)) return 1;
    if (!vt_path_join(blocks, sizeof(blocks), output, "reports/blocks.json") ||
        !vt_path_join(registries, sizeof(registries), output, "reports/registries.json")) return 1;
    if (vt_file_exists(blocks) && vt_file_exists(registries) &&
        vt_blockdb_build_reports(blocks, registries, destination)) return 0;
    home = getenv("MINECRAFT_HOME");
    if (home != NULL) vt_scan_root(home, 0, installations, 32, &count);
#ifdef _WIN32
    {
        const char* appdata = getenv("APPDATA");
        const char* local = getenv("LOCALAPPDATA");
        char root[VT_SETUP_PATH];
        if (appdata != NULL) {
            if (vt_path_join(root, sizeof(root), appdata, ".minecraft")) vt_scan_root(root, 0, installations, 32, &count);
            if (vt_path_join(root, sizeof(root), appdata, "PrismLauncher\\instances")) vt_scan_root(root, 0, installations, 32, &count);
            if (vt_path_join(root, sizeof(root), appdata, "MultiMC\\instances")) vt_scan_root(root, 0, installations, 32, &count);
            if (vt_path_join(root, sizeof(root), appdata, "ATLauncher\\instances")) vt_scan_root(root, 0, installations, 32, &count);
        }
        if (local != NULL && vt_path_join(root, sizeof(root), local, "Programs\\PrismLauncher\\instances"))
            vt_scan_root(root, 0, installations, 32, &count);
    }
#else
    home = getenv("HOME");
    if (home != NULL) {
        char root[VT_SETUP_PATH];
#  ifdef __APPLE__
        if (vt_path_join(root, sizeof(root), home, "Library/Application Support/minecraft")) vt_scan_root(root, 0, installations, 32, &count);
        if (vt_path_join(root, sizeof(root), home, "Library/Application Support/PrismLauncher/instances")) vt_scan_root(root, 0, installations, 32, &count);
        if (vt_path_join(root, sizeof(root), home, "Library/Application Support/MultiMC/instances")) vt_scan_root(root, 0, installations, 32, &count);
        if (vt_path_join(root, sizeof(root), home, "Library/Application Support/ATLauncher/instances")) vt_scan_root(root, 0, installations, 32, &count);
#  else
        if (vt_path_join(root, sizeof(root), home, ".minecraft")) vt_scan_root(root, 0, installations, 32, &count);
        if (vt_path_join(root, sizeof(root), home, ".local/share/PrismLauncher/instances")) vt_scan_root(root, 0, installations, 32, &count);
        if (vt_path_join(root, sizeof(root), home, ".local/share/multimc/instances")) vt_scan_root(root, 0, installations, 32, &count);
        if (vt_path_join(root, sizeof(root), home, ".var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/instances")) vt_scan_root(root, 0, installations, 32, &count);
#  endif
    }
#endif
    for (i = 0; i < count; i++) {
        if (!vt_run_generator(&installations[i], output)) continue;
        if (vt_file_exists(blocks) && vt_file_exists(registries) &&
            vt_blockdb_build_reports(blocks, registries, destination)) return 0;
    }
    fprintf(stderr, "Block database setup requires an installed Minecraft %s jar (protocol %d) and its Java runtime.\n",
            VT_SETUP_TARGET_VERSION, VT_SETUP_TARGET_PROTOCOL);
    return 1;
}
/* Vortex engine - block database loader.
 *
 * The binary is produced locally by tools/gen_blockdb.py from the vanilla data
 * generator's blocks report; it is not part of this repository. This file only
 * knows the container format (see the generator): a header, one fixed 20 byte
 * record per block sorted by first state, and a concatenated name blob.
 *
 * The tables are static because Cpyte module-level state is not reachable from
 * functions; every accessor is a plain C call.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define VT_BLOCKDB_MAGIC "VBLKDB01"
#define VT_BLOCKDB_RECORD 20
#define VT_BLOCKDB_MAX_FILE (64U * 1024U * 1024U)
#define VT_BLOCKDB_MAX_STATES (1U << 24)
#define VT_BLOCKDB_MAX_BLOCKS 65536U
#define VT_BLOCKDB_MAX_NAMES (16U * 1024U * 1024U)

static unsigned char* vt_blockdb_data = 0;
static int vt_blockdb_size = 0;
static uint32_t vt_blockdb_states = 0;
static uint32_t vt_blockdb_blocks = 0;
static uint32_t vt_blockdb_name_bytes = 0;
static const unsigned char* vt_blockdb_table = 0;
static const char* vt_blockdb_names = 0;

static uint32_t vt_blockdb_u32(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint16_t vt_blockdb_u16(const unsigned char* p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static int vt_blockdb_validate(const unsigned char* data, size_t length) {
    uint32_t states, blocks, names, expected_state = 0, expected_name = 0;
    size_t i;
    if (data == NULL || length < 20 || length > VT_BLOCKDB_MAX_FILE) return 0;
    if (memcmp(data, VT_BLOCKDB_MAGIC, 8) != 0) return 0;
    states = vt_blockdb_u32(data + 8);
    blocks = vt_blockdb_u32(data + 12);
    names = vt_blockdb_u32(data + 16);
    if (states == 0 || states > VT_BLOCKDB_MAX_STATES ||
        blocks == 0 || blocks > VT_BLOCKDB_MAX_BLOCKS ||
        names == 0 || names > VT_BLOCKDB_MAX_NAMES) return 0;
    if (20ULL + (unsigned long long)blocks * VT_BLOCKDB_RECORD +
            (unsigned long long)names != (unsigned long long)length) return 0;

    const unsigned char* table = data + 20;
    const unsigned char* name_data = table + (size_t)blocks * VT_BLOCKDB_RECORD;
    for (i = 0; i < blocks; i++) {
        const unsigned char* record = table + i * VT_BLOCKDB_RECORD;
        uint32_t protocol = vt_blockdb_u32(record);
        uint32_t first = vt_blockdb_u32(record + 4);
        uint32_t count = (uint32_t)vt_blockdb_u16(record + 8);
        uint16_t flags = vt_blockdb_u16(record + 10);
        uint32_t name_offset = vt_blockdb_u32(record + 12);
        uint32_t name_length = (uint32_t)vt_blockdb_u16(record + 16);
        uint16_t reserved = vt_blockdb_u16(record + 18);
        if (first != expected_state || count == 0 ||
            count > states - expected_state || protocol > 0x7fffffffU ||
            name_offset != expected_name || name_length == 0 ||
            name_length > names - expected_name || reserved != 0 ||
            (flags & (uint16_t)~0x7fU) != 0) return 0;
        if (memchr(name_data + name_offset, 0, name_length) != NULL) return 0;
        expected_state += count;
        expected_name += name_length;
    }
    return expected_state == states && expected_name == names;
}

void vt_blockdb_unload(void) {
    if (vt_blockdb_data != 0) free(vt_blockdb_data);
    vt_blockdb_data = 0;
    vt_blockdb_size = 0;
    vt_blockdb_states = 0;
    vt_blockdb_blocks = 0;
    vt_blockdb_name_bytes = 0;
    vt_blockdb_table = 0;
    vt_blockdb_names = 0;
}

/* 1 on success. A missing file is not an error: the mesher then falls back to
 * treating state 0 as air and every other state as an opaque cube. */
int vt_blockdb_load(const char* path) {
    FILE* file;
    long length;
    size_t got;
    unsigned char* data;
    uint32_t states, blocks, names;
    vt_blockdb_unload();
    if (path == 0) return 0;
    file = fopen(path, "rb");
    if (file == 0) return 0;
    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); return 0; }
    length = ftell(file);
    if (length < 20 || (unsigned long)length > VT_BLOCKDB_MAX_FILE) {
        fclose(file);
        return 0;
    }
    if (fseek(file, 0, SEEK_SET) != 0) { fclose(file); return 0; }
    data = (unsigned char*)malloc((size_t)length);
    if (data == 0) { fclose(file); return 0; }
    got = fread(data, 1, (size_t)length, file);
    fclose(file);
    if (got != (size_t)length) { free(data); return 0; }
    if (!vt_blockdb_validate(data, (size_t)length)) {
        free(data);
        return 0;
    }
    states = vt_blockdb_u32(data + 8);
    blocks = vt_blockdb_u32(data + 12);
    names = vt_blockdb_u32(data + 16);
    vt_blockdb_data = data;
    vt_blockdb_size = (int)length;
    vt_blockdb_states = states;
    vt_blockdb_blocks = blocks;
    vt_blockdb_name_bytes = names;
    vt_blockdb_table = data + 20;
    vt_blockdb_names = (const char*)(data + 20 + (size_t)blocks * VT_BLOCKDB_RECORD);
    return 1;
}

char* vt_blockdb_path_from_env(void) {
    char* path = getenv("VORTEX_BLOCK_DB");
    if (path == 0) path = (char*)"generated/blockdb.bin";
    return path;
}

int vt_blockdb_loaded(void) { return vt_blockdb_data != 0 ? 1 : 0; }
int vt_blockdb_state_count(void) { return (int)vt_blockdb_states; }
int vt_blockdb_block_count(void) { return (int)vt_blockdb_blocks; }

/* Record whose [first_state, first_state+state_count) contains `state`, or 0. */
static const unsigned char* vt_blockdb_find(int state) {
    int lo, hi;
    if (vt_blockdb_data == 0 || state < 0) return 0;
    lo = 0;
    hi = (int)vt_blockdb_blocks - 1;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        const unsigned char* record = vt_blockdb_table + (size_t)mid * VT_BLOCKDB_RECORD;
        uint32_t first = vt_blockdb_u32(record + 4);
        uint32_t count = (uint32_t)vt_blockdb_u16(record + 8);
        if ((uint32_t)state < first) {
            hi = mid - 1;
        } else if ((uint64_t)(uint32_t)state >= (uint64_t)first + count) {
            lo = mid + 1;
        } else {
            return record;
        }
    }
    return 0;
}

/* -1 when the database is absent or the state is unknown. */
int vt_blockdb_flags(int state) {
    const unsigned char* record = vt_blockdb_find(state);
    if (record == 0) return -1;
    return (int)vt_blockdb_u16(record + 10);
}

int vt_blockdb_protocol(int state) {
    const unsigned char* record = vt_blockdb_find(state);
    if (record == 0) return -1;
    return (int)vt_blockdb_u32(record);
}

/* Packed render word for the native mesher: classification flags in the low
 * byte, the texture layer code (protocol id + 1, or 0 for unknown) above it.
 * Mirrors the Cpyte mesher's fallback so both meshers agree without a database:
 * state 0 is air, an unknown state is an opaque cube of unknown layer. */
uint32_t vt_blockdb_render(int state) {
    const unsigned char* record;
    uint32_t flags, layer_code;
    if (state == 0) return 1u; /* VT_AIR */
    record = vt_blockdb_find(state);
    if (record == 0) {
        flags = 4u | 8u; /* VT_CUBE | VT_OPAQUE */
        layer_code = 0;
    } else {
        flags = (uint32_t)vt_blockdb_u16(record + 10);
        layer_code = vt_blockdb_u32(record) + 1u;
    }
    return (flags & 0xffu) | (layer_code << 8);
}

/* ---- geometry shape and tint classification -------------------------------
 *
 * The binary records flags and a name, not the block-state property map, so a
 * shape here is a name-based heuristic over the common non-cube families. It
 * picks one canonical variant (a slab meshes as the bottom half, a door as a
 * closed lower panel); exact per-state models would need the resource-pack
 * geometry this project deliberately does not ship. The mesher uses the code
 * to choose a box/quad layout instead of drawing every block as a full cube.
 *
 * Shape codes (kept in sync with engine/mesher.c):
 *   0 cube, 2 slab low, 3 slab high, 4 double slab, 5 stairs, 6 fence,
 *   7 wall, 8 pane/bars, 9 carpet, 10 door, 11 trapdoor, 12 fluid,
 *   13 pressure plate, 14 button, 255 skip (attached block with no safe box).
 * Tint kinds: 0 none, 1 grass, 2 foliage, 3 water. */

#define VT_SHAPE_CUBE 0u
#define VT_SHAPE_SLAB_LOW 2u
#define VT_SHAPE_SLAB_HIGH 3u
#define VT_SHAPE_SLAB_DOUBLE 4u
#define VT_SHAPE_STAIRS 5u
#define VT_SHAPE_FENCE 6u
#define VT_SHAPE_WALL 7u
#define VT_SHAPE_PANE 8u
#define VT_SHAPE_CARPET 9u
#define VT_SHAPE_DOOR 10u
#define VT_SHAPE_TRAPDOOR 11u
#define VT_SHAPE_FLUID 12u
#define VT_SHAPE_PLATE 13u
#define VT_SHAPE_BUTTON 14u
#define VT_SHAPE_SKIP 255u

#define VT_TINT_NONE 0u
#define VT_TINT_GRASS 1u
#define VT_TINT_FOLIAGE 2u
#define VT_TINT_WATER 3u

/* Name of `state` without copying: pointer into the blob and its length. */
static const char* vt_blockdb_name_ptr(int state, uint32_t* length) {
    const unsigned char* record = vt_blockdb_find(state);
    uint32_t offset;
    if (record == 0) { *length = 0; return ""; }
    offset = vt_blockdb_u32(record + 12);
    *length = (uint32_t)vt_blockdb_u16(record + 16);
    if ((uint64_t)offset + *length > vt_blockdb_name_bytes) { *length = 0; return ""; }
    return vt_blockdb_names + offset;
}

static int vt_name_is(const char* name, uint32_t length, const char* word) {
    size_t n = strlen(word);
    return length == (uint32_t)n && memcmp(name, word, n) == 0;
}

static int vt_name_ends(const char* name, uint32_t length, const char* suffix) {
    size_t n = strlen(suffix);
    if (length < (uint32_t)n) return 0;
    return memcmp(name + length - n, suffix, n) == 0;
}

static uint32_t vt_classify_shape(const char* name, uint32_t length) {
    if (vt_name_ends(name, length, "_slab")) return VT_SHAPE_SLAB_LOW;
    if (vt_name_is(name, length, "petrified_oak_slab")) return VT_SHAPE_SLAB_LOW;
    if (vt_name_ends(name, length, "_stairs")) return VT_SHAPE_STAIRS;
    if (vt_name_ends(name, length, "_fence")) return VT_SHAPE_FENCE;
    if (vt_name_is(name, length, "nether_brick_fence")) return VT_SHAPE_FENCE;
    if (vt_name_ends(name, length, "_wall")) return VT_SHAPE_WALL;
    if (vt_name_ends(name, length, "_pane")) return VT_SHAPE_PANE;
    if (vt_name_is(name, length, "iron_bars")) return VT_SHAPE_PANE;
    if (vt_name_ends(name, length, "_carpet")) return VT_SHAPE_CARPET;
    if (vt_name_ends(name, length, "_door")) return VT_SHAPE_DOOR;
    if (vt_name_ends(name, length, "_trapdoor")) return VT_SHAPE_TRAPDOOR;
    if (vt_name_ends(name, length, "_pressure_plate")) return VT_SHAPE_PLATE;
    if (vt_name_ends(name, length, "_button")) return VT_SHAPE_BUTTON;
    if (vt_name_is(name, length, "water") || vt_name_is(name, length, "lava") ||
        vt_name_is(name, length, "bubble_column")) return VT_SHAPE_FLUID;
    /* Attached families with no safe canonical box are left unmeshed rather
     * than drawn as a wrong full cube, matching the flag classifier. */
    return VT_SHAPE_SKIP;
}

static uint32_t vt_classify_tint(const char* name, uint32_t length) {
    if (vt_name_is(name, length, "water") ||
        vt_name_is(name, length, "bubble_column")) return VT_TINT_WATER;
    if (vt_name_ends(name, length, "_leaves") ||
        vt_name_is(name, length, "mangrove_roots")) return VT_TINT_FOLIAGE;
    if (vt_name_is(name, length, "grass_block") ||
        vt_name_is(name, length, "short_grass") ||
        vt_name_is(name, length, "tall_grass") ||
        vt_name_is(name, length, "grass") ||
        vt_name_is(name, length, "fern") ||
        vt_name_is(name, length, "large_fern") ||
        vt_name_is(name, length, "vine") ||
        vt_name_is(name, length, "lily_pad") ||
        vt_name_ends(name, length, "_stem")) return VT_TINT_GRASS;
    return VT_TINT_NONE;
}

/* Packed shape | (tint << 8). Memoised on the last state because the mesher
 * walks the halo spatially and neighbouring cells usually share a block. */
uint32_t vt_blockdb_shape_tint(int state) {
    static int cached_state = -1;
    static uint32_t cached_value = 0;
    const char* name;
    uint32_t length, shape, tint, flags;
    if (state == cached_state) return cached_value;
    if (state == 0) { cached_state = state; cached_value = VT_SHAPE_SKIP; return cached_value; }
    flags = (uint32_t)vt_blockdb_flags(state);
    name = vt_blockdb_name_ptr(state, &length);
    if (length == 0) {
        /* No database or unknown state: keep the opaque-cube fallback so a
         * world stays visible, exactly as vt_blockdb_render does. */
        cached_state = state;
        cached_value = VT_SHAPE_CUBE | (VT_TINT_NONE << 8);
        return cached_value;
    }
    if ((flags & 1u) != 0) shape = VT_SHAPE_SKIP;          /* air */
    else if ((flags & 64u) != 0) shape = VT_SHAPE_CUBE;    /* cross: handled by flag */
    else if ((flags & 4u) != 0) {                          /* full cube flag */
        shape = ((flags & 2u) != 0) ? VT_SHAPE_FLUID : VT_SHAPE_CUBE;
    } else {
        shape = vt_classify_shape(name, length);
    }
    tint = vt_classify_tint(name, length);
    cached_state = state;
    cached_value = shape | (tint << 8);
    return cached_value;
}

/* ---- biome tint colours ----------------------------------------------------
 *
 * Grass/foliage/water tint is climate-driven in the real game. The client does
 * not parse the biome registry's temperature/downfall, so the engine ships the
 * plains defaults and an override table the registry layer can fill once it
 * maps biome ids to colours. Returns a packed 0xRRGGBB. */

#define VT_BIOME_DEFAULT_GRASS 0x91BD59u
#define VT_BIOME_DEFAULT_FOLIAGE 0x77AB2Fu
#define VT_BIOME_DEFAULT_WATER 0x3F76E4u
#define VT_BIOME_OVERRIDES 256

typedef struct {
    int biome;
    int used;
    uint32_t grass;
    uint32_t foliage;
    uint32_t water;
} VTBiomeColor;

static VTBiomeColor vt_biome_colors[VT_BIOME_OVERRIDES];

static VTBiomeColor* vt_biome_slot(int biome) {
    uint32_t h = (uint32_t)biome * 2654435761u;
    int start = (int)(h % VT_BIOME_OVERRIDES);
    int i;
    for (i = 0; i < VT_BIOME_OVERRIDES; i++) {
        int at = (start + i) % VT_BIOME_OVERRIDES;
        VTBiomeColor* slot = &vt_biome_colors[at];
        if (!slot->used) return slot;
        if (slot->biome == biome) return slot;
    }
    return &vt_biome_colors[start];
}

void vt_biome_color_set(int biome, int grass, int foliage, int water) {
    VTBiomeColor* slot = vt_biome_slot(biome);
    slot->biome = biome;
    slot->grass = grass & 0xFFFFFFu;
    slot->foliage = foliage & 0xFFFFFFu;
    slot->water = water & 0xFFFFFFu;
    slot->used = 1;
}

void vt_biome_colors_reset(void) {
    memset(vt_biome_colors, 0, sizeof(vt_biome_colors));
}

uint32_t vt_biome_color(int biome, int tint_kind) {
    VTBiomeColor* slot;
    uint32_t h = (uint32_t)biome * 2654435761u;
    int start = (int)(h % VT_BIOME_OVERRIDES);
    int i;
    if (tint_kind == VT_TINT_NONE) return 0xFFFFFFu;
    for (i = 0; i < VT_BIOME_OVERRIDES; i++) {
        int at = (start + i) % VT_BIOME_OVERRIDES;
        slot = &vt_biome_colors[at];
        if (!slot->used) break;
        if (slot->biome == biome) {
            if (tint_kind == VT_TINT_GRASS) return slot->grass;
            if (tint_kind == VT_TINT_FOLIAGE) return slot->foliage;
            return slot->water;
        }
    }
    if (tint_kind == VT_TINT_GRASS) return VT_BIOME_DEFAULT_GRASS;
    if (tint_kind == VT_TINT_FOLIAGE) return VT_BIOME_DEFAULT_FOLIAGE;
    return VT_BIOME_DEFAULT_WATER;
}

int vt_blockdb_first_state_at(int index) {
    if (vt_blockdb_data == 0 || index < 0 || (uint32_t)index >= vt_blockdb_blocks) return -1;
    return (int)vt_blockdb_u32(vt_blockdb_table + (size_t)index * VT_BLOCKDB_RECORD + 4);
}

int vt_blockdb_state_count_at(int index) {
    if (vt_blockdb_data == 0 || index < 0 || (uint32_t)index >= vt_blockdb_blocks) return -1;
    return (int)vt_blockdb_u16(vt_blockdb_table + (size_t)index * VT_BLOCKDB_RECORD + 8);
}

int vt_blockdb_flags_at(int index) {
    if (vt_blockdb_data == 0 || index < 0 || (uint32_t)index >= vt_blockdb_blocks) return -1;
    return (int)vt_blockdb_u16(vt_blockdb_table + (size_t)index * VT_BLOCKDB_RECORD + 10);
}

int vt_blockdb_protocol_at(int index) {
    if (vt_blockdb_data == 0 || index < 0 || (uint32_t)index >= vt_blockdb_blocks) return -1;
    return (int)vt_blockdb_u32(vt_blockdb_table + (size_t)index * VT_BLOCKDB_RECORD);
}

/* Copies the block name of `state` into `out` (NUL terminated). Returns the
 * length, or -1 when absent. */
int vt_blockdb_name(int state, char* out, int cap) {
    const unsigned char* record = vt_blockdb_find(state);
    uint32_t offset, length, i;
    if (record == 0 || out == 0 || cap < 1) return -1;
    offset = vt_blockdb_u32(record + 12);
    length = (uint32_t)vt_blockdb_u16(record + 16);
    if ((uint64_t)offset + length > vt_blockdb_name_bytes) return -1;
    if ((uint32_t)(cap - 1) < length) length = (uint32_t)(cap - 1);
    for (i = 0; i < length; i++) out[i] = vt_blockdb_names[offset + i];
    out[length] = 0;
    return (int)length;
}

int vt_blockdb_name_at(int index, char* out, int cap) {
    const unsigned char* record;
    uint32_t offset, length, i;
    if (vt_blockdb_data == 0 || index < 0 || (uint32_t)index >= vt_blockdb_blocks) return -1;
    record = vt_blockdb_table + (size_t)index * VT_BLOCKDB_RECORD;
    offset = vt_blockdb_u32(record + 12);
    length = (uint32_t)vt_blockdb_u16(record + 16);
    if ((uint64_t)offset + length > vt_blockdb_name_bytes || out == 0 || cap < 1) return -1;
    if ((uint32_t)(cap - 1) < length) length = (uint32_t)(cap - 1);
    for (i = 0; i < length; i++) out[i] = vt_blockdb_names[offset + i];
    out[length] = 0;
    return (int)length;
}

int vt_blockdb_name_length_at(int index) {
    if (vt_blockdb_data == 0 || index < 0 || (uint32_t)index >= vt_blockdb_blocks) return -1;
    return (int)vt_blockdb_u16(vt_blockdb_table + (size_t)index * VT_BLOCKDB_RECORD + 16);
}

/* 1 when the records tile [0, states) exactly and every name is in bounds. */
int vt_blockdb_verify(void) {
    uint32_t expected = 0;
    uint32_t expected_name = 0;
    uint32_t i;
    if (vt_blockdb_data == 0) return 0;
    if (!vt_blockdb_validate(vt_blockdb_data, (size_t)vt_blockdb_size)) return 0;
    for (i = 0; i < vt_blockdb_blocks; i++) {
        const unsigned char* record = vt_blockdb_table + (size_t)i * VT_BLOCKDB_RECORD;
        uint32_t first = vt_blockdb_u32(record + 4);
        uint32_t count = (uint32_t)vt_blockdb_u16(record + 8);
        uint32_t offset = vt_blockdb_u32(record + 12);
        uint32_t length = (uint32_t)vt_blockdb_u16(record + 16);
        if (first != expected || count == 0 || count > vt_blockdb_states - expected) return 0;
        if (offset != expected_name || length == 0 ||
            (uint64_t)offset + length > vt_blockdb_name_bytes) return 0;
        expected += count;
        expected_name += length;
    }
    return expected == vt_blockdb_states && expected_name == vt_blockdb_name_bytes ? 1 : 0;
}

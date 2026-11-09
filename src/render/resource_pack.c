#include "resource_pack.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <png.h>

static DiscoveredPack s_discovered[MAX_DISCOVERED_PACKS];
static int s_discovered_count = 0;
static char s_current_pack[MAX_PATH_LEN] = {0};

static unsigned char s_atlas[256 * 256 * 4];
static int s_atlas_ready = 0;

/* Essential assets that MUST be present for a valid vanilla pack */
static const char* REQUIRED_ASSETS[] = {
    "stone.png",
    "dirt.png",
    "grass_block_top.png",
    "grass_block_side.png",
    "oak_planks.png",
    "oak_log.png",
    "oak_leaves.png",
    "cobblestone.png",
    "bedrock.png",
    "sand.png",
    "glass.png",
    "water_still.png"
};
#define NUM_REQUIRED_ASSETS (sizeof(REQUIRED_ASSETS) / sizeof(REQUIRED_ASSETS[0]))

/* All tile texture names mapped to tile slots in the 16x16 atlas */
static const char* ATLAS_TILES[33] = {
    "stone.png",                   // 0
    "dirt.png",                    // 1
    "grass_block_top.png",         // 2
    "grass_block_side.png",        // 3
    "grass_block_side_overlay.png",// 4
    "oak_planks.png",              // 5
    "oak_log.png",                 // 6
    "oak_log_top.png",             // 7
    "oak_leaves.png",              // 8
    "cobblestone.png",             // 9
    "bedrock.png",                 // 10
    "sand.png",                    // 11
    "gravel.png",                  // 12
    "glass.png",                   // 13
    "water_still.png",             // 14
    "poppy.png",                   // 15
    "dandelion.png",               // 16
    "crafting_table_top.png",      // 17
    "crafting_table_side.png",     // 18
    "crafting_table_front.png",    // 19
    "furnace_front.png",           // 20
    "furnace_side.png",            // 21
    "furnace_top.png",             // 22
    "bookshelf.png",               // 23
    "obsidian.png",                // 24
    "iron_block.png",              // 25
    "gold_block.png",              // 26
    "diamond_block.png",           // 27
    "torch.png",                   // 28
    "coal_ore.png",                // 29
    "iron_ore.png",                // 30
    "gold_ore.png",                // 31
    "diamond_ore.png"              // 32
};

static int ends_with(const char* str, const char* suffix) {
    if (!str || !suffix) return 0;
    size_t len_str = strlen(str);
    size_t len_suf = strlen(suffix);
    if (len_suf > len_str) return 0;
    return strcmp(str + len_str - len_suf, suffix) == 0;
}

static unsigned char* load_png_rgba(const char* filename, int* out_w, int* out_h) {
    FILE* fp = fopen(filename, "rb");
    if (!fp) return NULL;
    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png) { fclose(fp); return NULL; }
    png_infop info = png_create_info_struct(png);
    if (!info) { png_destroy_read_struct(&png, NULL, NULL); fclose(fp); return NULL; }
    if (setjmp(png_jmpbuf(png))) {
        png_destroy_read_struct(&png, &info, NULL);
        fclose(fp);
        return NULL;
    }
    png_init_io(png, fp);
    png_read_info(png, info);
    int width = png_get_image_width(png, info);
    int height = png_get_image_height(png, info);
    png_byte color_type = png_get_color_type(png, info);
    png_byte bit_depth = png_get_bit_depth(png, info);

    if (bit_depth == 16) png_set_strip_16(png);
    if (color_type == PNG_COLOR_TYPE_PALETTE) png_set_palette_to_rgb(png);
    if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8) png_set_expand_gray_1_2_4_to_8(png);
    if (png_get_valid(png, info, PNG_INFO_tRNS)) png_set_tRNS_to_alpha(png);
    if (color_type == PNG_COLOR_TYPE_RGB || color_type == PNG_COLOR_TYPE_GRAY || color_type == PNG_COLOR_TYPE_PALETTE)
        png_set_filler(png, 0xFF, PNG_FILLER_AFTER);
    if (color_type == PNG_COLOR_TYPE_GRAY || color_type == PNG_COLOR_TYPE_GRAY_ALPHA)
        png_set_gray_to_rgb(png);

    png_read_update_info(png, info);

    unsigned char* image_data = (unsigned char*)malloc((size_t)width * height * 4);
    if (!image_data) {
        png_destroy_read_struct(&png, &info, NULL);
        fclose(fp);
        return NULL;
    }
    png_bytep* row_pointers = (png_bytep*)malloc(sizeof(png_bytep) * height);
    for (int y = 0; y < height; y++) {
        row_pointers[y] = image_data + (size_t)y * width * 4;
    }
    png_read_image(png, row_pointers);
    free(row_pointers);
    png_destroy_read_struct(&png, &info, NULL);
    fclose(fp);

    *out_w = width;
    *out_h = height;
    return image_data;
}

int resource_pack_verify(const char* path, char* out_status, int max_status_len) {
    if (!path || strlen(path) == 0) {
        if (out_status) snprintf(out_status, max_status_len, "No resource pack selected.");
        return 0;
    }

    struct stat st;
    if (stat(path, &st) != 0) {
        if (out_status) snprintf(out_status, max_status_len, "Resource pack path not found on disk.");
        return 0;
    }

    int is_archive = ends_with(path, ".zip") || ends_with(path, ".jar");
    if (is_archive) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "unzip -l \"%s\" 2>/dev/null", path);
        FILE* p = popen(cmd, "r");
        if (!p) {
            if (out_status) snprintf(out_status, max_status_len, "Failed to read archive.");
            return 0;
        }

        int found_mask = 0;
        int total_textures = 0;
        char line[512];
        while (fgets(line, sizeof(line), p)) {
            if (strstr(line, "assets/minecraft/textures/block/")) {
                total_textures++;
                for (size_t i = 0; i < NUM_REQUIRED_ASSETS; i++) {
                    if (strstr(line, REQUIRED_ASSETS[i])) {
                        found_mask |= (1 << i);
                    }
                }
            }
        }
        pclose(p);

        int missing_count = 0;
        char missing_names[256] = {0};
        for (size_t i = 0; i < NUM_REQUIRED_ASSETS; i++) {
            if (!(found_mask & (1 << i))) {
                if (missing_count < 3) {
                    if (missing_count > 0) strncat(missing_names, ", ", sizeof(missing_names) - 1);
                    strncat(missing_names, REQUIRED_ASSETS[i], sizeof(missing_names) - 1);
                }
                missing_count++;
            }
        }

        if (missing_count > 0) {
            if (out_status) snprintf(out_status, max_status_len,
                "Incomplete pack: missing %d essential textures (e.g. %s)", missing_count, missing_names);
            return 0;
        }

        if (out_status) snprintf(out_status, max_status_len,
            "Valid Vanilla Pack (%d block textures found)", total_textures);
        return 1;
    } else if (S_ISDIR(st.st_mode)) {
        int missing_count = 0;
        char missing_names[256] = {0};
        for (size_t i = 0; i < NUM_REQUIRED_ASSETS; i++) {
            char check_path[1024];
            snprintf(check_path, sizeof(check_path), "%s/assets/minecraft/textures/block/%s", path, REQUIRED_ASSETS[i]);
            if (access(check_path, R_OK) != 0) {
                if (missing_count < 3) {
                    if (missing_count > 0) strncat(missing_names, ", ", sizeof(missing_names) - 1);
                    strncat(missing_names, REQUIRED_ASSETS[i], sizeof(missing_names) - 1);
                }
                missing_count++;
            }
        }

        if (missing_count > 0) {
            if (out_status) snprintf(out_status, max_status_len,
                "Incomplete directory: missing %d textures (%s)", missing_count, missing_names);
            return 0;
        }

        if (out_status) snprintf(out_status, max_status_len, "Valid Vanilla Pack Directory.");
        return 1;
    }

    if (out_status) snprintf(out_status, max_status_len, "Unsupported pack format (must be .zip, .jar, or directory).");
    return 0;
}

static void add_discovered_pack(const char* name, const char* path) {
    if (s_discovered_count >= MAX_DISCOVERED_PACKS) return;
    for (int i = 0; i < s_discovered_count; i++) {
        if (strcmp(s_discovered[i].path, path) == 0) return;
    }
    strncpy(s_discovered[s_discovered_count].name, name, 127);
    strncpy(s_discovered[s_discovered_count].path, path, MAX_PATH_LEN - 1);
    s_discovered[s_discovered_count].is_valid = resource_pack_verify(path, NULL, 0);
    s_discovered_count++;
}

static void scan_directory_for_packs(const char* dir_path) {
    DIR* d = opendir(dir_path);
    if (!d) return;
    struct dirent* entry;
    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.') continue;
        char full_path[MAX_PATH_LEN];
        snprintf(full_path, sizeof(full_path), "%s/%s", dir_path, entry->d_name);
        if (ends_with(entry->d_name, ".zip") || ends_with(entry->d_name, ".jar")) {
            add_discovered_pack(entry->d_name, full_path);
        } else {
            // Check if subfolder has assets/minecraft
            char check_sub[MAX_PATH_LEN];
            snprintf(check_sub, sizeof(check_sub), "%s/assets/minecraft/textures/block", full_path);
            if (access(check_sub, R_OK) == 0) {
                add_discovered_pack(entry->d_name, full_path);
            }
        }
    }
    closedir(d);
}

void resource_pack_discover(void) {
    s_discovered_count = 0;
    const char* home = getenv("HOME");
    if (home) {
        char mc_packs[MAX_PATH_LEN];
        snprintf(mc_packs, sizeof(mc_packs), "%s/Library/Application Support/minecraft/resourcepacks", home);
        scan_directory_for_packs(mc_packs);

        char mc_vers[MAX_PATH_LEN];
        snprintf(mc_vers, sizeof(mc_vers), "%s/Library/Application Support/minecraft/versions", home);
        DIR* d = opendir(mc_vers);
        if (d) {
            struct dirent* entry;
            while ((entry = readdir(d)) != NULL) {
                if (entry->d_name[0] == '.') continue;
                char jar_path[MAX_PATH_LEN];
                snprintf(jar_path, sizeof(jar_path), "%s/%s/%s.jar", mc_vers, entry->d_name, entry->d_name);
                if (access(jar_path, R_OK) == 0) {
                    char label[128];
                    snprintf(label, sizeof(label), "Minecraft %s Vanilla Jar", entry->d_name);
                    add_discovered_pack(label, jar_path);
                }
            }
            closedir(d);
        }
    }

    // Local project folders
    scan_directory_for_packs("resourcepacks");
    scan_directory_for_packs(".");

    // Default to first valid discovered pack
    if (strlen(s_current_pack) == 0) {
        for (int i = 0; i < s_discovered_count; i++) {
            if (s_discovered[i].is_valid) {
                resource_pack_set_current(s_discovered[i].path);
                break;
            }
        }
        if (strlen(s_current_pack) == 0 && s_discovered_count > 0) {
            resource_pack_set_current(s_discovered[0].path);
        }
    }
}

int resource_pack_get_discovered_count(void) {
    return s_discovered_count;
}

const char* resource_pack_get_discovered_name(int index) {
    if (index >= 0 && index < s_discovered_count) return s_discovered[index].name;
    return "";
}

const char* resource_pack_get_discovered_path(int index) {
    if (index >= 0 && index < s_discovered_count) return s_discovered[index].path;
    return "";
}

const char* resource_pack_get_current(void) {
    return s_current_pack;
}

void resource_pack_set_current(const char* path) {
    if (path) {
        strncpy(s_current_pack, path, MAX_PATH_LEN - 1);
        s_atlas_ready = 0;
    }
}

static void generate_fallback_tile(unsigned char* tile_rgba, int slot) {
    // Generate distinct, colored pixel-art fallback patterns
    unsigned char r = 120, g = 120, b = 120;
    switch (slot) {
        case 0: r = 128; g = 128; b = 128; break; // stone
        case 1: r = 134; g = 96; b = 67; break;   // dirt
        case 2: r = 90; g = 160; b = 50; break;   // grass top
        case 3: r = 110; g = 120; b = 60; break;  // grass side
        case 5: r = 162; g = 130; b = 78; break;  // planks
        case 6: r = 103; g = 82; b = 49; break;   // log side
        case 7: r = 168; g = 143; b = 92; break;  // log top
        case 8: r = 40; g = 110; b = 25; break;   // leaves
        case 9: r = 100; g = 100; b = 100; break; // cobble
        case 11: r = 219; g = 207; b = 153; break;// sand
        case 13: r = 200; g = 220; b = 230; break;// glass
        case 14: r = 40; g = 80; b = 200; break;  // water
        case 15: r = 200; g = 30; b = 30; break;  // poppy
        case 16: r = 240; g = 210; b = 30; break; // dandelion
        default: break;
    }

    for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
            int border = (x == 0 || y == 0 || x == 15 || y == 15);
            int noise = ((x * 7 + y * 13) % 23) - 11;
            int pr = r + noise + (border ? -20 : 0);
            int pg = g + noise + (border ? -20 : 0);
            int pb = b + noise + (border ? -20 : 0);
            if (pr < 0) pr = 0; if (pr > 255) pr = 255;
            if (pg < 0) pg = 0; if (pg > 255) pg = 255;
            if (pb < 0) pb = 0; if (pb > 255) pb = 255;
            int idx = (y * 16 + x) * 4;
            tile_rgba[idx + 0] = (unsigned char)pr;
            tile_rgba[idx + 1] = (unsigned char)pg;
            tile_rgba[idx + 2] = (unsigned char)pb;
            tile_rgba[idx + 3] = (slot == 13 ? 160 : (slot == 14 ? 180 : 255));
        }
    }
}

const unsigned char* resource_pack_build_atlas(int* out_width, int* out_height) {
    if (s_atlas_ready) {
        if (out_width) *out_width = 256;
        if (out_height) *out_height = 256;
        return s_atlas;
    }

    memset(s_atlas, 0, sizeof(s_atlas));

    char extract_dir[512] = {0};
    int is_archive = ends_with(s_current_pack, ".zip") || ends_with(s_current_pack, ".jar");

    if (is_archive) {
        system("mkdir -p build/pack_cache");
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "unzip -q -o \"%s\" \"assets/minecraft/textures/block/*\" -d build/pack_cache 2>/dev/null", s_current_pack);
        system(cmd);
        snprintf(extract_dir, sizeof(extract_dir), "build/pack_cache/assets/minecraft/textures/block");
    } else {
        snprintf(extract_dir, sizeof(extract_dir), "%s/assets/minecraft/textures/block", s_current_pack);
    }

    for (int slot = 0; slot < 33; slot++) {
        int tile_x = (slot % 16) * 16;
        int tile_y = (slot / 16) * 16;
        char file_path[1024];
        snprintf(file_path, sizeof(file_path), "%s/%s", extract_dir, ATLAS_TILES[slot]);

        int w = 0, h = 0;
        unsigned char* img = load_png_rgba(file_path, &w, &h);

        unsigned char tile_16x16[16 * 16 * 4];
        if (img && w > 0 && h > 0) {
            // Nearest-neighbor scale to 16x16
            for (int ty = 0; ty < 16; ty++) {
                for (int tx = 0; tx < 16; tx++) {
                    int src_x = (tx * w) / 16;
                    int src_y = (ty * h) / 16;
                    int src_idx = (src_y * w + src_x) * 4;
                    int dst_idx = (ty * 16 + tx) * 4;
                    tile_16x16[dst_idx + 0] = img[src_idx + 0];
                    tile_16x16[dst_idx + 1] = img[src_idx + 1];
                    tile_16x16[dst_idx + 2] = img[src_idx + 2];
                    tile_16x16[dst_idx + 3] = img[src_idx + 3];
                }
            }
            free(img);
        } else {
            generate_fallback_tile(tile_16x16, slot);
        }

        // Copy tile into atlas
        for (int row = 0; row < 16; row++) {
            int atlas_row = tile_y + row;
            int atlas_col = tile_x;
            int src_offset = row * 16 * 4;
            int dst_offset = (atlas_row * 256 + atlas_col) * 4;
            memcpy(&s_atlas[dst_offset], &tile_16x16[src_offset], 16 * 4);
        }
    }

    s_atlas_ready = 1;
    if (out_width) *out_width = 256;
    if (out_height) *out_height = 256;
    return s_atlas;
}

int resource_pack_get_tile_for_block_face(int block_protocol, int face) {
    // Protocol mapping:
    // 1: stone
    // 2: grass_block (top=2, bottom=1, sides=3)
    // 3: dirt
    // 4: cobblestone
    // 5: oak_planks
    // 7: bedrock
    // 8, 9: water (14)
    // 12: sand
    // 13: gravel
    // 17, 18: oak_log (top/bottom=7, sides=6)
    // 19: oak_leaves (8)
    // 20: glass (13)
    // 37, 38: flowers (dandelion 16, poppy 15)
    // 47: bookshelf (23)
    // 49: obsidian (24)
    // 50: torch (28)
    // 54: chest
    // 58: crafting_table (top=17, bottom=5, front=19, sides=18)
    // 61: furnace (front=20, top/bottom=22, sides=21)
    // 14, 15, 16, 56: ores
    switch (block_protocol) {
        case 1: return 0; // stone
        case 2: // grass_block
            if (face == 2) return 2; // top
            if (face == 3) return 1; // bottom (dirt)
            return 3;                // sides
        case 3: return 1; // dirt
        case 4: return 9; // cobblestone
        case 5: return 5; // oak_planks
        case 7: return 10; // bedrock
        case 8:
        case 9: return 14; // water
        case 12: return 11; // sand
        case 13: return 12; // gravel
        case 14: return 31; // gold_ore
        case 15: return 30; // iron_ore
        case 16: return 29; // coal_ore
        case 17:
        case 18: // oak_log
            if (face == 2 || face == 3) return 7; // log top
            return 6; // log side
        case 19: return 8; // oak_leaves
        case 20: return 13; // glass
        case 37: return 16; // dandelion
        case 38: return 15; // poppy
        case 47: return 23; // bookshelf
        case 49: return 24; // obsidian
        case 50: return 28; // torch
        case 56: return 32; // diamond_ore
        case 58: // crafting table
            if (face == 2) return 17;
            if (face == 3) return 5;
            if (face == 4) return 19;
            return 18;
        case 61: // furnace
            if (face == 4) return 20;
            if (face == 2 || face == 3) return 22;
            return 21;
        default:
            if (block_protocol == 0) return 0;
            return (block_protocol % 33);
    }
}

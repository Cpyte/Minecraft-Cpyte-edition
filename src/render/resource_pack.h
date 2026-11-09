#ifndef RESOURCE_PACK_H
#define RESOURCE_PACK_H

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_DISCOVERED_PACKS 32
#define MAX_PATH_LEN 512

typedef struct {
    char name[128];
    char path[MAX_PATH_LEN];
    int is_valid;
    int asset_count;
} DiscoveredPack;

void resource_pack_discover(void);
int resource_pack_get_discovered_count(void);
const char* resource_pack_get_discovered_name(int index);
const char* resource_pack_get_discovered_path(int index);

/* Verifies whether the given pack (zip/jar/dir) contains the needed vanilla assets.
 * Returns 1 on success, 0 on failure. Fills out_status with detailed message. */
int resource_pack_verify(const char* path, char* out_status, int max_status_len);

/* Returns current active pack path */
const char* resource_pack_get_current(void);
void resource_pack_set_current(const char* path);

/* Builds/loads the texture atlas (256x256 RGBA) from the current verified resource pack.
 * Returns pointer to 256*256*4 RGBA bytes. Caller does not free. */
const unsigned char* resource_pack_build_atlas(int* out_width, int* out_height);

/* Texture tile index mapping:
 * 0: stone
 * 1: dirt
 * 2: grass_block_top
 * 3: grass_block_side
 * 4: grass_block_side_overlay
 * 5: oak_planks
 * 6: oak_log
 * 7: oak_log_top
 * 8: oak_leaves
 * 9: cobblestone
 * 10: bedrock
 * 11: sand
 * 12: gravel
 * 13: glass
 * 14: water_still
 * 15: poppy
 * 16: dandelion
 * 17: crafting_table_top
 * 18: crafting_table_side
 * 19: crafting_table_front
 * 20: furnace_front
 * 21: furnace_side
 * 22: furnace_top
 * 23: bookshelf
 * 24: obsidian
 * 25: iron_block
 * 26: gold_block
 * 27: diamond_block
 * 28: torch
 * 29: coal_ore
 * 30: iron_ore
 * 31: gold_ore
 * 32: diamond_ore
 */
int resource_pack_get_tile_for_block_face(int block_protocol, int face);

#ifdef __cplusplus
}
#endif

#endif

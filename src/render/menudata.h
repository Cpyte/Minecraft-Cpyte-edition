/* Vortex - the menus' data: the files behind the world list, the server list
 * and options.txt.
 *
 * The screens in src/render/menus.c only hold what they show; this file moves
 * that to and from disk in the layout a Minecraft install already uses, so the
 * folder the client writes is a folder the original game can open. Everything
 * is plain C with stdio and one directory walk, and it uses the same tree on
 * every platform: Windows reads %APPDATA%\.minecraft, XDG data home elsewhere,
 * and both fall back to $VORTEX_HOME when it is set. */

#ifndef VT_MENUDATA_H
#define VT_MENUDATA_H

#include <stddef.h>
#include <stdint.h>

/* The Minecraft installation the client reads and writes: $VORTEX_HOME, else
 * %APPDATA%/.minecraft on Windows, else $XDG_DATA_HOME/Minecraft or
 * ~/.minecraft. Copies it into `out` and returns 0 when there was room. */
int vt_menudata_default_dir(char *out, size_t capacity);

/* Lists `dir`/saves by folder name with a last-modified date, and fills the
 * world list. Returns the number of worlds found, or -1 when the directory
 * does not exist. */
int vt_menudata_scan_worlds(const char *game_dir);

/* Reads `key:value` lines the way options.txt writes them and stores each one
 * in the menus' option table. Returns the number of lines taken. */
int vt_menudata_load_options(const char *game_dir);

/* Writes the whole option table back, one pair per line, sorted the way the
 * original client sorts it (alphabetically, by key). */
int vt_menudata_save_options(const char *game_dir);

/* servers.dat: the root compound's `servers` list, each entry a compound with
 * `ip`, `name`, `acceptTextures` and `hidden`. Replaces the in-memory list.
 * Returns the number of servers read, or -1 when the file is missing. */
int vt_menudata_load_servers(const char *game_dir);
int vt_menudata_save_servers(const char *game_dir);

/* Everything above in one call: the default directory, the player name, the
 * option table, the world list, the server list and the pack list. */
int64_t vt_menudata_open(const char *username);
char *vt_menudata_dir(void);
/* options.txt and servers.dat, written back from what the screens hold. */
int64_t vt_menudata_store(void);
/* Makes `path` the current pack and re-verifies it; 1 when it reads as valid. */
int64_t vt_menudata_apply_pack(const char *path);

/* Removes one save folder by name, refusing anything that is not a single
 * path element. 0 deleted it, -3 it was not there, anything else failed. */
int64_t vt_menudata_delete_world(const char *folder);

/* The resource packs already discovered by src/render/resource_pack.c, pushed
 * into the pack screen, with `current` marked as selected. */
void vt_menudata_fill_packs(const char *game_dir);

#endif /* VT_MENUDATA_H */

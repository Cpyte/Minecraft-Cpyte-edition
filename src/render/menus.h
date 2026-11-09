/* Vortex - the screen stack: title, world list, server list, options, pause.
 *
 * This is the menu half of the client. It owns which screen is visible, the
 * widget layout of each screen, and the selections the player makes, and it
 * turns a click into one action code per frame for whoever runs the client
 * loop. It never talks to a server, opens a file or touches Vulkan: the lists
 * it shows and the settings it edits are handed in from outside, and the
 * consequences (join this world, connect to this server, save options.txt)
 * belong to the caller.
 *
 * Screens are named after what the player sees, and going "back" returns to
 * the screen recorded when the current one was opened - the same nested
 * structure the original client uses, so Options reached from Pause goes back
 * to Pause rather than to the title. */

#ifndef VT_MENUS_H
#define VT_MENUS_H

#include <stdint.h>

/* One action, taken since the last frame, that the caller must act on. */
#define VT_MENU_ACTION_NONE              0
/* Start an offline single-player game in the world named by
 * vt_menus_action_text(), embedded server included when that text is empty
 * and the world has to be created first. */
#define VT_MENU_ACTION_SINGLEPLAYER      1
/* Create a world from the create-world form: name in
 * vt_menus_action_text(), seed in vt_menus_action_long(), game mode and
 * difficulty in vt_menus_action_text2(). */
#define VT_MENU_ACTION_CREATE_WORLD      2
/* Connect to the server at vt_menus_action_text2() ("host:port"), the list
 * index being vt_menus_action_index(). */
#define VT_MENU_ACTION_MULTIPLAYER       3
/* The direct-connect form, host:port in vt_menus_action_text2(). */
#define VT_MENU_ACTION_DIRECT_CONNECT    4
/* The player pressed Done on an options screen: read the table out with
 * vt_menus_option_* and write it to options.txt. */
#define VT_MENU_ACTION_OPTIONS_SAVED     5
/* The player picked a different resource pack; rebuild the atlases and
 * re-verify. */
#define VT_MENU_ACTION_RELOAD_ASSETS     6
/* Leave the current game and show the title screen. */
#define VT_MENU_ACTION_RETURN_TO_MENU    7
/* Leave the current game and, if the world was created this session, keep it
 * on disk: the caller stops the embedded server. */
#define VT_MENU_ACTION_DISCONNECT        8
/* The window close request, offered as an action as well as through the
 * renderer's own poll return value. */
#define VT_MENU_ACTION_QUIT              9
/* Rebuild the server list: clear it with vt_menus_clear_servers() and push
 * rows back, plus a LAN scan. */
#define VT_MENU_ACTION_REFRESH_SERVERS  10
/* Save the in-memory server list, after an Add or Edit. */
#define VT_MENU_ACTION_SAVE_SERVERS     11
/* A local text file world list is not read here; the caller fills it in. This
 * action means "ask me for the saves again". */
#define VT_MENU_ACTION_REFRESH_WORLDS   12
/* The chat prompt closed with Enter; the line is vt_menus_action_text(). */
#define VT_MENU_ACTION_SEND_CHAT        17
/* The demo landscape, no server involved. */
#define VT_MENU_ACTION_DEMO             13
/* Delete the selected world / server; the caller removes it from disk and
 * then refreshes the list. */
#define VT_MENU_ACTION_DELETE_WORLD     14
#define VT_MENU_ACTION_DELETE_SERVER    15
/* "Respawn" on the death screen: the caller sends the respawn packet. */
#define VT_MENU_ACTION_RESPAWN          16

/* --- input -------------------------------------------------------------
 * The renderer accumulates what happens between frames and the draw call
 * consumes it, because an immediate-mode widget can only answer "was I
 * clicked" while it is being drawn. */
void vt_menus_set_mouse(int x, int y, int down);
void vt_menus_add_click(int x, int y);
void vt_menus_add_wheel(int delta);
void vt_menus_add_key(int vt_gui_key_code);
void vt_menus_add_text(const char *utf8);

/* --- drawing -----------------------------------------------------------
 * Draws the visible screen and returns its action, if any. Called once per
 * frame: for menus when the world is not shown, and again over the HUD when
 * the pause or death screen is up. */
int vt_menus_draw(void);

/* 1 while a menu occupies the pointer, so the renderer knows not to feed the
 * world's own clicks or grab the mouse. */
int vt_menus_is_grabbing(void);

/* The game took over: hide the menu screens. `overlay` keeps the pause or
 * death screen visible above the world. */
void vt_menus_set_ingame(int playing, int overlay);
/* Which overlay the in-game path should draw: 0 none, 1 pause, 2 death,
 * 3 the chat prompt. */
void vt_menus_set_overlay(int kind);
/* Opens the chat prompt with an empty line, the T key. */
void vt_menus_open_chat(void);
int vt_menus_overlay_kind(void);

/* --- action payload ---------------------------------------------------- */
const char *vt_menus_action_text(void);
const char *vt_menus_action_text2(void);
int64_t vt_menus_action_long(void);
int vt_menus_action_index(void);

/* --- status shown by the connecting screen ----------------------------- */
/* The death screen, and the pause menu's note line. */
void vt_menus_set_hardcore(int hardcore);
void vt_menus_set_death_message(const char *text);

void vt_menus_set_status(const char *text);
/* The text under the title on the main menu, eg. the account and version. */
void vt_menus_set_subtitle(const char *text);

/* --- lists fed in by the caller ---------------------------------------- */
void vt_menus_clear_worlds(void);
void vt_menus_add_world(const char *name, const char *folder, const char *info);
int vt_menus_world_count(void);
const char *vt_menus_world_name(int index);
const char *vt_menus_world_folder(int index);

void vt_menus_clear_servers(void);
void vt_menus_add_server(const char *name, const char *host, int port);
int vt_menus_server_count(void);
const char *vt_menus_server_name(int index);
const char *vt_menus_server_host(int index);
int vt_menus_server_port(int index);
/* Filled by the caller after a refresh, indexed like the list rows. */
void vt_menus_set_server_ping(int index, int milliseconds);

/* --- the option table, keyed like options.txt -------------------------- */
const char *vt_menus_get_option(const char *key, const char *fallback);
void vt_menus_set_option(const char *key, const char *value);
int vt_menus_option_count(void);
const char *vt_menus_option_key(int index);
const char *vt_menus_option_value(int index);
int vt_menus_options_dirty(void);
void vt_menus_options_clean(void);
/* Filled from the player directory by the caller; also the account name the
 * menus show. */
void vt_menus_set_player_name(const char *name);

/* --- the pack screen's list ------------------------------------------ */
#define MAX_PACKS_PATH 256

void vt_menus_clear_packs(void);
/* `path` is what the caller opens when the row is clicked; the action carries
 * it, the label only ever reaches the screen. */
void vt_menus_add_pack(const char *label, const char *path, int selected);

#endif /* VT_MENUS_H */

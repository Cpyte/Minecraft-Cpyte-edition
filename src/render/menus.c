/* Vortex - the screen stack. See menus.h for the contract; the notes here
 * only record why a layout is where it is.
 *
 * The geometry follows the original client: 200 by 20 buttons in a centred
 * column 24 units apart, a heading 12 units above it, the options screen split
 * into a page list and a field grid, and the pause menu as two columns of
 * 98-unit buttons. All of it is in logical GUI pixels, so a 4K window and a
 * 1280x720 one put the same button on the same row. */

#include "menus.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gui.h"

enum {
    SCR_TITLE, SCR_SINGLE, SCR_CREATE, SCR_MULTI, SCR_DIRECT, SCR_SERVER_EDIT,
    SCR_OPTIONS, SCR_CONNECTING, SCR_PAUSE, SCR_DEATH
};

enum { OPT_VIDEO, OPT_SOUND, OPT_CONTROLS, OPT_CHAT, OPT_ACCESS,
       OPT_LANGUAGE, OPT_PACKS, OPT_COUNT };

#define ROW_H       20.0f
#define ROW_GAP     24.0f
#define COL_W      200.0f
#define HALF_COL    98.0f
#define MAX_WORLDS    32
#define MAX_SERVERS   64
#define MAX_PACKS     32

typedef struct { char name[64]; char folder[96]; char info[64]; } World;
typedef struct { char name[64]; char host[128]; int port; int ping; } Server;
typedef struct { char key[32]; char value[48]; } Option;

/* ------------------------------------------------------------------ state */

static World s_worlds[MAX_WORLDS];
static int s_world_count, s_world_sel, s_world_scroll;
static Server s_servers[MAX_SERVERS];
static int s_server_count, s_server_sel, s_server_scroll, s_edit_index;
static char s_pack_names[MAX_PACKS][64];
static char s_pack_paths[MAX_PACKS][MAX_PACKS_PATH];
static int s_pack_count, s_pack_sel, s_pack_scroll;

static Option s_options[64];
static int s_option_count, s_options_dirty;

static int s_screen = SCR_TITLE;
static int s_back[8], s_back_count;
static int s_option_page = OPT_VIDEO;

static int s_ingame, s_overlay;
static int s_action, s_action_index;
static int64_t s_action_long;
static char s_action_text[128], s_action_text2[128];

static char s_status[128] = "Connecting";
static char s_subtitle[128];
static double s_frame_count;
static int s_hardcore, s_action_note;
static char s_death_message[96];
static char s_chat_text[256];

/* The create-world and server forms edit these; the caller only ever sees a
 * finished action, never a half-typed field. */
static char s_world_name[64] = "New World";
static char s_world_seed[64];
static int s_world_mode, s_world_difficulty = 2, s_world_hardcore, s_world_bonus;
static char s_server_name[64], s_server_host[128], s_server_port[16] = "25565";
static char s_direct[160];
static int s_direct_new;

/* Between-frame input, consumed by vt_menus_draw: an immediate-mode widget can
 * only answer "was I clicked" while it is being drawn. */
static int s_mx, s_my, s_down, s_clicked, s_wheel, s_key;
static char s_typed[8];

static const char *const PAGE_NAMES[OPT_COUNT] = {
    "Video Settings", "Music and Sounds", "Controls", "Chat Settings",
    "Accessibility", "Language", "Resource Packs"
};
static const char *const MODE_NAMES[] = {"Survival", "Creative", "Adventure", "Spectator"};
static const char *const DIFF_NAMES[] = {"Peaceful", "Easy", "Normal", "Hard", "Hardcore"};
static const char *const SCALE_NAMES[] = {"Auto", "1", "2", "3", "4", "5", "6"};
static const char *const CHAT_NAMES[] = {"Shown", "Hidden", "Commands Only"};
static const char *const LANG_NAMES[] = {
    "en_us English", "de_de Deutsch", "es_es Espanol", "fr_fr Francais",
    "it_it Italiano", "ja_jp Japanese", "ko_kr Korean", "nl_nl Nederlands",
    "pt_br Portugues", "ru_ru Russian", "zh_cn Chinese", "en_au Aussie",
    "en_gb British"
};

#define MODE_COUNT   4
#define DIFF_COUNT   5
#define SCALE_COUNT  7
#define LANG_COUNT   ((int)(sizeof LANG_NAMES / sizeof LANG_NAMES[0]))

/* ------------------------------------------------------- option key/value */

static const char *opt_find(const char *key, const char *fallback) {
    int i;
    for (i = 0; i < s_option_count; i++)
        if (strcmp(s_options[i].key, key) == 0) return s_options[i].value;
    return fallback;
}

static void opt_set(const char *key, const char *value) {
    Option *slot = NULL;
    int i;
    for (i = 0; i < s_option_count; i++)
        if (strcmp(s_options[i].key, key) == 0) { slot = &s_options[i]; break; }
    if (slot == NULL) {
        if (s_option_count < (int)(sizeof s_options / sizeof s_options[0]))
            slot = &s_options[s_option_count++];
        else
            return;
        snprintf(slot->key, sizeof slot->key, "%s", key);
        slot->value[0] = 0;
    }
    if (strcmp(slot->value, value) != 0) {
        snprintf(slot->value, sizeof slot->value, "%s", value);
        s_options_dirty = 1;
    }
}

static int opt_int(const char *key, int fallback) {
    const char *v = opt_find(key, NULL);
    return v ? atoi(v) : fallback;
}

static float opt_float(const char *key, float fallback) {
    const char *v = opt_find(key, NULL);
    return v ? (float)atof(v) : fallback;
}

static int opt_flag(const char *key, int fallback) {
    const char *v = opt_find(key, NULL);
    if (v == NULL) return fallback;
    return strcmp(v, "true") == 0 || strcmp(v, "1") == 0;
}

static void opt_write(const char *key, const char *format, ...) {
    char value[48];
    va_list args;
    va_start(args, format);
    vsnprintf(value, sizeof value, format, args);
    va_end(args);
    opt_set(key, value);
}

/* A default table, so a first run with no options.txt still lays out the
 * classic values. The keys are the ones the original client writes. */
static void seed_defaults(void) {
    static const char *const pairs[][2] = {
        {"renderDistance", "12"}, {"fov", "70.0"}, {"mouseSensitivity", "0.5"},
        {"guiScale", "0"}, {"fullscreen", "false"}, {"enableVsync", "true"},
        {"showDebugInfo", "false"}, {"masterVolume", "1.0"},
        {"musicVolume", "0.5"}, {"soundVolume", "1.0"},
        {"chatVisibility", "0"}, {"chatOpacity", "1.0"}, {"chatWidth", "1.0"},
        {"textBackgroundEnabled", "true"}, {"hideHealthBar", "false"},
        {"invertYMouse", "false"}, {"viewBobbing", "true"}, {"autoSave", "true"},
        {"difficulty", "2"}, {"gamemode", "0"}, {"languageCode", "en_us"},
        {"hitboxOutline", "true"}, {"reducedMotion", "false"},
        {"dynamicFov", "false"}, {"playerNames", "true"},
        {"keepInventory", "false"}, {"playerName", ""}
    };
    size_t i;
    if (s_option_count > 0) return;
    for (i = 0; i < sizeof pairs / sizeof pairs[0]; i++) opt_set(pairs[i][0], pairs[i][1]);
    s_options_dirty = 0;
}

/* ------------------------------------------------------------- navigation */

static void open_screen(int screen, int came_from) {
    if (s_back_count < (int)(sizeof s_back / sizeof s_back[0]))
        s_back[s_back_count++] = came_from;
    s_screen = screen;
    vt_gui_reset();
}

static void go_back(void) {
    s_screen = s_back_count > 0 ? s_back[--s_back_count] : SCR_TITLE;
    vt_gui_reset();
}

static void claim(int action) {
    if (s_action) return;
    s_action = action;
    s_action_text[0] = 0;
    s_action_text2[0] = 0;
    s_action_long = 0;
    s_action_index = -1;
}

static void claim_text(int action, const char *text) {
    claim(action);
    if (s_action == action && text) snprintf(s_action_text, sizeof s_action_text, "%s", text);
}

static void claim_text2(int action, const char *a, const char *b) {
    claim_text(action, a);
    if (s_action == action && b) snprintf(s_action_text2, sizeof s_action_text2, "%s", b);
}

/* ---------------------------------------------------------------- helpers */

static float logical_w(void) { return vt_gui_logical_width(); }
static float logical_h(void) { return vt_gui_logical_height(); }

/* A button in the centred column. */
static int center_button(const char *id, float y, const char *label) {
    return vt_gui_button(id, (logical_w() - COL_W) * 0.5f, y, COL_W, ROW_H, label);
}

static void splash_text(void) {
    static const char *const lines[] = {
        "Also try Horizon!", "100% Cpyte!", "Now with an embedded server!",
        "Vulkan powered!", "Protocol 777!", "Zero-copy pipe!", "Made in Cpyte!"
    };
    int count = (int)(sizeof lines / sizeof lines[0]);
    const char *line = lines[(int)(s_frame_count / 30) % count];
    float x = logical_w() - vt_gui_text_width(line) - 12.0f;
    if (x < logical_w() * 0.5f + 44.0f) x = logical_w() * 0.5f + 44.0f;
    vt_gui_text(x, 30.0f, line, 1.0f, 1.0f, 0.0f);
}

static void corner_labels(void) {
    const char *name = opt_find("playerName", "");
    char line[96];
    snprintf(line, sizeof line, "Vortex 26.3 %s", name[0] ? name : s_subtitle);
    vt_gui_text(3.0f, logical_h() - 11.0f, line, VT_GUI_TEXT_DIM);
    vt_gui_text(logical_w() - vt_gui_text_width("Minecraft 26.3") - 3.0f,
                logical_h() - 11.0f, "Minecraft 26.3", VT_GUI_TEXT_DIM);
}

/* A full-height list of strings built from parallel arrays. */
static int name_list(const char *id, float x, float y, float w, float h,
                     const char *const *names, int count, int *selected, int *scroll) {
    return vt_gui_list(id, x, y, w, h, names, count, selected, scroll);
}

/* ---------------------------------------------------------------- screens */

static void draw_title(void) {
    float y = logical_h() * 0.42f;

    vt_gui_text_centered(logical_h() * 0.16f, "Minecraft", 1.0f, 1.0f, 1.0f);
    splash_text();

    if (center_button("title.single", y, "Singleplayer")) {
        claim(VT_MENU_ACTION_REFRESH_WORLDS);
        open_screen(SCR_SINGLE, SCR_TITLE);
    }
    if (center_button("title.multi", y + ROW_GAP, "Multiplayer")) {
        claim(VT_MENU_ACTION_REFRESH_SERVERS);
        open_screen(SCR_MULTI, SCR_TITLE);
    }
    if (center_button("title.options", y + ROW_GAP * 2.0f, "Options..."))
        open_screen(SCR_OPTIONS, SCR_TITLE);

    {
        float half = (logical_w() - 40.0f) * 0.25f;
        float row = logical_h() - ROW_H - 6.0f;
        if (vt_gui_button("title.packs", 6.0f, row, half, ROW_H, "Resource Packs")) {
            s_option_page = OPT_PACKS;
            open_screen(SCR_OPTIONS, SCR_TITLE);
        }
        if (vt_gui_button("title.language", 12.0f + half, row, half, ROW_H, "Language")) {
            s_option_page = OPT_LANGUAGE;
            open_screen(SCR_OPTIONS, SCR_TITLE);
        }
        if (vt_gui_button("title.demo", 18.0f + half * 2.0f, row, half, ROW_H, "Demo World"))
            claim(VT_MENU_ACTION_DEMO);
        if (vt_gui_button("title.quit", 24.0f + half * 3.0f, row, half, ROW_H, "Quit Game"))
            claim(VT_MENU_ACTION_QUIT);
    }
    corner_labels();
}

static void draw_single(void) {
    float w = logical_w(), h = logical_h();
    static const char *rows[MAX_WORLDS];
    static char labels[MAX_WORLDS][128];
    int i, hit;

    vt_gui_text_centered(12.0f, "Select World", VT_GUI_TEXT);
    for (i = 0; i < s_world_count; i++) {
        snprintf(labels[i], sizeof labels[i], "%s  -  %s", s_worlds[i].name, s_worlds[i].info);
        rows[i] = labels[i];
    }
    if (s_world_count == 0)
        vt_gui_text_centered(h * 0.45f, "No worlds found. Create one to play.", VT_GUI_TEXT_DIM);

    if (s_key == VT_GUI_KEY_UP && s_world_sel > 0) s_world_sel--;
    if (s_key == VT_GUI_KEY_DOWN && s_world_sel < s_world_count - 1) s_world_sel++;
    hit = name_list("worlds", 16.0f, 32.0f, w - 32.0f, h - 32.0f - 52.0f,
                    rows, s_world_count, &s_world_sel, &s_world_scroll);
    if ((hit >= 0 || s_key == VT_GUI_KEY_ENTER) && s_world_count > 0) {
        claim_text2(VT_MENU_ACTION_SINGLEPLAYER, s_worlds[s_world_sel].folder,
                    s_worlds[s_world_sel].name);
        open_screen(SCR_CONNECTING, SCR_SINGLE);
    }

    {
        float col = (w - 40.0f) * 0.25f;
        float row = h - ROW_H - 6.0f;
        if (vt_gui_button("world.create", 6.0f, row, col * 2.0f + 4.0f, ROW_H, "Create New World"))
            open_screen(SCR_CREATE, SCR_SINGLE);
        if (s_world_count > 0 &&
            vt_gui_button("world.delete", 14.0f + col * 2.0f, row, col, ROW_H, "Delete")) {
            claim_text(VT_MENU_ACTION_DELETE_WORLD, s_worlds[s_world_sel].folder);
            s_action_index = s_world_sel;
            if (s_world_sel < s_world_count) {
                int j;
                for (j = s_world_sel; j + 1 < s_world_count; j++) s_worlds[j] = s_worlds[j + 1];
                s_world_count--;
                if (s_world_sel >= s_world_count) s_world_sel = s_world_count - 1;
                if (s_world_sel < 0) s_world_sel = 0;
            }
        }
        if (vt_gui_button("world.back", w - 6.0f - col, row, col, ROW_H, "Back")) go_back();
    }
}

static void draw_create(void) {
    float w = logical_w(), h = logical_h();
    float x = (w - COL_W) * 0.5f;
    float y = 28.0f;
    int keep = opt_flag("keepInventory", 0);

    vt_gui_text_centered(10.0f, "Create New World", VT_GUI_TEXT);

    vt_gui_text(x, y, "World Name", VT_GUI_TEXT);
    vt_gui_field("create.name", x, y + 10.0f, COL_W, ROW_H, s_world_name, sizeof s_world_name);
    y += ROW_H + 26.0f;

    vt_gui_text(x, y, "Seed (optional, blank is random)", VT_GUI_TEXT);
    vt_gui_field("create.seed", x, y + 10.0f, COL_W, ROW_H, s_world_seed, sizeof s_world_seed);
    y += ROW_H + 26.0f;

    vt_gui_cycle("create.mode", x, y, COL_W, ROW_H, "Game Mode", MODE_NAMES, MODE_COUNT, &s_world_mode);
    y += ROW_GAP;
    vt_gui_cycle("create.diff", x, y, COL_W, ROW_H, "Difficulty", DIFF_NAMES, DIFF_COUNT, &s_world_difficulty);
    y += ROW_GAP;
    vt_gui_toggle("create.keep", x, y, COL_W, ROW_H, "Keep Inventory", &keep);
    opt_write("keepInventory", keep ? "true" : "false");
    y += ROW_GAP;
    vt_gui_toggle("create.hard", x, y, COL_W * 0.5f - 2.0f, ROW_H, "Hardcore", &s_world_hardcore);
    vt_gui_toggle("create.bonus", x + COL_W * 0.5f + 2.0f, y, COL_W * 0.5f - 2.0f, ROW_H,
                  "Bonus Chest", &s_world_bonus);

    if (center_button("create.make", h - ROW_H * 2.0f - 12.0f, "Create New World")) {
        char *end = NULL;
        long long numeric = strtoll(s_world_seed, &end, 10);
        claim_text(VT_MENU_ACTION_CREATE_WORLD, s_world_name);
        snprintf(s_action_text2, sizeof s_action_text2, "%s", s_world_seed);
        s_action_long = (end != s_world_seed && s_world_seed[0] != 0) ? (int64_t)numeric : 0;
        /* The rest of the form travels as difficulty | hardcore<<3 |
         * bonus<<4, which is all an embedded server needs to start. */
        s_action_index = s_world_difficulty | (s_world_hardcore << 3) | (s_world_bonus << 4);
        opt_write("gamemode", "%d", s_world_mode);
        opt_write("difficulty", "%d", s_world_difficulty);
        open_screen(SCR_CONNECTING, SCR_SINGLE);
    }
    if (center_button("create.back", h - ROW_H - 6.0f, "Back")) go_back();
}

static void draw_multi(void) {
    float w = logical_w(), h = logical_h();
    static const char *rows[MAX_SERVERS];
    static char labels[MAX_SERVERS][192];
    int i, hit;

    vt_gui_text_centered(12.0f, "Multiplayer", VT_GUI_TEXT);
    for (i = 0; i < s_server_count; i++) {
        char ping[24];
        if (s_servers[i].ping < 0) snprintf(ping, sizeof ping, "ping");
        else if (s_servers[i].ping > 999) snprintf(ping, sizeof ping, "timeout");
        else snprintf(ping, sizeof ping, "%d ms", s_servers[i].ping);
        snprintf(labels[i], sizeof labels[i], "%s   %s:%d   %s", s_servers[i].name,
                 s_servers[i].host, s_servers[i].port, ping);
        rows[i] = labels[i];
    }
    if (s_server_count == 0)
        vt_gui_text_centered(h * 0.45f, "No servers yet. Add one or connect directly.",
                             VT_GUI_TEXT_DIM);

    if (s_key == VT_GUI_KEY_UP && s_server_sel > 0) s_server_sel--;
    if (s_key == VT_GUI_KEY_DOWN && s_server_sel < s_server_count - 1) s_server_sel++;
    hit = name_list("servers", 16.0f, 32.0f, w - 32.0f, h - 32.0f - 52.0f,
                    rows, s_server_count, &s_server_sel, &s_server_scroll);
    if ((hit >= 0 || s_key == VT_GUI_KEY_ENTER) && s_server_count > 0) {
        char address[160];
        snprintf(address, sizeof address, "%s:%d", s_servers[s_server_sel].host,
                 s_servers[s_server_sel].port);
        claim_text2(VT_MENU_ACTION_MULTIPLAYER, s_servers[s_server_sel].name, address);
        s_action_index = s_server_sel;
        open_screen(SCR_CONNECTING, SCR_MULTI);
    }

    {
        float col = (w - 40.0f) * 0.22f;
        float row = h - ROW_H - 6.0f;
        float x = 6.0f;
        if (vt_gui_button("srv.add", x, row, col * 1.4f, ROW_H, "Add Server")) {
            s_direct_new = 1;
            s_edit_index = s_server_count;
            snprintf(s_server_name, sizeof s_server_name, "%s", "New Server");
            snprintf(s_server_host, sizeof s_server_host, "%s", "127.0.0.1");
            snprintf(s_server_port, sizeof s_server_port, "%s", "25565");
            open_screen(SCR_SERVER_EDIT, SCR_MULTI);
        }
        x += col * 1.4f + 4.0f;
        if (vt_gui_button("srv.edit", x, row, col, ROW_H, "Edit")) {
            if (s_server_count > 0) {
                s_direct_new = 0;
                s_edit_index = s_server_sel;
                snprintf(s_server_name, sizeof s_server_name, "%s", s_servers[s_server_sel].name);
                snprintf(s_server_host, sizeof s_server_host, "%s", s_servers[s_server_sel].host);
                snprintf(s_server_port, sizeof s_server_port, "%d", s_servers[s_server_sel].port);
                open_screen(SCR_SERVER_EDIT, SCR_MULTI);
            }
        }
        x += col + 4.0f;
        if (s_server_count > 0 && vt_gui_button("srv.delete", x, row, col, ROW_H, "Delete")) {
            char address[160];
            snprintf(address, sizeof address, "%s:%d", s_servers[s_server_sel].host,
                     s_servers[s_server_sel].port);
            claim_text2(VT_MENU_ACTION_DELETE_SERVER, s_servers[s_server_sel].name, address);
            s_action_index = s_server_sel;
            for (i = s_server_sel; i + 1 < s_server_count; i++) s_servers[i] = s_servers[i + 1];
            s_server_count--;
            if (s_server_sel >= s_server_count) s_server_sel = s_server_count - 1;
            if (s_server_sel < 0) s_server_sel = 0;
        }
        x += col + 4.0f;
        if (vt_gui_button("srv.refresh", x, row, col * 0.9f, ROW_H, "Refresh"))
            claim(VT_MENU_ACTION_REFRESH_SERVERS);
        if (vt_gui_button("srv.direct", x + col * 0.9f + 4.0f, row, col * 1.3f, ROW_H,
                          "Direct Connect"))
            open_screen(SCR_DIRECT, SCR_MULTI);
    }
}

static void parse_address(const char *text, char *host, size_t host_cap, int *port) {
    const char *colon = strrchr(text, ':');
    *port = 25565;
    if (colon && colon[1]) {
        size_t n = (size_t)(colon - text);
        if (n >= host_cap) n = host_cap - 1;
        memcpy(host, text, n);
        host[n] = 0;
        *port = atoi(colon + 1);
        if (*port <= 0 || *port > 65535) *port = 25565;
    } else {
        snprintf(host, host_cap, "%s", text);
    }
    if (host[0] == 0) snprintf(host, host_cap, "%s", "127.0.0.1");
}

static void connect_to(const char *address, int action, const char *label) {
    char host[160];
    int port;
    parse_address(address, host, sizeof host, &port);
    claim_text2(action, label, host);
    s_action_long = port;
    snprintf(s_action_text2, sizeof s_action_text2, "%s:%d", host, port);
    open_screen(SCR_CONNECTING, SCR_MULTI);
}

static void draw_direct(void) {
    float h = logical_h();
    float x = (logical_w() - COL_W) * 0.5f;

    vt_gui_text_centered(20.0f, "Direct Connection", VT_GUI_TEXT);
    vt_gui_text(x, 48.0f, "Server Address (host or host:port)", VT_GUI_TEXT);
    if (vt_gui_field("direct.host", x, 60.0f, COL_W, ROW_H, s_direct, sizeof s_direct) == 2 &&
        s_direct[0])
        connect_to(s_direct, VT_MENU_ACTION_DIRECT_CONNECT, "Direct");
    if (center_button("direct.go", h - ROW_H * 2.0f - 12.0f, "Connect"))
        connect_to(s_direct[0] ? s_direct : "127.0.0.1", VT_MENU_ACTION_DIRECT_CONNECT, "Direct");
    if (center_button("direct.back", h - ROW_H - 6.0f, "Back")) go_back();
}

static void draw_server_edit(void) {
    float h = logical_h();
    float x = (logical_w() - COL_W) * 0.5f;

    vt_gui_text_centered(20.0f, s_direct_new ? "Add Server" : "Edit Server", VT_GUI_TEXT);
    vt_gui_text(x, 44.0f, "Server Name", VT_GUI_TEXT);
    vt_gui_field("edit.name", x, 56.0f, COL_W, ROW_H, s_server_name, sizeof s_server_name);
    vt_gui_text(x, 88.0f, "Server Address", VT_GUI_TEXT);
    vt_gui_field("edit.host", x, 100.0f, COL_W, ROW_H, s_server_host, sizeof s_server_host);
    vt_gui_text(x, 132.0f, "Port", VT_GUI_TEXT);
    vt_gui_field("edit.port", x, 144.0f, COL_W * 0.4f, ROW_H, s_server_port, sizeof s_server_port);

    if (center_button("edit.done", h - ROW_H * 2.0f - 12.0f, "Done")) {
        int port = atoi(s_server_port);
        if (port <= 0 || port > 65535) port = 25565;
        if (s_edit_index <= s_server_count && s_edit_index < MAX_SERVERS) {
            if (s_edit_index == s_server_count) s_server_count++;
            snprintf(s_servers[s_edit_index].name, sizeof s_servers[s_edit_index].name, "%s", s_server_name);
            snprintf(s_servers[s_edit_index].host, sizeof s_servers[s_edit_index].host, "%s", s_server_host);
            s_servers[s_edit_index].port = port;
            s_servers[s_edit_index].ping = -1;
            s_server_sel = s_edit_index;
            claim(VT_MENU_ACTION_SAVE_SERVERS);
            s_action_index = s_edit_index;
        }
        go_back();
    }
    if (center_button("edit.cancel", h - ROW_H - 6.0f, "Cancel")) go_back();
}

static void draw_options(void) {
    float w = logical_w(), h = logical_h();
    float x = 184.0f;
    float col = (w - x - 16.0f) * 0.5f - 2.0f;
    float y = 40.0f;
    int i;
    static const char *rows[OPT_COUNT];

    vt_gui_text_centered(10.0f, "Options", VT_GUI_TEXT);
    for (i = 0; i < OPT_COUNT; i++) rows[i] = PAGE_NAMES[i];
    name_list("pages", 16.0f, 32.0f, 160.0f, h - 32.0f - 52.0f, rows, OPT_COUNT,
              &s_option_page, NULL);

    if (s_option_page == OPT_VIDEO) {
        float dist = opt_float("renderDistance", 12.0f);
        float fov = opt_float("fov", 70.0f);
        int scale = opt_int("guiScale", 0), full = opt_flag("fullscreen", 0);
        int vsync = opt_flag("enableVsync", 1), debug = opt_flag("showDebugInfo", 0);

        vt_gui_slider("opt.dist", x, y, col * 2.0f + 4.0f, ROW_H, "Render Distance",
                      &dist, 2.0f, 32.0f, " chunks");
        opt_write("renderDistance", "%d", (int)dist);
        y += ROW_GAP;
        vt_gui_slider("opt.fov", x, y, col * 2.0f + 4.0f, ROW_H, "Field of View",
                      &fov, 30.0f, 110.0f, "");
        opt_write("fov", "%.1f", fov);
        y += ROW_GAP;
        vt_gui_cycle("opt.scale", x, y, col, ROW_H, "GUI Scale", SCALE_NAMES, SCALE_COUNT, &scale);
        opt_write("guiScale", "%d", scale);
        vt_gui_toggle("opt.full", x + col + 4.0f, y, col, ROW_H, "Fullscreen", &full);
        opt_write("fullscreen", full ? "true" : "false");
        y += ROW_GAP;
        vt_gui_toggle("opt.vsync", x, y, col, ROW_H, "Use VSync", &vsync);
        opt_write("enableVsync", vsync ? "true" : "false");
        vt_gui_toggle("opt.debug", x + col + 4.0f, y, col, ROW_H, "Show Debug Info", &debug);
        opt_write("showDebugInfo", debug ? "true" : "false");
        y += ROW_GAP;
        vt_gui_text(x, y, "Render distance changes take effect as the", VT_GUI_TEXT_DIM);
        vt_gui_text(x, y + 10.0f, "world loads. GUI scale is applied at once.", VT_GUI_TEXT_DIM);
    } else if (s_option_page == OPT_SOUND) {
        static const char *const keys[] = {"masterVolume", "musicVolume", "soundVolume"};
        static const char *const names[] = {"Master Volume", "Music", "Sound Effects"};
        for (i = 0; i < 3; i++) {
            float value = opt_float(keys[i], 1.0f);
            vt_gui_slider("opt.vol", x, y + ROW_GAP * (float)i, col * 2.0f + 4.0f, ROW_H,
                          names[i], &value, 0.0f, 1.0f, "");
            opt_write(keys[i], "%.2f", value);
        }
        y += ROW_GAP * 3.0f + 8.0f;
        vt_gui_text(x, y, "Audio output is not connected yet; the values", VT_GUI_TEXT_DIM);
        vt_gui_text(x, y + 10.0f, "are stored in options.txt for it.", VT_GUI_TEXT_DIM);
    } else if (s_option_page == OPT_CONTROLS) {
        float sens = opt_float("mouseSensitivity", 0.5f);
        int invert = opt_flag("invertYMouse", 0), bob = opt_flag("viewBobbing", 1);

        vt_gui_slider("opt.sens", x, y, col * 2.0f + 4.0f, ROW_H, "Mouse Sensitivity",
                      &sens, 0.0f, 1.0f, "");
        opt_write("mouseSensitivity", "%.2f", sens);
        y += ROW_GAP;
        vt_gui_toggle("opt.invert", x, y, col, ROW_H, "Invert Mouse", &invert);
        opt_write("invertYMouse", invert ? "true" : "false");
        vt_gui_toggle("opt.bob", x + col + 4.0f, y, col, ROW_H, "View Bobbing", &bob);
        opt_write("viewBobbing", bob ? "true" : "false");
        y += ROW_GAP + 6.0f;
        vt_gui_text(x, y, "W/A/S/D move, SPACE jump, SHIFT sneak,", VT_GUI_TEXT_DIM);
        vt_gui_text(x, y + 10.0f, "T chat, ESC pause, F5 recentre the camera.", VT_GUI_TEXT_DIM);
    } else if (s_option_page == OPT_CHAT) {
        int visibility = opt_int("chatVisibility", 0), names = opt_flag("playerNames", 1);
        int background = opt_flag("textBackgroundEnabled", 1);
        float width = opt_float("chatWidth", 1.0f), opacity = opt_float("chatOpacity", 1.0f);

        vt_gui_cycle("opt.chatvis", x, y, col, ROW_H, "Chat", CHAT_NAMES, 3, &visibility);
        opt_write("chatVisibility", "%d", visibility);
        vt_gui_toggle("opt.names", x + col + 4.0f, y, col, ROW_H, "Show Player Names", &names);
        opt_write("playerNames", names ? "true" : "false");
        y += ROW_GAP;
        vt_gui_toggle("opt.bg", x, y, col * 2.0f + 4.0f, ROW_H, "Background Opacity", &background);
        opt_write("textBackgroundEnabled", background ? "true" : "false");
        y += ROW_GAP;
        vt_gui_slider("opt.chatw", x, y, col * 2.0f + 4.0f, ROW_H, "Chat Width",
                      &width, 0.5f, 1.0f, "");
        opt_write("chatWidth", "%.2f", width);
        y += ROW_GAP;
        vt_gui_slider("opt.chato", x, y, col * 2.0f + 4.0f, ROW_H, "Chat Opacity",
                      &opacity, 0.3f, 1.0f, "");
        opt_write("chatOpacity", "%.2f", opacity);
    } else if (s_option_page == OPT_ACCESS) {
        int reduced = opt_flag("reducedMotion", 0), dynfov = opt_flag("dynamicFov", 0);
        int hitbox = opt_flag("hitboxOutline", 1), hidden = opt_flag("hideHealthBar", 0);

        vt_gui_toggle("opt.motion", x, y, col * 2.0f + 4.0f, ROW_H, "Reduced Motion", &reduced);
        opt_write("reducedMotion", reduced ? "true" : "false");
        y += ROW_GAP;
        vt_gui_toggle("opt.dynfov", x, y, col * 2.0f + 4.0f, ROW_H, "Dynamic Field of View", &dynfov);
        opt_write("dynamicFov", dynfov ? "true" : "false");
        y += ROW_GAP;
        vt_gui_toggle("opt.hitbox", x, y, col * 2.0f + 4.0f, ROW_H, "Entity Outlines", &hitbox);
        opt_write("hitboxOutline", hitbox ? "true" : "false");
        y += ROW_GAP;
        vt_gui_toggle("opt.health", x, y, col * 2.0f + 4.0f, ROW_H, "Hide Health Bar", &hidden);
        opt_write("hideHealthBar", hidden ? "true" : "false");
    } else if (s_option_page == OPT_LANGUAGE) {
        const char *current = opt_find("languageCode", "en_us");
        int selected = 0;
        char code[16];
        for (i = 0; i < LANG_COUNT; i++)
            if (strncmp(LANG_NAMES[i], current, strlen(current)) == 0) selected = i;
        if (name_list("opt.lang", x, y, col * 2.0f + 4.0f, h - y - 64.0f,
                      LANG_NAMES, LANG_COUNT, &selected, NULL) >= 0) {
            snprintf(code, sizeof code, "%s", LANG_NAMES[selected]);
            { char *space = strchr(code, ' '); if (space) *space = 0; }
            opt_write("languageCode", "%s", code);
        }
        vt_gui_text(x, h - 54.0f, "The client keeps English labels; the code", VT_GUI_TEXT_DIM);
        vt_gui_text(x, h - 44.0f, "is what options.txt and the server see.", VT_GUI_TEXT_DIM);
    } else if (s_option_page == OPT_PACKS) {
        static const char *rows2[MAX_PACKS];
        for (i = 0; i < s_pack_count; i++) rows2[i] = s_pack_names[i];
        if (s_pack_count == 0) {
            vt_gui_text(x, y, "No resource packs were discovered.", VT_GUI_TEXT_DIM);
            vt_gui_text(x, y + 10.0f, "Point the launcher at a Minecraft install.", VT_GUI_TEXT_DIM);
        } else {
            vt_gui_text(x, y - 10.0f, "Choose the pack the assets come from", VT_GUI_TEXT);
            if (name_list("opt.packs", x, y + 4.0f, col * 2.0f + 4.0f, h - y - 68.0f,
                          rows2, s_pack_count, &s_pack_sel, &s_pack_scroll) >= 0)
                claim_text(VT_MENU_ACTION_RELOAD_ASSETS, s_pack_paths[s_pack_sel]);
        }
    }

    if (center_button("opt.done", h - ROW_H * 2.0f - 12.0f, "Done")) {
        if (s_options_dirty) claim(VT_MENU_ACTION_OPTIONS_SAVED);
        go_back();
    }
    if (center_button("opt.cancel", h - ROW_H - 6.0f, "Cancel")) go_back();
}

static void draw_connecting(void) {
    float h = logical_h();
    char line[192];
    int dots = (int)(s_frame_count / 12.0) % 4;
    static const char *const blanks = "    ";

    vt_gui_text_centered(h * 0.38f, s_status, VT_GUI_TEXT);
    snprintf(line, sizeof line, "%.*s", 4 - dots, blanks);
    vt_gui_text_centered(h * 0.38f + 16.0f, line, VT_GUI_TEXT_DIM);
    vt_gui_text_centered(h * 0.38f + 34.0f, "The world appears when the first chunk arrives.",
                         VT_GUI_TEXT_DIM);
    if (center_button("conn.cancel", h - ROW_H - 6.0f, "Cancel")) go_back();
}

/* The chat prompt: one field along the bottom, because the lines themselves
 * are already on screen as the HUD draws them. */
static void draw_chat(void) {
    float w = logical_w(), h = logical_h();
    int state;

    vt_gui_rect(0.0f, h - 22.0f, w, 22.0f, 0.0f, 0.0f, 0.0f, 0.70f);
    state = vt_gui_field("chat.line", 4.0f, h - 20.0f, w - 8.0f, ROW_H,
                         s_chat_text, sizeof s_chat_text);
    vt_gui_text(4.0f, h - 32.0f, "Enter sends, Escape closes", VT_GUI_TEXT_DIM);
    if (state == 2) {
        if (s_chat_text[0]) {
            claim_text(VT_MENU_ACTION_SEND_CHAT, s_chat_text);
            s_chat_text[0] = 0;
            s_overlay = 0;
        }
    }
}

/* Two columns of 98 units, the pause menu of the original. */
static void draw_pause(void) {
    float w = logical_w(), h = logical_h();
    float left = w * 0.5f - HALF_COL - 2.0f;
    float right = w * 0.5f + 2.0f;
    float y = h * 0.25f;
    int i;

    vt_gui_text_centered(y - 24.0f, "Game Menu", VT_GUI_TEXT);
    if (vt_gui_button("pause.return", left, y, HALF_COL * 2.0f + 4.0f, ROW_H, "Back to Game"))
        s_overlay = 0;
    y += ROW_GAP;
    if (vt_gui_button("pause.adv", left, y, HALF_COL, ROW_H, "Advancements"))
        s_action_note = 1;
    if (vt_gui_button("pause.stats", right, y, HALF_COL, ROW_H, "Statistics"))
        s_action_note = 2;
    y += ROW_GAP;
    if (vt_gui_button("pause.options", left, y, HALF_COL, ROW_H, "Options..."))
        open_screen(SCR_OPTIONS, SCR_PAUSE);
    if (vt_gui_button("pause.links", right, y, HALF_COL, ROW_H, "Server Links"))
        s_action_note = 3;
    y += ROW_GAP;
    if (vt_gui_button("pause.bug", left, y, HALF_COL, ROW_H, "Report Bug"))
        s_action_note = 4;
    if (vt_gui_button("pause.lang", right, y, HALF_COL, ROW_H, "Language")) {
        s_option_page = OPT_LANGUAGE;
        open_screen(SCR_OPTIONS, SCR_PAUSE);
    }
    y += ROW_GAP * 1.6f;
    if (vt_gui_button("pause.disconnect", left, y, HALF_COL * 2.0f + 4.0f, ROW_H, "Disconnect")) {
        claim(VT_MENU_ACTION_DISCONNECT);
        s_overlay = 0;
    }
    y += ROW_GAP;
    if (vt_gui_button("pause.quit", left, y, HALF_COL * 2.0f + 4.0f, ROW_H, "Quit to Title Screen")) {
        claim(VT_MENU_ACTION_RETURN_TO_MENU);
        s_overlay = 0;
    }
    if (s_action_note) {
        static const char *const notes[] = {
            "", "No advancements have been granted.", "Statistics are not tracked yet.",
            "This server advertised no links.", "Nothing was sent."
        };
        i = s_action_note;
        vt_gui_text_centered(y + ROW_GAP + 12.0f, notes[i], VT_GUI_TEXT_DIM);
        s_action_note = 0;
    }
}

static void draw_death(void) {
    float w = logical_w(), h = logical_h();
    int hardcore = s_hardcore;

    vt_gui_rect(0.0f, 0.0f, w, h, 0.60f, 0.0f, 0.0f, 0.62f);
    vt_gui_text_centered(h * 0.25f, "You died!", 1.0f, 1.0f, 1.0f);
    if (s_death_message[0]) vt_gui_text_centered(h * 0.25f + 14.0f, s_death_message, VT_GUI_TEXT);

    if (!hardcore) {
        if (center_button("dead.respawn", h * 0.42f, "Respawn")) {
            s_overlay = 0;
            claim(VT_MENU_ACTION_RESPAWN);
        }
        if (center_button("dead.title", h * 0.42f + ROW_GAP, "Title Screen")) {
            s_overlay = 0;
            claim(VT_MENU_ACTION_RETURN_TO_MENU);
        }
        if (center_button("dead.options", h * 0.42f + ROW_GAP * 2.0f, "Options..."))
            open_screen(SCR_OPTIONS, SCR_DEATH);
    } else {
        vt_gui_text_centered(h * 0.42f, "You do not have enough points to respawn.", VT_GUI_TEXT);
        if (center_button("dead.title", h * 0.42f + ROW_GAP, "Title Screen")) {
            s_overlay = 0;
            claim(VT_MENU_ACTION_RETURN_TO_MENU);
        }
    }
}

/* ------------------------------------------------------------------ frame */

void vt_menus_set_mouse(int x, int y, int down) { s_mx = x; s_my = y; s_down = down; }
void vt_menus_add_click(int x, int y) { s_clicked = 1; s_mx = x; s_my = y; }
void vt_menus_add_wheel(int delta) { s_wheel += delta; }
void vt_menus_add_key(int key) { s_key = key; }
void vt_menus_add_text(const char *utf8) {
    if (utf8) snprintf(s_typed, sizeof s_typed, "%s", utf8);
}

int vt_menus_draw(void) {
    int key = s_key;
    int overlay = s_ingame ? s_overlay : 0;

    s_frame_count += 1.0;
    seed_defaults();
    vt_gui_begin(s_mx, s_my, s_down, s_clicked, s_wheel, key, s_typed);

    s_action = 0;
    s_action_text[0] = 0;
    s_action_text2[0] = 0;
    s_action_long = 0;
    s_action_index = -1;

    if (overlay == 3) {
        draw_chat();
        if (key == VT_GUI_KEY_ESCAPE && vt_gui_focus_cleared(key)) s_overlay = 0;
    } else if (overlay == 1) {
        draw_pause();
    } else if (overlay == 2) {
        draw_death();
    } else if (s_ingame) {
        /* The world owns the screen. */
    } else {
        switch (s_screen) {
            case SCR_TITLE:       draw_title(); break;
            case SCR_SINGLE:      draw_single(); break;
            case SCR_CREATE:      draw_create(); break;
            case SCR_MULTI:       draw_multi(); break;
            case SCR_DIRECT:      draw_direct(); break;
            case SCR_SERVER_EDIT: draw_server_edit(); break;
            case SCR_OPTIONS:     draw_options(); break;
            case SCR_CONNECTING:  draw_connecting(); break;
            default: break;
        }
        if (key == VT_GUI_KEY_ESCAPE && vt_gui_focus_cleared(key)) {
            if (s_screen == SCR_TITLE) claim(VT_MENU_ACTION_QUIT);
            else go_back();
        }
    }

    s_clicked = 0;
    s_wheel = 0;
    s_key = 0;
    s_typed[0] = 0;
    return s_action;
}

int vt_menus_is_grabbing(void) { return s_ingame && s_overlay == 0 ? 0 : 1; }

void vt_menus_set_ingame(int playing, int overlay) {
    s_ingame = playing ? 1 : 0;
    s_overlay = overlay;
    if (!playing) { s_screen = SCR_TITLE; s_back_count = 0; }
    vt_gui_reset();
}

void vt_menus_set_overlay(int kind) {
    s_overlay = kind;
    vt_gui_reset();
}

void vt_menus_open_chat(void) {
    s_chat_text[0] = 0;
    s_overlay = 3;
    vt_gui_reset();
}

int vt_menus_overlay_kind(void) { return s_ingame ? s_overlay : 0; }

void vt_menus_set_hardcore(int hardcore) { s_hardcore = hardcore ? 1 : 0; }
void vt_menus_set_death_message(const char *text) {
    snprintf(s_death_message, sizeof s_death_message, "%s", text ? text : "");
}

const char *vt_menus_action_text(void) { return s_action_text; }
const char *vt_menus_action_text2(void) { return s_action_text2; }
int64_t vt_menus_action_long(void) { return s_action_long; }
int vt_menus_action_index(void) { return s_action_index; }

void vt_menus_set_status(const char *text) {
    if (text) snprintf(s_status, sizeof s_status, "%s", text);
}

void vt_menus_set_subtitle(const char *text) {
    if (text) snprintf(s_subtitle, sizeof s_subtitle, "%s", text);
}

void vt_menus_clear_worlds(void) { s_world_count = 0; s_world_sel = 0; s_world_scroll = 0; }

void vt_menus_add_world(const char *name, const char *folder, const char *info) {
    World *w;
    if (s_world_count >= MAX_WORLDS || !name) return;
    w = &s_worlds[s_world_count++];
    snprintf(w->name, sizeof w->name, "%s", name);
    snprintf(w->folder, sizeof w->folder, "%s", folder ? folder : name);
    snprintf(w->info, sizeof w->info, "%s", info ? info : "");
}

int vt_menus_world_count(void) { return s_world_count; }
const char *vt_menus_world_name(int index) {
    return index >= 0 && index < s_world_count ? s_worlds[index].name : "";
}
const char *vt_menus_world_folder(int index) {
    return index >= 0 && index < s_world_count ? s_worlds[index].folder : "";
}

void vt_menus_clear_servers(void) { s_server_count = 0; s_server_sel = 0; s_server_scroll = 0; }

void vt_menus_add_server(const char *name, const char *host, int port) {
    Server *s;
    if (s_server_count >= MAX_SERVERS || !name || !host) return;
    s = &s_servers[s_server_count++];
    snprintf(s->name, sizeof s->name, "%s", name);
    snprintf(s->host, sizeof s->host, "%s", host);
    s->port = port;
    s->ping = -1;
}

int vt_menus_server_count(void) { return s_server_count; }

const char *vt_menus_server_name(int index) {
    return index >= 0 && index < s_server_count ? s_servers[index].name : "";
}
const char *vt_menus_server_host(int index) {
    return index >= 0 && index < s_server_count ? s_servers[index].host : "";
}
int vt_menus_server_port(int index) {
    return index >= 0 && index < s_server_count ? s_servers[index].port : 0;
}

void vt_menus_set_server_ping(int index, int milliseconds) {
    if (index >= 0 && index < s_server_count) s_servers[index].ping = milliseconds;
}

const char *vt_menus_get_option(const char *key, const char *fallback) {
    seed_defaults();
    return opt_find(key, fallback ? fallback : "");
}

void vt_menus_set_option(const char *key, const char *value) {
    if (!key || !value) return;
    seed_defaults();
    opt_set(key, value);
    s_options_dirty = 0; /* loading is not an edit */
}

int vt_menus_option_count(void) { seed_defaults(); return s_option_count; }

const char *vt_menus_option_key(int index) {
    return index >= 0 && index < s_option_count ? s_options[index].key : "";
}

const char *vt_menus_option_value(int index) {
    return index >= 0 && index < s_option_count ? s_options[index].value : "";
}

int vt_menus_options_dirty(void) { return s_options_dirty; }
void vt_menus_options_clean(void) { s_options_dirty = 0; }

void vt_menus_set_player_name(const char *name) {
    if (!name) return;
    seed_defaults();
    opt_set("playerName", name);
    s_options_dirty = 0;
}

void vt_menus_clear_packs(void) { s_pack_count = 0; s_pack_sel = 0; s_pack_scroll = 0; }

void vt_menus_add_pack(const char *label, const char *path, int selected) {
    if (s_pack_count >= MAX_PACKS || !label) return;
    snprintf(s_pack_names[s_pack_count], sizeof s_pack_names[s_pack_count], "%s", label);
    snprintf(s_pack_paths[s_pack_count], sizeof s_pack_paths[s_pack_count], "%s", path ? path : "");
    if (selected) s_pack_sel = s_pack_count;
    s_pack_count++;
}

/* Vortex - see menudata.h. The formats here are the ones a Minecraft install
 * already carries: options.txt is plain key:value lines, servers.dat is an
 * uncompressed little-endian NBT compound, and a world is one folder under
 * saves/ whose name the original game shows until it reads level.dat. */

#include "menudata.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "menus.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#endif

#define MAX_PATH_LENGTH 512

static void join(char *out, size_t cap, const char *a, const char *b) {
#ifdef _WIN32
    snprintf(out, cap, "%s\\%s", a, b);
#else
    snprintf(out, cap, "%s/%s", a, b);
#endif
}

int vt_menudata_default_dir(char *out, size_t capacity) {
    const char *override = getenv("VORTEX_HOME");
    if (override && *override) {
        snprintf(out, capacity, "%s", override);
        return 0;
    }
#ifdef _WIN32
    {
        const char *appdata = getenv("APPDATA");
        if (appdata && *appdata) snprintf(out, capacity, "%s\\.minecraft", appdata);
        else snprintf(out, capacity, ".minecraft");
    }
#else
    {
        const char *xdg = getenv("XDG_DATA_HOME");
        const char *home = getenv("HOME");
        if (xdg && *xdg) snprintf(out, capacity, "%s/Minecraft", xdg);
        else if (home && *home) snprintf(out, capacity, "%s/.minecraft", home);
        else snprintf(out, capacity, ".minecraft");
    }
#endif
    return out[0] ? 0 : -1;
}

/* ------------------------------------------------------------------ worlds */

#ifdef _WIN32
int vt_menudata_scan_worlds(const char *game_dir) {
    char saves[MAX_PATH_LENGTH];
    char pattern[MAX_PATH_LENGTH];
    WIN32_FIND_DATAA found;
    HANDLE handle;
    int total = 0;

    join(saves, sizeof saves, game_dir, "saves");
    snprintf(pattern, sizeof pattern, "%s\\*", saves);
    handle = FindFirstFileA(pattern, &found);
    if (handle == INVALID_HANDLE_VALUE) return -1;

    vt_menus_clear_worlds();
    do {
        char label[64];
        const char *name = found.cFileName;
        FILE *probe;
        char level[MAX_PATH_LENGTH];

        if (name[0] == '.') continue;
        if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        /* The newest stamp in the folder is the last play session; level.dat is
         * what a saved game always touches last. */
        join(level, sizeof level, saves, name);
        {
            char level_path[MAX_PATH_LENGTH];
            snprintf(level_path, sizeof level_path, "%s\\level.dat", level);
            probe = fopen(level_path, "rb");
            if (probe != NULL) fclose(probe);
        }
        snprintf(label, sizeof label, "Folder %s", name);
        vt_menus_add_world(name, name, label);
        if (++total >= 32) break;
    } while (FindNextFileA(handle, &found));
    FindClose(handle);
    return total;
}
#else
int vt_menudata_scan_worlds(const char *game_dir) {
    char saves[MAX_PATH_LENGTH];
    DIR *directory;
    struct dirent *entry;
    int found = 0;

    join(saves, sizeof saves, game_dir, "saves");
    directory = opendir(saves);
    if (directory == NULL) return -1;

    vt_menus_clear_worlds();
    while ((entry = readdir(directory)) != NULL) {
        struct stat details;
        char path[MAX_PATH_LENGTH];
        char label[64];
        const char *name = entry->d_name;

        if (name[0] == '.') continue;
        join(path, sizeof path, saves, name);
        if (stat(path, &details) != 0) continue;
#ifndef S_ISDIR
        (void)details;
#endif
        if (!S_ISDIR(details.st_mode)) continue;
        {
            time_t newest = details.st_mtime;
            char level[MAX_PATH_LENGTH];
            struct stat level_details;
            join(level, sizeof level, path, "level.dat");
            if (stat(level, &level_details) == 0 && level_details.st_mtime > newest)
                newest = level_details.st_mtime;
            {
                struct tm *when = localtime(&newest);
                if (when != NULL)
                    strftime(label, sizeof label, "Last played %Y-%m-%d", when);
                else
                    snprintf(label, sizeof label, "Folder %s", name);
            }
        }
        /* The folder is the save: the original game names a world after the
         * folder until it has read level.dat, so this stays correct. */
        vt_menus_add_world(name, name, label);
        found++;
        if (found >= 32) break;
    }
    closedir(directory);
    return found;
}
#endif

/* ------------------------------------------------------------------ options */

int vt_menudata_load_options(const char *game_dir) {
    char path[MAX_PATH_LENGTH];
    FILE *stream;
    char line[128];
    int taken = 0;

    join(path, sizeof path, game_dir, "options.txt");
    stream = fopen(path, "rb");
    if (stream == NULL) return 0;
    while (fgets(line, sizeof line, stream) != NULL) {
        char *colon = strchr(line, ':');
        char *end;
        if (colon == NULL) continue;
        *colon = 0;
        end = colon + 1;
        while (*end == ' ' || *end == '\t') end++;
        {
            size_t length = strlen(end);
            while (length > 0 && (end[length - 1] == '\n' || end[length - 1] == '\r' ||
                                  end[length - 1] == ' '))
                end[--length] = 0;
            if (line[0] && length < 48) {
                vt_menus_set_option(line, end);
                taken++;
            }
        }
    }
    fclose(stream);
    return taken;
}

typedef struct { char key[32]; char value[48]; } Pair;

int vt_menudata_save_options(const char *game_dir) {
    char path[MAX_PATH_LENGTH];
    FILE *stream;
    Pair pairs[64];
    int count, i, j;

    count = vt_menus_option_count();
    if (count > (int)(sizeof pairs / sizeof pairs[0])) count = (int)(sizeof pairs / sizeof pairs[0]);
    for (i = 0; i < count; i++) {
        snprintf(pairs[i].key, sizeof pairs[i].key, "%s", vt_menus_option_key(i));
        snprintf(pairs[i].value, sizeof pairs[i].value, "%s", vt_menus_option_value(i));
    }
    for (i = 1; i < count; i++) {
        Pair moving = pairs[i];
        for (j = i - 1; j >= 0 && strcmp(pairs[j].key, moving.key) > 0; j--) pairs[j + 1] = pairs[j];
        pairs[j + 1] = moving;
    }

    join(path, sizeof path, game_dir, "options.txt");
    stream = fopen(path, "wb");
    if (stream == NULL) return -1;
    for (i = 0; i < count; i++) fprintf(stream, "%s:%s\n", pairs[i].key, pairs[i].value);
    fclose(stream);
    vt_menus_options_clean();
    return count;
}

/* ------------------------------------------------------------------ servers */

/* Enough of the NBT reader to walk one compound and its list of server
 * entries: the tags servers.dat actually uses. */
typedef struct {
    const unsigned char *at;
    const unsigned char *end;
    int failed;
} Cursor;

static unsigned char read_byte(Cursor *c) {
    if (c->at + 1 > c->end) { c->failed = 1; return 0; }
    return *c->at++;
}

static unsigned int read_be(Cursor *c, int bytes) {
    unsigned int value = 0;
    int i;
    if (c->at + bytes > c->end) { c->failed = 1; return 0; }
    for (i = 0; i < bytes; i++) value = (value << 8) | *c->at++;
    return value;
}

static unsigned int read_le(Cursor *c, int bytes) {
    unsigned int value = 0;
    int i;
    if (c->at + bytes > c->end) { c->failed = 1; return 0; }
    for (i = bytes - 1; i >= 0; i--) value = (value << 8) | c->at[i];
    c->at += bytes;
    return value;
}

static void read_text(Cursor *c, char *out, size_t cap, int length_bytes) {
    unsigned int length = length_bytes == 2 ? read_be(c, 2) : read_be(c, 1);
    size_t taken = 0;
    unsigned int i;
    if (c->failed) return;
    if (c->at + length > c->end) { c->failed = 1; return; }
    for (i = 0; i < length; i++) {
        unsigned char byte = c->at[i];
        if (byte == 0) continue; /* a UTF-8 continuation never starts a key */
        if (taken + 1 < cap) out[taken++] = (char)byte;
    }
    out[taken] = 0;
    c->at += length;
}

static void skip_payload(Cursor *c, int type, int depth);

static void skip_compound(Cursor *c, int depth) {
    for (;;) {
        int type = read_byte(c);
        if (c->failed) return;
        if (type == 0) return;
        if (type < 1 || type > 11) { c->failed = 1; return; }
        if (depth > 16) { c->failed = 1; return; }
        read_text(c, (char[64]){0}, 64, 2);
        skip_payload(c, type, depth + 1);
        if (c->failed) return;
    }
}

static void skip_payload(Cursor *c, int type, int depth) {
    switch (type) {
        case 1: read_byte(c); break;
        case 2: read_be(c, 2); break;
        case 3: case 6: read_be(c, 4); break;
        case 4: case 5: read_be(c, 8); break;
        case 7: { unsigned int n = read_be(c, 4), i; for (i = 0; i < n && !c->failed; i++) read_be(c, 2); } break;
        case 8: read_text(c, (char[128]){0}, 128, 2); break;
        case 9: case 11: {
            int element = read_byte(c);
            unsigned int count = read_be(c, 4), i;
            if (element == 0) count = 0;
            for (i = 0; i < count && !c->failed; i++) skip_payload(c, element, depth + 1);
            if (element == 10) { /* the list loop already walked the compounds */ }
            break;
        }
        case 10: skip_compound(c, depth); break;
        default: c->failed = 1; break;
    }
}

/* A compound whose fields the caller wants, read one field at a time. */
static void read_server_entry(Cursor *c, char *name, size_t name_cap,
                              char *ip, size_t ip_cap, int *port) {
    for (;;) {
        int type = read_byte(c);
        char key[64];
        if (c->failed) return;
        if (type == 0) return;
        read_text(c, key, sizeof key, 2);
        if (type == 8) {
            if (strcmp(key, "ip") == 0) read_text(c, ip, ip_cap, 2);
            else if (strcmp(key, "name") == 0) read_text(c, name, name_cap, 2);
            else read_text(c, key, sizeof key, 2);
            continue;
        }
        if (type == 3 && strcmp(key, "port") == 0) { *port = (int)read_le(c, 4); continue; }
        skip_payload(c, type, 2);
        if (c->failed) return;
    }
}

/* servers.dat has no port field: the address is "host" or "host:port". */
static void store_server(const char *name, const char *address) {
    char host[128];
    int port = 25565;
    const char *colon = strrchr(address, ':');
    if (colon && colon[1]) {
        size_t length = (size_t)(colon - address);
        if (length >= sizeof host) length = sizeof host - 1;
        memcpy(host, address, length);
        host[length] = 0;
        port = atoi(colon + 1);
        if (port <= 0 || port > 65535) port = 25565;
    } else {
        snprintf(host, sizeof host, "%s", address);
    }
    if (host[0] == 0) return;
    vt_menus_add_server(name && name[0] ? name : host, host, port);
}

int vt_menudata_load_servers(const char *game_dir) {
    char path[MAX_PATH_LENGTH];
    FILE *stream;
    unsigned char *data;
    long size;
    Cursor cursor;
    int found = 0;

    join(path, sizeof path, game_dir, "servers.dat");
    stream = fopen(path, "rb");
    if (stream == NULL) return -1;
    fseek(stream, 0, SEEK_END);
    size = ftell(stream);
    fseek(stream, 0, SEEK_SET);
    if (size <= 0 || size > 4 * 1024 * 1024) { fclose(stream); return -1; }
    data = (unsigned char *)malloc((size_t)size);
    if (data == NULL) { fclose(stream); return -1; }
    if (fread(data, 1, (size_t)size, stream) != (size_t)size) {
        free(data);
        fclose(stream);
        return -1;
    }
    fclose(stream);

    cursor.at = data;
    cursor.end = data + size;
    cursor.failed = 0;

    if (read_byte(&cursor) != 10) { free(data); return -1; }
    read_text(&cursor, (char[64]){0}, 64, 2); /* the root's own name */
    for (;;) {
        int type = read_byte(&cursor);
        char key[64];
        if (cursor.failed || type == 0) break;
        read_text(&cursor, key, sizeof key, 2);
        if (type == 9 && strcmp(key, "servers") == 0) {
            int element = read_byte(&cursor);
            unsigned int count = read_be(&cursor, 4), i;
            if (element != 10) break;
            for (i = 0; i < count && !cursor.failed; i++) {
                char name[64] = "";
                char ip[128] = "";
                int port = 0;
                read_server_entry(&cursor, name, sizeof name, ip, sizeof ip, &port);
                if (cursor.failed) break;
                if (ip[0] == 0 && port > 0) { free(data); return found; }
                store_server(name, ip);
                found++;
            }
            break;
        }
        skip_payload(&cursor, type, 1);
        if (cursor.failed) break;
    }
    free(data);
    return cursor.failed ? -1 : found;
}

static unsigned char *out_at;
static unsigned char *out_end;
static int out_failed;

static void write_byte(unsigned char value) {
    if (out_at + 1 > out_end) { out_failed = 1; return; }
    *out_at++ = value;
}

static void write_be(unsigned int value, int bytes) {
    int i;
    if (out_at + bytes > out_end) { out_failed = 1; return; }
    for (i = bytes - 1; i >= 0; i--) out_at[i] = (unsigned char)((value >> (8 * (bytes - 1 - i))) & 0xFF);
    out_at += bytes;
}

static void write_text(const char *text, int length_bytes) {
    size_t length = strlen(text);
    if (length > 32767) length = 32767;
    write_be((unsigned int)length, length_bytes);
    if (out_at + (int)length > out_end) { out_failed = 1; return; }
    memcpy(out_at, text, length);
    out_at += length;
}

int vt_menudata_save_servers(const char *game_dir) {
    char path[MAX_PATH_LENGTH];
    unsigned char buffer[65536];
    FILE *stream;
    int count = vt_menus_server_count();
    int i;

    out_at = buffer;
    out_end = buffer + sizeof buffer;
    out_failed = 0;

    write_byte(10);            /* root compound */
    write_text("", 2);
    write_byte(9);             /* servers: a list of compounds */
    write_text("servers", 2);
    write_byte(10);
    write_be((unsigned int)count, 4);
    for (i = 0; i < count; i++) {
        char address[192];
        snprintf(address, sizeof address, "%s:%d", vt_menus_server_host(i), vt_menus_server_port(i));
        write_byte(8); write_text("ip", 2); write_text(address, 2);
        write_byte(8); write_text("name", 2); write_text(vt_menus_server_name(i), 2);
        write_byte(7); write_text("icon", 2); write_be(0, 4);       /* empty ByteArray */
        write_byte(1); write_text("acceptTextures", 2); write_byte(1);
        write_byte(0);                                              /* end of entry */
    }
    write_byte(0);                                                  /* end of root */
    if (out_failed) return -1;

    join(path, sizeof path, game_dir, "servers.dat");
    stream = fopen(path, "wb");
    if (stream == NULL) return -1;
    if (fwrite(buffer, 1, (size_t)(out_at - buffer), stream) != (size_t)(out_at - buffer)) {
        fclose(stream);
        return -1;
    }
    fclose(stream);
    return count;
}

/* ---------------------------------------------------------------- delete */

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#define VT_FTW _ftw
#define VT_WALK_DEPTH 8
#define VT_ENTRY_D _FTW_D
#else
#include <ftw.h>
#include <unistd.h>
#define VT_FTW nftw
#define VT_WALK_DEPTH 8
#define VT_ENTRY_D FTW_D
#endif

/* nftw and _ftw take the same shape of callback: a path, its stat, a flag and
 * the walk record. A directory is removed only after its contents, which is
 * what the depth-first walk guarantees. */
static int vt_remove_entry(const char *path, const struct stat *info, int flag,
                           struct FTW *walk) {
    (void)info;
    (void)walk;
    if (flag == VT_ENTRY_D) {
#ifdef _WIN32
        _rmdir(path);
#else
        rmdir(path);
#endif
    } else {
        remove(path);
    }
    return 0;
}

/* A world is one folder under saves/, so deleting one is the whole save: the
 * region files, level.dat and the stats inside it. */
int64_t vt_menudata_delete_world(const char *folder) {
    char path[MAX_PATH_LENGTH];
    struct stat details;

    if (folder == NULL || folder[0] == 0) return -1;
    if (strchr(folder, '/') != NULL || strchr(folder, '\\') != NULL
        || strcmp(folder, ".") == 0 || strcmp(folder, "..") == 0)
        return -2; /* only a name the list itself produced */
    {
        join(path, sizeof path, vt_menudata_dir(), "saves");
    }
    {
        char full[MAX_PATH_LENGTH];
        join(full, sizeof full, path, folder);
        if (stat(full, &details) != 0) return -3;
        if (VT_FTW(full, vt_remove_entry, VT_WALK_DEPTH, 0) != 0) return -1;
        return 0;
    }
}

/* ------------------------------------------------------------------- packs */

int64_t vt_menudata_open(const char *username) {
    char directory[MAX_PATH_LENGTH];
    if (username && username[0]) vt_menus_set_player_name(username);
    vt_menudata_default_dir(directory, sizeof directory);
    vt_menus_set_subtitle(directory);
    vt_menudata_load_options(directory);
    if (vt_menudata_scan_worlds(directory) < 0) vt_menus_clear_worlds();
    if (vt_menudata_load_servers(directory) < 0) vt_menus_clear_servers();
    vt_menudata_fill_packs(directory);
    return 0;
}

char *vt_menudata_dir(void) {
    static char directory[MAX_PATH_LENGTH];
    if (directory[0] == 0) vt_menudata_default_dir(directory, sizeof directory);
    return directory;
}

int64_t vt_menudata_store(void) {
    const char *directory = vt_menudata_dir();
    int written = vt_menudata_save_options(directory);
    int servers = vt_menudata_save_servers(directory);
    if (servers < 0) return written;
    return written;
}

/* The pack the player just picked on the pack screen becomes the current one,
 * and the list is rebuilt with it marked, so the screen stays honest about
 * what is in use. */
int64_t vt_menudata_apply_pack(const char *path) {
    extern int resource_pack_set_current(const char *path);
    extern const char *resource_pack_get_current(void);
    extern int resource_pack_verify(const char *path, char *out_status, int max);
    char status[256];
    if (path == NULL || path[0] == 0) return -1;
    resource_pack_set_current(path);
    resource_pack_verify(resource_pack_get_current(), status, sizeof status);
    return status[0] != 0 ? 1 : 0;
}

void vt_menudata_fill_packs(const char *game_dir) {
    extern int resource_pack_get_discovered_count(void);
    extern const char *resource_pack_get_discovered_name(int index);
    extern const char *resource_pack_get_discovered_path(int index);
    extern const char *resource_pack_get_current(void);
    int count, i;
    const char *current;

    (void)game_dir;
    count = resource_pack_get_discovered_count();
    if (count <= 0) { vt_menus_clear_packs(); return; }
    current = resource_pack_get_current();
    vt_menus_clear_packs();
    for (i = 0; i < count; i++) {
        const char *name = resource_pack_get_discovered_name(i);
        const char *path = resource_pack_get_discovered_path(i);
        char label[128];
        snprintf(label, sizeof label, "%s - %s", name && name[0] ? name : path, path);
        vt_menus_add_pack(label, path, current && path && strcmp(current, path) == 0);
    }
}

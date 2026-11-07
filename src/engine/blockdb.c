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
    unsigned long long expected;
    vt_blockdb_unload();
    if (path == 0) return 0;
    file = fopen(path, "rb");
    if (file == 0) return 0;
    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); return 0; }
    length = ftell(file);
    if (length < 20) { fclose(file); return 0; }
    if (fseek(file, 0, SEEK_SET) != 0) { fclose(file); return 0; }
    data = (unsigned char*)malloc((size_t)length);
    if (data == 0) { fclose(file); return 0; }
    got = fread(data, 1, (size_t)length, file);
    fclose(file);
    if (got != (size_t)length) { free(data); return 0; }
    if (memcmp(data, VT_BLOCKDB_MAGIC, 8) != 0) { free(data); return 0; }
    states = vt_blockdb_u32(data + 8);
    blocks = vt_blockdb_u32(data + 12);
    names = vt_blockdb_u32(data + 16);
    expected = 20ULL + (unsigned long long)blocks * VT_BLOCKDB_RECORD + (unsigned long long)names;
    if (expected != (unsigned long long)length) { free(data); return 0; }
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
        } else if ((uint32_t)state >= first + count) {
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
    if (offset + length > vt_blockdb_name_bytes) return -1;
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
    if (offset + length > vt_blockdb_name_bytes || out == 0 || cap < 1) return -1;
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
    uint32_t i;
    if (vt_blockdb_data == 0) return 0;
    for (i = 0; i < vt_blockdb_blocks; i++) {
        const unsigned char* record = vt_blockdb_table + (size_t)i * VT_BLOCKDB_RECORD;
        uint32_t first = vt_blockdb_u32(record + 4);
        uint32_t count = (uint32_t)vt_blockdb_u16(record + 8);
        uint32_t offset = vt_blockdb_u32(record + 12);
        uint32_t length = (uint32_t)vt_blockdb_u16(record + 16);
        if (first != expected || count == 0) return 0;
        if (offset + length > vt_blockdb_name_bytes) return 0;
        expected += count;
    }
    return expected == vt_blockdb_states ? 1 : 0;
}

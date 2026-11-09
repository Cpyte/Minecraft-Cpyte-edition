/* Vortex engine - region file I/O and the compression Anvil uses.
 *
 * A Minecraft region (.mca) file is a header of two 4 KiB tables followed by
 * 4 KiB sectors that hold one record per chunk. Each record is a big endian
 * length, a compression byte and that many payload bytes, and the payload is a
 * gzip stream around the chunk's NBT. So the storage layer needs three things
 * the rest of the engine has no use for: whole-file reads, whole-file writes
 * and a gzip/zlib codec that keeps its own state.
 *
 * The codec is deliberately separate from src/network.c's mc_codec_* helpers.
 * Those hold one global input/output pair for the live socket, and a region
 * save runs while a connection may be mid-packet; sharing the buffers would
 * corrupt whichever side yielded first. The two halves here are reentrant only
 * in the sense that each call finishes before the next starts - the caller
 * copies what it wants to keep out of vt_gz_buf() before calling again.
 *
 * Buffers returned by vt_file_buf / vt_gz_buf are malloc'd and owned by this
 * file: Cpyte must copy anything it retains. That keeps the GC out of the
 * picture, because a raw malloc'd pointer is never a collected object.
 *
 * Cross-platform: <direct.h> and _mkdir on Windows, mkdir(2) elsewhere.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <zlib.h>

#ifdef _WIN32
#  define vt_make_dir(path) _mkdir(path)
#else
#  include <unistd.h>
#  define vt_make_dir(path) mkdir((path), 0777)
#endif

/* A region file with every chunk filled is bounded by the 24 bit sector
 * offset the format allows, so 128 GiB is the ceiling; 512 MiB is far above
 * anything vanilla writes and stops a hostile header from allocating wildly. */
#define VT_FILE_LIMIT 536870912LL
#define VT_GZ_LIMIT 67108864LL

/* Anvil chunk record compression bytes. */
#define VT_GZ_GZIP 0
#define VT_GZ_ZLIB 1
#define VT_GZ_NONE 2

/* ---- file bytes ----------------------------------------------------------- */

static char *vt_file_data = NULL;
static int64_t vt_file_length = 0;
static int64_t vt_file_capacity = 0;

static void vt_file_clear(void) {
    free(vt_file_data);
    vt_file_data = NULL;
    vt_file_length = 0;
    vt_file_capacity = 0;
}

int64_t vt_file_exists(const char *path) {
    struct stat info;
    if (path == NULL || path[0] == 0) return 0;
    if (stat(path, &info) != 0) return 0;
    return S_ISREG(info.st_mode) ? 1 : 0;
}

int64_t vt_file_dir_exists(const char *path) {
    struct stat info;
    if (path == NULL || path[0] == 0) return 0;
    if (stat(path, &info) != 0) return 0;
    return S_ISDIR(info.st_mode) ? 1 : 0;
}

int64_t vt_file_size(const char *path) {
    struct stat info;
    if (path == NULL || path[0] == 0) return -1;
    if (stat(path, &info) != 0) return -1;
    if (!S_ISREG(info.st_mode)) return -1;
    return (int64_t)info.st_size;
}

/* Every directory in `path` up to but not including the final component.
 * Existing directories are not an error, so re-saving a loaded world never
 * fights the filesystem. */
int64_t vt_file_mkdirs(const char *path) {
    char *copy;
    char *slash;

    if (path == NULL || path[0] == 0) return -1;
    copy = (char *)malloc(strlen(path) + 1);
    if (copy == NULL) return -1;
    strcpy(copy, path);
    /* Drop the final component: it is the file the caller is about to open,
     * not a directory. */
    slash = copy + strlen(copy);
    while (slash > copy + 1 && slash[-1] != '/' && slash[-1] != '\\') slash--;
    while (slash > copy + 1 && (slash[-1] == '/' || slash[-1] == '\\')) slash--;
    if (slash > copy) {
        *slash = 0;
        for (slash = copy + 1; *slash; slash++) {
            if (*slash != '/' && *slash != '\\') continue;
            *slash = 0;
            vt_make_dir(copy);
            *slash = '/';
        }
        vt_make_dir(copy);
    }
    free(copy);
    return 0;
}

int64_t vt_file_remove(const char *path) {
    if (path == NULL || path[0] == 0) return -1;
    if (remove(path) == 0) return 0;
    return -1;
}

/* Reads the whole file into the internal buffer. Returns 0 on success. */
int64_t vt_file_slurp(const char *path) {
    FILE *handle;
    int64_t size;
    char *grown;
    size_t read;
    int64_t want;

    if (path == NULL || path[0] == 0) return -1;
    size = vt_file_size(path);
    if (size < 0 || size > VT_FILE_LIMIT) return -1;
    want = size == 0 ? 1 : size;
    if (want > vt_file_capacity) {
        grown = (char *)realloc(vt_file_data, (size_t)want);
        if (grown == NULL) return -1;
        vt_file_data = grown;
        vt_file_capacity = want;
    }
    handle = fopen(path, "rb");
    if (handle == NULL) {
        vt_file_length = 0;
        return -1;
    }
    read = fread(vt_file_data, 1, (size_t)size, handle);
    fclose(handle);
    if ((int64_t)read != size) {
        vt_file_length = 0;
        return -1;
    }
    vt_file_length = (int64_t)read;
    return 0;
}

/* Drops the file from the buffer, freeing it: a region is several megabytes
 * and the caller may hold a list of them. */
int64_t vt_file_release(void) {
    vt_file_clear();
    return 0;
}

char *vt_file_buf(void) { return vt_file_data; }
int64_t vt_file_buf_len(void) { return vt_file_length; }

/* Writes `len` bytes and replaces any previous contents. A partial write is
 * reported as a failure and the file is removed, so a region is never left
 * truncated on disk by a full disk. */
int64_t vt_file_spit(const char *path, const char *data, int64_t len) {
    FILE *handle;
    size_t written;

    if (path == NULL || path[0] == 0 || len < 0) return -1;
    if (len > 0 && data == NULL) return -1;
    if (len > VT_FILE_LIMIT) return -1;
    handle = fopen(path, "wb");
    if (handle == NULL) return -1;
    written = len == 0 ? 0 : fwrite(data, 1, (size_t)len, handle);
    if (fclose(handle) != 0 || (int64_t)written != len) {
        remove(path);
        return -1;
    }
    return 0;
}

/* ---- codec ---------------------------------------------------------------- */

static char *vt_gz_data = NULL;
static int64_t vt_gz_length = 0;
static int64_t vt_gz_capacity = 0;

static int vt_gz_reserve(int64_t need) {
    char *grown;
    if (need <= vt_gz_capacity) return 1;
    grown = (char *)realloc(vt_gz_data, (size_t)need);
    if (grown == NULL) return 0;
    vt_gz_data = grown;
    vt_gz_capacity = need;
    return 1;
}

char *vt_gz_buf(void) { return vt_gz_data; }
int64_t vt_gz_buf_len(void) { return vt_gz_length; }

int64_t vt_gz_buf_reset(void) {
    vt_gz_length = 0;
    return 0;
}

int64_t vt_gz_release(void) {
    free(vt_gz_data);
    vt_gz_data = NULL;
    vt_gz_length = 0;
    vt_gz_capacity = 0;
    return 0;
}

/* Compresses [off, off+len) of `src` into the codec buffer. `format` picks the
 * framing: 0 gzip (what vanilla writes for a chunk record), 1 zlib, 2 none.
 * Returns 0 on success; the compressed length comes from vt_gz_buf_len(). */
int64_t vt_gz_compress(const char *src, int64_t off, int64_t len, int64_t format,
                       int64_t level) {
    z_stream stream;
    uLongf bound;
    int window;
    int result;

    if (src == NULL || off < 0 || len < 0 || off + len < 0) return -1;
    if (format == VT_GZ_NONE) {
        if (!vt_gz_reserve(len == 0 ? 1 : len)) return -1;
        if (len > 0) memcpy(vt_gz_data, src + off, (size_t)len);
        vt_gz_length = len;
        return 0;
    }
    memset(&stream, 0, sizeof(stream));
    window = format == VT_GZ_GZIP ? (MAX_WBITS + 16) : MAX_WBITS;
    if (level < 0 || level > 9) level = 1;
    if (deflateInit2(&stream, (int)level, Z_DEFLATED, window, 9,
                     Z_DEFAULT_STRATEGY) != Z_OK) {
        return -1;
    }
    bound = deflateBound(&stream, (uLong)len);
    if ((int64_t)bound > VT_GZ_LIMIT) {
        deflateEnd(&stream);
        return -1;
    }
    if (!vt_gz_reserve((int64_t)bound + 1)) {
        deflateEnd(&stream);
        return -1;
    }
    stream.next_in = (Bytef *)(src + off);
    stream.avail_in = (uInt)len;
    stream.next_out = (Bytef *)vt_gz_data;
    stream.avail_out = (uInt)bound;
    result = deflate(&stream, Z_FINISH);
    if (result != Z_STREAM_END) {
        deflateEnd(&stream);
        vt_gz_length = 0;
        return -1;
    }
    vt_gz_length = (int64_t)stream.total_out;
    deflateEnd(&stream);
    return 0;
}

/* Inflates [off, off+len) of `src` into the codec buffer, growing it until the
 * stream ends. `format` selects the framing; a stream that claims to expand
 * past VT_GZ_LIMIT is refused, because a hostile region header can name any
 * sector count. */
int64_t vt_gz_decompress(const char *src, int64_t off, int64_t len, int64_t format) {
    z_stream stream;
    int window;
    int64_t capacity;
    int result;

    if (src == NULL || off < 0 || len <= 0) return -1;
    if (format == VT_GZ_NONE) {
        if (len > VT_GZ_LIMIT) return -1;
        if (!vt_gz_reserve(len)) return -1;
        memcpy(vt_gz_data, src + off, (size_t)len);
        vt_gz_length = len;
        return 0;
    }
    memset(&stream, 0, sizeof(stream));
    window = format == VT_GZ_GZIP ? (MAX_WBITS + 16) : MAX_WBITS;
    if (inflateInit2(&stream, window) != Z_OK) return -1;
    capacity = len * 4 + 4096;
    if (capacity > VT_GZ_LIMIT) capacity = VT_GZ_LIMIT;
    stream.next_in = (Bytef *)(src + off);
    stream.avail_in = (uInt)len;
    while (1) {
        if (!vt_gz_reserve(capacity)) {
            inflateEnd(&stream);
            return -1;
        }
        /* Output keeps appending across grows: restarting the cursor each pass
         * would overwrite the bytes already inflated. */
        stream.next_out = (Bytef *)vt_gz_data + (size_t)stream.total_out;
        stream.avail_out = (uInt)(capacity - (int64_t)stream.total_out);
        result = inflate(&stream, Z_NO_FLUSH);
        if (result == Z_STREAM_END) {
            vt_gz_length = (int64_t)stream.total_out;
            inflateEnd(&stream);
            return 0;
        }
        if (result != Z_OK && result != Z_BUF_ERROR) {
            inflateEnd(&stream);
            vt_gz_length = 0;
            return -1;
        }
        if (stream.avail_out != 0) {
            /* Input exhausted without an end marker: a truncated stream. */
            inflateEnd(&stream);
            vt_gz_length = 0;
            return -1;
        }
        if (capacity >= VT_GZ_LIMIT) {
            inflateEnd(&stream);
            vt_gz_length = 0;
            return -1;
        }
        capacity = capacity * 2;
        if (capacity > VT_GZ_LIMIT) capacity = VT_GZ_LIMIT;
    }
}

/* ---- checksum ------------------------------------------------------------ */

/* Seconds since the epoch, for the region timestamp table. The format stores
 * it in a 32 bit field, so only the low 32 bits are meaningful to a reader. */
int64_t vt_file_now(void) {
    return (int64_t)time(NULL);
}

/* The environment variable `env`, or `fallback` when it is unset or empty.
 * Copied, because Cpyte hands a `str` around as an ordinary pointer and the
 * caller cannot tell an environ string from its own allocation. */
char *vt_env_or(const char *env, const char *fallback) {
    const char *value = getenv(env);
    char *out;
    if (value == NULL || value[0] == 0) value = fallback;
    out = (char *)malloc(strlen(value) + 1);
    if (out == NULL) return NULL;
    strcpy(out, value);
    return out;
}

/* Appends `suffix` to `dir`, skipping a duplicated separator. Returns NULL
 * when the result would not fit in `capacity` bytes. */
char *vt_path_join(char *out, int64_t capacity, const char *dir,
                   const char *suffix) {
    size_t length;
    if (out == NULL || capacity < 1) return NULL;
    if (dir == NULL) dir = "";
    if (suffix == NULL) suffix = "";
    length = strlen(dir);
    if (length > 0 && (dir[length - 1] == '/' || dir[length - 1] == '\\')) length--;
    if (length + 1 + strlen(suffix) + 1 > (size_t)capacity) return NULL;
    memcpy(out, dir, length);
    out[length] = '/';
    strcpy(out + length + 1, suffix);
    return out;
}

int64_t vt_text_length(const char *text) {
    if (text == NULL) return 0;
    return (int64_t)strlen(text);
}

/* `left`/`right` with exactly one separator between them. */
char *vt_path_append(const char *left, const char *right) {
    size_t a;
    char *out;
    if (left == NULL) left = "";
    if (right == NULL) right = "";
    a = strlen(left);
    while (a > 0 && (left[a - 1] == '/' || left[a - 1] == '\\')) a--;
    out = (char *)malloc(a + 1 + strlen(right) + 1);
    if (out == NULL) return NULL;
    memcpy(out, left, a);
    out[a] = '/';
    strcpy(out + a + 1, right);
    return out;
}

/* The path Anvil uses inside a dimension folder: <base>/<dim>/region/
 * r.<x>.<z>.mca. Built in C because Cpyte cannot append a number to text. */
char *vt_region_path(const char *base, const char *dimension, int64_t region_x,
                     int64_t region_z) {
    char name[64];
    char *folder;
    char *middle;
    char *out;

    if (snprintf(name, sizeof(name), "r.%lld.%lld.mca", (long long)region_x,
                 (long long)region_z) < 0) {
        return NULL;
    }
    folder = vt_path_append("region", name);
    if (folder == NULL) return NULL;
    middle = vt_path_append(base, dimension);
    if (middle == NULL) {
        free(folder);
        return NULL;
    }
    out = vt_path_append(middle, folder);
    free(folder);
    free(middle);
    return out;
}

/* Concatenation. Cpyte has `+` for two strings but no way to build a path from
 * pieces, and both operands are copied into a new allocation the caller owns. */
char *vt_text_join(const char *left, const char *right) {
    size_t a;
    size_t b;
    char *out;

    if (left == NULL) left = "";
    if (right == NULL) right = "";
    a = strlen(left);
    b = strlen(right);
    out = (char *)malloc(a + b + 1);
    if (out == NULL) return NULL;
    memcpy(out, left, a);
    memcpy(out + a, right, b + 1);
    return out;
}

/* adler32 is exposed for tests that want to confirm the codec produced a real
 * stream rather than a byte-for-byte copy. */
int64_t vt_gz_adler32(const char *data, int64_t off, int64_t len, int64_t value) {
    uLong sum = (uLong)value;
    if (data == NULL || off < 0 || len < 0) return -1;
    sum = adler32(sum, (const Bytef *)(data + off), (uInt)len);
    return (int64_t)sum;
}

int64_t vt_gz_crc32(const char *data, int64_t off, int64_t len, int64_t value) {
    uLong sum = (uLong)value;
    if (data == NULL || off < 0 || len < 0) return -1;
    sum = crc32(sum, (const Bytef *)(data + off), (uInt)len);
    return (int64_t)sum;
}

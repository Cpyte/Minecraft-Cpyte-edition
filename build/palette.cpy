# Vortex engine - generated bundle. Do not edit: this file is assembled from
# the modules listed below by tools/bundle.py.
#
#   native.cpy, core.cpy, strings.cpy, protocol_ids.cpy, vbuf.cpy, nbt.cpy, palette.cpy, section.cpy, heightmap.cpy, world.cpy, protocol_chunk.cpy, blockdb.cpy, mesher.cpy, harness.cpy, test_palette.cpy

import stdlib
import "../src/engine/blockdb.c"


# ===== native.cpy =====
# Vortex engine - the C layer.
#
# Cpyte's text support stops at `+` on two strings and `len()`: there is no
# slicing, no char concatenation, and a character literal casts to a string
# pointer rather than a byte. All text handling therefore goes through this
# thin C layer, which is also the only place the engine touches raw bytes,
# because indexing a `char*` from Cpyte is not something the codecs should
# depend on - `vt_at` and `vt_put` cover it.
#
# This is the engine's only `ccode:` block; every other module calls these
# helpers. Rules that apply to it:
#   * nothing may sit between the body and the first Cpyte statement, because
#     the raw block only ends at a statement;
#   * <stdlib.h> and <string.h> must be included at the top, otherwise calloc
#     and size_t are undeclared; <stdio.h> breaks the mingw header chain;
#   * no `?:` ternaries - they crash the compiler;
#   * no `strdup` - it is not declared in the C dialect Cpyte emits.

ccode:
    #include <stdlib.h>
    #include <string.h>

    /* --- text ---------------------------------------------------------- */
    /* Cpyte hands a `str` to a `const char*` parameter directly, and a
     * NUL-terminated `char*` prints as text. */
    int vt_strlen(const char* s) { return (int)strlen(s); }
    int vt_at(const char* s, int i) { return (int)(unsigned char)s[i]; }
    int vt_eq(const char* a, const char* b) {
        if (strcmp(a, b) == 0) return 1;
        return 0;
    }
    int vt_cmp(const char* a, const char* b) { return strcmp(a, b); }
    int vt_starts(const char* s, const char* prefix) {
        size_t n = strlen(prefix);
        if (strncmp(s, prefix, n) == 0) return 1;
        return 0;
    }
    int vt_find_str(const char* hay, const char* needle) {
        if (needle[0] == 0) return 0;
        const char* p = strstr(hay, needle);
        if (p == 0) return -1;
        return (int)(p - hay);
    }
    int vt_find_code(const char* s, int from, int code) {
        const char* p = strchr(s + from, code);
        if (p == 0) return -1;
        return (int)(p - s);
    }
    int vt_count(const char* s, int code) {
        int n = 0;
        const char* p;
        for (p = s; *p; p++) { if (*p == code) n++; }
        return n;
    }
    char* vt_dup(const char* s) {
        int n = (int)strlen(s);
        char* out = (char*)calloc((size_t)n + 1, 1);
        if (out != 0) memcpy(out, s, (size_t)n);
        return out;
    }
    void vt_put(char* s, int i, int code) { s[i] = (char)code; }
    char* vt_slice(const char* s, int begin, int end) {
        int n = end - begin;
        if (n < 0) n = 0;
        char* out = (char*)calloc((size_t)n + 1, 1);
        if (out == 0) return 0;
        memcpy(out, s + begin, (size_t)n);
        return out;
    }
    char* vt_calloc_char(int count) { return (char*)calloc((size_t)count + 1, 1); }
    char* vt_trim(const char* s) {
        const char* a = s;
        const char* b;
        while (*a == ' ' || *a == '\t' || *a == '\r' || *a == '\n') a++;
        b = a + strlen(a);
        while (b > a) {
            char c = b[-1];
            if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
            b--;
        }
        return vt_slice(s, (int)(a - s), (int)(b - s));
    }
    /* Field `index` of `line` split on `code`; "" when the index is absent. */
    char* vt_field(const char* line, int code, int index) {
        int cur = 0;
        const char* start = line;
        const char* p = line;
        while (1) {
            if (*p == 0 || *p == code) {
                if (cur == index) {
                    return vt_slice(line, (int)(start - line), (int)(p - line));
                }
                if (*p == 0) {
                    return vt_calloc_char(0);
                }
                cur++;
                start = p + 1;
            }
            p++;
        }
    }

    /* --- numbers -------------------------------------------------------- */
    /* `strict` comes back 0 when the text is not a complete number. */
    long long vt_parse_int(const char* s, int* strict) {
        char* end = 0;
        long long v = strtoll(s, &end, 10);
        while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') end++;
        if (strict == 0) return v;
        if (*end == 0 && end != s) *strict = 1;
        else *strict = 0;
        return v;
    }
    double vt_parse_double(const char* s, int* strict) {
        char* end = 0;
        double v = strtod(s, &end);
        while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') end++;
        if (strict == 0) return v;
        if (*end == 0 && end != s) *strict = 1;
        else *strict = 0;
        return v;
    }
    unsigned long long vt_fnv1a(const char* s) {
        unsigned long long hash = 14695981039346656037ULL;
        while (*s) {
            hash ^= (unsigned long long)(unsigned char)*s++;
            hash *= 1099511628211ULL;
        }
        return hash;
    }

    /* --- buffers -------------------------------------------------------- */
    void vt_free(void* p) { free(p); }
    void vt_copy_bytes(char* dst, int dst_off, const char* src, int src_off, int n) {
        if (n > 0) memcpy(dst + dst_off, src + src_off, (size_t)n);
    }
    char* vt_realloc_char(char* p, int bytes) {
        /* realloc(0) is a plain free, and a zero length allocates nothing, so
         * the caller always asks for at least one byte. */
        if (bytes < 1) bytes = 1;
        return (char*)realloc(p, (size_t)bytes);
    }

    /* --- typed arrays --------------------------------------------------- */
    /* Cpyte never indexes these directly: the accessors keep every raw
     * subscript inside C, where the element widths are known. */
    int* vt_calloc_int(int count) {
        if (count < 1) count = 1;
        return (int*)calloc((size_t)count, sizeof(int));
    }
    int vt_iget(const int* arr, int i) { return arr[i]; }
    void vt_iset(int* arr, int i, int v) { arr[i] = v; }
    unsigned long long* vt_calloc_u64(int count) {
        if (count < 1) count = 1;
        return (unsigned long long*)calloc((size_t)count, sizeof(unsigned long long));
    }
    unsigned long long vt_uget(const unsigned long long* arr, int i) { return arr[i]; }
    void vt_uset(unsigned long long* arr, int i, unsigned long long v) { arr[i] = v; }
    char* vt_calloc_ptrs(int count) {
        if (count < 1) count = 1;
        return (char*)calloc((size_t)count, sizeof(void*));
    }
    void* vt_ptr_get(const char* arr, int i) {
        void* slot;
        memcpy(&slot, arr + ((size_t)i * sizeof(void*)), sizeof(void*));
        return slot;
    }
    void vt_ptr_set(char* arr, int i, void* p) {
        memcpy(arr + ((size_t)i * sizeof(void*)), &p, sizeof(void*));
    }
    int vt_ptr_size(void) { return (int)sizeof(void*); }

    /* --- variable length integers --------------------------------------- */
    /* The 7-bit group loops live here rather than in Cpyte: Cpyte compares a
     * uint64 relationally as a *signed* value, so `v < 128` is true for every
     * negative number and the encoder stops after one group. */
    int vt_write_varint_at(char* buf, int off, int value) {
        unsigned int v = (unsigned int)value;
        int i = 0;
        while (v >= 0x80U && i < 4) {
            buf[off + i] = (char)((v & 0x7FU) | 0x80U);
            v = v >> 7;
            i++;
        }
        buf[off + i] = (char)v;
        return i + 1;
    }
    int vt_write_varlong_at(char* buf, int off, long long value) {
        unsigned long long v = (unsigned long long)value;
        int i = 0;
        while (v >= 0x80ULL && i < 9) {
            buf[off + i] = (char)((v & 0x7FULL) | 0x80ULL);
            v = v >> 7;
            i++;
        }
        buf[off + i] = (char)v;
        return i + 1;
    }
    /* Reads from [off, end). Returns the offset after the last group, or -1
     * when the run is truncated or longer than the encoding allows. VarInt is
     * 32 bit, so its result is sign extended from the low four bytes; `wide`
     * selects the 64 bit VarLong rule instead. */
    int vt_read_varint(const char* buf, int off, int end, long long* out, int wide) {
        unsigned long long acc = 0;
        int limit = 5;
        int i = off;
        if (wide != 0) limit = 10;
        while (i < end && i - off < limit) {
            unsigned long long byte = (unsigned long long)((unsigned char)buf[i]);
            acc = acc | ((byte & 0x7FULL) << ((unsigned long long)(i - off) * 7ULL));
            i++;
            if ((byte & 0x80ULL) == 0) {
                if (wide != 0) *out = (long long)acc;
                else *out = (long long)(int)(unsigned int)(acc & 0xFFFFFFFFULL);
                return i;
            }
        }
        return -1;
    }
    /* Keeps the low 32 bits of `raw`, sign extended. */
    int vt_sign_extend_32(unsigned long long raw) {
        return (int)(unsigned int)(raw & 0xFFFFFFFFULL);
    }
    /* Block position: x 26 bits, z 26 bits, y 12 bits, each signed. */
    void vt_unpack_block_pos(long long packed, int* out) {
        out[0] = (int)(packed >> 38);
        out[1] = (int)((packed << 26) >> 52);
        out[2] = (int)((packed << 38) >> 38);
    }
    /* Section position: x 22 bits, z 22 bits, y 20 bits, each signed. */
    void vt_unpack_section_pos(long long packed, int* out) {
        out[0] = (int)(packed >> 42);
        out[1] = (int)((packed << 44) >> 44);
        out[2] = (int)((packed << 22) >> 42);
    }

    /* --- packed long arrays --------------------------------------------- */
    /* Section palettes use the community "padded" packing: a 64 bit word holds
     * floor(64 / bits) whole entries and the leftover high bits of each word
     * go unused, so an entry never straddles two words. The width arithmetic
     * is unsigned throughout, because Cpyte compares uint64 as signed. */
    int vt_values_per_long(int bits) {
        if (bits <= 0 || bits > 64) return 0;
        return (int)(64 / bits);
    }
    int vt_packed_words(int count, int bits) {
        int per = vt_values_per_long(bits);
        if (per <= 0 || count <= 0) return 0;
        return (count + per - 1) / per;
    }
    unsigned long long vt_packed_mask(int bits) {
        if (bits <= 0) return 0;
        if (bits >= 64) return 0xFFFFFFFFFFFFFFFFULL;
        return (1ULL << bits) - 1ULL;
    }
    unsigned long long vt_packed_get(const unsigned long long* words, int index, int bits) {
        int per = vt_values_per_long(bits);
        if (per <= 0 || words == 0) return 0;
        int word = index / per;
        int shift = (index % per) * bits;
        return (words[word] >> shift) & vt_packed_mask(bits);
    }
    void vt_packed_set(unsigned long long* words, int index, int bits, unsigned long long value) {
        int per = vt_values_per_long(bits);
        if (per <= 0 || words == 0) return;
        int word = index / per;
        int shift = (index % per) * bits;
        unsigned long long mask = vt_packed_mask(bits);
        words[word] = (words[word] & ~(mask << shift)) | ((value & mask) << shift);
    }

    /* --- straddling bit packing ----------------------------------------- */
    /* Heightmaps fill the long array end to end in little endian bit order, so
     * an entry may run across a word boundary - the opposite of the palette
     * packing above. */
    int vt_bits_words(int count, int bits) {
        if (count <= 0 || bits <= 0) return 0;
        long long total = (long long)count * (long long)bits;
        return (int)((total + 63LL) / 64LL);
    }
    unsigned long long vt_bits_get(const unsigned long long* words, int index, int bits) {
        if (bits <= 0 || bits > 64 || words == 0) return 0;
        long long bit = (long long)index * (long long)bits;
        int word = (int)(bit >> 6);
        int shift = (int)(bit & 63LL);
        unsigned long long mask = vt_packed_mask(bits);
        unsigned long long low = words[word] >> shift;
        if (shift == 0 || shift + bits <= 64) return low & mask;
        return (low | (words[word + 1] << (64 - shift))) & mask;
    }
    void vt_bits_set(unsigned long long* words, int index, int bits, unsigned long long value) {
        if (bits <= 0 || bits > 64 || words == 0) return;
        long long bit = (long long)index * (long long)bits;
        int word = (int)(bit >> 6);
        int shift = (int)(bit & 63LL);
        unsigned long long mask = vt_packed_mask(bits);
        value = value & mask;
        words[word] = (words[word] & ~(mask << shift)) | (value << shift);
        if (shift != 0 && shift + bits > 64) {
            int left = bits - (64 - shift);
            unsigned long long rmask = vt_packed_mask(left);
            unsigned long long rest = (value >> (64 - shift)) & rmask;
            words[word + 1] = (words[word + 1] & ~rmask) | rest;
        }
    }

    /* --- bit casts ------------------------------------------------------ */
    /* NBT stores floats and doubles as their IEEE bit patterns, so the codec
     * needs to move them to and from integers without Cpyte getting a say in
     * the conversion.
     *
     * Both helpers cross the boundary as a C `double`: Cpyte's `float` is
     * double width, and a `float` parameter here receives garbage. TAG_Float
     * therefore narrows to 32 bit IEEE bits on the way out and widens back on
     * the way in. */
    double vt_bits_to_float(int bits) {
        float f = (float)0;
        memcpy(&f, &bits, sizeof(f));
        return (double)f;
    }
    int vt_float_to_bits(double f) {
        float narrow = (float)f;
        int bits = 0;
        memcpy(&bits, &narrow, sizeof(bits));
        return bits;
    }
    double vt_bits_to_double(unsigned long long bits) {
        double d = (double)0;
        memcpy(&d, &bits, sizeof(d));
        return d;
    }
    unsigned long long vt_double_to_bits(double d) {
        unsigned long long bits = (unsigned long long)0;
        memcpy(&bits, &d, sizeof(bits));
        return bits;
    }

    /* --- first-launch block database setup ------------------------------ */
    /* tools/setup_blockdb.py discovers a local installation, runs the vanilla
     * data generator and writes generated/blockdb.bin. The client calls this
     * only when the database is missing, so normal launches do no work. The
     * command is fixed (no user input), and the tool falls back gracefully. */
    int vt_run_blockdb_setup(void) {
        int rc = 0;
    #ifdef _WIN32
        rc = system("py -3 tools/setup_blockdb.py --auto");
        if (rc == 0) return 0;
        rc = system("python tools/setup_blockdb.py --auto");
    #else
        rc = system("python3 tools/setup_blockdb.py --auto");
        if (rc == 0) return 0;
        rc = system("python tools/setup_blockdb.py --auto");
    #endif
        if (rc == 0) return 0;
        return 1;
    }


# ===== core.cpy =====
# Vortex engine - shared scalar constants.
#
# Cpyte only resolves a module-level `int NAME = value` inside `main()`: any
# other function that reads one aborts codegen with "Undefined variable", even
# within a single flat translation unit. Engine-wide values are therefore plain
# accessor functions.
#
# Delimiters have to be integers as well: a Cpyte character literal compiles to
# a string pointer, so `code_at(text, i) == '|'` is never true.


# ---- character codes used by the text formats --------------------------------

public def code_nul() -> int:
    return 0


public def code_tab() -> int:
    return 9


public def code_newline() -> int:
    return 10


public def code_cr() -> int:
    return 13


public def code_space() -> int:
    return 32


public def code_hash() -> int:
    return 35


public def code_plus() -> int:
    return 43


public def code_comma() -> int:
    return 44


public def code_minus() -> int:
    return 45


public def code_dot() -> int:
    return 46


public def code_zero() -> int:
    return 48


public def code_nine() -> int:
    return 57


public def code_colon() -> int:
    return 58


public def code_semicolon() -> int:
    return 59


public def code_equals() -> int:
    return 61


public def code_underscore() -> int:
    return 95


public def code_pipe() -> int:
    return 124


# ---- the usual limits --------------------------------------------------------

public def i8_min() -> int:
    return -128


public def i8_max() -> int:
    return 127


public def i16_min() -> int:
    return -32768


public def i16_max() -> int:
    return 32767


public def i32_min() -> int:
    return -2147483648


public def i32_max() -> int:
    return 2147483647


# ===== strings.cpy =====
# Vortex engine - text and numeric helpers.
#
# Every operation here delegates to the C layer in src/engine/native.cpy:
# Cpyte's own support stops at `+` on two strings and `len()`, a character
# literal is a string pointer rather than a byte, and text cannot be built by
# appending characters.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.


public def text_len(text: str) -> int:
    return vt_strlen(text)


# Characters [begin, end) of `text`, clamped to the string bounds.
public def str_slice(text: str, begin: int, end: int) -> str:
    int length = vt_strlen(text)
    if begin < 0:
        begin = 0
    if end > length:
        end = length
    if begin >= end:
        return ""
    return vt_slice(text, begin, end)


public def str_trim(text: str) -> str:
    return vt_trim(text)


public def str_equals(a: str, b: str) -> bool:
    return vt_eq(a, b) == 1


# Ordering (-1, 0, 1) for the registry's sorted name index.
public def str_compare(a: str, b: str) -> int:
    return vt_cmp(a, b)


public def str_starts(text: str, prefix: str) -> bool:
    return vt_starts(text, prefix) == 1


# Index of the first occurrence of `needle`, or -1.
public def str_find(text: str, needle: str) -> int:
    return vt_find_str(text, needle)


# Index of the first character with code `sep` at or after `from`, or -1.
public def str_find_code(text: str, from: int, sep: int) -> int:
    return vt_find_code(text, from, sep)


# `index`th field of `line` split on `sep`. Fields are kept verbatim and
# untrimmed, so "a,,b" still reads as three fields - the registry file format
# depends on that.
public def str_field(line: str, sep: int, index: int) -> str:
    return vt_field(line, sep, index)


# Number of fields a `str_field` walk would see.
public def str_field_count(line: str, sep: int) -> int:
    return vt_count(line, sep) + 1


# Byte at `index` as an unsigned code, for comparison against the code_xxx()
# accessors in src/engine/core.cpy.
public def code_at(text: str, index: int) -> int:
    return vt_at(text, index)


# Parses a decimal integer. `ok` receives 1 on success, 0 on failure, in which
# case `fallback` is returned. (`default` is a reserved word in Cpyte, so the
# fallback value carries a different name.)
public def parse_int_or(text: str, fallback: int, ok: int*) -> int:
    int strict = 0
    int64 wide = vt_parse_int(text, &strict)
    if strict == 0:
        *ok = 0
        return fallback
    *ok = 1
    return (int)wide


public def parse_int(text: str) -> int:
    int ok = 0
    return parse_int_or(text, 0, &ok)


public def parse_float(text: str) -> float:
    int strict = 0
    return (float)vt_parse_double(text, &strict)


public def parse_bool(text: str) -> bool:
    str body = vt_trim(text)
    if vt_eq(body, "1") == 1:
        return true
    if vt_eq(body, "true") == 1:
        return true
    if vt_eq(body, "yes") == 1:
        return true
    return false


# FNV-1a over the ASCII bytes; used by the registry's name index.
public def str_hash(text: str) -> uint64:
    return (uint64)vt_fnv1a(text)


# ---- growable text -----------------------------------------------------------

# A character sink. Cpyte cannot append a character to a string, so readers
# that assemble names byte by byte build them through this instead.
struct VStr:
    char* data
    int len
    int cap


public def vstr_new(cap: int) -> VStr*:
    VStr* s = new VStr
    if cap < 16:
        cap = 16
    s.data = vt_calloc_char(cap)
    s.len = 0
    s.cap = cap
    return s


public def vstr_put(s: VStr*, code: int) -> void:
    if s.len + 1 >= s.cap:
        int cap = s.cap * 2
        char* next = vt_calloc_char(cap)
        vt_copy_bytes(next, 0, s.data, 0, s.len)
        vt_free((void*)s.data)
        s.data = next
        s.cap = cap
    vt_put(s.data, s.len, code)
    s.len += 1
    vt_put(s.data, s.len, code_nul())


public def vstr_text(s: VStr*) -> str:
    return vt_dup(s.data)


public def vstr_put_text(s: VStr*, text: str) -> void:
    int n = vt_strlen(text)
    int i = 0
    while i < n:
        vstr_put(s, vt_at(text, i))
        i += 1


public def vstr_hash(s: VStr*) -> uint64:
    return (uint64)vt_fnv1a(s.data)


public def vstr_free(s: VStr*) -> void:
    if s == null:
        return
    if s.data != null:
        vt_free((void*)s.data)
        s.data = null
    s.len = 0
    s.cap = 0
    del s


# ===== protocol_ids.cpy =====
# Vortex engine - protocol 777 packet ids (Minecraft 26.3).
#
# GENERATED by tools/gen_protocol_ids.py from the vanilla data generator's
# reports/packets.json; do not edit by hand. The report itself is not part of
# this repository (see docs/PARITY_BOUNDARY.md); these tables are transport
# metadata, not game data.
#
# States: handshake=0 status=1 login=2 configuration=3 play=4.
# Directions: clientbound=0 serverbound=1. Packet names are stored without the
# "minecraft:" namespace.


public def pkt_state_handshake() -> int:
    return 0

public def pkt_state_status() -> int:
    return 1

public def pkt_state_login() -> int:
    return 2

public def pkt_state_configuration() -> int:
    return 3

public def pkt_state_play() -> int:
    return 4

public def pkt_dir_clientbound() -> int:
    return 0

public def pkt_dir_serverbound() -> int:
    return 1

public def pkt_empty_names() -> str[]:
    str[] names = new str[0]
    return names

public def pkt_empty_ids() -> int64[]:
    int64[] ids = new int64[0]
    return ids

def pkt_names_0_0() -> str[]:
    str[] names = pkt_empty_names()
    return names

def pkt_ids_0_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    return ids

def pkt_names_0_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "intention")
    return names

def pkt_ids_0_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    return ids

def pkt_names_1_0() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "status_response")
    append(names, "pong_response")
    return names

def pkt_ids_1_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    return ids

def pkt_names_1_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "status_request")
    append(names, "ping_request")
    return names

def pkt_ids_1_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    return ids

def pkt_names_2_0() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "login_disconnect")
    append(names, "hello")
    append(names, "login_finished")
    append(names, "login_compression")
    append(names, "custom_query")
    append(names, "cookie_request")
    return names

def pkt_ids_2_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    return ids

def pkt_names_2_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "hello")
    append(names, "key")
    append(names, "custom_query_answer")
    append(names, "login_acknowledged")
    append(names, "cookie_response")
    return names

def pkt_ids_2_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    return ids

def pkt_names_3_0() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "cookie_request")
    append(names, "custom_payload")
    append(names, "disconnect")
    append(names, "finish_configuration")
    append(names, "keep_alive")
    append(names, "ping")
    append(names, "reset_chat")
    append(names, "registry_data")
    append(names, "resource_pack_pop")
    append(names, "resource_pack_push")
    append(names, "post_effects")
    append(names, "store_cookie")
    append(names, "transfer")
    append(names, "update_enabled_features")
    append(names, "update_tags")
    append(names, "select_known_packs")
    append(names, "custom_report_details")
    append(names, "server_links")
    append(names, "clear_dialog")
    append(names, "show_dialog")
    append(names, "code_of_conduct")
    return names

def pkt_ids_3_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    append(ids, 6)
    append(ids, 7)
    append(ids, 8)
    append(ids, 9)
    append(ids, 10)
    append(ids, 11)
    append(ids, 12)
    append(ids, 13)
    append(ids, 14)
    append(ids, 15)
    append(ids, 16)
    append(ids, 17)
    append(ids, 18)
    append(ids, 19)
    append(ids, 20)
    return ids

def pkt_names_3_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "client_information")
    append(names, "cookie_response")
    append(names, "custom_payload")
    append(names, "finish_configuration")
    append(names, "keep_alive")
    append(names, "pong")
    append(names, "resource_pack")
    append(names, "select_known_packs")
    append(names, "custom_click_action")
    append(names, "accept_code_of_conduct")
    return names

def pkt_ids_3_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    append(ids, 6)
    append(ids, 7)
    append(ids, 8)
    append(ids, 9)
    return ids

def pkt_names_4_0() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "bundle_delimiter")
    append(names, "add_entity")
    append(names, "animate")
    append(names, "award_stats")
    append(names, "block_changed_ack")
    append(names, "block_destruction")
    append(names, "block_entity_data")
    append(names, "block_event")
    append(names, "block_update")
    append(names, "boss_event")
    append(names, "change_difficulty")
    append(names, "chunk_batch_finished")
    append(names, "chunk_batch_start")
    append(names, "chunks_biomes")
    append(names, "clear_titles")
    append(names, "command_suggestions")
    append(names, "commands")
    append(names, "container_close")
    append(names, "container_set_content")
    append(names, "container_set_data")
    append(names, "container_set_slot")
    append(names, "cookie_request")
    append(names, "cooldown")
    append(names, "custom_chat_completions")
    append(names, "custom_payload")
    append(names, "damage_event")
    append(names, "debug/block_value")
    append(names, "debug/chunk_value")
    append(names, "debug/entity_value")
    append(names, "debug/event")
    append(names, "debug_sample")
    append(names, "delete_chat")
    append(names, "disconnect")
    append(names, "disguised_chat")
    append(names, "entity_event")
    append(names, "entity_position_sync")
    append(names, "explode")
    append(names, "add_transient_block")
    append(names, "forget_level_chunk")
    append(names, "game_event")
    append(names, "game_rule_values")
    append(names, "game_test_highlight_pos")
    append(names, "mount_screen_open")
    append(names, "hurt_animation")
    append(names, "initialize_border")
    append(names, "keep_alive")
    append(names, "level_chunk_with_light")
    append(names, "level_event")
    append(names, "level_particles")
    append(names, "light_update")
    append(names, "login")
    append(names, "low_disk_space_warning")
    append(names, "map_item_data")
    append(names, "merchant_offers")
    append(names, "move_entity_pos")
    append(names, "move_entity_pos_rot")
    append(names, "move_minecart_along_track")
    append(names, "move_entity_rot")
    append(names, "move_vehicle")
    append(names, "open_book")
    append(names, "open_screen")
    append(names, "open_sign_editor")
    append(names, "ping")
    append(names, "pong_response")
    append(names, "place_ghost_recipe")
    append(names, "player_abilities")
    append(names, "player_chat")
    append(names, "player_combat_end")
    append(names, "player_combat_enter")
    append(names, "player_combat_kill")
    append(names, "player_info_remove")
    append(names, "player_info_update")
    append(names, "player_look_at")
    append(names, "player_position")
    append(names, "player_rotation")
    append(names, "recipe_book_add")
    append(names, "recipe_book_remove")
    append(names, "recipe_book_settings")
    append(names, "remove_entities")
    append(names, "remove_mob_effect")
    append(names, "reset_score")
    append(names, "resource_pack_pop")
    append(names, "resource_pack_push")
    append(names, "post_effects")
    append(names, "respawn")
    append(names, "rotate_head")
    append(names, "section_blocks_update")
    append(names, "select_advancements_tab")
    append(names, "server_data")
    append(names, "set_action_bar_text")
    append(names, "set_border_center")
    append(names, "set_border_lerp_size")
    append(names, "set_border_size")
    append(names, "set_border_warning_delay")
    append(names, "set_border_warning_distance")
    append(names, "set_camera")
    append(names, "set_chunk_cache_center")
    append(names, "set_chunk_cache_radius")
    append(names, "set_cursor_item")
    append(names, "set_default_spawn_position")
    append(names, "set_display_objective")
    append(names, "set_entity_data")
    append(names, "set_entity_link")
    append(names, "set_entity_motion")
    append(names, "set_equipment")
    append(names, "set_experience")
    append(names, "set_health")
    append(names, "set_held_slot")
    append(names, "set_objective")
    append(names, "set_passengers")
    append(names, "set_player_inventory")
    append(names, "set_player_team")
    append(names, "set_score")
    append(names, "set_simulation_distance")
    append(names, "set_subtitle_text")
    append(names, "set_time")
    append(names, "set_title_text")
    append(names, "set_titles_animation")
    append(names, "sound_entity")
    append(names, "sound")
    append(names, "start_configuration")
    append(names, "stop_sound")
    append(names, "store_cookie")
    append(names, "swing_animation")
    append(names, "system_chat")
    append(names, "tab_list")
    append(names, "tag_query")
    append(names, "take_item_entity")
    append(names, "teleport_entity")
    append(names, "test_instance_block_status")
    append(names, "ticking_state")
    append(names, "ticking_step")
    append(names, "transfer")
    append(names, "update_advancements")
    append(names, "update_attributes")
    append(names, "update_mob_effect")
    append(names, "update_recipes")
    append(names, "update_tags")
    append(names, "projectile_power")
    append(names, "custom_report_details")
    append(names, "server_links")
    append(names, "waypoint")
    append(names, "clear_dialog")
    append(names, "show_dialog")
    return names

def pkt_ids_4_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    append(ids, 6)
    append(ids, 7)
    append(ids, 8)
    append(ids, 9)
    append(ids, 10)
    append(ids, 11)
    append(ids, 12)
    append(ids, 13)
    append(ids, 14)
    append(ids, 15)
    append(ids, 16)
    append(ids, 17)
    append(ids, 18)
    append(ids, 19)
    append(ids, 20)
    append(ids, 21)
    append(ids, 22)
    append(ids, 23)
    append(ids, 24)
    append(ids, 25)
    append(ids, 26)
    append(ids, 27)
    append(ids, 28)
    append(ids, 29)
    append(ids, 30)
    append(ids, 31)
    append(ids, 32)
    append(ids, 33)
    append(ids, 34)
    append(ids, 35)
    append(ids, 36)
    append(ids, 37)
    append(ids, 38)
    append(ids, 39)
    append(ids, 40)
    append(ids, 41)
    append(ids, 42)
    append(ids, 43)
    append(ids, 44)
    append(ids, 45)
    append(ids, 46)
    append(ids, 47)
    append(ids, 48)
    append(ids, 49)
    append(ids, 50)
    append(ids, 51)
    append(ids, 52)
    append(ids, 53)
    append(ids, 54)
    append(ids, 55)
    append(ids, 56)
    append(ids, 57)
    append(ids, 58)
    append(ids, 59)
    append(ids, 60)
    append(ids, 61)
    append(ids, 62)
    append(ids, 63)
    append(ids, 64)
    append(ids, 65)
    append(ids, 66)
    append(ids, 67)
    append(ids, 68)
    append(ids, 69)
    append(ids, 70)
    append(ids, 71)
    append(ids, 72)
    append(ids, 73)
    append(ids, 74)
    append(ids, 75)
    append(ids, 76)
    append(ids, 77)
    append(ids, 78)
    append(ids, 79)
    append(ids, 80)
    append(ids, 81)
    append(ids, 82)
    append(ids, 83)
    append(ids, 84)
    append(ids, 85)
    append(ids, 86)
    append(ids, 87)
    append(ids, 88)
    append(ids, 89)
    append(ids, 90)
    append(ids, 91)
    append(ids, 92)
    append(ids, 93)
    append(ids, 94)
    append(ids, 95)
    append(ids, 96)
    append(ids, 97)
    append(ids, 98)
    append(ids, 99)
    append(ids, 100)
    append(ids, 101)
    append(ids, 102)
    append(ids, 103)
    append(ids, 104)
    append(ids, 105)
    append(ids, 106)
    append(ids, 107)
    append(ids, 108)
    append(ids, 109)
    append(ids, 110)
    append(ids, 111)
    append(ids, 112)
    append(ids, 113)
    append(ids, 114)
    append(ids, 115)
    append(ids, 116)
    append(ids, 117)
    append(ids, 118)
    append(ids, 119)
    append(ids, 120)
    append(ids, 121)
    append(ids, 122)
    append(ids, 123)
    append(ids, 124)
    append(ids, 125)
    append(ids, 126)
    append(ids, 127)
    append(ids, 128)
    append(ids, 129)
    append(ids, 130)
    append(ids, 131)
    append(ids, 132)
    append(ids, 133)
    append(ids, 134)
    append(ids, 135)
    append(ids, 136)
    append(ids, 137)
    append(ids, 138)
    append(ids, 139)
    append(ids, 140)
    append(ids, 141)
    append(ids, 142)
    append(ids, 143)
    return ids

def pkt_names_4_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "accept_teleportation")
    append(names, "attack")
    append(names, "block_entity_tag_query")
    append(names, "bundle_item_selected")
    append(names, "change_difficulty")
    append(names, "change_game_mode")
    append(names, "chat_ack")
    append(names, "chat_command")
    append(names, "chat_command_signed")
    append(names, "chat")
    append(names, "chat_session_update")
    append(names, "chunk_batch_received")
    append(names, "client_command")
    append(names, "client_tick_end")
    append(names, "client_information")
    append(names, "command_suggestion")
    append(names, "configuration_acknowledged")
    append(names, "container_button_click")
    append(names, "container_click")
    append(names, "container_close")
    append(names, "container_slot_state_changed")
    append(names, "cookie_response")
    append(names, "custom_payload")
    append(names, "debug_subscription_request")
    append(names, "edit_book")
    append(names, "entity_tag_query")
    append(names, "interact")
    append(names, "jigsaw_generate")
    append(names, "keep_alive")
    append(names, "lock_difficulty")
    append(names, "move_player_pos")
    append(names, "move_player_pos_rot")
    append(names, "move_player_rot")
    append(names, "move_player_status_only")
    append(names, "move_vehicle")
    append(names, "paddle_boat")
    append(names, "pick_item_from_block")
    append(names, "pick_item_from_entity")
    append(names, "ping_request")
    append(names, "place_recipe")
    append(names, "player_abilities")
    append(names, "player_action")
    append(names, "player_command")
    append(names, "player_input")
    append(names, "player_loaded")
    append(names, "pong")
    append(names, "punch")
    append(names, "recipe_book_change_settings")
    append(names, "recipe_book_seen_recipe")
    append(names, "rename_item")
    append(names, "resource_pack")
    append(names, "seen_advancements")
    append(names, "select_trade")
    append(names, "set_beacon")
    append(names, "set_carried_item")
    append(names, "set_command_block")
    append(names, "set_command_minecart")
    append(names, "set_creative_mode_slot")
    append(names, "set_game_rule")
    append(names, "set_jigsaw_block")
    append(names, "set_structure_block")
    append(names, "set_test_block")
    append(names, "sign_update")
    append(names, "spectator_action")
    append(names, "teleport_to_entity")
    append(names, "test_instance_block_action")
    append(names, "use_item_on")
    append(names, "use_item")
    append(names, "custom_click_action")
    return names

def pkt_ids_4_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    append(ids, 6)
    append(ids, 7)
    append(ids, 8)
    append(ids, 9)
    append(ids, 10)
    append(ids, 11)
    append(ids, 12)
    append(ids, 13)
    append(ids, 14)
    append(ids, 15)
    append(ids, 16)
    append(ids, 17)
    append(ids, 18)
    append(ids, 19)
    append(ids, 20)
    append(ids, 21)
    append(ids, 22)
    append(ids, 23)
    append(ids, 24)
    append(ids, 25)
    append(ids, 26)
    append(ids, 27)
    append(ids, 28)
    append(ids, 29)
    append(ids, 30)
    append(ids, 31)
    append(ids, 32)
    append(ids, 33)
    append(ids, 34)
    append(ids, 35)
    append(ids, 36)
    append(ids, 37)
    append(ids, 38)
    append(ids, 39)
    append(ids, 40)
    append(ids, 41)
    append(ids, 42)
    append(ids, 43)
    append(ids, 44)
    append(ids, 45)
    append(ids, 46)
    append(ids, 47)
    append(ids, 48)
    append(ids, 49)
    append(ids, 50)
    append(ids, 51)
    append(ids, 52)
    append(ids, 53)
    append(ids, 54)
    append(ids, 55)
    append(ids, 56)
    append(ids, 57)
    append(ids, 58)
    append(ids, 59)
    append(ids, 60)
    append(ids, 61)
    append(ids, 62)
    append(ids, 63)
    append(ids, 64)
    append(ids, 65)
    append(ids, 66)
    append(ids, 67)
    append(ids, 68)
    return ids

# Names indexed by packet id for one state/direction; empty for an
# unknown state or direction.
public def pkt_names(state: int, direction: int) -> str[]:
    if state == pkt_state_handshake() and direction == pkt_dir_clientbound():
        return pkt_names_0_0()
    if state == pkt_state_handshake() and direction == pkt_dir_serverbound():
        return pkt_names_0_1()
    if state == pkt_state_status() and direction == pkt_dir_clientbound():
        return pkt_names_1_0()
    if state == pkt_state_status() and direction == pkt_dir_serverbound():
        return pkt_names_1_1()
    if state == pkt_state_login() and direction == pkt_dir_clientbound():
        return pkt_names_2_0()
    if state == pkt_state_login() and direction == pkt_dir_serverbound():
        return pkt_names_2_1()
    if state == pkt_state_configuration() and direction == pkt_dir_clientbound():
        return pkt_names_3_0()
    if state == pkt_state_configuration() and direction == pkt_dir_serverbound():
        return pkt_names_3_1()
    if state == pkt_state_play() and direction == pkt_dir_clientbound():
        return pkt_names_4_0()
    if state == pkt_state_play() and direction == pkt_dir_serverbound():
        return pkt_names_4_1()
    return pkt_empty_names()

public def pkt_table_ids(state: int, direction: int) -> int64[]:
    if state == pkt_state_handshake() and direction == pkt_dir_clientbound():
        return pkt_ids_0_0()
    if state == pkt_state_handshake() and direction == pkt_dir_serverbound():
        return pkt_ids_0_1()
    if state == pkt_state_status() and direction == pkt_dir_clientbound():
        return pkt_ids_1_0()
    if state == pkt_state_status() and direction == pkt_dir_serverbound():
        return pkt_ids_1_1()
    if state == pkt_state_login() and direction == pkt_dir_clientbound():
        return pkt_ids_2_0()
    if state == pkt_state_login() and direction == pkt_dir_serverbound():
        return pkt_ids_2_1()
    if state == pkt_state_configuration() and direction == pkt_dir_clientbound():
        return pkt_ids_3_0()
    if state == pkt_state_configuration() and direction == pkt_dir_serverbound():
        return pkt_ids_3_1()
    if state == pkt_state_play() and direction == pkt_dir_clientbound():
        return pkt_ids_4_0()
    if state == pkt_state_play() and direction == pkt_dir_serverbound():
        return pkt_ids_4_1()
    return pkt_empty_ids()

public def pkt_count(state: int, direction: int) -> int:
    return (int)len(pkt_names(state, direction))

# Numeric id of `name` in one table, or -1. `name` may be bare or
# namespace qualified.
public def pkt_id(state: int, direction: int, name: str) -> int:
    str bare = name
    if str_starts(bare, "minecraft:"):
        bare = str_slice(bare, 10, text_len(bare))
    str[] names = pkt_names(state, direction)
    int i = 0
    while i < (int)len(names):
        if str_equals(names[i], bare):
            return i
        i += 1
    return -1

# Namespace-qualified name of packet `packet_id`, or "" when absent.
public def pkt_name(state: int, direction: int, packet_id: int) -> str:
    str[] names = pkt_names(state, direction)
    if packet_id < 0 or packet_id >= (int)len(names):
        return ""
    return "minecraft:" + names[packet_id]

public def pkt_known(state: int, direction: int, packet_id: int) -> bool:
    if packet_id < 0:
        return false
    return packet_id < pkt_count(state, direction)

# FNV-1a over "name=id\n" for every entry, masked to 31 bits, so a
# test can pin the whole table without duplicating it.
public def pkt_table_digest(state: int, direction: int) -> uint64:
    VStr* sink = vstr_new(4096)
    str[] names = pkt_names(state, direction)
    int i = 0
    while i < (int)len(names):
        vstr_put_text(sink, names[i])
        vstr_put(sink, code_equals())
        vstr_put_text(sink, str(i))
        vstr_put(sink, code_newline())
        i += 1
    uint64 hash = vstr_hash(sink)
    vstr_free(sink)
    return hash

public def pid_hs_s_intention() -> int:
    return 0

public def pid_st_c_status_response() -> int:
    return 0

public def pid_st_c_pong_response() -> int:
    return 1

public def pid_st_s_status_request() -> int:
    return 0

public def pid_st_s_ping_request() -> int:
    return 1

public def pid_lg_c_login_disconnect() -> int:
    return 0

public def pid_lg_c_hello() -> int:
    return 1

public def pid_lg_c_login_finished() -> int:
    return 2

public def pid_lg_c_login_compression() -> int:
    return 3

public def pid_lg_c_custom_query() -> int:
    return 4

public def pid_lg_c_cookie_request() -> int:
    return 5

public def pid_lg_s_hello() -> int:
    return 0

public def pid_lg_s_key() -> int:
    return 1

public def pid_lg_s_custom_query_answer() -> int:
    return 2

public def pid_lg_s_login_acknowledged() -> int:
    return 3

public def pid_lg_s_cookie_response() -> int:
    return 4

public def pid_cfg_c_cookie_request() -> int:
    return 0

public def pid_cfg_c_custom_payload() -> int:
    return 1

public def pid_cfg_c_disconnect() -> int:
    return 2

public def pid_cfg_c_finish_configuration() -> int:
    return 3

public def pid_cfg_c_keep_alive() -> int:
    return 4

public def pid_cfg_c_ping() -> int:
    return 5

public def pid_cfg_c_reset_chat() -> int:
    return 6

public def pid_cfg_c_registry_data() -> int:
    return 7

public def pid_cfg_c_resource_pack_pop() -> int:
    return 8

public def pid_cfg_c_resource_pack_push() -> int:
    return 9

public def pid_cfg_c_post_effects() -> int:
    return 10

public def pid_cfg_c_store_cookie() -> int:
    return 11

public def pid_cfg_c_transfer() -> int:
    return 12

public def pid_cfg_c_update_enabled_features() -> int:
    return 13

public def pid_cfg_c_update_tags() -> int:
    return 14

public def pid_cfg_c_select_known_packs() -> int:
    return 15

public def pid_cfg_c_custom_report_details() -> int:
    return 16

public def pid_cfg_c_server_links() -> int:
    return 17

public def pid_cfg_c_clear_dialog() -> int:
    return 18

public def pid_cfg_c_show_dialog() -> int:
    return 19

public def pid_cfg_c_code_of_conduct() -> int:
    return 20

public def pid_cfg_s_client_information() -> int:
    return 0

public def pid_cfg_s_cookie_response() -> int:
    return 1

public def pid_cfg_s_custom_payload() -> int:
    return 2

public def pid_cfg_s_finish_configuration() -> int:
    return 3

public def pid_cfg_s_keep_alive() -> int:
    return 4

public def pid_cfg_s_pong() -> int:
    return 5

public def pid_cfg_s_resource_pack() -> int:
    return 6

public def pid_cfg_s_select_known_packs() -> int:
    return 7

public def pid_cfg_s_custom_click_action() -> int:
    return 8

public def pid_cfg_s_accept_code_of_conduct() -> int:
    return 9

public def pid_pl_c_bundle_delimiter() -> int:
    return 0

public def pid_pl_c_add_entity() -> int:
    return 1

public def pid_pl_c_animate() -> int:
    return 2

public def pid_pl_c_award_stats() -> int:
    return 3

public def pid_pl_c_block_changed_ack() -> int:
    return 4

public def pid_pl_c_block_destruction() -> int:
    return 5

public def pid_pl_c_block_entity_data() -> int:
    return 6

public def pid_pl_c_block_event() -> int:
    return 7

public def pid_pl_c_block_update() -> int:
    return 8

public def pid_pl_c_boss_event() -> int:
    return 9

public def pid_pl_c_change_difficulty() -> int:
    return 10

public def pid_pl_c_chunk_batch_finished() -> int:
    return 11

public def pid_pl_c_chunk_batch_start() -> int:
    return 12

public def pid_pl_c_chunks_biomes() -> int:
    return 13

public def pid_pl_c_clear_titles() -> int:
    return 14

public def pid_pl_c_command_suggestions() -> int:
    return 15

public def pid_pl_c_commands() -> int:
    return 16

public def pid_pl_c_container_close() -> int:
    return 17

public def pid_pl_c_container_set_content() -> int:
    return 18

public def pid_pl_c_container_set_data() -> int:
    return 19

public def pid_pl_c_container_set_slot() -> int:
    return 20

public def pid_pl_c_cookie_request() -> int:
    return 21

public def pid_pl_c_cooldown() -> int:
    return 22

public def pid_pl_c_custom_chat_completions() -> int:
    return 23

public def pid_pl_c_custom_payload() -> int:
    return 24

public def pid_pl_c_damage_event() -> int:
    return 25

public def pid_pl_c_debug_block_value() -> int:
    return 26

public def pid_pl_c_debug_chunk_value() -> int:
    return 27

public def pid_pl_c_debug_entity_value() -> int:
    return 28

public def pid_pl_c_debug_event() -> int:
    return 29

public def pid_pl_c_debug_sample() -> int:
    return 30

public def pid_pl_c_delete_chat() -> int:
    return 31

public def pid_pl_c_disconnect() -> int:
    return 32

public def pid_pl_c_disguised_chat() -> int:
    return 33

public def pid_pl_c_entity_event() -> int:
    return 34

public def pid_pl_c_entity_position_sync() -> int:
    return 35

public def pid_pl_c_explode() -> int:
    return 36

public def pid_pl_c_add_transient_block() -> int:
    return 37

public def pid_pl_c_forget_level_chunk() -> int:
    return 38

public def pid_pl_c_game_event() -> int:
    return 39

public def pid_pl_c_game_rule_values() -> int:
    return 40

public def pid_pl_c_game_test_highlight_pos() -> int:
    return 41

public def pid_pl_c_mount_screen_open() -> int:
    return 42

public def pid_pl_c_hurt_animation() -> int:
    return 43

public def pid_pl_c_initialize_border() -> int:
    return 44

public def pid_pl_c_keep_alive() -> int:
    return 45

public def pid_pl_c_level_chunk_with_light() -> int:
    return 46

public def pid_pl_c_level_event() -> int:
    return 47

public def pid_pl_c_level_particles() -> int:
    return 48

public def pid_pl_c_light_update() -> int:
    return 49

public def pid_pl_c_login() -> int:
    return 50

public def pid_pl_c_low_disk_space_warning() -> int:
    return 51

public def pid_pl_c_map_item_data() -> int:
    return 52

public def pid_pl_c_merchant_offers() -> int:
    return 53

public def pid_pl_c_move_entity_pos() -> int:
    return 54

public def pid_pl_c_move_entity_pos_rot() -> int:
    return 55

public def pid_pl_c_move_minecart_along_track() -> int:
    return 56

public def pid_pl_c_move_entity_rot() -> int:
    return 57

public def pid_pl_c_move_vehicle() -> int:
    return 58

public def pid_pl_c_open_book() -> int:
    return 59

public def pid_pl_c_open_screen() -> int:
    return 60

public def pid_pl_c_open_sign_editor() -> int:
    return 61

public def pid_pl_c_ping() -> int:
    return 62

public def pid_pl_c_pong_response() -> int:
    return 63

public def pid_pl_c_place_ghost_recipe() -> int:
    return 64

public def pid_pl_c_player_abilities() -> int:
    return 65

public def pid_pl_c_player_chat() -> int:
    return 66

public def pid_pl_c_player_combat_end() -> int:
    return 67

public def pid_pl_c_player_combat_enter() -> int:
    return 68

public def pid_pl_c_player_combat_kill() -> int:
    return 69

public def pid_pl_c_player_info_remove() -> int:
    return 70

public def pid_pl_c_player_info_update() -> int:
    return 71

public def pid_pl_c_player_look_at() -> int:
    return 72

public def pid_pl_c_player_position() -> int:
    return 73

public def pid_pl_c_player_rotation() -> int:
    return 74

public def pid_pl_c_recipe_book_add() -> int:
    return 75

public def pid_pl_c_recipe_book_remove() -> int:
    return 76

public def pid_pl_c_recipe_book_settings() -> int:
    return 77

public def pid_pl_c_remove_entities() -> int:
    return 78

public def pid_pl_c_remove_mob_effect() -> int:
    return 79

public def pid_pl_c_reset_score() -> int:
    return 80

public def pid_pl_c_resource_pack_pop() -> int:
    return 81

public def pid_pl_c_resource_pack_push() -> int:
    return 82

public def pid_pl_c_post_effects() -> int:
    return 83

public def pid_pl_c_respawn() -> int:
    return 84

public def pid_pl_c_rotate_head() -> int:
    return 85

public def pid_pl_c_section_blocks_update() -> int:
    return 86

public def pid_pl_c_select_advancements_tab() -> int:
    return 87

public def pid_pl_c_server_data() -> int:
    return 88

public def pid_pl_c_set_action_bar_text() -> int:
    return 89

public def pid_pl_c_set_border_center() -> int:
    return 90

public def pid_pl_c_set_border_lerp_size() -> int:
    return 91

public def pid_pl_c_set_border_size() -> int:
    return 92

public def pid_pl_c_set_border_warning_delay() -> int:
    return 93

public def pid_pl_c_set_border_warning_distance() -> int:
    return 94

public def pid_pl_c_set_camera() -> int:
    return 95

public def pid_pl_c_set_chunk_cache_center() -> int:
    return 96

public def pid_pl_c_set_chunk_cache_radius() -> int:
    return 97

public def pid_pl_c_set_cursor_item() -> int:
    return 98

public def pid_pl_c_set_default_spawn_position() -> int:
    return 99

public def pid_pl_c_set_display_objective() -> int:
    return 100

public def pid_pl_c_set_entity_data() -> int:
    return 101

public def pid_pl_c_set_entity_link() -> int:
    return 102

public def pid_pl_c_set_entity_motion() -> int:
    return 103

public def pid_pl_c_set_equipment() -> int:
    return 104

public def pid_pl_c_set_experience() -> int:
    return 105

public def pid_pl_c_set_health() -> int:
    return 106

public def pid_pl_c_set_held_slot() -> int:
    return 107

public def pid_pl_c_set_objective() -> int:
    return 108

public def pid_pl_c_set_passengers() -> int:
    return 109

public def pid_pl_c_set_player_inventory() -> int:
    return 110

public def pid_pl_c_set_player_team() -> int:
    return 111

public def pid_pl_c_set_score() -> int:
    return 112

public def pid_pl_c_set_simulation_distance() -> int:
    return 113

public def pid_pl_c_set_subtitle_text() -> int:
    return 114

public def pid_pl_c_set_time() -> int:
    return 115

public def pid_pl_c_set_title_text() -> int:
    return 116

public def pid_pl_c_set_titles_animation() -> int:
    return 117

public def pid_pl_c_sound_entity() -> int:
    return 118

public def pid_pl_c_sound() -> int:
    return 119

public def pid_pl_c_start_configuration() -> int:
    return 120

public def pid_pl_c_stop_sound() -> int:
    return 121

public def pid_pl_c_store_cookie() -> int:
    return 122

public def pid_pl_c_swing_animation() -> int:
    return 123

public def pid_pl_c_system_chat() -> int:
    return 124

public def pid_pl_c_tab_list() -> int:
    return 125

public def pid_pl_c_tag_query() -> int:
    return 126

public def pid_pl_c_take_item_entity() -> int:
    return 127

public def pid_pl_c_teleport_entity() -> int:
    return 128

public def pid_pl_c_test_instance_block_status() -> int:
    return 129

public def pid_pl_c_ticking_state() -> int:
    return 130

public def pid_pl_c_ticking_step() -> int:
    return 131

public def pid_pl_c_transfer() -> int:
    return 132

public def pid_pl_c_update_advancements() -> int:
    return 133

public def pid_pl_c_update_attributes() -> int:
    return 134

public def pid_pl_c_update_mob_effect() -> int:
    return 135

public def pid_pl_c_update_recipes() -> int:
    return 136

public def pid_pl_c_update_tags() -> int:
    return 137

public def pid_pl_c_projectile_power() -> int:
    return 138

public def pid_pl_c_custom_report_details() -> int:
    return 139

public def pid_pl_c_server_links() -> int:
    return 140

public def pid_pl_c_waypoint() -> int:
    return 141

public def pid_pl_c_clear_dialog() -> int:
    return 142

public def pid_pl_c_show_dialog() -> int:
    return 143

public def pid_pl_s_accept_teleportation() -> int:
    return 0

public def pid_pl_s_attack() -> int:
    return 1

public def pid_pl_s_block_entity_tag_query() -> int:
    return 2

public def pid_pl_s_bundle_item_selected() -> int:
    return 3

public def pid_pl_s_change_difficulty() -> int:
    return 4

public def pid_pl_s_change_game_mode() -> int:
    return 5

public def pid_pl_s_chat_ack() -> int:
    return 6

public def pid_pl_s_chat_command() -> int:
    return 7

public def pid_pl_s_chat_command_signed() -> int:
    return 8

public def pid_pl_s_chat() -> int:
    return 9

public def pid_pl_s_chat_session_update() -> int:
    return 10

public def pid_pl_s_chunk_batch_received() -> int:
    return 11

public def pid_pl_s_client_command() -> int:
    return 12

public def pid_pl_s_client_tick_end() -> int:
    return 13

public def pid_pl_s_client_information() -> int:
    return 14

public def pid_pl_s_command_suggestion() -> int:
    return 15

public def pid_pl_s_configuration_acknowledged() -> int:
    return 16

public def pid_pl_s_container_button_click() -> int:
    return 17

public def pid_pl_s_container_click() -> int:
    return 18

public def pid_pl_s_container_close() -> int:
    return 19

public def pid_pl_s_container_slot_state_changed() -> int:
    return 20

public def pid_pl_s_cookie_response() -> int:
    return 21

public def pid_pl_s_custom_payload() -> int:
    return 22

public def pid_pl_s_debug_subscription_request() -> int:
    return 23

public def pid_pl_s_edit_book() -> int:
    return 24

public def pid_pl_s_entity_tag_query() -> int:
    return 25

public def pid_pl_s_interact() -> int:
    return 26

public def pid_pl_s_jigsaw_generate() -> int:
    return 27

public def pid_pl_s_keep_alive() -> int:
    return 28

public def pid_pl_s_lock_difficulty() -> int:
    return 29

public def pid_pl_s_move_player_pos() -> int:
    return 30

public def pid_pl_s_move_player_pos_rot() -> int:
    return 31

public def pid_pl_s_move_player_rot() -> int:
    return 32

public def pid_pl_s_move_player_status_only() -> int:
    return 33

public def pid_pl_s_move_vehicle() -> int:
    return 34

public def pid_pl_s_paddle_boat() -> int:
    return 35

public def pid_pl_s_pick_item_from_block() -> int:
    return 36

public def pid_pl_s_pick_item_from_entity() -> int:
    return 37

public def pid_pl_s_ping_request() -> int:
    return 38

public def pid_pl_s_place_recipe() -> int:
    return 39

public def pid_pl_s_player_abilities() -> int:
    return 40

public def pid_pl_s_player_action() -> int:
    return 41

public def pid_pl_s_player_command() -> int:
    return 42

public def pid_pl_s_player_input() -> int:
    return 43

public def pid_pl_s_player_loaded() -> int:
    return 44

public def pid_pl_s_pong() -> int:
    return 45

public def pid_pl_s_punch() -> int:
    return 46

public def pid_pl_s_recipe_book_change_settings() -> int:
    return 47

public def pid_pl_s_recipe_book_seen_recipe() -> int:
    return 48

public def pid_pl_s_rename_item() -> int:
    return 49

public def pid_pl_s_resource_pack() -> int:
    return 50

public def pid_pl_s_seen_advancements() -> int:
    return 51

public def pid_pl_s_select_trade() -> int:
    return 52

public def pid_pl_s_set_beacon() -> int:
    return 53

public def pid_pl_s_set_carried_item() -> int:
    return 54

public def pid_pl_s_set_command_block() -> int:
    return 55

public def pid_pl_s_set_command_minecart() -> int:
    return 56

public def pid_pl_s_set_creative_mode_slot() -> int:
    return 57

public def pid_pl_s_set_game_rule() -> int:
    return 58

public def pid_pl_s_set_jigsaw_block() -> int:
    return 59

public def pid_pl_s_set_structure_block() -> int:
    return 60

public def pid_pl_s_set_test_block() -> int:
    return 61

public def pid_pl_s_sign_update() -> int:
    return 62

public def pid_pl_s_spectator_action() -> int:
    return 63

public def pid_pl_s_teleport_to_entity() -> int:
    return 64

public def pid_pl_s_test_instance_block_action() -> int:
    return 65

public def pid_pl_s_use_item_on() -> int:
    return 66

public def pid_pl_s_use_item() -> int:
    return 67

public def pid_pl_s_custom_click_action() -> int:
    return 68



# ===== vbuf.cpy =====
# Vortex engine - growable byte buffer and the variable length integer
# encodings used by world data (chunk palettes, region files).
#
# The varint / varlong rules are the ones published by the community protocol
# references; no Mojang byte code or decompiled source was consulted.
# See docs/PARITY_BOUNDARY.md.
#
# Byte access goes through vt_at / vt_put rather than `b.data[i]`: the C layer
# is the only place the engine is known to index raw memory reliably.


struct VBuf:
    char* data       # owned, zero initialised, grows by doubling
    int len          # bytes written
    int cap          # bytes allocated
    int pos          # read cursor for the take_* helpers


public def vbuf_min_cap() -> int:
    return 512


public def vbuf_new(cap: int) -> VBuf*:
    VBuf* b = new VBuf
    if cap < vbuf_min_cap():
        cap = vbuf_min_cap()
    b.data = vt_calloc_char(cap)
    b.len = 0
    b.cap = cap
    b.pos = 0
    return b


public def vbuf_free(b: VBuf*) -> void:
    if b == null:
        return
    if b.data != null:
        vt_free((void*)b.data)
        b.data = null
    b.len = 0
    b.cap = 0
    b.pos = 0
    del b


public def vbuf_reset(b: VBuf*) -> void:
    b.len = 0
    b.pos = 0


public def vbuf_ensure(b: VBuf*, need: int) -> void:
    if need <= b.cap:
        return
    int cap = b.cap
    while cap < need:
        cap = cap * 2
    char* next = vt_calloc_char(cap)
    vt_copy_bytes(next, 0, b.data, 0, b.len)
    if b.data != null:
        vt_free((void*)b.data)
    b.data = next
    b.cap = cap


# Byte value as an unsigned 0..255 integer.
public def vbuf_at(b: VBuf*, index: int) -> uint64:
    if index < 0 or index >= b.len:
        return (uint64)0
    return (uint64)vt_at(b.data, index)


# ---- little endian -----------------------------------------------------------

public def vbuf_put_u8(b: VBuf*, v: uint64) -> void:
    vbuf_ensure(b, b.len + 1)
    vt_put(b.data, b.len, (int)(v & (uint64)255))
    b.len += 1


public def vbuf_put_u16_le(b: VBuf*, v: uint64) -> void:
    vbuf_put_u8(b, v & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)8) & (uint64)255)


public def vbuf_put_u32_le(b: VBuf*, v: uint64) -> void:
    vbuf_put_u8(b, v & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)8) & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)16) & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)24) & (uint64)255)


public def vbuf_put_u64_le(b: VBuf*, v: uint64) -> void:
    int i = 0
    while i < 8:
        vbuf_put_u8(b, (v >> ((uint64)i * (uint64)8)) & (uint64)255)
        i += 1


# ---- big endian --------------------------------------------------------------

public def vbuf_put_u16_be(b: VBuf*, v: uint64) -> void:
    vbuf_put_u8(b, (v >> (uint64)8) & (uint64)255)
    vbuf_put_u8(b, v & (uint64)255)


public def vbuf_put_u32_be(b: VBuf*, v: uint64) -> void:
    vbuf_put_u8(b, (v >> (uint64)24) & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)16) & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)8) & (uint64)255)
    vbuf_put_u8(b, v & (uint64)255)


public def vbuf_put_u64_be(b: VBuf*, v: uint64) -> void:
    vbuf_put_u32_be(b, (v >> (uint64)32) & (uint64)4294967295)
    vbuf_put_u32_be(b, v & (uint64)4294967295)


public def vbuf_put_i64_be(b: VBuf*, v: int64) -> void:
    vbuf_put_u64_be(b, (uint64)v)


public def vbuf_put_i8(b: VBuf*, v: int) -> void:
    vbuf_put_u8(b, (uint64)(v & 255))


public def vbuf_put_i16_be(b: VBuf*, v: int) -> void:
    vbuf_put_u16_be(b, (uint64)(v & 65535))


public def vbuf_put_i32_be(b: VBuf*, v: int) -> void:
    vbuf_put_u32_be(b, (uint64)v & (uint64)4294967295)


public def vbuf_put_f32_be(b: VBuf*, v: float) -> void:
    vbuf_put_u32_be(b, (uint64)vt_float_to_bits(v))


public def vbuf_put_f64_be(b: VBuf*, v: double) -> void:
    vbuf_put_u64_be(b, vt_double_to_bits(v))


# ---- varint / varlong --------------------------------------------------------

# A VarInt is the low 32 bits of the value in 7-bit little-endian groups, so a
# negative int runs to the full five groups. The group loop lives in C: Cpyte
# compares uint64 relationally as a signed value, which makes the "more groups
# follow?" test come out wrong for every negative number.
public def vbuf_put_varint(b: VBuf*, value: int) -> void:
    vbuf_ensure(b, b.len + 5)
    int n = vt_write_varint_at(b.data, b.len, value)
    b.len += n


# VarLong keeps the full 64 bit two's complement form, so a negative value
# always runs to ten groups.
public def vbuf_put_varlong(b: VBuf*, value: int64) -> void:
    vbuf_ensure(b, b.len + 10)
    int n = vt_write_varlong_at(b.data, b.len, (int64)value)
    b.len += n


# ---- reading -----------------------------------------------------------------

public def vbuf_avail(b: VBuf*) -> int:
    return b.len - b.pos


# Keeps the low 32 bits of `raw` and sign extends them into a Cpyte int.
public def vsign_extend_32(raw: uint64) -> int:
    return vt_sign_extend_32((uint64)raw)


public def vbuf_take_u8(b: VBuf*) -> uint64:
    if b.pos >= b.len:
        return (uint64)0
    uint64 v = (uint64)vt_at(b.data, b.pos)
    b.pos += 1
    return v


public def vbuf_take_u16_le(b: VBuf*) -> uint64:
    uint64 a = vbuf_take_u8(b)
    uint64 c = vbuf_take_u8(b)
    return a | (c << (uint64)8)


public def vbuf_take_u32_le(b: VBuf*) -> uint64:
    uint64 a = vbuf_take_u8(b)
    uint64 c = vbuf_take_u8(b)
    uint64 e = vbuf_take_u8(b)
    uint64 f = vbuf_take_u8(b)
    return a | (c << (uint64)8) | (e << (uint64)16) | (f << (uint64)24)


public def vbuf_take_u64_le(b: VBuf*) -> uint64:
    uint64 low = vbuf_take_u32_le(b)
    uint64 high = vbuf_take_u32_le(b)
    return low | (high << (uint64)32)


public def vbuf_take_u16_be(b: VBuf*) -> uint64:
    uint64 a = vbuf_take_u8(b)
    uint64 c = vbuf_take_u8(b)
    return (a << (uint64)8) | c


public def vbuf_take_u32_be(b: VBuf*) -> uint64:
    uint64 a = vbuf_take_u8(b)
    uint64 c = vbuf_take_u8(b)
    uint64 e = vbuf_take_u8(b)
    uint64 f = vbuf_take_u8(b)
    return (a << (uint64)24) | (c << (uint64)16) | (e << (uint64)8) | f


public def vbuf_take_i32_be(b: VBuf*) -> int:
    return vsign_extend_32(vbuf_take_u32_be(b))


public def vbuf_take_u64_be(b: VBuf*) -> uint64:
    uint64 high = vbuf_take_u32_be(b)
    uint64 low = vbuf_take_u32_be(b)
    return (high << (uint64)32) | low


public def vbuf_take_i64_be(b: VBuf*) -> int64:
    return (int64)vbuf_take_u64_be(b)


# Signed fixed-width reads. The wrap-around is done on Cpyte `int` values,
# where relational operators are trustworthy.
public def vbuf_take_i8(b: VBuf*) -> int:
    int raw = (int)vbuf_take_u8(b)
    if raw >= 128:
        raw -= 256
    return raw


public def vbuf_take_i16_be(b: VBuf*) -> int:
    int raw = (int)vbuf_take_u16_be(b)
    if raw >= 32768:
        raw -= 65536
    return raw


public def vbuf_take_f32_be(b: VBuf*) -> float:
    return vt_bits_to_float((int)vbuf_take_u32_be(b))


public def vbuf_take_f64_be(b: VBuf*) -> double:
    return vt_bits_to_double(vbuf_take_u64_be(b))


# Decodes a VarLong. `ok` receives 0 when the buffer runs out or more than ten
# groups are consumed; the cursor only advances on success.
public def vbuf_take_varlong(b: VBuf*, ok: int*) -> int64:
    int64 value = (int64)0
    int next = vt_read_varint(b.data, b.pos, b.len, &value, 1)
    if next < 0:
        *ok = 0
        return (int64)0
    b.pos = next
    *ok = 1
    return value


# Decodes a VarInt: five groups at most, sign extended from 32 bits.
public def vbuf_take_varint(b: VBuf*, ok: int*) -> int:
    int64 value = (int64)0
    int next = vt_read_varint(b.data, b.pos, b.len, &value, 0)
    *ok = 0
    if next < 0:
        return 0
    b.pos = next
    *ok = 1
    return (int)value


public def vbuf_take_varlong_unchecked(b: VBuf*) -> int64:
    int ok = 0
    return vbuf_take_varlong(b, &ok)


public def vbuf_take_varint_unchecked(b: VBuf*) -> int:
    int ok = 0
    return vbuf_take_varint(b, &ok)


# ---- bulk --------------------------------------------------------------------

public def vbuf_put_bytes(b: VBuf*, src: char*, count: int) -> void:
    if count <= 0:
        return
    vbuf_ensure(b, b.len + count)
    vt_copy_bytes(b.data, b.len, src, 0, count)
    b.len += count


public def vbuf_take_bytes(b: VBuf*, dst: char*, count: int) -> void:
    int i = 0
    while i < count:
        if b.pos < b.len:
            vt_put(dst, i, vt_at(b.data, b.pos))
            b.pos += 1
        else:
            vt_put(dst, i, code_nul())
        i += 1


public def vbuf_skip(b: VBuf*, count: int) -> void:
    b.pos += count
    if b.pos > b.len:
        b.pos = b.len


# The NBT string payload: a big endian u16 byte count followed by the bytes.
public def vbuf_put_str_u16_be(b: VBuf*, text: str) -> void:
    int n = vt_strlen(text)
    vbuf_put_u16_be(b, (uint64)n)
    int i = 0
    while i < n:
        vbuf_put_u8(b, (uint64)vt_at(text, i))
        i += 1


# Reads a u16 big endian length followed by that many bytes. `ok` receives 0
# when the buffer cannot supply the whole payload: a length that outruns the
# data must not read back as silent NUL padding.
public def vbuf_take_str_u16_be(b: VBuf*, ok: int*) -> str:
    int n = (int)vbuf_take_u16_be(b)
    *ok = 0
    if n < 0 or vbuf_avail(b) < n:
        return ""
    VStr* sink = vstr_new(n + 2)
    int i = 0
    while i < n:
        vstr_put(sink, (int)vbuf_take_u8(b))
        i += 1
    str result = vstr_text(sink)
    vstr_free(sink)
    *ok = 1
    return result


# ===== nbt.cpy =====
# Vortex engine - NBT tag tree, reader and writer.
#
# NBT is the community-documented tree format used by region files, structure
# files and (through the user's protocol layer) network chunk data: big endian
# fixed width payloads, TAG_End terminated compounds, one element type per
# list. Tag numbering and payload sizes are the published interchange rules,
# not a reimplementation of any decompiled source. See docs/PARITY_BOUNDARY.md.
#
# A tag is a flat union: exactly one payload group is live for a given kind.
# Keeping it flat avoids virtual dispatch per node, which matters because a
# chunk section's palette is a compound of a list of compounds.


# ---- tag kinds ---------------------------------------------------------------

public def nbt_end() -> int:
    return 0


public def nbt_byte() -> int:
    return 1


public def nbt_short() -> int:
    return 2


public def nbt_int() -> int:
    return 3


public def nbt_long() -> int:
    return 4


public def nbt_float() -> int:
    return 5


public def nbt_double() -> int:
    return 6


public def nbt_byte_array() -> int:
    return 7


public def nbt_string() -> int:
    return 8


public def nbt_list() -> int:
    return 9


public def nbt_compound() -> int:
    return 10


public def nbt_int_array() -> int:
    return 11


public def nbt_long_array() -> int:
    return 12


# Depth a reader will accept before calling the input hostile; region files
# nest at most four or five levels.
public def nbt_max_depth() -> int:
    return 64


# ---- the node ----------------------------------------------------------------

struct VNbt:
    int kind
    str name                   # key inside its parent compound, "" in a list
    int val_int                # byte / short / int payload
    int64 val_long
    float val_float
    double val_double
    str val_str                # string payload
    char* bytes                # byte array
    int bytes_len
    int* ints                  # int array
    int ints_len
    uint64* longs              # long array
    int longs_len
    char* items                # child pointers, one slot per entry
    int items_len
    int items_cap


public def nbt_new(kind: int, name: str) -> VNbt*:
    VNbt* t = new VNbt
    t.kind = kind
    t.name = name
    t.val_int = 0
    t.val_long = (int64)0
    t.val_float = (float)0
    t.val_double = (double)0
    t.val_str = ""
    t.bytes = null
    t.bytes_len = 0
    t.ints = null
    t.ints_len = 0
    t.longs = null
    t.longs_len = 0
    t.items = null
    t.items_len = 0
    t.items_cap = 0
    return t


public def nbt_free(t: VNbt*) -> void:
    if t == null:
        return
    int i = 0
    while i < t.items_len:
        nbt_free((VNbt*)vt_ptr_get(t.items, i))
        i += 1
    if t.bytes != null:
        vt_free((void*)t.bytes)
    if t.ints != null:
        vt_free((void*)t.ints)
    if t.longs != null:
        vt_free((void*)t.longs)
    if t.items != null:
        vt_free((void*)t.items)
    del t


public def nbt_child_count(t: VNbt*) -> int:
    if t == null:
        return 0
    return t.items_len


public def nbt_child_at(t: VNbt*, index: int) -> VNbt*:
    if t == null:
        return null
    if index < 0 or index >= t.items_len:
        return null
    return (VNbt*)vt_ptr_get(t.items, index)


# Appends `child` to `t`, adopting it. Grows the slot array by doubling.
public def nbt_append(t: VNbt*, child: VNbt*) -> void:
    if child == null:
        return
    if t.items_len >= t.items_cap:
        int cap = t.items_cap * 2
        if cap < 4:
            cap = 4
        char* next = vt_calloc_ptrs(cap)
        vt_copy_bytes(next, 0, t.items, 0, t.items_len * vt_ptr_size())
        if t.items != null:
            vt_free((void*)t.items)
        t.items = next
        t.items_cap = cap
    vt_ptr_set(t.items, t.items_len, (void*)child)
    t.items_len += 1


# The child of compound `t` stored under `name`, or null.
public def nbt_find(t: VNbt*, name: str) -> VNbt*:
    if t == null:
        return null
    int i = 0
    while i < t.items_len:
        VNbt* child = (VNbt*)vt_ptr_get(t.items, i)
        if child != null and vt_eq(child.name, name) == 1:
            return child
        i += 1
    return null


public def nbt_has(t: VNbt*, name: str) -> bool:
    return nbt_find(t, name) != null


# ---- typed constructors ------------------------------------------------------

public def nbt_int_of(name: str, value: int) -> VNbt*:
    VNbt* t = nbt_new(nbt_int(), name)
    t.val_int = value
    return t


public def nbt_byte_of(name: str, value: int) -> VNbt*:
    VNbt* t = nbt_new(nbt_byte(), name)
    t.val_int = value
    return t


public def nbt_short_of(name: str, value: int) -> VNbt*:
    VNbt* t = nbt_new(nbt_short(), name)
    t.val_int = value
    return t


public def nbt_long_of(name: str, value: int64) -> VNbt*:
    VNbt* t = nbt_new(nbt_long(), name)
    t.val_long = value
    return t


public def nbt_float_of(name: str, value: float) -> VNbt*:
    VNbt* t = nbt_new(nbt_float(), name)
    t.val_float = value
    return t


public def nbt_double_of(name: str, value: double) -> VNbt*:
    VNbt* t = nbt_new(nbt_double(), name)
    t.val_double = value
    return t


public def nbt_string_of(name: str, value: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_string(), name)
    t.val_str = value
    return t


public def nbt_compound_of(name: str) -> VNbt*:
    return nbt_new(nbt_compound(), name)


public def nbt_list_of(name: str, kind: int) -> VNbt*:
    # The list's element type is a property of the tag, not of each entry.
    VNbt* t = nbt_new(nbt_list(), name)
    t.val_int = kind
    return t


# val_int of a list node records the element type, so list constructors use
# val_long for their own scalar payloads - hence these take the element kind.
public def nbt_list_element_kind(t: VNbt*) -> int:
    return t.val_int


# ---- value accessors with fallbacks ------------------------------------------

public def nbt_int_value(t: VNbt*, fallback: int) -> int:
    if t == null:
        return fallback
    if t.kind == nbt_byte() or t.kind == nbt_short() or t.kind == nbt_int():
        return t.val_int
    if t.kind == nbt_long():
        return (int)t.val_long
    return fallback


public def nbt_long_value(t: VNbt*, fallback: int64) -> int64:
    if t == null:
        return fallback
    if t.kind == nbt_long():
        return t.val_long
    return nbt_int_value(t, (int)fallback)


public def nbt_str_value(t: VNbt*, fallback: str) -> str:
    if t == null:
        return fallback
    if t.kind == nbt_string():
        return t.val_str
    return fallback


public def nbt_get_int(t: VNbt*, name: str, fallback: int) -> int:
    return nbt_int_value(nbt_find(t, name), fallback)


public def nbt_get_str(t: VNbt*, name: str, fallback: str) -> str:
    return nbt_str_value(nbt_find(t, name), fallback)


public def nbt_byte_at(t: VNbt*, index: int) -> int:
    if t == null or index < 0 or index >= t.bytes_len:
        return 0
    return vt_at(t.bytes, index)


public def nbt_int_at(t: VNbt*, index: int) -> int:
    if t == null or index < 0 or index >= t.ints_len:
        return 0
    return vt_iget(t.ints, index)


public def nbt_long_at(t: VNbt*, index: int) -> int64:
    if t == null or index < 0 or index >= t.longs_len:
        return (int64)0
    return (int64)vt_uget(t.longs, index)


# Array lengths: nbt_child_count counts list and compound children, and an
# array holds none of those.
public def nbt_byte_len(t: VNbt*) -> int:
    if t == null:
        return 0
    return t.bytes_len


public def nbt_int_len(t: VNbt*) -> int:
    if t == null:
        return 0
    return t.ints_len


public def nbt_long_len(t: VNbt*) -> int:
    if t == null:
        return 0
    return t.longs_len


# ---- writing -----------------------------------------------------------------

public def nbt_set_bytes(t: VNbt*, src: char*, count: int) -> void:
    if t.bytes != null:
        vt_free((void*)t.bytes)
    t.bytes = vt_calloc_char(count)
    vt_copy_bytes(t.bytes, 0, src, 0, count)
    t.bytes_len = count


public def nbt_set_ints(t: VNbt*, count: int) -> void:
    if t.ints != null:
        vt_free((void*)t.ints)
    t.ints = vt_calloc_int(count)
    t.ints_len = count


public def nbt_set_longs(t: VNbt*, count: int) -> void:
    if t.longs != null:
        vt_free((void*)t.longs)
    t.longs = vt_calloc_u64(count)
    t.longs_len = count


public def nbt_set_int_at(t: VNbt*, index: int, value: int) -> void:
    vt_iset(t.ints, index, value)


public def nbt_set_long_at(t: VNbt*, index: int, value: int64) -> void:
    vt_uset(t.longs, index, (uint64)value)


# mode 0 writes a complete named tag - kind byte, name, payload. mode 1 writes
# a payload alone, which is how list elements are stored (the element type is
# recorded once in the list header). One function keeps the recursion inside a
# single scope: Cpyte resolves a call to a function that is defined later.
def nbt_write_tag(b: VBuf*, t: VNbt*, mode: int) -> void:
    if mode == 0:
        vbuf_put_u8(b, (uint64)t.kind)
        if t.kind == nbt_end():
            return
        vbuf_put_str_u16_be(b, t.name)
    if t.kind == nbt_byte():
        vbuf_put_i8(b, t.val_int)
        return
    if t.kind == nbt_short():
        vbuf_put_i16_be(b, t.val_int)
        return
    if t.kind == nbt_int():
        vbuf_put_i32_be(b, t.val_int)
        return
    if t.kind == nbt_long():
        vbuf_put_i64_be(b, t.val_long)
        return
    if t.kind == nbt_float():
        vbuf_put_f32_be(b, t.val_float)
        return
    if t.kind == nbt_double():
        vbuf_put_f64_be(b, t.val_double)
        return
    if t.kind == nbt_string():
        vbuf_put_str_u16_be(b, t.val_str)
        return
    if t.kind == nbt_byte_array():
        vbuf_put_i32_be(b, t.bytes_len)
        vbuf_put_bytes(b, t.bytes, t.bytes_len)
        return
    if t.kind == nbt_int_array():
        vbuf_put_i32_be(b, t.ints_len)
        int i = 0
        while i < t.ints_len:
            vbuf_put_i32_be(b, vt_iget(t.ints, i))
            i += 1
        return
    if t.kind == nbt_long_array():
        vbuf_put_i32_be(b, t.longs_len)
        int j = 0
        while j < t.longs_len:
            vbuf_put_i64_be(b, (int64)vt_uget(t.longs, j))
            j += 1
        return
    if t.kind == nbt_list():
        # An empty list still writes its element type, so a reader can tell an
        # empty compound list from an empty int list.
        int elem = t.val_int
        if elem == nbt_end() and t.items_len > 0:
            VNbt* first = (VNbt*)vt_ptr_get(t.items, 0)
            elem = first.kind
        vbuf_put_u8(b, (uint64)elem)
        vbuf_put_i32_be(b, t.items_len)
        int k = 0
        while k < t.items_len:
            nbt_write_tag(b, (VNbt*)vt_ptr_get(t.items, k), 1)
            k += 1
        return
    if t.kind == nbt_compound():
        int m = 0
        while m < t.items_len:
            nbt_write_tag(b, (VNbt*)vt_ptr_get(t.items, m), 0)
            m += 1
        vbuf_put_u8(b, (uint64)nbt_end())


# Writes kind byte, name and payload - a complete named tag.
public def nbt_write(b: VBuf*, t: VNbt*) -> void:
    nbt_write_tag(b, t, 0)


# ---- reading -----------------------------------------------------------------

# True when `b` still holds at least `count` bytes at the cursor.
def nbt_need(b: VBuf*, count: int) -> bool:
    return vbuf_avail(b) >= count


# Reads a payload only (no kind byte, no name) - the list element form. Names
# are absent inside a list, so `name` is "" there. A truncated buffer fails the
# `nbt_need` guards and yields null rather than a partly built tag.
def nbt_read_payload(kind: int, name: str, b: VBuf*, depth: int) -> VNbt*:
    if depth > nbt_max_depth() or kind == nbt_end():
        return null
    if kind == nbt_byte():
        if not nbt_need(b, 1):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_int = vbuf_take_i8(b)
        return t
    if kind == nbt_short():
        if not nbt_need(b, 2):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_int = vbuf_take_i16_be(b)
        return t
    if kind == nbt_int():
        if not nbt_need(b, 4):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_int = vbuf_take_i32_be(b)
        return t
    if kind == nbt_long():
        if not nbt_need(b, 8):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_long = vbuf_take_i64_be(b)
        return t
    if kind == nbt_float():
        if not nbt_need(b, 4):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_float = vbuf_take_f32_be(b)
        return t
    if kind == nbt_double():
        if not nbt_need(b, 8):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_double = vbuf_take_f64_be(b)
        return t
    if kind == nbt_string():
        if not nbt_need(b, 2):
            return null
        int ok = 0
        str text = vbuf_take_str_u16_be(b, &ok)
        if ok == 0:
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_str = text
        return t
    if kind == nbt_byte_array():
        if not nbt_need(b, 4):
            return null
        int n = vbuf_take_i32_be(b)
        if n < 0 or not nbt_need(b, n):
            return null
        VNbt* t = nbt_new(kind, name)
        t.bytes = vt_calloc_char(n)
        vbuf_take_bytes(b, t.bytes, n)
        t.bytes_len = n
        return t
    if kind == nbt_int_array():
        if not nbt_need(b, 4):
            return null
        int n = vbuf_take_i32_be(b)
        if n < 0 or not nbt_need(b, n * 4):
            return null
        VNbt* t = nbt_new(kind, name)
        t.ints = vt_calloc_int(n)
        t.ints_len = n
        int i = 0
        while i < n:
            vt_iset(t.ints, i, vbuf_take_i32_be(b))
            i += 1
        return t
    if kind == nbt_long_array():
        if not nbt_need(b, 4):
            return null
        int n = vbuf_take_i32_be(b)
        if n < 0 or not nbt_need(b, n * 8):
            return null
        VNbt* t = nbt_new(kind, name)
        t.longs = vt_calloc_u64(n)
        t.longs_len = n
        int j = 0
        while j < n:
            vt_uset(t.longs, j, (uint64)vbuf_take_i64_be(b))
            j += 1
        return t
    if kind == nbt_list():
        if not nbt_need(b, 5):
            return null
        int elem = (int)vbuf_take_u8(b)
        int n = vbuf_take_i32_be(b)
        if n < 0:
            return null
        VNbt* t = nbt_new(kind, name)
        # The element type is a property of the list node itself.
        t.val_int = elem
        int k = 0
        while k < n:
            VNbt* child = nbt_read_payload(elem, "", b, depth + 1)
            if child == null:
                return null
            nbt_append(t, child)
            k += 1
        return t
    if kind == nbt_compound():
        VNbt* t = nbt_new(kind, name)
        while true:
            if not nbt_need(b, 1):
                return null
            int next = (int)vbuf_take_u8(b)
            if next == nbt_end():
                return t
            if not nbt_need(b, 2):
                return null
            int ok_name = 0
            str child_name = vbuf_take_str_u16_be(b, &ok_name)
            if ok_name == 0:
                return null
            VNbt* child = nbt_read_payload(next, child_name, b, depth + 1)
            if child == null:
                return null
            nbt_append(t, child)
    return null


# Reads a complete named tag: kind byte, name, payload.
public def nbt_read(b: VBuf*) -> VNbt*:
    if not nbt_need(b, 3):
        return null
    int kind = (int)vbuf_take_u8(b)
    if kind == nbt_end():
        return null
    int ok_name = 0
    str name = vbuf_take_str_u16_be(b, &ok_name)
    if ok_name == 0:
        return null
    return nbt_read_payload(kind, name, b, 0)



# ===== palette.cpy =====
# Vortex engine - paletted container.
#
# A chunk section's 4096 block states and a biome section's 64 biomes are both
# stored the same way, so one container serves both and only the entry count,
# the width bounds and the value meanings differ.
#
# Three storage modes, following the community "paletted container" rules:
#   uniform   - every entry holds the same value; no palette, no data words;
#   indirect  - a palette of values plus packed palette indices;
#   direct    - the values themselves, packed at the full width, no palette.
#
# The packed words use padded packing (an entry never straddles two 64 bit
# words); the arithmetic lives in src/engine/native.cpy because Cpyte compares
# unsigned values as signed.
#
# Reading a section is a one way trip: vcont_reset, vcont_palette_add for each
# palette entry, vcont_alloc_words, then vcont_set_word for each stored word.
# The palette may be added before or after the words because only vcont_at
# reads them.
#
# The compiler resolves a call against what it has already read, so this module
# is ordered bottom up: every helper is defined before its callers.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.


public def vcont_uniform_mode() -> int:
    return 0


public def vcont_indirect_mode() -> int:
    return 1


public def vcont_direct_mode() -> int:
    return 2


struct VContainer:
    int count             # entries held: 4096 blocks, 64 biomes
    int min_bits          # narrowest indirect encoding
    int max_bits          # widest indirect encoding
    int direct_bits       # width once the palette is dropped
    int mode
    int bits              # current encoding width; 0 while uniform
    int uniform_value
    int* palette          # palette slot -> stored value
    int palette_len
    int palette_cap
    int palette_limit     # most palette slots the encoding may use
    uint64* words         # packed indices (indirect) or values (direct)
    int words_len


# ---- arithmetic helpers ------------------------------------------------------

# 2**bits as an int, computed by doubling so no widening shift is involved.
def vcont_pow2(bits: int) -> int:
    int v = 1
    int i = 0
    while i < bits:
        v = v * 2
        i += 1
    return v


def vcont_capacity_bits(max_bits: int) -> int:
    if max_bits < 1:
        return 2
    if max_bits > 30:
        return vcont_pow2(30)
    return vcont_pow2(max_bits)


# Smallest width whose range covers `needed` values, never below `min_bits`.
public def vcont_bits_for(needed: int, min_bits: int) -> int:
    int bits = min_bits
    int cap = vcont_pow2(bits)
    while cap < needed and bits < 30:
        bits += 1
        cap = cap * 2
    return bits


# ---- slots and words ---------------------------------------------------------

# Ensures the slot array can hold one more entry within palette_limit.
def vcont_grow_palette(c: VContainer*) -> void:
    if c.palette_len < c.palette_cap:
        return
    int cap = c.palette_cap * 2
    if cap < 8:
        cap = 8
    if cap > c.palette_limit:
        cap = c.palette_limit
    int* next = vt_calloc_int(cap)
    int keep = c.palette_len
    if keep > cap:
        keep = cap
    int i = 0
    while i < keep:
        vt_iset(next, i, vt_iget(c.palette, i))
        i += 1
    if c.palette != null:
        vt_free((void*)c.palette)
    c.palette = next
    c.palette_cap = cap


def vcont_palette_push(c: VContainer*, value: int) -> int:
    vcont_grow_palette(c)
    int index = c.palette_len
    vt_iset(c.palette, index, value)
    c.palette_len += 1
    return index


def vcont_palette_index_of(c: VContainer*, value: int) -> int:
    int i = 0
    while i < c.palette_len:
        if vt_iget(c.palette, i) == value:
            return i
        i += 1
    return -1


def vcont_palette_get(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.palette_len:
        return 0
    return vt_iget(c.palette, index)


# Allocates words for `bits`, discarding whatever was stored before.
def vcont_alloc_words(c: VContainer*, bits: int) -> void:
    int need = vt_packed_words(c.count, bits)
    if c.words != null:
        vt_free((void*)c.words)
    if need < 1:
        need = 1
    c.words = vt_calloc_u64(need)
    c.words_len = need
    c.bits = bits


# The value at `index`, whatever the current mode. An indirect container stores
# palette slots, so the slot has to be resolved before returning.
def vcont_at(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.count:
        return 0
    if c.mode == vcont_uniform_mode():
        return c.uniform_value
    if c.mode == vcont_direct_mode():
        return (int)vt_packed_get(c.words, index, c.direct_bits)
    int slot = (int)vt_packed_get(c.words, index, c.bits)
    return vcont_palette_get(c, slot)


# ---- mode transitions --------------------------------------------------------

# Back to uniform storage holding `value`. The palette and word arrays stay
# allocated for the next encoding to reuse.
public def vcont_reset(c: VContainer*, value: int) -> void:
    c.mode = vcont_uniform_mode()
    c.bits = 0
    c.uniform_value = value
    c.palette_len = 0
    c.words_len = 0
    c.palette_limit = vcont_capacity_bits(c.max_bits)


# Re-encodes every entry at `new_bits`, keeping the palette unchanged.
def vcont_repack(c: VContainer*, new_bits: int) -> void:
    uint64* old = c.words
    int old_bits = c.bits
    c.words = null
    c.words_len = 0
    vcont_alloc_words(c, new_bits)
    if old == null:
        return
    int i = 0
    while i < c.count:
        uint64 slot = vt_packed_get(old, i, old_bits)
        vt_packed_set(c.words, i, new_bits, slot)
        i += 1
    vt_free((void*)old)


# Leaves uniform storage: the old value and the new one enter the palette,
# every entry is re-encoded as the old value's index, and `index` takes the new
# one.
def vcont_leave_uniform(c: VContainer*, index: int, value: int) -> void:
    int old_value = c.uniform_value
    int bits = c.min_bits
    vcont_alloc_words(c, bits)
    int first = vcont_palette_push(c, old_value)
    int second = vcont_palette_push(c, value)
    c.mode = vcont_indirect_mode()
    int i = 0
    while i < c.count:
        vt_packed_set(c.words, i, bits, (uint64)first)
        i += 1
    vt_packed_set(c.words, index, bits, (uint64)second)


# Drops the palette and stores values at the full direct width. Every entry
# keeps the value its palette slot pointed at.
def vcont_promote(c: VContainer*) -> void:
    uint64* old = c.words
    int* slots = c.palette
    int old_bits = c.bits
    int entries = c.palette_len
    c.words = null
    c.words_len = 0
    vcont_alloc_words(c, c.direct_bits)
    if old != null:
        int i = 0
        while i < c.count:
            int slot = (int)vt_packed_get(old, i, old_bits)
            uint64 value = (uint64)0
            if slot >= 0 and slot < entries:
                value = (uint64)vt_iget(slots, slot)
            vt_packed_set(c.words, i, c.direct_bits, value)
            i += 1
        vt_free((void*)old)
    c.palette_len = 0
    c.mode = vcont_direct_mode()


# ---- rebuild from values -----------------------------------------------------

# Reads every entry into `values` as the value it denotes; `values` needs
# `count` slots.
def vcont_collect(c: VContainer*, values: int*) -> void:
    int i = 0
    while i < c.count:
        vt_iset(values, i, vcont_at(c, i))
        i += 1


# Counts distinct values in linear expected time; section compaction calls this
# on all 4096 block entries, so a pairwise scan is prohibitively slow.
def vcont_count_distinct(values: int*, count: int) -> int:
    if count <= 0:
        return 0
    int capacity = 1
    while capacity < count * 2:
        capacity *= 2
    int* slots = vt_calloc_int(capacity)
    char* occupied = vt_calloc_char(capacity)
    int distinct = 0
    int probe = 0
    while probe < count:
        int candidate = vt_iget(values, probe)
        uint64 key = (uint64)candidate
        key = key ^ (key >> (uint64)16)
        key = key * (uint64)2654435761
        key = key ^ (key >> (uint64)13)
        int slot = (int)(key & (uint64)(capacity - 1))
        while vt_at(occupied, slot) != 0 and vt_iget(slots, slot) != candidate:
            slot = (slot + 1) & (capacity - 1)
        if vt_at(occupied, slot) == 0:
            vt_put(occupied, slot, 1)
            vt_iset(slots, slot, candidate)
            distinct += 1
        probe += 1
    vt_free((void*)slots)
    vt_free((void*)occupied)
    return distinct


# Number of distinct values held, which a save needs to size its palette.
public def vcont_distinct_count(c: VContainer*) -> int:
    if c.mode == vcont_uniform_mode():
        return 1
    if c.mode == vcont_indirect_mode():
        return c.palette_len
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
    vt_free((void*)values)
    return distinct


def vcont_rebuild_indirect(c: VContainer*, values: int*, bits: int) -> void:
    vcont_reset(c, vt_iget(values, 0))
    vcont_alloc_words(c, bits)
    c.mode = vcont_indirect_mode()
    int i = 0
    while i < c.count:
        int value = vt_iget(values, i)
        int slot = vcont_palette_index_of(c, value)
        if slot < 0:
            slot = vcont_palette_push(c, value)
        vt_packed_set(c.words, i, bits, (uint64)slot)
        i += 1


def vcont_rebuild_direct(c: VContainer*, values: int*) -> void:
    vcont_reset(c, vt_iget(values, 0))
    vcont_alloc_words(c, c.direct_bits)
    c.mode = vcont_direct_mode()
    int i = 0
    while i < c.count:
        vt_packed_set(c.words, i, c.direct_bits, (uint64)vt_iget(values, i))
        i += 1


# ---- writing -----------------------------------------------------------------

# Width and word count the section records for this container.
def vcont_save_bits(c: VContainer*) -> int:
    int distinct = vcont_distinct_count(c)
    if distinct <= 1:
        return 0
    int bits = vcont_bits_for(distinct, c.min_bits)
    if bits > c.max_bits:
        return c.direct_bits
    return bits


def vcont_save_word_count(c: VContainer*, bits: int) -> int:
    if bits <= 0:
        return 0
    return vt_packed_words(c.count, bits)


# Collapses the encoding to its narrowest form: uniform for one distinct
# value, otherwise the smallest width that indexes the palette.
public def vcont_compact(c: VContainer*) -> void:
    if c.mode == vcont_uniform_mode():
        return
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
    if distinct <= 1:
        vcont_reset(c, vt_iget(values, 0))
        vt_free((void*)values)
        return
    int bits = vcont_bits_for(distinct, c.min_bits)
    if bits > c.max_bits:
        vcont_rebuild_direct(c, values)
        vt_free((void*)values)
        return
    vcont_rebuild_indirect(c, values, bits)
    vt_free((void*)values)


# ---- palette view ------------------------------------------------------------

public def vcont_palette_len(c: VContainer*) -> int:
    return c.palette_len


# 1 when `index` is a palette slot, so vcont_palette_at returns its value.
public def vcont_has_palette(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.palette_len:
        return 0
    return 1


public def vcont_palette_at(c: VContainer*, index: int) -> int:
    return vcont_palette_get(c, index)


# ---- word view ---------------------------------------------------------------

# 1 when the container is uniform, which is when a save writes no words at all.
public def vcont_is_uniform(c: VContainer*) -> int:
    if c.mode == vcont_uniform_mode():
        return 1
    int first = vcont_at(c, 0)
    int i = 1
    while i < c.count:
        if vcont_at(c, i) != first:
            return 0
        i += 1
    return 1


public def vcont_uniform_value(c: VContainer*) -> int:
    return vcont_at(c, 0)


# Collapses a container that has gone back to a single value. 1 when it did.
public def vcont_try_uniform(c: VContainer*) -> int:
    if vcont_is_uniform(c) == 0:
        return 0
    vcont_reset(c, vcont_at(c, 0))
    return 1


public def vcont_save_bits_for(c: VContainer*) -> int:
    return vcont_save_bits(c)


public def vcont_save_words_for(c: VContainer*, bits: int) -> int:
    return vcont_save_word_count(c, bits)


# 1 when `index` is a stored word; the caller reads it with vcont_save_word.
public def vcont_has_save_word(c: VContainer*, index: int) -> int:
    if c.words == null or c.bits <= 0 or index < 0:
        return 0
    if index >= vcont_save_word_count(c, c.bits):
        return 0
    return 1


public def vcont_save_word(c: VContainer*, index: int) -> uint64:
    if c.words == null or index < 0 or index >= c.words_len:
        return (uint64)0
    return (uint64)vt_uget(c.words, index)


# ---- accessors ---------------------------------------------------------------

public def vcont_new(count: int, min_bits: int, max_bits: int, direct_bits: int) -> VContainer*:
    VContainer* c = new VContainer
    c.count = count
    c.min_bits = min_bits
    c.max_bits = max_bits
    c.direct_bits = direct_bits
    c.mode = vcont_uniform_mode()
    c.bits = 0
    c.uniform_value = 0
    c.palette = null
    c.palette_len = 0
    c.palette_cap = 0
    c.palette_limit = vcont_capacity_bits(max_bits)
    c.words = null
    c.words_len = 0
    return c


public def vcont_free(c: VContainer*) -> void:
    if c == null:
        return
    if c.palette != null:
        vt_free((void*)c.palette)
    if c.words != null:
        vt_free((void*)c.words)
    del c


public def vcont_bits(c: VContainer*) -> int:
    return c.bits


public def vcont_mode(c: VContainer*) -> int:
    return c.mode


public def vcont_count(c: VContainer*) -> int:
    return c.count


# A uniform container stores no words, which is what the saved form records.
public def vcont_word_count(c: VContainer*) -> int:
    return vcont_save_word_count(c, c.bits)


# Appends a value read from the saved palette; the words can be filled before
# or after, only vcont_at reads them.
public def vcont_palette_add(c: VContainer*, value: int) -> void:
    if c.palette_len >= c.palette_limit:
        return
    vcont_palette_push(c, value)


# Allocates and clears the data words for `bits`; pairs with vcont_set_word and
# vcont_palette_add.
public def vcont_alloc(c: VContainer*, bits: int) -> void:
    vcont_alloc_words(c, bits)
    c.mode = vcont_indirect_mode()


public def vcont_alloc_direct(c: VContainer*, bits: int) -> void:
    vcont_alloc_words(c, bits)
    c.mode = vcont_direct_mode()


public def vcont_set_word(c: VContainer*, index: int, value: uint64) -> void:
    if c.words == null or index < 0 or index >= c.words_len:
        return
    vt_uset(c.words, index, (uint64)value)


public def vcont_set(c: VContainer*, index: int, value: int) -> void:
    if index < 0 or index >= c.count:
        return
    if c.mode == vcont_uniform_mode():
        if value == c.uniform_value:
            return
        vcont_leave_uniform(c, index, value)
        return
    if c.mode == vcont_direct_mode():
        vt_packed_set(c.words, index, c.direct_bits, (uint64)value)
        return
    int slot = vcont_palette_index_of(c, value)
    if slot >= 0:
        vt_packed_set(c.words, index, c.bits, (uint64)slot)
        return
    if c.palette_len >= c.palette_limit:
        vcont_promote(c)
        vt_packed_set(c.words, index, c.direct_bits, (uint64)value)
        return
    int new_bits = vcont_bits_for(c.palette_len + 1, c.bits)
    if new_bits > c.bits:
        vcont_repack(c, new_bits)
    int added = vcont_palette_push(c, value)
    vt_packed_set(c.words, index, c.bits, (uint64)added)


# A direct container carries no palette, but a saved section always has one,
# so the values are re-collected at `save_bits` before writing. Returns 0 when
# the distinct values do not fit that width, leaving the container untouched.
public def vcont_save_prepare(c: VContainer*, save_bits: int) -> int:
    if c.mode != vcont_direct_mode():
        return 1
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
    int needed = vcont_bits_for(distinct, 1)
    if needed > save_bits:
        vt_free((void*)values)
        return 0
    vcont_rebuild_indirect(c, values, save_bits)
    vt_free((void*)values)
    return 1


# ===== section.cpy =====
# Vortex engine - chunk section.
#
# One 16x16x16 slice of the world: 4096 block states plus, following Horizon's
# split of the biome container, 64 biomes at 4x4x4 resolution, and the two
# four bit light masks.
#
# Entries are addressed the way the game lays a section out in memory:
#   block (x, y, z) -> x + z * 16 + y * 256
#   biome (x, y, z) -> x + z *  4 + y *  16
#
# Block states and biomes are held as ids chosen by the caller's registry; the
# engine never numbers them itself, so the NBT mapping here records the palette
# as ids. The io layer that owns a registry turns those ids into the
# Name/Properties compounds the game writes, and can read them back, through
# vcont_palette_at and sec_load_palette - the seams this module leaves open.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.


public def sec_size() -> int:
    return 16


public def sec_block_count() -> int:
    return 4096


public def sec_biome_count() -> int:
    return 64


# Two 4 bit light levels per byte.
public def sec_light_bytes() -> int:
    return 2048


def sec_block_index(x: int, y: int, z: int) -> int:
    return x + z * 16 + y * 256


def sec_biome_index(x: int, y: int, z: int) -> int:
    return x + z * 4 + y * 16


# The block and biome containers differ only in entry count and width bounds.
def sec_blocks_min_bits() -> int:
    return 4


def sec_blocks_max_bits() -> int:
    return 8


def sec_blocks_direct_bits() -> int:
    return 16


def sec_biomes_min_bits() -> int:
    return 1


def sec_biomes_max_bits() -> int:
    return 3


def sec_biomes_direct_bits() -> int:
    return 7


struct VSection:
    int y                 # section index in the column, not a block coordinate
    int non_empty         # non-air block count from a network section, if known
    VContainer* blocks
    VContainer* biomes
    char* block_light     # 2048 bytes, two 4 bit levels per byte
    char* sky_light


# ---- light -------------------------------------------------------------------

def sec_light_at(light: char*, index: int) -> int:
    if light == null or index < 0 or index >= 4096:
        return 0
    int byte = (int)vt_at(light, index / 2)
    if index % 2 == 0:
        return byte & 15
    return (byte >> 4) & 15


def sec_light_set(light: char*, index: int, level: int) -> void:
    if light == null or index < 0 or index >= 4096:
        return
    int at = index / 2
    int other = 0
    if index % 2 == 0:
        other = sec_light_at(light, index + 1) << 4
        vt_put(light, at, other | (level & 15))
    else:
        other = sec_light_at(light, index - 1)
        vt_put(light, at, other | ((level & 15) << 4))


# 256 longs, each holding eight bytes little endian.
def sec_light_words() -> int:
    return 256


def sec_light_to_tag(light: char*, name: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_long_array(), name)
    nbt_set_longs(t, sec_light_words())
    int w = 0
    while w < sec_light_words():
        int64 value = (int64)0
        int b = 0
        while b < 8:
            int byte = (int)vt_at(light, w * 8 + b) & 255
            value = value | ((int64)byte << ((int64)b * (int64)8))
            b += 1
        nbt_set_long_at(t, w, value)
        w += 1
    return t


def sec_light_from_tag(t: VNbt*, light: char*) -> void:
    if t == null or light == null:
        return
    int count = nbt_long_len(t)
    if count > sec_light_words():
        count = sec_light_words()
    int w = 0
    while w < count:
        int64 value = nbt_long_at(t, w)
        int b = 0
        while b < 8:
            int byte = (int)((value >> ((int64)b * (int64)8)) & (int64)255)
            vt_put(light, w * 8 + b, byte)
            b += 1
        w += 1
    while w < sec_light_words():
        int b = 0
        while b < 8:
            vt_put(light, w * 8 + b, 0)
            b += 1
        w += 1
    return


# ---- container to and from NBT -----------------------------------------------

# Palette entry count, whether the tag is a list of ints or an int array. A
# list of Name/Properties compounds is the registry layer's to read, so it is
# reported as no palette here rather than silently decoding to zeros.
def sec_palette_slots(t: VNbt*) -> int:
    VNbt* palette = nbt_find(t, "palette")
    if palette == null:
        return 0
    if palette.kind == nbt_list():
        int elem = nbt_list_element_kind(palette)
        if elem != nbt_int() and elem != nbt_byte() and elem != nbt_short():
            return 0
        return nbt_child_count(palette)
    if palette.kind == nbt_int_array():
        return nbt_int_len(palette)
    return 0


# Appends each palette entry to `c`, in tag order.
def sec_load_palette(palette: VNbt*, c: VContainer*) -> void:
    if palette == null:
        return
    int count = nbt_child_count(palette)
    if palette.kind == nbt_int_array():
        count = nbt_int_len(palette)
    int i = 0
    while i < count:
        if palette.kind == nbt_int_array():
            vcont_palette_add(c, nbt_int_at(palette, i))
        else:
            vcont_palette_add(c, nbt_int_value(nbt_child_at(palette, i), 0))
        i += 1
    return


# The palette the saved form records: one entry while the container is uniform,
# otherwise its own. An io layer translating ids to Name compounds walks these,
# so it sees exactly what the tag will hold.
public def sec_palette_size(c: VContainer*) -> int:
    if vcont_mode(c) == vcont_uniform_mode():
        return 1
    return vcont_palette_len(c)


public def sec_palette_entry(c: VContainer*, index: int) -> int:
    if vcont_mode(c) == vcont_uniform_mode():
        return vcont_uniform_value(c)
    return vcont_palette_at(c, index)


# TAG_Compound `{palette: [...], data: [long...]}` for one container. A uniform
# container writes the single palette entry and no data array, which is exactly
# what the game does.
def sec_container_to_nbt(c: VContainer*, name: str) -> VNbt*:
    VContainer* encoded = c
    VContainer* temporary = c
    if vcont_mode(c) == vcont_direct_mode():
        temporary = vcont_new(vcont_count(c), c.min_bits, 30, c.direct_bits)
        int at = 0
        while at < vcont_count(c):
            vcont_set(temporary, at, vcont_at(c, at))
            at += 1
        vcont_compact(temporary)
        encoded = temporary

    VNbt* root = nbt_compound_of(name)
    VNbt* palette = nbt_list_of("palette", nbt_int())
    int slots = sec_palette_size(encoded)
    int i = 0
    while i < slots:
        nbt_append(palette, nbt_int_of("", sec_palette_entry(encoded, i)))
        i += 1
    nbt_append(root, palette)

    int bits = vcont_save_bits_for(encoded)
    if bits <= 0:
        if temporary != c:
            vcont_free(temporary)
        return root
    VNbt* data = nbt_new(nbt_long_array(), "data")
    int words = vcont_save_words_for(encoded, bits)
    nbt_set_longs(data, words)
    int w = 0
    while w < words:
        nbt_set_long_at(data, w, (int64)vcont_save_word(encoded, w))
        w += 1
    nbt_append(root, data)
    if temporary != c:
        vcont_free(temporary)
    return root


# Fills `c` from a `{palette, data}` compound. Returns 0 when the tag is not a
# compound or carries no palette.
def sec_container_from_nbt(t: VNbt*, c: VContainer*, min_bits: int) -> int:
    if t == null:
        return 0
    if t.kind != nbt_compound():
        return 0
    int slots = sec_palette_slots(t)
    if slots <= 0:
        return 0
    int bits = vcont_bits_for(slots, min_bits)
    vcont_reset(c, 0)
    VNbt* palette = nbt_find(t, "palette")
    VNbt* data = nbt_find(t, "data")
    if data == null:
        sec_load_palette(palette, c)
        if vcont_palette_len(c) <= 0:
            return 0
        # A single valued palette needs no data array: the whole section holds
        # the one entry.
        if vcont_palette_len(c) == 1:
            vcont_reset(c, vcont_palette_at(c, 0))
            return 1
        return 0
    if data.kind != nbt_long_array():
        return 0
    VContainer* decoded = c
    VContainer* temporary = c
    if bits > c.max_bits:
        temporary = vcont_new(vcont_count(c), min_bits, 30, c.direct_bits)
        decoded = temporary
    sec_load_palette(palette, decoded)

    vcont_alloc(decoded, bits)
    int words = nbt_long_len(data)
    int want = vcont_save_words_for(decoded, bits)
    if words > want:
        words = want
    int w = 0
    while w < words:
        vcont_set_word(decoded, w, (uint64)nbt_long_at(data, w))
        w += 1

    if temporary != c:
        int at = 0
        while at < vcont_count(c):
            vcont_set(c, at, vcont_at(decoded, at))
            at += 1
        vcont_free(temporary)
    return 1


# ---- the section itself ------------------------------------------------------

public def sec_new_for_wire(y: int, block_global_bits: int, biome_global_bits: int) -> VSection*:
    VSection* s = new VSection
    s.y = y
    s.non_empty = 0
    s.blocks = vcont_new(sec_block_count(), sec_blocks_min_bits(),
                         sec_blocks_max_bits(), block_global_bits)
    s.biomes = vcont_new(sec_biome_count(), sec_biomes_min_bits(),
                         sec_biomes_max_bits(), biome_global_bits)
    s.block_light = vt_calloc_char(sec_light_bytes())
    s.sky_light = vt_calloc_char(sec_light_bytes())
    return s


public def sec_new(y: int) -> VSection*:
    return sec_new_for_wire(y, sec_blocks_direct_bits(), sec_biomes_direct_bits())


public def sec_free(s: VSection*) -> void:
    if s == null:
        return
    vcont_free(s.blocks)
    vcont_free(s.biomes)
    if s.block_light != null:
        vt_free((void*)s.block_light)
    if s.sky_light != null:
        vt_free((void*)s.sky_light)
    del s


public def sec_index_ok(x: int, y: int, z: int, stride: int) -> int:
    if x < 0 or x >= stride:
        return 0
    if y < 0 or y >= stride:
        return 0
    if z < 0 or z >= stride:
        return 0
    return 1


public def sec_block_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return vcont_at(s.blocks, sec_block_index(x, y, z))


public def sec_block_set(s: VSection*, x: int, y: int, z: int, state: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    vcont_set(s.blocks, sec_block_index(x, y, z), state)


public def sec_biome_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 4) == 0:
        return 0
    return vcont_at(s.biomes, sec_biome_index(x, y, z))


public def sec_biome_set(s: VSection*, x: int, y: int, z: int, biome: int) -> void:
    if sec_index_ok(x, y, z, 4) == 0:
        return
    vcont_set(s.biomes, sec_biome_index(x, y, z), biome)


public def sec_block_light_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return sec_light_at(s.block_light, sec_block_index(x, y, z))


public def sec_block_light_set(s: VSection*, x: int, y: int, z: int, level: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    sec_light_set(s.block_light, sec_block_index(x, y, z), level)


public def sec_sky_light_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return sec_light_at(s.sky_light, sec_block_index(x, y, z))


public def sec_sky_light_set(s: VSection*, x: int, y: int, z: int, level: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    sec_light_set(s.sky_light, sec_block_index(x, y, z), level)


# Shrinks both containers before a save so the palette and data width are the
# narrowest the contents allow.
public def sec_compact(s: VSection*) -> void:
    vcont_compact(s.blocks)
    vcont_compact(s.biomes)
    return


# The whole section compound: `block_states`, `biomes`, the Y index and the
# light masks. `AltValues` is the block light array and `SkyLight` the sky one.
public def sec_to_nbt(s: VSection*, name: str) -> VNbt*:
    sec_compact(s)
    VNbt* root = nbt_compound_of(name)
    nbt_append(root, sec_container_to_nbt(s.blocks, "block_states"))
    nbt_append(root, sec_container_to_nbt(s.biomes, "biomes"))
    nbt_append(root, nbt_byte_of("Y", s.y))
    nbt_append(root, sec_light_to_tag(s.block_light, "AltValues"))
    nbt_append(root, sec_light_to_tag(s.sky_light, "SkyLight"))
    return root


# Accepts either tag spelling for the light arrays, which differ between
# versions of the format.
public def sec_from_nbt(t: VNbt*, y: int) -> VSection*:
    VSection* s = sec_new(y)
    VNbt* blocks = nbt_find(t, "block_states")
    if sec_container_from_nbt(blocks, s.blocks, sec_blocks_min_bits()) == 0:
        sec_free(s)
        return null
    VNbt* biomes = nbt_find(t, "biomes")
    if sec_container_from_nbt(biomes, s.biomes, sec_biomes_min_bits()) == 0:
        sec_free(s)
        return null
    s.y = nbt_get_int(t, "Y", y)
    VNbt* light = nbt_find(t, "AltValues")
    if light == null:
        light = nbt_find(t, "BlockLight")
    sec_light_from_tag(light, s.block_light)
    sec_light_from_tag(nbt_find(t, "SkyLight"), s.sky_light)
    return s


# ===== heightmap.cpy =====
# Vortex engine - chunk column heightmaps.
#
# A server sends one height value per block column, packed 9 bits at a time
# least significant bit first across a big endian long array, so 256 values
# occupy 36 longs. The values are absolute world Y, which is why a dimension
# that starts below y = 0 still reports heights above its minimum: the packing
# carries no offset. Cpyte shifts and masks `int64` correctly but compares an
# unsigned value as signed, so the unpack loops stay in `int64` and only ever
# test the low nine bits after the mask.


public def hm_cells() -> int:
    return 256


public def hm_kind_count() -> int:
    return 2


# The kinds this engine stores. The wire names each one with its own id, so
# these numbers only index the stored column.
public def hm_motion_blocking() -> int:
    return 0


public def hm_world_surface() -> int:
    return 1


# `Heightmap.Type` ids as they appear in a chunk packet. The other types the
# server may send - world surface and ocean floor before world generation -
# are walked but not stored.
public def hm_wire_world_surface() -> int64:
    return (int64)1


public def hm_wire_motion_blocking() -> int64:
    return (int64)4


public def hm_wire_kind_count() -> int64:
    return (int64)6


public def hm_bits() -> int:
    return 9


public def hm_value_mask() -> int64:
    return (int64)511


public def hm_long_count() -> int:
    return (hm_cells() * hm_bits() + 63) / 64


public def hm_values() -> int:
    return hm_cells() * hm_kind_count()


public def hm_kind_offset(kind: int) -> int:
    if kind < 0 or kind >= hm_kind_count():
        return -1
    return kind * hm_cells()


public def hm_new() -> int*:
    return vt_calloc_int(hm_values())


public def hm_free(values: int*) -> void:
    if values != null:
        vt_free((void*)values)


public def hm_index(kind: int, x: int, z: int) -> int:
    if x < 0 or x >= 16 or z < 0 or z >= 16:
        return -1
    int base = hm_kind_offset(kind)
    if base < 0:
        return -1
    return base + z * 16 + x


public def hm_set(values: int*, kind: int, x: int, z: int, height: int) -> int:
    int slot = hm_index(kind, x, z)
    if values == null or slot < 0:
        return 0
    vt_iset(values, slot, height)
    return 1


public def hm_get(values: int*, kind: int, x: int, z: int) -> int:
    int slot = hm_index(kind, x, z)
    if values == null or slot < 0:
        return -1
    return vt_iget(values, slot)


# Unpacks one kind's 36 longs into `cells` heights at `kind * 256`.
public def hm_unpack(longs: int64[], kind: int, values: int*) -> int:
    int base = hm_kind_offset(kind)
    if values == null or base < 0:
        return 0
    int i = 0
    while i < hm_cells():
        int bit = i * hm_bits()
        int word = bit / 64
        int shift = bit % 64
        int64 raw = longs[word] >> shift
        if shift > 64 - hm_bits():
            # The field continues in the next long. `>>` sign extends, so the
            # part held by this word has to be masked before the rest is
            # OR-ed in, or the extension overwrites the high field bits.
            int keep = 64 - shift
            raw = (raw & (((int64)1 << keep) - (int64)1)) | (longs[word + 1] << keep)
        vt_iset(values, base + i, (int)(raw & hm_value_mask()))
        i += 1
    return 1


# Packs one kind's heights back into longs; the inverse, used by the tests and
# by any future serverbound heightmap.
public def hm_pack(values: int*, kind: int, longs: int64[]) -> int:
    int base = hm_kind_offset(kind)
    if values == null or base < 0:
        return 0
    int i = 0
    while i < hm_long_count():
        longs[i] = (int64)0
        i += 1
    i = 0
    while i < hm_cells():
        int bit = i * hm_bits()
        int word = bit / 64
        int shift = bit % 64
        int64 value = (int64)vt_iget(values, base + i) & hm_value_mask()
        longs[word] = longs[word] | (value << shift)
        if shift > 64 - hm_bits():
            longs[word + 1] = longs[word + 1] | (value >> (64 - shift))
        i += 1
    return 1


# ===== world.cpy =====
# Vortex engine - bounded loaded-chunk store.


struct VWorld:
    int capacity
    int count
    int min_section
    int section_count
    int block_global_bits
    int biome_global_bits
    int* chunk_x
    int* chunk_z
    char* columns
    char* heightmaps


struct VDimensionRegistry:
    int capacity
    int dimension_count
    int dimension_registry_seen
    int biome_registry_seen
    int block_global_bits
    int biome_global_bits
    int* min_sections
    int* section_counts


public def vdimension_registry_new() -> VDimensionRegistry*:
    VDimensionRegistry* registry = new VDimensionRegistry
    registry.capacity = 256
    registry.dimension_count = 0
    registry.dimension_registry_seen = 0
    registry.biome_registry_seen = 0
    registry.block_global_bits = 15
    registry.biome_global_bits = 6
    registry.min_sections = vt_calloc_int(registry.capacity)
    registry.section_counts = vt_calloc_int(registry.capacity)
    return registry


public def vdimension_registry_free(registry: VDimensionRegistry*) -> void:
    if registry == null:
        return
    vt_free((void*)registry.min_sections)
    vt_free((void*)registry.section_counts)
    del registry


public def vdimension_registry_add_dimension(registry: VDimensionRegistry*,
                                             index: int, min_y: int,
                                             height: int) -> int:
    if registry == null or index < 0 or index >= registry.capacity:
        return 0
    if height < 16 or height > 4096 or height % 16 != 0 or min_y % 16 != 0:
        return 0
    vt_iset(registry.min_sections, index, min_y / 16)
    vt_iset(registry.section_counts, index, height / 16)
    if registry.dimension_count <= index:
        registry.dimension_count = index + 1
    return 1


public def vdimension_registry_finish_dimensions(registry: VDimensionRegistry*,
                                                  count: int) -> int:
    if registry == null or count < 0 or count > registry.capacity:
        return 0
    registry.dimension_count = count
    registry.dimension_registry_seen = 1
    return 1


public def vdimension_registry_dimension(registry: VDimensionRegistry*,
                                         index: int) -> int64[]:
    int64[] result = new int64[3]
    if registry == null or index < 0 or index >= registry.dimension_count:
        return result
    result[0] = vt_iget(registry.section_counts, index) > 0
    result[1] = vt_iget(registry.min_sections, index)
    result[2] = vt_iget(registry.section_counts, index)
    return result


public def vdimension_registry_set_biome_count(registry: VDimensionRegistry*,
                                                count: int) -> int:
    if registry == null or count < 1 or count > 1048576:
        return 0
    int bits = 0
    int capacity = 1
    while capacity < count:
        bits += 1
        capacity *= 2
    if bits < 1:
        bits = 1
    if bits > 32:
        return 0
    registry.biome_global_bits = bits
    registry.biome_registry_seen = 1
    return 1


def vworld_find(world: VWorld*, x: int, z: int) -> int:
    int i = 0
    while i < world.count:
        if vt_iget(world.chunk_x, i) == x and vt_iget(world.chunk_z, i) == z:
            return i
        i += 1
    return -1


def vworld_free_column(sections: char*, count: int) -> void:
    if sections == null:
        return
    int i = 0
    while i < count:
        sec_free((VSection*)vt_ptr_get(sections, i))
        i += 1
    vt_free((void*)sections)


public def vworld_new(capacity: int, min_section: int, section_count: int,
                      block_global_bits: int, biome_global_bits: int) -> VWorld*:
    if capacity < 1:
        capacity = 1
    if section_count < 1:
        section_count = 1
    VWorld* world = new VWorld
    world.capacity = capacity
    world.count = 0
    world.min_section = min_section
    world.section_count = section_count
    world.block_global_bits = block_global_bits
    world.biome_global_bits = biome_global_bits
    world.chunk_x = vt_calloc_int(capacity)
    world.chunk_z = vt_calloc_int(capacity)
    world.columns = vt_calloc_ptrs(capacity)
    world.heightmaps = vt_calloc_ptrs(capacity)
    return world


public def vworld_free(world: VWorld*) -> void:
    if world == null:
        return
    int i = 0
    while i < world.count:
        vworld_free_column((char*)vt_ptr_get(world.columns, i), world.section_count)
        hm_free((int*)vt_ptr_get(world.heightmaps, i))
        i += 1
    vt_free((void*)world.chunk_x)
    vt_free((void*)world.chunk_z)
    vt_free((void*)world.columns)
    vt_free((void*)world.heightmaps)
    del world


public def vworld_chunk_count(world: VWorld*) -> int:
    return world.count


public def vworld_set_dimension(world: VWorld*, min_section: int,
                                section_count: int,
                                block_global_bits: int,
                                biome_global_bits: int) -> int:
    if world == null or world.count != 0 or section_count < 1 or section_count > 256:
        return 0
    if block_global_bits < 1 or block_global_bits > 32 or biome_global_bits < 1 or biome_global_bits > 32:
        return 0
    world.min_section = min_section
    world.section_count = section_count
    world.block_global_bits = block_global_bits
    world.biome_global_bits = biome_global_bits
    return 1


# The column slot for (x, z), inserting an empty one when the chunk is new and
# returning -1 once the store is full. A fresh slot has neither sections nor
# heightmaps, so either half of the chunk packet may arrive first.
def vworld_slot(world: VWorld*, x: int, z: int) -> int:
    int index = vworld_find(world, x, z)
    if index >= 0:
        return index
    if world.count >= world.capacity:
        return -1
    index = world.count
    world.count += 1
    vt_iset(world.chunk_x, index, x)
    vt_iset(world.chunk_z, index, z)
    return index


public def vworld_replace_sections(world: VWorld*, x: int, z: int,
                                   sections: char*) -> int:
    if world == null or sections == null:
        return 0
    int index = vworld_slot(world, x, z)
    if index < 0:
        return 0
    vworld_free_column((char*)vt_ptr_get(world.columns, index), world.section_count)
    vt_ptr_set(world.columns, index, (void*)sections)
    return 1


# Takes ownership of `values`, one packed heightmap column of `hm_values()`
# entries, and frees whatever the chunk held before.
public def vworld_set_heightmaps(world: VWorld*, x: int, z: int,
                                 values: int*) -> int:
    if world == null or values == null:
        return 0
    int index = vworld_slot(world, x, z)
    if index < 0:
        return 0
    hm_free((int*)vt_ptr_get(world.heightmaps, index))
    vt_ptr_set(world.heightmaps, index, (void*)values)
    return 1


public def vworld_unload_chunk(world: VWorld*, x: int, z: int) -> int:
    if world == null:
        return 0
    int index = vworld_find(world, x, z)
    if index < 0:
        return 0
    vworld_free_column((char*)vt_ptr_get(world.columns, index), world.section_count)
    hm_free((int*)vt_ptr_get(world.heightmaps, index))
    int i = index + 1
    while i < world.count:
        vt_iset(world.chunk_x, i - 1, vt_iget(world.chunk_x, i))
        vt_iset(world.chunk_z, i - 1, vt_iget(world.chunk_z, i))
        vt_ptr_set(world.columns, i - 1, vt_ptr_get(world.columns, i))
        vt_ptr_set(world.heightmaps, i - 1, vt_ptr_get(world.heightmaps, i))
        i += 1
    world.count -= 1
    vt_ptr_set(world.columns, world.count, null)
    vt_ptr_set(world.heightmaps, world.count, null)
    return 1


public def vworld_section(world: VWorld*, chunk_x: int, chunk_z: int,
                          section_y: int) -> VSection*:
    if world == null:
        return null
    int column_index = vworld_find(world, chunk_x, chunk_z)
    int section_index = section_y - world.min_section
    if column_index < 0 or section_index < 0 or section_index >= world.section_count:
        return null
    char* sections = (char*)vt_ptr_get(world.columns, column_index)
    if sections == null:
        return null
    return (VSection*)vt_ptr_get(sections, section_index)


public def vworld_block_at(world: VWorld*, x: int, y: int, z: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 0
    return sec_block_at(section, local_x, local_y, local_z)


public def vworld_biome_at(world: VWorld*, x: int, y: int, z: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 0
    return sec_biome_at(section, local_x / 4, local_y / 4, local_z / 4)


# The stored height for one world block column, or -1 while the chunk is not
# loaded or the server sent no heightmap of that kind. Heights are absolute
# world Y as packed on the wire, so a negative minimum build height does not
# shift them.
public def vworld_height_at(world: VWorld*, kind: int, x: int, z: int) -> int:
    if world == null:
        return -1
    int local_x = x % 16
    int chunk_x = x / 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int local_z = z % 16
    int chunk_z = z / 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int column_index = vworld_find(world, chunk_x, chunk_z)
    if column_index < 0:
        return -1
    int* values = (int*)vt_ptr_get(world.heightmaps, column_index)
    if values == null:
        return -1
    return hm_get(values, kind, local_x, local_z)


# Packed sky/block light: sky * 16 + block. An unloaded section reads as full
# sky, which keeps the mesh of a partially loaded world visible.
public def vworld_light_at(world: VWorld*, x: int, y: int, z: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 15 * 16
    return sec_sky_light_at(section, local_x, local_y, local_z) * 16 + sec_block_light_at(section, local_x, local_y, local_z)


# Writes one block. Returns 0 when the chunk or section is not loaded, so a
# block update for an unloaded chunk is a no-op rather than an error.
public def vworld_set_block_at(world: VWorld*, x: int, y: int, z: int,
                               state: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 0
    sec_block_set(section, local_x, local_y, local_z, state)
    return 1


# ===== protocol_chunk.cpy =====
# Vortex engine - protocol PalettedContainer decoder.


def sec_wire_read_varint(b: VBuf*, ok: int*) -> int:
    *ok = 0
    int value = vbuf_take_varint(b, ok)
    if *ok == 0 or value < 0:
        *ok = 0
        return 0
    return value


def sec_wire_read_container(b: VBuf*, c: VContainer*, entries: int,
                            blocks: bool, global_bits: int) -> int:
    if vbuf_avail(b) < 1:
        return 0
    int wire_bits = (int)vbuf_take_u8(b)
    int bits = 0
    bool has_palette = false
    if wire_bits == 0:
        int ok = 0
        int value = sec_wire_read_varint(b, &ok)
        if ok == 0:
            return 0
        vcont_reset(c, value)
        return 1
    if blocks:
        if wire_bits <= 4:
            bits = 4
            has_palette = true
        elif wire_bits <= 8:
            bits = wire_bits
            has_palette = true
        else:
            bits = global_bits
            if bits < wire_bits:
                bits = wire_bits
    else:
        if wire_bits <= 3:
            bits = wire_bits
            has_palette = true
        else:
            bits = global_bits
            if bits < wire_bits:
                bits = wire_bits
    if bits < 1 or bits > 32:
        return 0
    if has_palette:
        int ok = 0
        int palette_count = sec_wire_read_varint(b, &ok)
        if ok == 0 or palette_count < 1 or palette_count > (1 << bits):
            return 0
        vcont_reset(c, 0)
        int i = 0
        while i < palette_count:
            int value = sec_wire_read_varint(b, &ok)
            if ok == 0:
                return 0
            vcont_palette_add(c, value)
            i += 1
        if vcont_palette_len(c) != palette_count:
            return 0
    else:
        c.direct_bits = bits
    int per_word = 64 / bits
    int word_count = (entries + per_word - 1) / per_word
    if vbuf_avail(b) < word_count * 8:
        return 0
    if has_palette:
        vcont_alloc(c, bits)
    else:
        vcont_alloc_direct(c, bits)
    int word = 0
    while word < word_count:
        vcont_set_word(c, word, (uint64)vbuf_take_i64_be(b))
        word += 1
    return 1


public def sec_read_wire_sections(b: VBuf*, count: int, min_section: int,
                                 block_global_bits: int,
                                 biome_global_bits: int,
                                 ok: int*) -> char*:
    *ok = 0
    if b == null or count < 1 or block_global_bits < 1 or biome_global_bits < 1:
        return null
    char* sections = vt_calloc_ptrs(count)
    int i = 0
    while i < count:
        if vbuf_avail(b) < 2:
            vworld_free_column(sections, count)
            return null
        int non_empty = vbuf_take_i16_be(b)
        if non_empty < 0 or non_empty > 4096:
            vworld_free_column(sections, count)
            return null
        VSection* section = sec_new_for_wire(min_section + i,
                                             block_global_bits,
                                             biome_global_bits)
        section.non_empty = non_empty
        int blocks_ok = sec_wire_read_container(b, section.blocks,
                                                sec_block_count(), true,
                                                block_global_bits)
        int biomes_ok = sec_wire_read_container(b, section.biomes,
                                                sec_biome_count(), false,
                                                biome_global_bits)
        if blocks_ok == 0 or biomes_ok == 0:
            sec_free(section)
            vworld_free_column(sections, count)
            return null
        vt_ptr_set(sections, i, (void*)section)
        i += 1
    if vbuf_avail(b) != 0:
        vworld_free_column(sections, count)
        return null
    *ok = 1
    return sections


# ===== blockdb.cpy =====
# Vortex engine - block facts lookup.
#
# The mesher needs three things for a block state id: whether it is air, what
# geometry it has, and whether it hides the neighbour's face. The block state
# id -> block mapping is delivered by the data generator's blocks report, which
# tools/gen_blockdb.py turns into a compact binary read by the C layer in
# src/engine/blockdb.c.
#
# The database is optional. Without it the mesher falls back to state 0 = air
# and every other state = opaque cube, which keeps a world visible even when
# the generated data has not been built.
#
# License boundary: the binary is generated from user-supplied version data and
# lives under generated/; it is not part of the repository. See
# docs/PARITY_BOUNDARY.md.


# ---- classification flags, matching tools/gen_blockdb.py ---------------------

public def block_flag_air() -> int:
    return 1


public def block_flag_fluid() -> int:
    return 2


public def block_flag_cube() -> int:
    return 4


public def block_flag_opaque() -> int:
    return 8


public def block_flag_translucent() -> int:
    return 16


public def block_flag_leaves() -> int:
    return 32


public def block_flag_cross() -> int:
    return 64


# ---- loading -----------------------------------------------------------------

public def blockdb_default_path() -> str:
    return vt_blockdb_path_from_env()


public def blockdb_load(path: str) -> int:
    return vt_blockdb_load(path)


public def blockdb_load_default() -> int:
    return vt_blockdb_load(vt_blockdb_path_from_env())


public def blockdb_unload() -> void:
    vt_blockdb_unload()


public def blockdb_loaded() -> int:
    return vt_blockdb_loaded()


public def blockdb_verify() -> int:
    return vt_blockdb_verify()


public def blockdb_state_count() -> int:
    return vt_blockdb_state_count()


public def blockdb_block_count() -> int:
    return vt_blockdb_block_count()


# ---- state queries -----------------------------------------------------------

# Raw flags, or -1 when the state is unknown or no database is loaded.
public def blockdb_flags(state: int) -> int:
    return vt_blockdb_flags(state)


public def blockdb_protocol(state: int) -> int:
    return vt_blockdb_protocol(state)


public def blockdb_has(state: int, flag: int) -> int:
    int flags = vt_blockdb_flags(state)
    if flags < 0:
        if state == 0:
            return 1 if flag == block_flag_air() else 0
        return 1 if flag == block_flag_opaque() or flag == block_flag_cube() else 0
    if (flags & flag) != 0:
        return 1
    return 0


public def blockdb_is_air(state: int) -> int:
    return blockdb_has(state, block_flag_air())


# A full cube, so the mesher emits its six faces (subject to culling).
public def blockdb_is_cube(state: int) -> int:
    return blockdb_has(state, block_flag_cube())


# Opaque enough that a neighbouring full cube's shared face is invisible.
public def blockdb_is_opaque(state: int) -> int:
    return blockdb_has(state, block_flag_opaque())


public def blockdb_is_translucent(state: int) -> int:
    return blockdb_has(state, block_flag_translucent())


public def blockdb_is_leaves(state: int) -> int:
    return blockdb_has(state, block_flag_leaves())


public def blockdb_is_cross(state: int) -> int:
    return blockdb_has(state, block_flag_cross())


public def blockdb_is_fluid(state: int) -> int:
    return blockdb_has(state, block_flag_fluid())


# 1 when two neighbouring states share a face that can be dropped: the near
# block is a full cube and the far one hides the face. Leaves are culled
# against leaves, translucent blocks against their own block, everything else
# only against opaque cubes.
public def blockdb_hides_face(near: int, far: int) -> int:
    if blockdb_is_air(near) == 1 or blockdb_is_cube(near) == 0:
        return 0
    if blockdb_is_air(far) == 1:
        return 0
    if blockdb_is_opaque(far) == 1:
        return 1
    if blockdb_is_leaves(near) == 1 and blockdb_is_leaves(far) == 1:
        return 1
    if blockdb_is_translucent(near) == 1 and blockdb_is_translucent(far) == 1:
        int a = vt_blockdb_protocol(near)
        int b = vt_blockdb_protocol(far)
        if a >= 0 and a == b:
            return 1
    return 0


# Block name without the namespace, or "" when unknown.
public def blockdb_name(state: int) -> str:
    char* buffer = vt_calloc_char(96)
    int length = vt_blockdb_name(state, buffer, 96)
    if length < 0:
        vt_free((void*)buffer)
        return ""
    str out = vt_dup(buffer)
    vt_free((void*)buffer)
    return out


# ---- record view, used by the loader test ------------------------------------

public def blockdb_first_state_at(index: int) -> int:
    return vt_blockdb_first_state_at(index)


public def blockdb_state_count_at(index: int) -> int:
    return vt_blockdb_state_count_at(index)


public def blockdb_flags_at(index: int) -> int:
    return vt_blockdb_flags_at(index)


public def blockdb_protocol_at(index: int) -> int:
    return vt_blockdb_protocol_at(index)


public def blockdb_name_at(index: int) -> str:
    char* buffer = vt_calloc_char(96)
    int length = vt_blockdb_name_at(index, buffer, 96)
    if length < 0:
        vt_free((void*)buffer)
        return ""
    str out = vt_dup(buffer)
    vt_free((void*)buffer)
    return out


public def blockdb_name_length_at(index: int) -> int:
    return vt_blockdb_name_length_at(index)


# ===== mesher.cpy =====
# Vortex engine - greedy section mesher.
#
# Turns a loaded 16x16x16 section into two vertex/index streams: opaque
# (solid cubes, cutout leaves and cross-shaped plants) and translucent (water,
# lava, glass, ice). The algorithm follows Horizon's terrain mesher in shape:
#
#   * one pass per face direction; each 16x16 slice builds a mask of visible
#     faces, with the neighbour sampled through VWorld so faces on a section
#     or chunk boundary are culled correctly;
#   * equal mask cells are merged into maximal rectangles (width first, then
#     height), so a flat stone section needs six quads, not 24,576;
#   * a mask cell's key is the block's protocol id plus the light of the cell
#     in front of the face, so a merge never crosses a material or light
#     boundary;
#   * translucent faces go to the second stream so a renderer can order them.
#
# Vertices are typed, packed int64 vectors, nine components each:
#
#   0 x, 1 y, 2 z      absolute block corner (integers; a quad is planar)
#   3 u, 4 v           texture coordinates in block units, 0..width/height
#   5 layer            block protocol id (the renderer's texture layer)
#   6 sky_light        0..15
#   7 block_light      0..15
#   8 face             +X -X +Y -Y +Z -Z, or mesh_face_cross()
#
# Indices are int64, two triangles per quad, counter-clockwise from outside.
#
# License boundary: no Mojang-derived code or data. Block classification comes
# from the optional generated database (see world/blockdb.cpy); without it the
# mesher treats state 0 as air and everything else as an opaque cube.
#
# The compiler resolves calls against what it has already read, so the helpers
# below are ordered bottom up.


public def mesh_face_pos_x() -> int:
    return 0


public def mesh_face_neg_x() -> int:
    return 1


public def mesh_face_pos_y() -> int:
    return 2


public def mesh_face_neg_y() -> int:
    return 3


public def mesh_face_pos_z() -> int:
    return 4


public def mesh_face_neg_z() -> int:
    return 5


public def mesh_face_cross() -> int:
    return 6


# Components per vertex, matching the list in the module comment.
public def mesh_vertex_stride() -> int:
    return 9


def mesh_kind_scale() -> int:
    return 1000000000


def mesh_unknown_layer() -> int:
    return 65535


# ---- typed vectors -----------------------------------------------------------

def mesh_empty_ints() -> int64[]:
    int64[] none = new int64[0]
    return none


struct VMesh:
    int64[] verts
    int64[] indices
    int vertex_count
    int index_count
    int quad_count


public def vmesh_new() -> VMesh*:
    VMesh* mesh = new VMesh
    mesh.verts = mesh_empty_ints()
    mesh.indices = mesh_empty_ints()
    mesh.vertex_count = 0
    mesh.index_count = 0
    mesh.quad_count = 0
    return mesh


public def vmesh_free(mesh: VMesh*) -> void:
    if mesh == null:
        return
    del mesh


public def vmesh_vertex_count(mesh: VMesh*) -> int:
    return mesh.vertex_count


public def vmesh_index_count(mesh: VMesh*) -> int:
    return mesh.index_count


public def vmesh_quad_count(mesh: VMesh*) -> int:
    return mesh.quad_count


# Component `component` of vertex `vertex`.
public def vmesh_component(mesh: VMesh*, vertex: int, component: int) -> int64:
    int at = vertex * mesh_vertex_stride() + component
    if at < 0 or at >= (int)len(mesh.verts):
        return (int64)0
    return mesh.verts[at]


public def vmesh_index(mesh: VMesh*, index: int) -> int64:
    if index < 0 or index >= (int)len(mesh.indices):
        return (int64)0
    return mesh.indices[index]


def vmesh_add_vertex(mesh: VMesh*, x: int, y: int, z: int, u: int, v: int,
                     layer: int, sky: int, block: int, face: int) -> void:
    append(mesh.verts, (int64)x)
    append(mesh.verts, (int64)y)
    append(mesh.verts, (int64)z)
    append(mesh.verts, (int64)u)
    append(mesh.verts, (int64)v)
    append(mesh.verts, (int64)layer)
    append(mesh.verts, (int64)sky)
    append(mesh.verts, (int64)block)
    append(mesh.verts, (int64)face)
    mesh.vertex_count += 1


# Four corners in counter-clockwise order seen from outside the block.
def vmesh_add_quad(mesh: VMesh*, x0: int, y0: int, z0: int,
                   x1: int, y1: int, z1: int,
                   x2: int, y2: int, z2: int,
                   x3: int, y3: int, z3: int,
                   width: int, height: int, layer: int, sky: int, block: int,
                   face: int) -> void:
    int base = mesh.vertex_count
    vmesh_add_vertex(mesh, x0, y0, z0, 0, 0, layer, sky, block, face)
    vmesh_add_vertex(mesh, x1, y1, z1, width, 0, layer, sky, block, face)
    vmesh_add_vertex(mesh, x2, y2, z2, width, height, layer, sky, block, face)
    vmesh_add_vertex(mesh, x3, y3, z3, 0, height, layer, sky, block, face)
    append(mesh.indices, (int64)base)
    append(mesh.indices, (int64)(base + 1))
    append(mesh.indices, (int64)(base + 2))
    append(mesh.indices, (int64)base)
    append(mesh.indices, (int64)(base + 2))
    append(mesh.indices, (int64)(base + 3))
    mesh.index_count += 6
    mesh.quad_count += 1


# ---- result ------------------------------------------------------------------

struct VMeshResult:
    VMesh* opaque
    VMesh* translucent
    int sections
    int quads


public def vmesh_result_new() -> VMeshResult*:
    VMeshResult* result = new VMeshResult
    result.opaque = vmesh_new()
    result.translucent = vmesh_new()
    result.sections = 0
    result.quads = 0
    return result


public def vmesh_result_free(result: VMeshResult*) -> void:
    if result == null:
        return
    vmesh_free(result.opaque)
    vmesh_free(result.translucent)
    del result


public def vmesh_result_opaque(result: VMeshResult*) -> VMesh*:
    return result.opaque


public def vmesh_result_translucent(result: VMeshResult*) -> VMesh*:
    return result.translucent


public def vmesh_result_sections(result: VMeshResult*) -> int:
    return result.sections


public def vmesh_result_quads(result: VMeshResult*) -> int:
    VMesh* opaque = result.opaque
    VMesh* translucent = result.translucent
    return opaque.quad_count + translucent.quad_count


# ---- mask --------------------------------------------------------------------

# Cell coordinate for one face slice. `a` runs along the first axis, `b` along
# the second; see the emission table below for the mapping.
def mesh_cell_x(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return slice
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return a
    return a


def mesh_cell_y(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return b
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return slice
    return b


def mesh_cell_z(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return a
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return b
    return slice


def mesh_neighbor_x(dir: int, x: int) -> int:
    if dir == mesh_face_pos_x():
        return x + 1
    if dir == mesh_face_neg_x():
        return x - 1
    return x


def mesh_neighbor_y(dir: int, y: int) -> int:
    if dir == mesh_face_pos_y():
        return y + 1
    if dir == mesh_face_neg_y():
        return y - 1
    return y


def mesh_neighbor_z(dir: int, z: int) -> int:
    if dir == mesh_face_pos_z():
        return z + 1
    if dir == mesh_face_neg_z():
        return z - 1
    return z


# Mask key for the face of the block at (x, y, z) in direction `dir`, or 0
# when the face is absent or hidden. The key packs the render layer, the block
# id and the light of the cell in front of the face.
def mesh_face_key(world: VWorld*, chunk_x: int, chunk_z: int, section_y: int,
                  section: VSection*, x: int, y: int, z: int, dir: int) -> int:
    int state = sec_block_at(section, x, y, z)
    if state == 0:
        return 0
    if blockdb_is_cube(state) == 0:
        return 0
    int nx = mesh_neighbor_x(dir, x)
    int ny = mesh_neighbor_y(dir, y)
    int nz = mesh_neighbor_z(dir, z)
    int wx = chunk_x * 16 + nx
    int wy = section_y * 16 + ny
    int wz = chunk_z * 16 + nz
    int neighbor = vworld_block_at(world, wx, wy, wz)
    if blockdb_hides_face(state, neighbor) == 1:
        return 0
    int light = vworld_light_at(world, wx, wy, wz)
    int layer = blockdb_protocol(state)
    if layer < 0:
        layer = mesh_unknown_layer()
    int kind = 0
    if blockdb_is_translucent(state) == 1:
        kind = 1
    return kind * mesh_kind_scale() + (layer + 1) * 256 + light


def mesh_build_mask(world: VWorld*, chunk_x: int, chunk_z: int, section_y: int,
                    section: VSection*, dir: int, slice: int, mask: int*) -> void:
    int a = 0
    while a < 16:
        int b = 0
        while b < 16:
            int x = mesh_cell_x(dir, slice, a, b)
            int y = mesh_cell_y(dir, slice, a, b)
            int z = mesh_cell_z(dir, slice, a, b)
            int key = mesh_face_key(world, chunk_x, chunk_z, section_y, section,
                                    x, y, z, dir)
            vt_iset(mask, a + b * 16, key)
            b += 1
        a += 1


# ---- emission ----------------------------------------------------------------

# Absolute base of the section, so the vertex vectors need no per-section
# translation later.
def mesh_emit_rect(mesh: VMesh*, dir: int, slice: int, base_x: int, base_y: int,
                   base_z: int, a: int, b: int, width_a: int, width_b: int,
                   layer: int, sky: int, block: int) -> void:
    int x = base_x + slice
    int y = base_y + slice
    int z = base_z + slice
    if dir == mesh_face_pos_x():
        vmesh_add_quad(mesh, x + 1, base_y + b, base_z + a,
                       x + 1, base_y + b + width_b, base_z + a,
                       x + 1, base_y + b + width_b, base_z + a + width_a,
                       x + 1, base_y + b, base_z + a + width_a,
                       width_b, width_a, layer, sky, block, dir)
    elif dir == mesh_face_neg_x():
        vmesh_add_quad(mesh, x, base_y + b, base_z + a + width_a,
                       x, base_y + b + width_b, base_z + a + width_a,
                       x, base_y + b + width_b, base_z + a,
                       x, base_y + b, base_z + a,
                       width_b, width_a, layer, sky, block, dir)
    elif dir == mesh_face_pos_y():
        vmesh_add_quad(mesh, base_x + a, y + 1, base_z + b,
                       base_x + a, y + 1, base_z + b + width_b,
                       base_x + a + width_a, y + 1, base_z + b + width_b,
                       base_x + a + width_a, y + 1, base_z + b,
                       width_a, width_b, layer, sky, block, dir)
    elif dir == mesh_face_neg_y():
        vmesh_add_quad(mesh, base_x + a, y, base_z + b,
                       base_x + a + width_a, y, base_z + b,
                       base_x + a + width_a, y, base_z + b + width_b,
                       base_x + a, y, base_z + b + width_b,
                       width_a, width_b, layer, sky, block, dir)
    elif dir == mesh_face_pos_z():
        vmesh_add_quad(mesh, base_x + a, base_y + b, z + 1,
                       base_x + a + width_a, base_y + b, z + 1,
                       base_x + a + width_a, base_y + b + width_b, z + 1,
                       base_x + a, base_y + b + width_b, z + 1,
                       width_a, width_b, layer, sky, block, dir)
    else:
        vmesh_add_quad(mesh, base_x + a + width_a, base_y + b, z,
                       base_x + a, base_y + b, z,
                       base_x + a, base_y + b + width_b, z,
                       base_x + a + width_a, base_y + b + width_b, z,
                       width_a, width_b, layer, sky, block, dir)


# Merges equal mask cells into maximal rectangles and emits one quad each.
def mesh_greedy(opaque: VMesh*, translucent: VMesh*, mask: int*, dir: int,
                slice: int, base_x: int, base_y: int, base_z: int) -> void:
    int a = 0
    while a < 16:
        int b = 0
        while b < 16:
            int key = vt_iget(mask, a + b * 16)
            if key != 0:
                int width_b = 1
                while b + width_b < 16 and vt_iget(mask, a + (b + width_b) * 16) == key:
                    width_b += 1
                int width_a = 1
                bool grow = true
                while a + width_a < 16 and grow:
                    int i = 0
                    while i < width_b:
                        if vt_iget(mask, (a + width_a) + (b + i) * 16) != key:
                            grow = false
                        i += 1
                    if grow:
                        width_a += 1
                int kind = key / mesh_kind_scale()
                int rest = key % mesh_kind_scale()
                int layer = rest / 256 - 1
                int sky = (rest % 256) / 16
                int block = rest % 16
                VMesh* target = opaque
                if kind == 1:
                    target = translucent
                mesh_emit_rect(target, dir, slice, base_x, base_y, base_z,
                               a, b, width_a, width_b, layer, sky, block)
                int ai = 0
                while ai < width_a:
                    int bi = 0
                    while bi < width_b:
                        vt_iset(mask, (a + ai) + (b + bi) * 16, 0)
                        bi += 1
                    ai += 1
                b += width_b
            else:
                b += 1
        a += 1


# ---- cross geometry ----------------------------------------------------------

def mesh_cross_quads(mesh: VMesh*, base_x: int, base_y: int, base_z: int,
                     x: int, y: int, z: int, layer: int, sky: int, block: int) -> void:
    int x0 = base_x + x
    int y0 = base_y + y
    int z0 = base_z + z
    # Both diagonals, each emitted twice so the quad is visible from either
    # side; plants are not sorted into a back-face stream.
    vmesh_add_quad(mesh, x0, y0, z0, x0 + 1, y0, z0 + 1,
                   x0 + 1, y0 + 1, z0 + 1, x0, y0 + 1, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0, y0 + 1, z0, x0 + 1, y0 + 1, z0 + 1,
                   x0 + 1, y0, z0 + 1, x0, y0, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0 + 1, y0, z0, x0, y0, z0 + 1,
                   x0, y0 + 1, z0 + 1, x0 + 1, y0 + 1, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0 + 1, y0 + 1, z0, x0, y0 + 1, z0 + 1,
                   x0, y0, z0 + 1, x0 + 1, y0, z0,
                   1, 1, layer, sky, block, mesh_face_cross())


def mesh_cross_pass(result: VMeshResult*, world: VWorld*, chunk_x: int,
                    chunk_z: int, section_y: int, section: VSection*) -> void:
    int base_x = chunk_x * 16
    int base_y = section_y * 16
    int base_z = chunk_z * 16
    int x = 0
    while x < 16:
        int y = 0
        while y < 16:
            int z = 0
            while z < 16:
                int state = sec_block_at(section, x, y, z)
                if state != 0 and blockdb_is_cross(state) == 1:
                    int light = vworld_light_at(world, base_x + x, base_y + y,
                                                base_z + z)
                    int layer = blockdb_protocol(state)
                    if layer < 0:
                        layer = mesh_unknown_layer()
                    mesh_cross_quads(result.opaque, base_x, base_y, base_z,
                                     x, y, z, layer, light / 16, light % 16)
                z += 1
            y += 1
        x += 1


# ---- section and world entry points -----------------------------------------

def vmesh_section_into(result: VMeshResult*, world: VWorld*, chunk_x: int,
                       chunk_z: int, section_y: int) -> void:
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return
    int base_x = chunk_x * 16
    int base_y = section_y * 16
    int base_z = chunk_z * 16
    int* mask = vt_calloc_int(256)
    int dir = 0
    while dir < 6:
        int slice = 0
        while slice < 16:
            int i = 0
            while i < 256:
                vt_iset(mask, i, 0)
                i += 1
            mesh_build_mask(world, chunk_x, chunk_z, section_y, section, dir,
                            slice, mask)
            mesh_greedy(result.opaque, result.translucent, mask, dir, slice,
                        base_x, base_y, base_z)
            slice += 1
        dir += 1
    vt_free((void*)mask)
    mesh_cross_pass(result, world, chunk_x, chunk_z, section_y, section)
    result.sections += 1
    result.quads = vmesh_result_quads(result)


# Mesh one section; absolute vertex coordinates.
public def vmesh_section(world: VWorld*, chunk_x: int, chunk_z: int,
                         section_y: int) -> VMeshResult*:
    VMeshResult* result = vmesh_result_new()
    vmesh_section_into(result, world, chunk_x, chunk_z, section_y)
    return result


# Mesh every loaded section of the world into one pair of streams.
public def vmesh_world(world: VWorld*) -> VMeshResult*:
    VMeshResult* result = vmesh_result_new()
    if world == null:
        return result
    int column = 0
    while column < world.count:
        int chunk_x = vt_iget(world.chunk_x, column)
        int chunk_z = vt_iget(world.chunk_z, column)
        int i = 0
        while i < world.section_count:
            vmesh_section_into(result, world, chunk_x, chunk_z,
                               world.min_section + i)
            i += 1
        column += 1
    return result


# ===== harness.cpy =====
# Vortex engine - the shared assertion harness for the test bundles.
#
# A test target's manifest lists the engine, this file, and the test itself;
# failures count up through an `int*` out parameter because Cpyte module-level
# variables are only reachable from `main()`.


def check(label: str, cond: bool, fails: int*) -> void:
    if cond:
        print("  ok   " + label)
    else:
        print("  FAIL " + label)
        *fails = *fails + 1


def check_int(label: str, got: int, want: int, fails: int*) -> void:
    if got == want:
        print("  ok   " + label)
    else:
        print("  FAIL " + label + ": got " + str(got) + " want " + str(want))
        *fails = *fails + 1


def check_str(label: str, got: str, want: str, fails: int*) -> void:
    if str_equals(got, want):
        print("  ok   " + label)
    else:
        print("  FAIL " + label + ": got '" + got + "' want '" + want + "'")
        *fails = *fails + 1


# Runs the suite and returns the process exit code.
public def report(title: str, fails: int) -> int:
    if fails == 0:
        print(title + ": all passed")
        return 0
    print(title + ": " + str(fails) + " failure(s)")
    return 1


# ===== test_palette.cpy =====
# Vortex engine - paletted container tests.
#
#   ./build.sh --run tests/palette.txt


def block_container() -> VContainer*:
    return vcont_new(4096, 4, 8, 16)


# A two bit palette indexes four values, so the fifth distinct value goes
# direct: entries 0, 200, 400, 600 hold 1, 2, 3, 4 and the rest hold 0.
def small_direct() -> VContainer*:
    VContainer* c = vcont_new(4096, 2, 2, 14)
    int i = 0
    while i < 4:
        vcont_set(c, i * 200, i + 1)
        i += 1
    return c


def test_uniform(fails: int*) -> void:
    print("uniform start:")
    VContainer* c = block_container()
    check_int("mode", vcont_mode(c), vcont_uniform_mode(), fails)
    check_int("bits", vcont_bits(c), 0, fails)
    check_int("word count", vcont_word_count(c), 0, fails)
    check_int("palette len", vcont_palette_len(c), 0, fails)
    check_int("entry 0", vcont_at(c, 0), 0, fails)
    check_int("entry 4095", vcont_at(c, 4095), 0, fails)
    check_int("uniform value", vcont_uniform_value(c), 0, fails)
    check_int("is uniform", vcont_is_uniform(c), 1, fails)

    # Writing the value it already holds must not cost a palette.
    vcont_set(c, 100, 0)
    check_int("same value stays uniform", vcont_mode(c), vcont_uniform_mode(), fails)
    check_int("still no words", vcont_word_count(c), 0, fails)

    vcont_set(c, 16, 7)
    check_int("left uniform", vcont_mode(c), vcont_indirect_mode(), fails)
    check_int("starts at min bits", vcont_bits(c), 4, fails)
    check_int("palette holds old and new", vcont_palette_len(c), 2, fails)
    check_int("palette 0", vcont_palette_at(c, 0), 0, fails)
    check_int("palette 1", vcont_palette_at(c, 1), 7, fails)
    check_int("changed entry", vcont_at(c, 16), 7, fails)
    check_int("neighbour entry", vcont_at(c, 15), 0, fails)
    check_int("far entry", vcont_at(c, 4095), 0, fails)
    check_int("no longer uniform", vcont_is_uniform(c), 0, fails)
    vcont_free(c)


def test_padded_words(fails: int*) -> void:
    print("padded packing:")
    check_int("4 bits", vt_packed_words(4096, 4), 256, fails)
    check_int("5 bits", vt_packed_words(4096, 5), 342, fails)
    check_int("6 bits", vt_packed_words(4096, 6), 410, fails)
    check_int("7 bits", vt_packed_words(4096, 7), 456, fails)
    check_int("8 bits", vt_packed_words(4096, 8), 512, fails)
    check_int("14 bits", vt_packed_words(4096, 14), 1024, fails)
    check_int("16 bits", vt_packed_words(4096, 16), 1024, fails)
    check_int("3 bits over 64", vt_packed_words(64, 3), 4, fails)
    check_int("9 bits over 64", vt_packed_words(64, 9), 10, fails)
    check_int("zero width", vt_packed_words(4096, 0), 0, fails)

    # Sixteen 4 bit entries fit a word, so entry 16 opens the next one.
    VContainer* a = block_container()
    vcont_set(a, 16, 7)
    check_int("entry 16 in word 1", (int)vcont_save_word(a, 1), 1, fails)
    check_int("word 0 left empty", (int)vcont_save_word(a, 0), 0, fails)
    VContainer* b = block_container()
    vcont_set(b, 15, 7)
    check("entry 15 in word 0", vcont_save_word(b, 0) != (uint64)0, fails)
    check_int("word 1 left empty", (int)vcont_save_word(b, 1), 0, fails)
    vcont_free(a)
    vcont_free(b)


def test_width_growth(fails: int*) -> void:
    print("width growth:")
    VContainer* c = block_container()
    int i = 0
    while i < 15:
        vcont_set(c, i * 10, i + 1)
        i += 1
    check_int("16 palette entries", vcont_palette_len(c), 16, fails)
    check_int("still 4 bits", vcont_bits(c), 4, fails)
    check_int("256 words", vcont_word_count(c), 256, fails)

    # The sixteenth distinct value needs a fifth bit for the index.
    vcont_set(c, 200, 16)
    check_int("17 palette entries", vcont_palette_len(c), 17, fails)
    check_int("repacked to 5 bits", vcont_bits(c), 5, fails)
    check_int("342 words", vcont_word_count(c), 342, fails)
    check_int("first entry kept", vcont_at(c, 0), 1, fails)
    check_int("last entry kept", vcont_at(c, 140), 15, fails)
    check_int("new entry", vcont_at(c, 200), 16, fails)
    check_int("untouched entry", vcont_at(c, 141), 0, fails)

    # Five bits give twelve entries per word, so index 12 opens word 1 and
    # writing it cannot disturb the eleven that came before.
    uint64 before = vcont_save_word(c, 0)
    vcont_set(c, 12, 77)
    check("word 0 unchanged", vcont_save_word(c, 0) == before, fails)
    check_int("entry 12 reads back", vcont_at(c, 12), 77, fails)
    check_int("entry 11 unaffected", vcont_at(c, 11), 0, fails)
    vcont_free(c)


def test_direct_promotion(fails: int*) -> void:
    print("direct promotion:")
    VContainer* c = block_container()
    int i = 0
    while i < 255:
        vcont_set(c, i, i + 1)
        i += 1
    check_int("full palette", vcont_palette_len(c), 256, fails)
    check_int("widest indirect", vcont_bits(c), 8, fails)
    check_int("mode", vcont_mode(c), vcont_indirect_mode(), fails)

    vcont_set(c, 300, 256)
    check_int("palette dropped", vcont_palette_len(c), 0, fails)
    check_int("direct mode", vcont_mode(c), vcont_direct_mode(), fails)
    check_int("direct width", vcont_bits(c), 16, fails)
    check_int("1024 words", vcont_word_count(c), 1024, fails)
    check_int("new value", vcont_at(c, 300), 256, fails)
    check_int("first promoted entry", vcont_at(c, 0), 1, fails)
    check_int("last promoted entry", vcont_at(c, 254), 255, fails)
    check_int("entry before the new one", vcont_at(c, 299), 0, fails)
    check_int("entry after the new one", vcont_at(c, 301), 0, fails)
    check_int("distinct values", vcont_distinct_count(c), 257, fails)
    vcont_free(c)


def test_compaction(fails: int*) -> void:
    print("compaction:")
    VContainer* c = block_container()
    int i = 0
    while i < 20:
        vcont_set(c, i * 7, i + 1)
        i += 1
    check_int("5 bits for 21 values", vcont_bits(c), 5, fails)
    check_int("palette", vcont_palette_len(c), 21, fails)

    i = 0
    while i < 20:
        vcont_set(c, i * 7, 3)
        i += 1
    vcont_compact(c)
    check_int("back to 4 bits", vcont_bits(c), 4, fails)
    check_int("two palette entries", vcont_palette_len(c), 2, fails)
    check_int("256 words", vcont_word_count(c), 256, fails)
    check_int("held entry", vcont_at(c, 7), 3, fails)
    check_int("empty entry", vcont_at(c, 8), 0, fails)
    check_int("last held entry", vcont_at(c, 133), 3, fails)

    i = 0
    while i < 20:
        vcont_set(c, i * 7, 0)
        i += 1
    check_int("single valued again", vcont_is_uniform(c), 1, fails)
    check_int("try uniform collapses", vcont_try_uniform(c), 1, fails)
    check_int("uniform mode", vcont_mode(c), vcont_uniform_mode(), fails)
    check_int("no words", vcont_word_count(c), 0, fails)
    vcont_free(c)


def test_compact_stays_direct(fails: int*) -> void:
    print("compaction with too many values:")
    VContainer* c = block_container()
    int i = 0
    while i < 255:
        vcont_set(c, i, i + 1)
        i += 1
    vcont_set(c, 300, 256)
    vcont_compact(c)
    check_int("257 values do not fit 8 bits", vcont_mode(c), vcont_direct_mode(), fails)
    check_int("16 bit words", vcont_word_count(c), 1024, fails)
    check_int("entry kept", vcont_at(c, 120), 121, fails)
    check_int("new value kept", vcont_at(c, 300), 256, fails)

    # Collapsing most entries lets the palette take over again.
    i = 0
    while i < 255:
        vcont_set(c, i, 0)
        i += 1
    vcont_compact(c)
    check_int("indirect after shrinking", vcont_mode(c), vcont_indirect_mode(), fails)
    check_int("two values", vcont_palette_len(c), 2, fails)
    check_int("4 bits", vcont_bits(c), 4, fails)
    check_int("the value that stayed", vcont_at(c, 300), 256, fails)
    check_int("a cleared entry", vcont_at(c, 120), 0, fails)
    vcont_free(c)


def test_save_prepare(fails: int*) -> void:
    print("direct save form:")
    VContainer* c = small_direct()
    check_int("promoted", vcont_mode(c), vcont_direct_mode(), fails)
    check_int("14 bit direct", vcont_bits(c), 14, fails)
    check_int("no palette", vcont_palette_len(c), 0, fails)
    check_int("five distinct values", vcont_distinct_count(c), 5, fails)

    # A saved section always carries a palette, so the direct values have to be
    # re-collected before writing.
    check_int("prepare fits 3 bits", vcont_save_prepare(c, 3), 1, fails)
    check_int("indirect again", vcont_mode(c), vcont_indirect_mode(), fails)
    check_int("palette rebuilt", vcont_palette_len(c), 5, fails)
    check_int("width recorded", vcont_bits(c), 3, fails)
    check_int("entry 0", vcont_at(c, 0), 1, fails)
    check_int("entry 200", vcont_at(c, 200), 2, fails)
    check_int("entry 400", vcont_at(c, 400), 3, fails)
    check_int("entry 600", vcont_at(c, 600), 4, fails)
    check_int("empty entry", vcont_at(c, 100), 0, fails)

    VContainer* d = small_direct()
    check_int("two bits cannot index five values", vcont_save_prepare(d, 2), 0, fails)
    check_int("container untouched", vcont_mode(d), vcont_direct_mode(), fails)
    check_int("entry still readable", vcont_at(d, 400), 3, fails)
    vcont_free(c)
    vcont_free(d)


def test_biome_container(fails: int*) -> void:
    print("biome container:")
    VContainer* c = vcont_new(64, 3, 8, 14)
    vcont_set(c, 5, 2)
    check_int("min bits", vcont_bits(c), 3, fails)
    check_int("4 words for 64 entries", vcont_word_count(c), 4, fails)
    check_int("written biome", vcont_at(c, 5), 2, fails)
    check_int("neighbour biome", vcont_at(c, 6), 0, fails)
    int i = 0
    while i < 64:
        vcont_set(c, i, i * 3)
        i += 1
    # The 64 multiples of three plus the 2 written first make 65 distinct
    # values, which needs seven bits of index.
    check_int("65 values at 7 bits", vcont_bits(c), 7, fails)
    check_int("8 words", vcont_word_count(c), 8, fails)
    check_int("entry 5 overwritten by the sweep", vcont_at(c, 5), 15, fails)
    int bad = 0
    i = 0
    while i < 64:
        if vcont_at(c, i) != i * 3:
            bad = bad + 1
        i += 1
    check_int("round trip mismatches", bad, 0, fails)
    vcont_free(c)


def test_serialisation(fails: int*) -> void:
    print("save and reload:")
    VContainer* c = block_container()
    int* want = vt_calloc_int(4096)
    int i = 0
    while i < 40:
        vcont_set(c, i * 97, i + 1)
        vt_iset(want, i * 97, i + 1)
        i += 1
    vcont_compact(c)
    check_int("41 values at 6 bits", vcont_bits(c), 6, fails)
    check_int("palette", vcont_palette_len(c), 41, fails)
    check_int("words", vcont_word_count(c), 410, fails)

    VBuf* b = vbuf_new(1024)
    vbuf_put_u8(b, (uint64)vcont_bits(c))
    vbuf_put_i32_be(b, vcont_palette_len(c))
    vbuf_put_i32_be(b, vcont_word_count(c))
    int p = 0
    while p < vcont_palette_len(c):
        vbuf_put_i32_be(b, vcont_palette_at(c, p))
        p += 1
    int w = 0
    while w < vcont_word_count(c):
        vbuf_put_i64_be(b, (int64)vcont_save_word(c, w))
        w += 1

    VContainer* d = block_container()
    int bits = (int)vbuf_take_u8(b)
    int palette_len = vbuf_take_i32_be(b)
    int word_len = vbuf_take_i32_be(b)
    int q = 0
    while q < palette_len:
        vcont_palette_add(d, vbuf_take_i32_be(b))
        q += 1
    vcont_alloc(d, bits)
    int r = 0
    while r < word_len:
        vcont_set_word(d, r, (uint64)vbuf_take_i64_be(b))
        r += 1
    check_int("loaded width", vcont_bits(d), 6, fails)
    check_int("loaded palette", vcont_palette_len(d), 41, fails)
    check_int("loaded words", vcont_word_count(d), 410, fails)
    check_int("indirect mode", vcont_mode(d), vcont_indirect_mode(), fails)
    check_int("buffer drained", b.pos, b.len, fails)

    int bad = 0
    int k = 0
    while k < 4096:
        if vcont_at(d, k) != vt_iget(want, k):
            bad = bad + 1
        k += 1
    check_int("entry mismatches", bad, 0, fails)

    vt_free((void*)want)
    vbuf_free(b)
    vcont_free(c)
    vcont_free(d)


def test_save_iteration(fails: int*) -> void:
    print("save iteration:")
    VContainer* c = block_container()
    int i = 0
    while i < 3:
        vcont_set(c, i, i + 1)
        i += 1
    check_int("bits to record", vcont_save_bits_for(c), 4, fails)
    check_int("words to record", vcont_save_words_for(c, 4), 256, fails)
    int slots = 0
    int q = 0
    while q < 64:
        if vcont_has_palette(c, q) == 1:
            slots += 1
        q += 1
    check_int("palette walk", slots, 4, fails)
    int filled = 0
    int r = 0
    while r < 300:
        if vcont_has_save_word(c, r) == 1:
            filled += 1
        r += 1
    check_int("word walk stops at the end", filled, 256, fails)
    vcont_free(c)


def main() -> int:
    int fails = 0
    test_uniform(&fails)
    test_padded_words(&fails)
    test_width_growth(&fails)
    test_direct_promotion(&fails)
    test_compaction(&fails)
    test_compact_stays_direct(&fails)
    test_save_prepare(&fails)
    test_biome_container(&fails)
    test_serialisation(&fails)
    test_save_iteration(&fails)
    return report("vortex palette tests", fails)

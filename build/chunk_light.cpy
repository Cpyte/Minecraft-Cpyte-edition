# Vortex engine - generated bundle. Do not edit: this file is assembled from
# the modules listed below by tools/bundle.py.
#
#   native.cpy, core.cpy, strings.cpy, vbuf.cpy, nbt.cpy, palette.cpy, section.cpy, heightmap.cpy, world.cpy, protocol_chunk.cpy, protocol.cpy, harness.cpy, test_chunk_light.cpy

import stdlib
import "../src/network.c"


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


public def vstr_free(s: VStr*) -> void:
    if s == null:
        return
    if s.data != null:
        vt_free((void*)s.data)
        s.data = null
    s.len = 0
    s.cap = 0
    del s


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


# ===== protocol.cpy =====

public def decode_result(status: int64, value: int64, position: int64) -> int64[]:
    int64[] decoded = new int64[3]
    decoded[0] = status
    decoded[1] = value
    decoded[2] = position
    return decoded

public def encode_varint(value: int64) -> int64[]:
    int64[] encoded = new int64[0]
    int64 remaining = value & 0xFFFFFFFF
    while remaining > 127:
        append(encoded, remaining & 0x7F | 0x80)
        remaining = remaining >> 7
    append(encoded, remaining)
    return encoded

public def encode_wire_frame(body: int64[]) -> int64[]:
    int64[] frame = encode_varint(len(body))
    int64 index = 0
    while index < len(body):
        append(frame, body[index])
        index = index + 1
    return frame

public def make_packet_frame(body: int64[]) -> int64[]:
    int64 compression_threshold = mc_get_compression_threshold()
    if compression_threshold < 0:
        return encode_wire_frame(body)
    if compression_threshold >= 0:
        if len(body) >= compression_threshold:
            mc_codec_reset()
            int64 index = 0
            while index < len(body):
                if mc_codec_input_byte(body[index]) != 0:
                    return new int64[0]
                index = index + 1
            if mc_codec_run(0, 0) != 0:
                print("Could not compress outbound packet")
                return new int64[0]
            int64 compressed_length = mc_codec_output_length()
            int64[] data_length = encode_varint(len(body))
            int64[] frame = encode_varint(len(data_length) + compressed_length)
            index = 0
            while index < len(data_length):
                append(frame, data_length[index])
                index = index + 1
            index = 0
            while index < compressed_length:
                append(frame, mc_codec_output_byte(index))
                index = index + 1
            return frame
        else:
            int64[] frame = encode_varint(len(body) + 1)
            append(frame, 0)
            int64 index = 0
            while index < len(body):
                append(frame, body[index])
                index = index + 1
            return frame
    return new int64[0]

public def append_varint(target: int64[], value: int64) -> int64[]:
    int64 remaining = value & 0xFFFFFFFF
    while remaining > 127:
        append(target, remaining & 0x7F | 0x80)
        remaining = remaining >> 7
    append(target, remaining)
    return target

public def decode_varint(data: int64[], offset: int64) -> int64[]:
    int64 value = 0
    int64 position = offset
    int64 shift = 0
    if offset < 0:
        return decode_result(-3, 0, offset)
    while shift < 35:
        if position >= len(data):
            return decode_result(-1, 0, position)
        int64 current = data[position]
        if current < 0 or current > 255:
            return decode_result(-3, 0, position)
        if shift == 28 and current > 15:
            return decode_result(-2, 0, position)
        value = value | (current & 0x7F) << shift
        position = position + 1
        if (current & 0x80) == 0:
            if value >= 0x80000000:
                value = value - 0x100000000
            return decode_result(1, value, position)
        shift = shift + 7
    return decode_result(-2, 0, position)

public def encode_packet_frame(packet_id: int64, payload: int64[]) -> int64[]:
    int64[] packet = encode_varint(packet_id)
    int64 index = 0
    while index < len(payload):
        append(packet, payload[index])
        index = index + 1
    return make_packet_frame(packet)

public def decode_frame_header(data: int64[]) -> int64[]:
    int64 length = 0
    int64 index = 0
    while index < 3:
        if index >= len(data):
            return decode_result(-1, 0, index)
        int64 current = data[index]
        if current < 0 or current > 255:
            return decode_result(-3, 0, index)
        length = length | (current & 0x7F) << index * 7
        if (current & 0x80) == 0:
            if length == 0 or length > 2097151:
                return decode_result(-2, 0, index + 1)
            return decode_result(1, length, index + 1)
        index = index + 1
    return decode_result(-2, 0, index)

public def decode_frame(data: int64[]) -> int64[]:
    int64[] header = decode_frame_header(data)
    if header[0] != 1:
        return decode_result(header[0], header[1], header[2])
    int64 body_length = header[1]
    int64 header_length = header[2]
    int64 consumed = header_length + body_length
    if len(data) < consumed:
        return decode_result(-1, consumed, 0)
    int64[] decoded = new int64[3 + body_length]
    decoded[0] = 1
    decoded[1] = consumed
    decoded[2] = body_length
    int64 index = 0
    while index < body_length:
        decoded[3 + index] = data[header_length + index]
        index = index + 1
    return decoded

public def encode_handshake(protocol_version: int64, host: int64[], host_length: int64, port: int64, intent: int64) -> int64[]:
    int64[] body = encode_varint(0)
    body = append_varint(body, protocol_version)
    body = append_varint(body, host_length)
    int64 index = 0
    while index < host_length:
        append(body, host[index])
        index = index + 1
    append(body, port >> 8 & 0xFF)
    append(body, port & 0xFF)
    body = append_varint(body, intent)
    int64[] frame = encode_varint(len(body))
    index = 0
    while index < len(body):
        append(frame, body[index])
        index = index + 1
    return frame

public def encode_status_request() -> int64[]:
    int64[] empty = new int64[0]
    return encode_packet_frame(0, empty)

public def encode_ping_request(time: int64) -> int64[]:
    int64[] ping = new int64[8]
    int64 index = 0
    while index < 8:
        ping[index] = time >> (7 - index) * 8 & 0xFF
        index = index + 1
    return encode_packet_frame(1, ping)

public def send_bytes(socket_handle: int64, data: int64[]) -> int64:
    if len(data) == 0:
        return -1
    mc_tcp_send_begin(socket_handle)
    int64 index = 0
    while index < len(data):
        if mc_tcp_send_byte(data[index]) != 0:
            return -1
        index = index + 1
    return mc_tcp_send_end()

public def read_frame(socket_handle: int64) -> int64[]:
    int64[] prefix = new int64[0]
    int64[] header = decode_frame_header(prefix)
    while header[0] == -1:
        int64 byte = mc_tcp_recv_byte(socket_handle)
        if byte < 0:
            return decode_result(-4, 0, len(prefix))
        append(prefix, byte)
        header = decode_frame_header(prefix)
    if header[0] != 1:
        return decode_result(-2, 0, len(prefix))
    int64[] frame = new int64[header[1] + header[2]]
    int64 index = 0
    while index < header[2]:
        frame[index] = prefix[index]
        index = index + 1
    while index < len(frame):
        int64 byte = mc_tcp_recv_byte(socket_handle)
        if byte < 0:
            return decode_result(-4, 0, index)
        frame[index] = byte
        index = index + 1
    return decode_frame(frame)

public def packet_body_result(packet_body: int64[]) -> int64[]:
    int64[] decoded = new int64[len(packet_body) + 3]
    decoded[0] = 1
    decoded[1] = len(packet_body)
    decoded[2] = len(packet_body)
    int64 index = 0
    while index < len(packet_body):
        decoded[index + 3] = packet_body[index]
        index = index + 1
    return decoded

public def read_packet_frame(socket_handle: int64) -> int64[]:
    int64[] incoming = read_frame(socket_handle)
    int64 compression_threshold = mc_get_compression_threshold()
    if incoming[0] != 1 or compression_threshold < 0:
        return incoming
    int64[] wire_body = new int64[incoming[2]]
    int64 copy_index = 0
    while copy_index < incoming[2]:
        wire_body[copy_index] = incoming[copy_index + 3]
        copy_index = copy_index + 1
    int64[] data_length = decode_varint(wire_body, 0)
    if data_length[0] != 1 or data_length[1] < 0:
        return decode_result(-5, 0, 0)
    int64 data_start = data_length[2]
    if data_length[1] == 0:
        int64 packet_length = len(wire_body) - data_start
        if packet_length >= compression_threshold:
            return decode_result(-5, 0, 0)
        int64[] packet_body = new int64[packet_length]
        int64 index = 0
        while index < packet_length:
            packet_body[index] = wire_body[data_start + index]
            index = index + 1
        return packet_body_result(packet_body)
    else:
        if data_length[1] < compression_threshold or data_length[1] > 2097151:
            return decode_result(-5, 0, 0)
        mc_codec_reset()
        int64 index = data_start
        while index < len(wire_body):
            if mc_codec_input_byte(wire_body[index]) != 0:
                return decode_result(-5, 0, 0)
            index = index + 1
        if mc_codec_run(1, data_length[1]) != 0:
            return decode_result(-5, 0, 0)
        int64[] compressed_packet_body = new int64[data_length[1]]
        index = 0
        while index < data_length[1]:
            compressed_packet_body[index] = mc_codec_output_byte(index)
            index = index + 1
        return packet_body_result(compressed_packet_body)

public def parse_port(text: str) -> int64[]:
    int64 length = mc_string_length(text)
    if length < 0:
        return decode_result(-1, 0, 0)
    if length == 0:
        return decode_result(1, 25565, 0)
    if length > 5:
        return decode_result(-1, 0, 0)
    int64 port = 0
    int64 index = 0
    while index < length:
        int64 digit = mc_string_byte(text, index)
        if digit < 48 or digit > 57:
            return decode_result(-1, 0, index)
        port = port * 10 + (digit - 48)
        if port > 65535:
            return decode_result(-1, 0, index)
        index = index + 1
    if port < 1:
        return decode_result(-1, 0, index)
    return decode_result(1, port, index)

public def read_string_field(data: int64[], offset: int64, maximum: int64) -> int64[]:
    int64[] length = decode_varint(data, offset)
    if length[0] != 1 or (length[1] < 0 or length[1] > maximum):
        return decode_result(-1, 0, offset)
    if length[2] + length[1] > len(data):
        return decode_result(-1, 0, offset)
    return decode_result(1, length[1], length[2])

public def frame_body(frame: int64[]) -> int64[]:
    if frame[0] != 1 or frame[2] < 1:
        return new int64[0]
    int64[] body = new int64[frame[2]]
    int64 index = 0
    while index < frame[2]:
        body[index] = frame[index + 3]
        index = index + 1
    return body

public def read_login_response_body(socket_handle: int64, frame: int64[]) -> int64[]:
    int64[] body = frame_body(frame)
    int64[] packet_id = decode_varint(body, 0)
    if packet_id[0] != 1:
        print("Malformed login response packet id")
        return new int64[0]
    if packet_id[1] != 3:
        return body
    int64[] threshold = decode_varint(body, packet_id[2])
    if threshold[0] != 1 or (threshold[1] < 0 or (threshold[1] > 2097151 or threshold[2] != len(body))):
        print("Malformed login compression threshold")
        return new int64[0]
    if mc_set_compression_threshold(threshold[1]) != 0:
        print("Could not enable packet compression")
        return new int64[0]
    print(f"Login compression enabled at threshold {threshold[1]}")
    int64[] compressed_frame = read_packet_frame(socket_handle)
    if compressed_frame[0] != 1:
        print("Could not read the next login packet or decompress it")
        return new int64[0]
    int64[] compressed_body = frame_body(compressed_frame)
    return compressed_body

public def encode_config_client_information() -> int64[]:
    int64[] payload = new int64[14]
    payload[0] = 5
    payload[1] = 101
    payload[2] = 110
    payload[3] = 95
    payload[4] = 117
    payload[5] = 115
    payload[6] = 12
    payload[7] = 0
    payload[8] = 1
    payload[9] = 127
    payload[10] = 1
    payload[11] = 0
    payload[12] = 1
    payload[13] = 0
    return encode_packet_frame(0, payload)

public def decode_be_int32(data: int64[], offset: int64) -> int64:
    int64 value = data[offset] << 24 | (data[offset + 1] << 16 | (data[offset + 2] << 8 | data[offset + 3]))
    if value >= 0x80000000:
        value = value - 0x100000000
    return value

public def decode_be_int64(data: int64[], offset: int64) -> double:
    return mc_double_from_be(data[offset], data[offset + 1], data[offset + 2], data[offset + 3], data[offset + 4], data[offset + 5], data[offset + 6], data[offset + 7])

public def decode_be_float(data: int64[], offset: int64) -> double:
    return mc_float_from_be(data[offset], data[offset + 1], data[offset + 2], data[offset + 3])

public def encode_keepalive_response(packet_id: int64, body: int64[], offset: int64) -> int64[]:
    int64[] payload = new int64[8]
    int64 index = 0
    while index < 8:
        payload[index] = body[offset + index]
        index = index + 1
    return encode_packet_frame(packet_id, payload)

public def is_ignorable_configuration_packet(packet_id: int64) -> bool:
    if packet_id == 1:
        return true
    if packet_id == 6:
        return true
    if packet_id == 8:
        return true
    if packet_id == 10:
        return true
    if packet_id == 11:
        return true
    if packet_id == 13:
        return true
    if packet_id == 14:
        return true
    if packet_id == 16:
        return true
    if packet_id == 17:
        return true
    if packet_id == 18:
        return true
    return false

public def read_nbt_string(data: int64[], offset: int64) -> int64[]:
    if offset < 0 or offset + 2 > len(data):
        return decode_result(-1, 0, offset)
    int64 length = data[offset] << 8 | data[offset + 1]
    if length < 0 or offset + (2 + length) > len(data):
        return decode_result(-1, 0, offset)
    return decode_result(1, length, offset + 2)

public def nbt_string_equals(data: int64[], value: int64[], expected: str) -> bool:
    int64 expected_length = mc_string_length(expected)
    if value[0] != 1 or value[1] != expected_length:
        return false
    int64 index = 0
    while index < expected_length:
        if data[value[2] + index] != mc_string_byte(expected, index):
            return false
        index = index + 1
    return true

public def read_dialog_line() -> int64[]:
    int64 line_length = mc_stdin_read_line()
    if line_length < 0:
        return decode_result(line_length, 0, 0)
    int64[] line = new int64[line_length + 2]
    line[0] = 1
    line[1] = line_length
    int64 index = 0
    while index < line_length:
        line[index + 2] = mc_stdin_line_byte(index)
        index = index + 1
    return line

public def dialog_line_equals(line: int64[], expected: str) -> bool:
    int64 expected_length = mc_string_length(expected)
    if line[0] != 1 or line[1] != expected_length:
        return false
    int64 index = 0
    while index < expected_length:
        if line[index + 2] != mc_string_byte(expected, index):
            return false
        index = index + 1
    return true

public def parse_dialog_choice(line: int64[]) -> int64[]:
    if line[0] != 1 or (line[1] < 1 or line[1] > 3):
        return decode_result(-1, 0, 0)
    int64 value = 0
    int64 index = 0
    while index < line[1]:
        int64 digit = line[index + 2]
        if digit < 48 or digit > 57:
            return decode_result(-1, 0, index)
        value = value * 10 + (digit - 48)
        index = index + 1
    if value < 1 or value > 65535:
        return decode_result(-1, 0, index)
    return decode_result(1, value, index)

public def skip_nbt_payload(data: int64[], tag_type: int64, offset: int64, depth: int64) -> int64[]:
    if offset < 0 or depth > 64:
        return decode_result(-1, 0, offset)
    if tag_type == 0:
        return decode_result(1, 0, offset)
    if tag_type == 1:
        return decode_result(1, 0, offset + 1)
    if tag_type == 2:
        return decode_result(1, 0, offset + 2)
    if tag_type == 3 or tag_type == 5:
        return decode_result(1, 0, offset + 4)
    if tag_type == 4 or tag_type == 6:
        return decode_result(1, 0, offset + 8)
    if tag_type == 8:
        int64[] value = read_nbt_string(data, offset)
        if value[0] != 1:
            return value
        return decode_result(1, 0, value[2] + value[1])
    if tag_type == 7 or (tag_type == 11 or tag_type == 12):
        if offset + 4 > len(data):
            return decode_result(-1, 0, offset)
        int64 count = decode_be_int32(data, offset)
        int64 bytes_per_item = 1
        if tag_type == 11:
            bytes_per_item = 4
        if tag_type == 12:
            bytes_per_item = 8
        if count < 0 or (count > len(data) or offset + (4 + count * bytes_per_item) > len(data)):
            return decode_result(-1, 0, offset)
        return decode_result(1, 0, offset + (4 + count * bytes_per_item))
    if tag_type == 9:
        if offset + 5 > len(data):
            return decode_result(-1, 0, offset)
        int64 element_type = data[offset]
        int64 count = decode_be_int32(data, offset + 1)
        if count < 0 or count > len(data):
            return decode_result(-1, 0, offset)
        int64 position = offset + 5
        int64 index = 0
        while index < count:
            int64[] element = skip_nbt_payload(data, element_type, position, depth + 1)
            if element[0] != 1 or element[2] <= position:
                return decode_result(-1, 0, position)
            position = element[2]
            index = index + 1
        return decode_result(1, 0, position)
    if tag_type == 10:
        int64 position = offset
        while position < len(data):
            int64 child_type = data[position]
            position = position + 1
            if child_type == 0:
                return decode_result(1, 0, position)
            int64[] name = read_nbt_string(data, position)
            if name[0] != 1:
                return decode_result(-1, 0, position)
            position = name[2] + name[1]
            int64[] child = skip_nbt_payload(data, child_type, position, depth + 1)
            if child[0] != 1 or child[2] <= position:
                return decode_result(-1, 0, position)
            position = child[2]
        return decode_result(-1, 0, position)
    return decode_result(-1, 0, offset)

public def find_nbt_field(data: int64[], compound_offset: int64, field_name: str) -> int64[]:
    int64 position = compound_offset
    int64 name_length = mc_string_length(field_name)
    while position < len(data):
        int64 tag_type = data[position]
        position = position + 1
        if tag_type == 0:
            return decode_result(0, 0, position)
        int64[] name = read_nbt_string(data, position)
        if name[0] != 1:
            return decode_result(-1, 0, position)
        position = name[2] + name[1]
        bool matches = name[1] == name_length
        int64 index = 0
        while matches and index < name_length:
            if data[name[2] + index] != mc_string_byte(field_name, index):
                matches = false
            index = index + 1
        if matches:
            return decode_result(1, tag_type, position)
        int64[] child = skip_nbt_payload(data, tag_type, position, 0)
        if child[0] != 1 or child[2] <= position:
            return decode_result(-1, 0, position)
        position = child[2]
    return decode_result(-1, 0, position)

public def nbt_int_field(data: int64[], compound_offset: int64,
                         field_name: str) -> int64[]:
    int64[] field = find_nbt_field(data, compound_offset, field_name)
    if field[0] != 1 or field[1] != 3 or field[2] + 4 > len(data):
        return decode_result(-1, 0, compound_offset)
    return decode_result(1, decode_be_int32(data, field[2]), field[2] + 4)

public def parse_dimension_type_entry(data: int64[], nbt_offset: int64,
                                      registry: VDimensionRegistry*,
                                      entry_index: int64) -> int:
    if nbt_offset < 0 or nbt_offset >= len(data) or data[nbt_offset] != 10:
        return 0
    int64 root = nbt_offset + 1
    int64[] min_y = nbt_int_field(data, root, "min_y")
    int64[] height = nbt_int_field(data, root, "height")
    if min_y[0] != 1 or height[0] != 1:
        int64[] element = find_nbt_field(data, root, "element")
        if element[0] != 1 or element[1] != 10:
            return 0
        min_y = nbt_int_field(data, element[2], "min_y")
        height = nbt_int_field(data, element[2], "height")
    if min_y[0] != 1 or height[0] != 1:
        return 0
    return vdimension_registry_add_dimension(registry, (int)entry_index,
                                              (int)min_y[1], (int)height[1])

public def parse_configuration_registry(body: int64[], packet_offset: int64,
                                        registry: VDimensionRegistry*) -> int:
    int64[] key = read_string_field(body, packet_offset, 32767)
    if key[0] != 1:
        return 0
    int64[] entry_count = decode_varint(body, key[2] + key[1])
    if entry_count[0] != 1 or entry_count[1] < 0 or entry_count[1] > 65536:
        return 0
    bool dimensions = nbt_string_equals(body, key, "minecraft:dimension_type")
    bool biomes = nbt_string_equals(body, key, "minecraft:worldgen/biome")
    if (dimensions or biomes) and entry_count[1] < 1:
        return 0
    if dimensions and entry_count[1] > 256:
        return 0

    int64 position = entry_count[2]
    int64 index = 0
    while index < entry_count[1]:
        int64[] name = read_string_field(body, position, 32767)
        if name[0] != 1:
            return 0
        position = name[2] + name[1]
        if position >= len(body) or (body[position] != 0 and body[position] != 1):
            return 0
        int64 has_data = body[position]
        position += 1
        if has_data == 1:
            if position >= len(body) or body[position] != 10:
                return 0
            if dimensions and parse_dimension_type_entry(body, position, registry, index) == 0:
                return 0
            int64[] end = skip_nbt_payload(body, 10, position + 1, 0)
            if end[0] != 1 or end[2] <= position:
                return 0
            position = end[2]
        index += 1
    if position != len(body):
        return 0
    if dimensions and vdimension_registry_finish_dimensions(registry, (int)entry_count[1]) == 0:
        return 0
    if biomes and vdimension_registry_set_biome_count(registry, (int)entry_count[1]) == 0:
        return 0
    return 1

public def print_nbt_text_depth(data: int64[], tag_type: int64, offset: int64, depth: int64) -> int:
    if depth > 64:
        print("[component nesting limit]")
        return 0
    if tag_type == 8:
        int64[] value = read_nbt_string(data, offset)
        if value[0] != 1:
            return 1
        int64 index = value[2]
        while index < value[2] + value[1]:
            mc_write_byte(data[index])
            index = index + 1
        return 0
    if tag_type == 10:
        int64[] text_field = find_nbt_field(data, offset, "text")
        if text_field[0] == 1:
            if print_nbt_text_depth(data, text_field[1], text_field[2], depth + 1) != 0:
                return 1
        else:
            int64[] translate_field = find_nbt_field(data, offset, "translate")
            if translate_field[0] == 1:
                print("[translation: ")
                if print_nbt_text_depth(data, translate_field[1], translate_field[2], depth + 1) != 0:
                    return 1
                print("]")
            else:
                print("[component]")
        int64[] extra = find_nbt_field(data, offset, "extra")
        if extra[0] == 1 and (extra[1] == 9 and extra[2] + 5 <= len(data)):
            int64 element_type = data[extra[2]]
            int64 count = decode_be_int32(data, extra[2] + 1)
            if count < 0 or count > 256:
                print("[component extras omitted]")
                return 0
            int64 position = extra[2] + 5
            int64 index = 0
            while index < count:
                if print_nbt_text_depth(data, element_type, position, depth + 1) != 0:
                    return 1
                int64[] element_end = skip_nbt_payload(data, element_type, position, 0)
                if element_end[0] != 1:
                    return 1
                position = element_end[2]
                index = index + 1
        return 0
    print("[unsupported component]")
    return 0

public def print_nbt_text(data: int64[], tag_type: int64, offset: int64) -> int:
    return print_nbt_text_depth(data, tag_type, offset, 0)

public def append_nbt_string_field(data: int64[], position: int64, key: int64[], key_length: int64, value: str, value_length: int64) -> int64:
    data[position] = 8
    position = position + 1
    data[position] = key_length >> 8 & 0xFF
    data[position + 1] = key_length & 0xFF
    position = position + 2
    int64 index = 0
    while index < key_length:
        data[position + index] = key[index]
        index = index + 1
    position = position + key_length
    data[position] = value_length >> 8 & 0xFF
    data[position + 1] = value_length & 0xFF
    position = position + 2
    index = 0
    while index < value_length:
        data[position + index] = mc_string_byte(value, index)
        index = index + 1
    return position + value_length

public def append_nbt_string_bytes(data: int64[], position: int64, key: int64[], key_length: int64, value: int64[], value_offset: int64, value_length: int64) -> int64:
    data[position] = 8
    position = position + 1
    data[position] = key_length >> 8 & 0xFF
    data[position + 1] = key_length & 0xFF
    position = position + 2
    int64 index = 0
    while index < key_length:
        data[position + index] = key[index]
        index = index + 1
    position = position + key_length
    data[position] = value_length >> 8 & 0xFF
    data[position + 1] = value_length & 0xFF
    position = position + 2
    index = 0
    while index < value_length:
        data[position + index] = value[value_offset + index]
        index = index + 1
    return position + value_length

public def append_nbt_byte_field(data: int64[], position: int64, key: int64[], key_length: int64, value: int64) -> int64:
    data[position] = 1
    position = position + 1
    data[position] = key_length >> 8 & 0xFF
    data[position + 1] = key_length & 0xFF
    position = position + 2
    int64 index = 0
    while index < key_length:
        data[position + index] = key[index]
        index = index + 1
    data[position + key_length] = value & 0xFF
    return position + (key_length + 1)

public def append_nbt_float_field(data: int64[], position: int64, key: int64[], key_length: int64, value: double) -> int64:
    data[position] = 5
    position = position + 1
    data[position] = key_length >> 8 & 0xFF
    data[position + 1] = key_length & 0xFF
    position = position + 2
    int64 index = 0
    while index < key_length:
        data[position + index] = key[index]
        index = index + 1
    position = position + key_length
    index = 0
    while index < 4:
        data[position + index] = mc_float_be_byte(value, index)
        index = index + 1
    return position + 4

public def encode_dialog_click(packet_id: int64, action_id: int64[], action_id_length: int64, tag_payload: int64[], tag_payload_length: int64) -> int64[]:
    int64[] id_length = encode_varint(action_id_length)
    int64[] tag_length = encode_varint(tag_payload_length)
    int64[] payload = new int64[len(id_length) + (action_id_length + (len(tag_length) + tag_payload_length))]
    int64 index = 0
    while index < len(id_length):
        payload[index] = id_length[index]
        index = index + 1
    int64 position = len(id_length)
    index = 0
    while index < action_id_length:
        payload[position + index] = action_id[index]
        index = index + 1
    position = position + action_id_length
    index = 0
    while index < len(tag_length):
        payload[position + index] = tag_length[index]
        index = index + 1
    position = position + len(tag_length)
    index = 0
    while index < tag_payload_length:
        payload[position + index] = tag_payload[index]
        index = index + 1
    return encode_packet_frame(packet_id, payload)

public def print_dialog_body_entry(body: int64[], entry_offset: int64) -> int:
    int64[] body_type = find_nbt_field(body, entry_offset, "type")
    if body_type[0] != 1 or body_type[1] != 8:
        print("Dialog body entry has no supported type")
        return 1
    int64[] kind = read_nbt_string(body, body_type[2])
    if nbt_string_equals(body, kind, "minecraft:plain_message") or nbt_string_equals(body, kind, "plain_message"):
        int64[] contents = find_nbt_field(body, entry_offset, "contents")
        if contents[0] != 1:
            print("Dialog message has no contents")
            return 1
        if print_nbt_text(body, contents[1], contents[2]) != 0:
            print("Could not decode dialog message")
            return 1
        print("")
        return 0
    if nbt_string_equals(body, kind, "minecraft:item") or nbt_string_equals(body, kind, "item"):
        int64[] description = find_nbt_field(body, entry_offset, "description")
        if description[0] == 1:
            if print_nbt_text(body, description[1], description[2]) != 0:
                print("Could not decode dialog item description")
                return 1
        else:
            print("[item]")
        print("")
        return 0
    print("[unsupported dialog body element]")
    return 0

public def print_dialog_body(body: int64[], body_field: int64[]) -> int:
    if body_field[0] != 1:
        return 0
    if body_field[1] == 10:
        return print_dialog_body_entry(body, body_field[2])
    if body_field[1] != 9 or body_field[2] + 5 > len(body):
        print("Dialog body list is malformed")
        return 1
    int64 element_type = body[body_field[2]]
    int64 count = decode_be_int32(body, body_field[2] + 1)
    if count < 0 or count > 128:
        print("Dialog has too many body elements")
        return 1
    int64 position = body_field[2] + 5
    int64 index = 0
    while index < count:
        if element_type == 10:
            if print_dialog_body_entry(body, position) != 0:
                return 1
            int64[] element_end = skip_nbt_payload(body, element_type, position, 0)
            if element_end[0] != 1:
                print("Malformed dialog body element")
                return 1
            position = element_end[2]
        else:
            int64[] element_end = skip_nbt_payload(body, element_type, position, 0)
            if element_end[0] != 1:
                print("Malformed dialog body element")
                return 1
            print("[unsupported dialog body element]")
            position = element_end[2]
        index = index + 1
    return 0

public def handle_configuration_dialog(socket_handle: int64, body: int64[], packet_offset: int64, play_state: bool) -> int:
    int64 root_offset = packet_offset
    if play_state:
        int64[] holder_id = decode_varint(body, packet_offset)
        if holder_id[0] != 1:
            print("Malformed Play dialog holder")
            return 1
        if holder_id[1] != 0:
            print(f"Dialog references an unavailable registry entry {holder_id[1] - 1}")
            return 1
        root_offset = holder_id[2]
    if root_offset >= len(body) or body[root_offset] != 10:
        print("Malformed configuration dialog: expected a compound NBT root")
        return 1
    int64 root = root_offset + 1
    int64[] title = find_nbt_field(body, root, "title")
    print("Server dialog:")
    if title[0] == 1:
        print("Title: ")
        if print_nbt_text(body, title[1], title[2]) != 0:
            print("Could not decode dialog title")
            return 1
        print("")
    int64[] dialog_body = find_nbt_field(body, root, "body")
    if dialog_body[0] == 1:
        print("Message:")
        if print_dialog_body(body, dialog_body) != 0:
            return 1
    int64[] input_list = find_nbt_field(body, root, "inputs")
    int64[] input_values = new int64[65536]
    int64 value_position = 1
    if input_list[0] == 1:
        if input_list[1] != 9 or input_list[2] + 5 > len(body):
            print("Unsupported or malformed dialog input list")
            return 1
        int64 element_type = body[input_list[2]]
        int64 input_count = decode_be_int32(body, input_list[2] + 1)
        if element_type != 10 or (input_count < 0 or input_count > 32):
            print("Unsupported dialog inputs; expected at most 32 input controls")
            return 1
        int64 position = input_list[2] + 5
        int64 input_index = 0
        while input_index < input_count:
            int64[] key = find_nbt_field(body, position, "key")
            int64[] control_type = find_nbt_field(body, position, "type")
            int64[] label = find_nbt_field(body, position, "label")
            if key[0] != 1 or (key[1] != 8 or (control_type[0] != 1 or control_type[1] != 8)):
                print("Malformed or unsupported dialog input control")
                return 1
            int64[] key_value = read_nbt_string(body, key[2])
            int64[] kind_value = read_nbt_string(body, control_type[2])
            if key_value[0] != 1 or kind_value[0] != 1:
                print("Malformed dialog input name")
                return 1
            int64 key_bytes_length = key_value[1]
            int64[] key_bytes = new int64[key_bytes_length]
            int64 copy_index = 0
            while copy_index < key_bytes_length:
                key_bytes[copy_index] = body[key_value[2] + copy_index]
                copy_index = copy_index + 1
            print("Input ")
            if label[0] == 1 and print_nbt_text(body, label[1], label[2]) != 0:
                print("Could not decode dialog input label")
                return 1
            print(":")
            if nbt_string_equals(body, kind_value, "minecraft:text") or nbt_string_equals(body, kind_value, "text"):
                int64[] value = read_dialog_line()
                int64 value_length = value[1]
                if value[0] != 1 or (value_length > 4096 or value_position + (key_value[1] + (value_length + 5)) > 65535):
                    print("Dialog input is too long")
                    return 1
                value_position = append_nbt_string_bytes(input_values, value_position, key_bytes, key_bytes_length, value, 2, value_length)
                mc_stdin_line_done()
            elif nbt_string_equals(body, kind_value, "minecraft:boolean") or nbt_string_equals(body, kind_value, "boolean"):
                print("Enter true or false:")
                int64[] boolean_text = read_dialog_line()
                if boolean_text[0] != 1:
                    print("Could not read the boolean dialog input")
                    return 1
                int64 boolean_value = 0
                if dialog_line_equals(boolean_text, "true") or (dialog_line_equals(boolean_text, "yes") or dialog_line_equals(boolean_text, "1")):
                    boolean_value = 1
                elif not dialog_line_equals(boolean_text, "false") and (not dialog_line_equals(boolean_text, "no") and not dialog_line_equals(boolean_text, "0")):
                    print("Expected true/false, yes/no, or 1/0")
                    return 1
                value_position = append_nbt_byte_field(input_values, value_position, key_bytes, key_bytes_length, boolean_value)
                mc_stdin_line_done()
            elif nbt_string_equals(body, kind_value, "minecraft:single_option") or nbt_string_equals(body, kind_value, "single_option"):
                int64[] options = find_nbt_field(body, position, "options")
                if options[0] != 1 or (options[1] != 9 or options[2] + 5 > len(body)):
                    print("Dialog single-option input has no valid option list")
                    return 1
                int64 option_type = body[options[2]]
                int64 option_count = decode_be_int32(body, options[2] + 1)
                if option_count < 1 or (option_count > 128 or option_type != 8 and option_type != 10):
                    print("Dialog option list is unsupported or malformed")
                    return 1
                int64 option_position = options[2] + 5
                int64[] option_offsets = new int64[128]
                int64[] option_lengths = new int64[128]
                int64 option_index = 0
                while option_index < option_count:
                    int64 option_start = option_position
                    if option_type == 10:
                        int64[] option_id = find_nbt_field(body, option_position, "id")
                        if option_id[0] != 1 or option_id[1] != 8:
                            print("Dialog option entry has no string id")
                            return 1
                        int64[] option_string = read_nbt_string(body, option_id[2])
                        option_offsets[option_index] = option_string[2]
                        option_lengths[option_index] = option_string[1]
                    else:
                        int64[] option_string = read_nbt_string(body, option_position)
                        if option_string[0] != 1:
                            print("Malformed dialog option")
                            return 1
                        option_offsets[option_index] = option_string[2]
                        option_lengths[option_index] = option_string[1]
                    print(option_index + 1)
                    print(": ")
                    int64 display_offset = option_offsets[option_index]
                    int64 display_length = option_lengths[option_index]
                    if option_type == 10:
                        int64[] option_label = find_nbt_field(body, option_start, "display")
                        if option_label[0] == 1:
                            if print_nbt_text(body, option_label[1], option_label[2]) != 0:
                                print("Could not decode dialog option label")
                                return 1
                        else:
                            int64 display_index = 0
                            while display_index < display_length:
                                mc_write_byte(body[display_offset + display_index])
                                display_index = display_index + 1
                    else:
                        int64 display_index = 0
                        while display_index < display_length:
                            mc_write_byte(body[display_offset + display_index])
                            display_index = display_index + 1
                    print("")
                    if option_type == 10:
                        int64[] option_end = skip_nbt_payload(body, 10, option_start, 0)
                        if option_end[0] != 1:
                            print("Malformed dialog option entry")
                            return 1
                        option_position = option_end[2]
                    else:
                        option_position = option_offsets[option_index] + option_lengths[option_index]
                    option_index = option_index + 1
                print("Select an option by number:")
                int64[] option_choice_text = read_dialog_line()
                int64[] option_choice = parse_dialog_choice(option_choice_text)
                if option_choice[0] != 1 or option_choice[1] > option_count:
                    print("Invalid dialog option selection")
                    return 1
                mc_stdin_line_done()
                int64 selected = option_choice[1] - 1
                value_position = append_nbt_string_bytes(input_values, value_position, key_bytes, key_bytes_length, body, option_offsets[selected], option_lengths[selected])
            elif nbt_string_equals(body, kind_value, "minecraft:number_range") or nbt_string_equals(body, kind_value, "number_range"):
                int64[] range_start = find_nbt_field(body, position, "start")
                int64[] range_end = find_nbt_field(body, position, "end")
                if range_start[0] != 1 or (range_end[0] != 1 or (range_start[1] != 5 or (range_end[1] != 5 or (range_start[2] + 4 > len(body) or range_end[2] + 4 > len(body))))):
                    print("Dialog number range is malformed or unsupported")
                    return 1
                double minimum = decode_be_float(body, range_start[2])
                double maximum = decode_be_float(body, range_end[2])
                double midpoint = (minimum + maximum) / 2.0
                print(f"Enter a number from {minimum} to {maximum} (default {midpoint}):")
                int64[] number_text = read_dialog_line()
                if number_text[0] != 1:
                    print("Could not read the number-range dialog input")
                    return 1
                double numeric_value = midpoint
                if number_text[1] > 0:
                    numeric_value = mc_parse_finite_stdin_line()
                mc_stdin_line_done()
                if mc_is_finite_double(numeric_value) == 0 or (numeric_value < minimum or numeric_value > maximum):
                    print("Number is invalid or outside the dialog\'s allowed range")
                    return 1
                value_position = append_nbt_float_field(input_values, value_position, key_bytes, key_bytes_length, numeric_value)
            else:
                print("Unsupported dialog input control type")
                return 1
            int64[] input_end = skip_nbt_payload(body, 10, position, 0)
            if input_end[0] != 1:
                print("Malformed dialog input entry")
                return 1
            position = input_end[2]
            input_index = input_index + 1
    input_values[0] = 10
    input_values[value_position] = 0
    int64 values_length = value_position + 1
    int64[] actions = find_nbt_field(body, root, "actions")
    int64[] action_offsets = new int64[64]
    int64 action_count = 0
    int64 action_position = 0
    int64[] dialog_type_field = find_nbt_field(body, root, "type")
    int64[] dialog_type = read_nbt_string(body, dialog_type_field[2])
    if actions[0] == 1:
        if actions[1] != 9 or (actions[2] + 5 > len(body) or body[actions[2]] != 10):
            print("Unsupported or malformed dialog action list")
            return 1
        action_count = decode_be_int32(body, actions[2] + 1)
        if action_count < 0 or action_count > 64:
            print("Dialog has too many actions")
            return 1
        action_position = actions[2] + 5
    elif nbt_string_equals(body, dialog_type, "minecraft:confirmation") or nbt_string_equals(body, dialog_type, "confirmation"):
        int64[] yes_action = find_nbt_field(body, root, "yes")
        int64[] no_action = find_nbt_field(body, root, "no")
        if yes_action[0] == 1 and (yes_action[1] == 10 and (no_action[0] == 1 and no_action[1] == 10)):
            action_count = 2
            action_offsets[0] = yes_action[2]
            action_offsets[1] = no_action[2]
    else:
        int64[] single_action = find_nbt_field(body, root, "action")
        if single_action[0] != 1 or single_action[1] != 10:
            single_action = find_nbt_field(body, root, "exit_action")
        if single_action[0] == 1 and single_action[1] == 10:
            action_count = 1
            action_offsets[0] = single_action[2]
    if action_count == 0:
        if nbt_string_equals(body, dialog_type, "minecraft:notice") or nbt_string_equals(body, dialog_type, "notice"):
            print("Notice dialog has no server action; acknowledged locally")
            return 0
        print("This dialog has no selectable actions")
        return 1
    int64 action_index = 0
    while action_index < action_count:
        if actions[0] == 1:
            action_offsets[action_index] = action_position
        int64[] label = find_nbt_field(body, action_offsets[action_index], "label")
        print(action_index + 1)
        print(": ")
        if label[0] == 1 and print_nbt_text(body, label[1], label[2]) != 0:
            print("Could not decode dialog action label")
            return 1
        print("")
        if actions[0] == 1:
            int64[] action_end = skip_nbt_payload(body, 10, action_position, 0)
            if action_end[0] != 1:
                print(f"Malformed dialog action entry at {action_position}, status {action_end[0]}, offset {action_end[2]}")
                return 1
            action_position = action_end[2]
        action_index = action_index + 1
    print("Choose a dialog action by number:")
    int64[] choice_text = read_dialog_line()
    int64[] choice = parse_dialog_choice(choice_text)
    mc_stdin_line_done()
    if choice[0] != 1 or choice[1] > action_count:
        print(f"Invalid dialog action selection: status {choice[0]}, value {choice[1]}, actions {action_count}")
        return 1
    int64[] action = find_nbt_field(body, action_offsets[choice[1] - 1], "action")
    if action[0] == 0:
        print("Selected dialog action has no server-side action")
        return 0
    if action[0] != 1 or action[1] != 10:
        print("Selected dialog action has a malformed response")
        return 1
    int64[] action_type = find_nbt_field(body, action[2], "type")
    int64[] action_id = find_nbt_field(body, action[2], "id")
    if action_type[0] != 1 or (action_type[1] != 8 or (action_id[0] != 1 or action_id[1] != 8)):
        print("Selected dialog action has no supported custom-action id")
        return 1
    int64[] type_value = read_nbt_string(body, action_type[2])
    int64[] id_value = read_nbt_string(body, action_id[2])
    if type_value[0] != 1 or id_value[0] != 1:
        print("Malformed custom dialog action")
        return 1
    if not nbt_string_equals(body, type_value, "minecraft:dynamic/custom") and (not nbt_string_equals(body, type_value, "dynamic/custom") and (not nbt_string_equals(body, type_value, "minecraft:custom") and not nbt_string_equals(body, type_value, "custom"))):
        print("Selected dialog action type cannot be sent during Configuration; only custom click actions are supported")
        return 1
    int64 id_length = id_value[1]
    int64[] encoded_id = new int64[id_length]
    int64 index = 0
    while index < id_length:
        encoded_id[index] = body[id_value[2] + index]
        index = index + 1
    int64[] click_payload = new int64[65536]
    int64 click_payload_length = values_length
    index = 0
    while index < values_length:
        click_payload[index] = input_values[index]
        index = index + 1
    if nbt_string_equals(body, type_value, "minecraft:dynamic/custom") or nbt_string_equals(body, type_value, "dynamic/custom"):
        int64[] additions = find_nbt_field(body, action[2], "additions")
        int64 additions_fields_length = 0
        if additions[0] == 1 and additions[1] == 10:
            int64[] additions_end = skip_nbt_payload(body, 10, additions[2], 0)
            if additions_end[0] != 1:
                print("Malformed custom dialog action additions")
                return 1
            additions_fields_length = additions_end[2] - (additions[2] + 1)
        int64 input_fields_length = value_position - 1
        if additions_fields_length + (input_fields_length + 2) > 65536:
            print("Custom dialog response exceeds the protocol payload limit")
            return 1
        click_payload_length = additions_fields_length + (input_fields_length + 2)
        click_payload[0] = 10
        int64 payload_position = 1
        if additions[0] == 1 and additions[1] == 10:
            index = additions[2]
            while index < additions[2] + additions_fields_length:
                click_payload[payload_position] = body[index]
                payload_position = payload_position + 1
                index = index + 1
        index = 1
        while index < value_position:
            click_payload[payload_position] = input_values[index]
            payload_position = payload_position + 1
            index = index + 1
        click_payload[payload_position] = 0
    elif nbt_string_equals(body, type_value, "minecraft:custom") or nbt_string_equals(body, type_value, "custom"):
        int64[] custom_payload = find_nbt_field(body, action[2], "payload")
        if custom_payload[0] == 1:
            if custom_payload[1] == 0:
                click_payload[0] = 0
                click_payload_length = 1
            else:
                int64[] payload_end = skip_nbt_payload(body, custom_payload[1], custom_payload[2], 0)
                if payload_end[0] != 1:
                    print("Malformed custom dialog action payload")
                    return 1
                click_payload_length = payload_end[2] - (custom_payload[2] - 1)
                click_payload[0] = custom_payload[1]
                index = 1
                while index < click_payload_length:
                    click_payload[index] = body[custom_payload[2] + (index - 1)]
                    index = index + 1
        else:
            click_payload[0] = 0
            click_payload_length = 1
    int64 click_packet_id = 8
    if play_state:
        click_packet_id = 68
    int64[] click = encode_dialog_click(click_packet_id, encoded_id, id_length, click_payload, click_payload_length)
    if send_bytes(socket_handle, click) != 0:
        print("Failed to send custom dialog action")
        return 1
    print("Custom dialog response sent")
    return 0

public def encode_chat_message(message: int64[], message_length: int64, timestamp: int64) -> int64[]:
    int64[] encoded_length = encode_varint(message_length)
    int64 payload_length = len(encoded_length) + (message_length + 22)
    int64[] payload = new int64[payload_length]
    int64 index = 0
    while index < len(encoded_length):
        payload[index] = encoded_length[index]
        index = index + 1
    int64 position = len(encoded_length)
    index = 0
    while index < message_length:
        payload[position + index] = message[index]
        index = index + 1
    position = position + message_length
    index = 0
    while index < 8:
        payload[position + index] = timestamp >> (7 - index) * 8 & 0xFF
        payload[position + (8 + index)] = 0
        index = index + 1
    position = position + 16
    payload[position] = 0
    payload[position + 1] = 0
    payload[position + 2] = 0
    payload[position + 3] = 0
    payload[position + 4] = 0
    payload[position + 5] = 0
    return encode_packet_frame(9, payload)

public def encode_chat_command(command: int64[], command_length: int64) -> int64[]:
    int64[] encoded_length = encode_varint(command_length)
    int64[] payload = new int64[len(encoded_length) + command_length]
    int64 index = 0
    while index < len(encoded_length):
        payload[index] = encoded_length[index]
        index = index + 1
    index = 0
    while index < command_length:
        payload[len(encoded_length) + index] = command[index + 1]
        index = index + 1
    return encode_packet_frame(7, payload)

public def print_system_chat(body: int64[], offset: int64) -> int:
    if offset >= len(body):
        print("Received an empty system chat packet")
        return 1
    int64 tag_type = body[offset]
    if tag_type == 8:
        int64[] text = read_nbt_string(body, offset + 1)
        if text[0] != 1:
            print("Received a malformed system chat component")
            return 1
        print("Server:")
        int64 index = text[2]
        while index < text[2] + text[1]:
            mc_write_byte(body[index])
            index = index + 1
        print("")
        return 0
    if tag_type == 10:
        int64 position = offset + 1
        while position < len(body):
            int64 field_type = body[position]
            position = position + 1
            if field_type == 0:
                break
            int64[] name = read_nbt_string(body, position)
            if name[0] != 1:
                print("Received a malformed system chat component")
                return 1
            position = name[2] + name[1]
            if field_type != 8:
                print("Received a structured system chat component that cannot be rendered")
                return 0
            int64[] value = read_nbt_string(body, position)
            if value[0] != 1:
                print("Received a malformed system chat component")
                return 1
            if name[1] == 4 and (body[name[2]] == 116 and (body[name[2] + 1] == 101 and (body[name[2] + 2] == 120 and body[name[2] + 3] == 116))):
                print("Server:")
                int64 index = value[2]
                while index < value[2] + value[1]:
                    mc_write_byte(body[index])
                    index = index + 1
                print("")
                return 0
            if name[1] == 9 and (body[name[2]] == 116 and (body[name[2] + 1] == 114 and (body[name[2] + 2] == 97 and (body[name[2] + 3] == 110 and (body[name[2] + 4] == 115 and (body[name[2] + 5] == 108 and (body[name[2] + 6] == 97 and (body[name[2] + 7] == 116 and body[name[2] + 8] == 101)))))))):
                print("Server (untranslated):")
                int64 index = value[2]
                while index < value[2] + value[1]:
                    mc_write_byte(body[index])
                    index = index + 1
                print("")
                return 0
            position = value[2] + value[1]
        print("Received a system chat component without a plain-text field")
        return 0
    print("Received a system chat component in an unsupported format")
    return 0

def chunk_light_mask_has_bit(data: int64[], words_offset: int64,
                             word_count: int64, bit: int64) -> bool:
    if bit < 0 or bit / 64 >= word_count:
        return false
    int64 byte_offset = words_offset + (bit / 64) * 8 + 7 - (bit % 64) / 8
    int64 bit_in_byte = bit % 8
    return (data[byte_offset] & (1 << bit_in_byte)) != 0


def chunk_read_light_mask(data: int64[], offset: int64,
                          bit_limit: int64) -> int64[]:
    int64[] mask = new int64[4]
    int64[] count = decode_varint(data, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > (bit_limit + 63) / 64:
        return mask
    if count[2] + count[1] * 8 > len(data):
        return mask
    int64 bit = bit_limit
    while bit < count[1] * 64:
        if chunk_light_mask_has_bit(data, count[2], count[1], bit):
            return mask
        bit += 1
    mask[0] = 1
    mask[1] = count[2]
    mask[2] = count[1]
    mask[3] = count[2] + count[1] * 8
    return mask


def chunk_mask_bit_count(data: int64[], words_offset: int64,
                         word_count: int64, bit_limit: int64) -> int64:
    int64 total = 0
    int64 bit = 0
    while bit < bit_limit:
        if chunk_light_mask_has_bit(data, words_offset, word_count, bit):
            total += 1
        bit += 1
    return total


def chunk_masks_overlap(data: int64[], first_offset: int64,
                        first_words: int64, second_offset: int64,
                        second_words: int64, bit_limit: int64) -> bool:
    int64 bit = 0
    while bit < bit_limit:
        if chunk_light_mask_has_bit(data, first_offset, first_words, bit) and chunk_light_mask_has_bit(data, second_offset, second_words, bit):
            return true
        bit += 1
    return false


def chunk_skip_block_entities(data: int64[], offset: int64) -> int64[]:
    int64[] result = decode_result(-1, 0, offset)
    int64[] count = decode_varint(data, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > 4096:
        return result
    int64 position = count[2]
    int64 index = 0
    while index < count[1]:
        if position + 3 > len(data) or data[position] < 0 or data[position] > 255:
            return result
        position += 3
        int64[] entity_type = decode_varint(data, position)
        if entity_type[0] != 1 or entity_type[1] < 0:
            return result
        position = entity_type[2]
        if position >= len(data) or data[position] != 10:
            return result
        int64[] nbt_end = skip_nbt_payload(data, 10, position + 1, 0)
        if nbt_end[0] != 1 or nbt_end[2] <= position:
            return result
        position = nbt_end[2]
        index += 1
    return decode_result(1, count[1], position)


def chunk_read_light_arrays(data: int64[], offset: int64,
                            mask_offset: int64, mask_words: int64,
                            bit_limit: int64, sections: char*,
                            sky_light: bool) -> int64[]:
    int64[] failure = decode_result(-1, 0, offset)
    int64[] count = decode_varint(data, offset)
    if count[0] != 1 or count[1] != chunk_mask_bit_count(
        data, mask_offset, mask_words, bit_limit):
        return failure
    int64 position = count[2]
    int64 bit = 0
    while bit < bit_limit:
        if chunk_light_mask_has_bit(data, mask_offset, mask_words, bit):
            int64[] length = decode_varint(data, position)
            if length[0] != 1 or length[1] != 2048 or length[2] + 2048 > len(data):
                return failure
            if bit > 0 and bit < bit_limit - 1:
                VSection* section = (VSection*)vt_ptr_get(sections, (int)(bit - 1))
                char* target = section.block_light
                if sky_light:
                    target = section.sky_light
                int64 byte = 0
                while byte < 2048:
                    if data[length[2] + byte] < 0 or data[length[2] + byte] > 255:
                        return failure
                    vt_put(target, (int)(byte), (int)data[length[2] + byte])
                    byte += 1
            position = length[2] + 2048
        bit += 1
    return decode_result(1, count[1], position)


def chunk_decode_light_and_entities(world: VWorld*, body: int64[],
                                    offset: int64, sections: char*) -> int:
    int64[] entities = chunk_skip_block_entities(body, offset)
    if entities[0] != 1:
        print("Malformed chunk block-entity data")
        return 1
    int64 bit_limit = world.section_count + 2
    int64 position = entities[2]
    int64[] sky_mask = chunk_read_light_mask(body, position, bit_limit)
    if sky_mask[0] != 1:
        print("Malformed chunk sky-light mask")
        return 1
    position = sky_mask[3]
    int64[] block_mask = chunk_read_light_mask(body, position, bit_limit)
    if block_mask[0] != 1:
        print("Malformed chunk block-light mask")
        return 1
    position = block_mask[3]
    int64[] empty_sky_mask = chunk_read_light_mask(body, position, bit_limit)
    if empty_sky_mask[0] != 1:
        print("Malformed chunk empty-sky-light mask")
        return 1
    position = empty_sky_mask[3]
    int64[] empty_block_mask = chunk_read_light_mask(body, position, bit_limit)
    if empty_block_mask[0] != 1:
        print("Malformed chunk empty-block-light mask")
        return 1
    position = empty_block_mask[3]
    if chunk_masks_overlap(body, sky_mask[1], sky_mask[2],
                           empty_sky_mask[1], empty_sky_mask[2], bit_limit):
        print("Chunk sky-light masks overlap")
        return 1
    if chunk_masks_overlap(body, block_mask[1], block_mask[2],
                           empty_block_mask[1], empty_block_mask[2], bit_limit):
        print("Chunk block-light masks overlap")
        return 1
    int64[] sky_arrays = chunk_read_light_arrays(
        body, position, sky_mask[1], sky_mask[2], bit_limit, sections, true)
    if sky_arrays[0] != 1:
        print("Malformed chunk sky-light arrays")
        return 1
    position = sky_arrays[2]
    int64[] block_arrays = chunk_read_light_arrays(
        body, position, block_mask[1], block_mask[2], bit_limit, sections, false)
    if block_arrays[0] != 1 or block_arrays[2] != len(body):
        print("Malformed chunk block-light arrays or trailing data")
        return 1
    return 0


# Chunk heightmaps: a varint count of entries, each one a varint heightmap
# type id followed by a varint-counted big endian long array of 256 nine-bit
# absolute heights. Types the engine does not store are still walked, so a
# server that sends ocean floor data does not break the chunk, but a known
# type with the wrong number of longs is rejected rather than misread.
def chunk_heightmap_kind(type_id: int64) -> int:
    if type_id == hm_wire_motion_blocking():
        return hm_motion_blocking()
    if type_id == hm_wire_world_surface():
        return hm_world_surface()
    return -1


public def chunk_read_heightmaps(data: int64[], offset: int64,
                                 values: int*) -> int64[]:
    if values == null or offset < 0:
        return decode_result(-1, 0, offset)
    int64[] count = decode_varint(data, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > hm_wire_kind_count():
        return decode_result(-1, 0, offset)
    int64 position = count[2]
    int64 index = 0
    while index < count[1]:
        int64[] type_id = decode_varint(data, position)
        if type_id[0] != 1 or type_id[1] < 0:
            return decode_result(-1, index, position)
        position = type_id[2]
        int64[] longs = decode_varint(data, position)
        int64 packed_bytes = hm_long_count() * 8
        if longs[0] != 1 or longs[1] != hm_long_count() or longs[2] + packed_bytes > len(data):
            return decode_result(-1, index, position)
        position = longs[2]
        int64[] words = new int64[hm_long_count()]
        int64 word_index = 0
        while word_index < hm_long_count():
            int64 word = 0
            int64 byte_index = 0
            while byte_index < 8:
                word = word << 8 | data[position + word_index * 8 + byte_index]
                byte_index = byte_index + 1
            words[word_index] = word
            word_index = word_index + 1
        position = position + packed_bytes
        int kind = chunk_heightmap_kind(type_id[1])
        if kind >= 0 and hm_unpack(words, kind, values) == 0:
            return decode_result(-1, index, position)
        index = index + 1
    return decode_result(1, index, position)


public def decode_chunk_sections(world: VWorld*, body: int64[],
                                 packet_offset: int64) -> int:
    if world == null or packet_offset < 0 or packet_offset + 8 > len(body):
        return 1
    int64 chunk_x = decode_be_int32(body, packet_offset)
    int64 chunk_z = decode_be_int32(body, packet_offset + 4)
    int64 heightmaps_offset = packet_offset + 8
    int* heights = hm_new()
    int64[] heightmaps = chunk_read_heightmaps(body, heightmaps_offset, heights)
    if heightmaps[0] != 1:
        print("Malformed chunk heightmaps")
        hm_free(heights)
        return 1
    int64[] data_length = decode_varint(body, heightmaps[2])
    if data_length[0] != 1 or data_length[1] < 0 or data_length[2] + data_length[1] > len(body):
        print("Malformed chunk section-data length")
        hm_free(heights)
        return 1
    VBuf* section_data = vbuf_new((int)data_length[1])
    int64 index = 0
    while index < data_length[1]:
        vbuf_put_u8(section_data, (uint64)body[data_length[2] + index])
        index += 1
    section_data.pos = 0
    int sections_ok = 0
    char* sections = sec_read_wire_sections(
        section_data, world.section_count, world.min_section,
        world.block_global_bits, world.biome_global_bits, &sections_ok)
    vbuf_free(section_data)
    if sections_ok == 0 or sections == null:
        print("Malformed or unsupported chunk section palettes")
        hm_free(heights)
        return 1
    int64 tail_offset = data_length[2] + data_length[1]
    if chunk_decode_light_and_entities(world, body, tail_offset, sections) != 0:
        vworld_free_column(sections, world.section_count)
        hm_free(heights)
        return 1
    if vworld_replace_sections(world, (int)chunk_x, (int)chunk_z, sections) == 0:
        vworld_free_column(sections, world.section_count)
        hm_free(heights)
        print("Loaded chunk capacity reached")
        return 1
    if vworld_set_heightmaps(world, (int)chunk_x, (int)chunk_z, heights) == 0:
        hm_free(heights)
    print(f"Decoded chunk ({chunk_x}, {chunk_z}) into {world.section_count} sections with lighting")
    return 0


public def read_play_login_dimension(body: int64[],
                                     packet_offset: int64) -> int64[]:
    if packet_offset < 0 or packet_offset + 5 > len(body):
        return decode_result(-1, 0, packet_offset)
    int64 position = packet_offset + 4
    position += 1
    int64[] dimension_count = decode_varint(body, position)
    if dimension_count[0] != 1 or dimension_count[1] < 1 or dimension_count[1] > 1024:
        return decode_result(-1, 0, position)
    position = dimension_count[2]
    int64 index = 0
    while index < dimension_count[1]:
        int64[] name = read_string_field(body, position, 32767)
        if name[0] != 1:
            return decode_result(-1, 0, position)
        position = name[2] + name[1]
        index += 1
    index = 0
    while index < 3:
        int64[] value = decode_varint(body, position)
        if value[0] != 1 or value[1] < 0:
            return decode_result(-1, 0, position)
        position = value[2]
        index += 1
    if position + 3 > len(body):
        return decode_result(-1, 0, position)
    position += 3
    int64[] dimension_type = decode_varint(body, position)
    if dimension_type[0] != 1 or dimension_type[1] < 0:
        return decode_result(-1, 0, position)
    return dimension_type


public def play_session_loop(socket_handle: int64, world: VWorld*,
                             registry: VDimensionRegistry*) -> int:
    int64[] tracked_chunks_x = new int64[8192]
    int64[] tracked_chunks_z = new int64[8192]
    int64 tracked_chunk_count = 0
    int64[] tracked_entity_ids = new int64[8192]
    int64 tracked_entity_count = 0
    int64 packet_count = 0
    bool received_play_login = false
    while packet_count < 1000000:
        int64 events = mc_poll_events(socket_handle)
        if events < 0:
            print("Could not poll Play socket and terminal input")
            return 1
        if events & 2 and received_play_login:
            int64 line_length = mc_stdin_line_length()
            if line_length < 0:
                print("Could not read terminal input")
                return 1
            if line_length == 5 and (mc_stdin_line_byte(0) == 47 and (mc_stdin_line_byte(1) == 113 and (mc_stdin_line_byte(2) == 117 and (mc_stdin_line_byte(3) == 105 and mc_stdin_line_byte(4) == 116)))):
                mc_stdin_line_done()
                print("Leaving Play session")
                return 0
            if line_length > 256:
                print("Chat and command input is limited to 256 UTF-8 bytes")
            elif line_length > 0 and mc_stdin_line_byte(0) == 47:
                if line_length == 1:
                    print("Command cannot be empty")
                else:
                    int64[] command_line = new int64[line_length]
                    int64 index = 0
                    while index < line_length:
                        command_line[index] = mc_stdin_line_byte(index)
                        index = index + 1
                    int64[] command_packet = encode_chat_command(command_line, line_length - 1)
                    if send_bytes(socket_handle, command_packet) != 0:
                        print("Failed to send chat command")
                        return 1
                    print("Command sent")
            elif line_length > 0:
                int64[] chat_line = new int64[line_length]
                int64 index = 0
                while index < line_length:
                    chat_line[index] = mc_stdin_line_byte(index)
                    index = index + 1
                int64 timestamp = mc_time_millis()
                if timestamp < 0:
                    print("Could not read system clock for chat message")
                    return 1
                int64[] chat_packet = encode_chat_message(chat_line, line_length, timestamp)
                if send_bytes(socket_handle, chat_packet) != 0:
                    print("Failed to send chat message")
                    return 1
                print("Chat message sent without a secure-chat signature")
            mc_stdin_line_done()
        if (events & 1) == 0:
            continue
        int64[] incoming = read_packet_frame(socket_handle)
        if incoming[0] != 1:
            if incoming[0] == -5:
                print("Malformed or invalid compressed Play packet")
            else:
                print("Play connection ended or packet framing failed")
            return 1
        int64[] body = frame_body(incoming)
        int64[] packet_id = decode_varint(body, 0)
        if packet_id[0] != 1:
            print("Malformed Play packet id")
            return 1
        if packet_id[1] == 50:
            int64[] dimension_type = read_play_login_dimension(body, packet_id[2])
            if dimension_type[0] != 1:
                print("Malformed Play login dimension metadata")
                return 1
            int64[] dimension = vdimension_registry_dimension(registry, (int)dimension_type[1])
            if registry.dimension_registry_seen == 0 or registry.biome_registry_seen == 0 or dimension[0] == 0:
                print("Configuration did not provide the active dimension and biome registries")
                return 1
            if vworld_set_dimension(world, dimension[1], dimension[2],
                                    registry.block_global_bits,
                                    registry.biome_global_bits) == 0:
                print("Could not configure world for the server dimension")
                return 1
            print(f"Configured dimension sections: min={world.min_section}, count={world.section_count}, block bits={world.block_global_bits}, biome bits={world.biome_global_bits}")
            received_play_login = true
            int64[] player_loaded = new int64[0]
            int64[] response = encode_packet_frame(44, player_loaded)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to acknowledge Play login")
                return 1
            print("Play login accepted; type chat, /command, or /quit")
        elif packet_id[1] == 45:
            if len(body) != packet_id[2] + 8:
                print("Malformed Play keep-alive")
                return 1
            int64[] response = encode_keepalive_response(28, body, packet_id[2])
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to Play keep-alive")
                return 1
        elif packet_id[1] == 62:
            if len(body) != packet_id[2] + 4:
                print("Malformed Play ping")
                return 1
            int64[] pong = new int64[4]
            int64 index = 0
            while index < 4:
                pong[index] = body[packet_id[2] + index]
                index = index + 1
            int64[] response = encode_packet_frame(45, pong)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to answer Play ping")
                return 1
        elif packet_id[1] == 73:
            int64[] teleport_id = decode_varint(body, packet_id[2])
            int64 position_start = teleport_id[2]
            if teleport_id[0] != 1 or position_start + 60 != len(body):
                print("Malformed Play player-position update")
                return 1
            double x = decode_be_int64(body, position_start)
            double y = decode_be_int64(body, position_start + 8)
            double z = decode_be_int64(body, position_start + 16)
            double yaw = decode_be_float(body, position_start + 48)
            double pitch = decode_be_float(body, position_start + 52)
            int64[] encoded_id = encode_varint(teleport_id[1])
            int64[] payload = new int64[len(encoded_id) + 32]
            int64 index = 0
            while index < len(encoded_id):
                payload[index] = encoded_id[index]
                index = index + 1
            int64 output_index = len(encoded_id)
            index = 0
            while index < 8:
                payload[output_index + index] = mc_double_be_byte(x, index)
                payload[output_index + (8 + index)] = mc_double_be_byte(y, index)
                payload[output_index + (16 + index)] = mc_double_be_byte(z, index)
                index = index + 1
            index = 0
            while index < 4:
                payload[output_index + (24 + index)] = mc_float_be_byte(yaw, index)
                index = index + 1
            index = 0
            while index < 4:
                payload[output_index + (28 + index)] = mc_float_be_byte(pitch, index)
                index = index + 1
            int64[] response = encode_packet_frame(0, payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to acknowledge player teleport")
                return 1
        elif packet_id[1] == 46:
            if packet_id[2] + 8 > len(body):
                print("Truncated chunk-with-light packet")
                return 1
            int64 chunk_x = decode_be_int32(body, packet_id[2])
            int64 chunk_z = decode_be_int32(body, packet_id[2] + 4)
            if decode_chunk_sections(world, body, packet_id[2]) != 0:
                print("Could not decode incoming chunk data")
                return 1
            bool found_chunk = false
            int64 index = 0
            while index < tracked_chunk_count:
                if tracked_chunks_x[index] == chunk_x and tracked_chunks_z[index] == chunk_z:
                    found_chunk = true
                    break
                index = index + 1
            if not found_chunk and tracked_chunk_count < 8192:
                tracked_chunks_x[tracked_chunk_count] = chunk_x
                tracked_chunks_z[tracked_chunk_count] = chunk_z
                tracked_chunk_count = tracked_chunk_count + 1
            if not found_chunk:
                print(f"Stored chunk ({chunk_x}, {chunk_z}); loaded chunk count: {tracked_chunk_count}")
        elif packet_id[1] == 38:
            if packet_id[2] + 8 > len(body):
                print("Truncated chunk-unload packet")
                return 1
            int64 chunk_x = decode_be_int32(body, packet_id[2])
            int64 chunk_z = decode_be_int32(body, packet_id[2] + 4)
            int64 index = 0
            while index < tracked_chunk_count:
                if tracked_chunks_x[index] == chunk_x and tracked_chunks_z[index] == chunk_z:
                    int64 source_index = index + 1
                    while source_index < tracked_chunk_count:
                        tracked_chunks_x[source_index - 1] = tracked_chunks_x[source_index]
                        tracked_chunks_z[source_index - 1] = tracked_chunks_z[source_index]
                        source_index = source_index + 1
                    tracked_chunk_count = tracked_chunk_count - 1
                    break
                index = index + 1
            vworld_unload_chunk(world, (int)chunk_x, (int)chunk_z)
            print(f"Forgot chunk ({chunk_x}, {chunk_z})")
        elif packet_id[1] == 1:
            int64[] entity_id = decode_varint(body, packet_id[2])
            if entity_id[0] != 1:
                print("Malformed entity spawn packet")
                return 1
            bool found_entity = false
            int64 index = 0
            while index < tracked_entity_count:
                if tracked_entity_ids[index] == entity_id[1]:
                    found_entity = true
                    break
                index = index + 1
            if not found_entity and tracked_entity_count < 8192:
                tracked_entity_ids[tracked_entity_count] = entity_id[1]
                tracked_entity_count = tracked_entity_count + 1
                print(f"Tracked entity {entity_id[1]}; entity count: {tracked_entity_count}")
        elif packet_id[1] == 78:
            int64[] count = decode_varint(body, packet_id[2])
            if count[0] != 1 or (count[1] < 0 or count[1] > 8192):
                print("Malformed entity-removal packet")
                return 1
            int64 position = count[2]
            int64 index = 0
            while index < count[1]:
                int64[] entity_id = decode_varint(body, position)
                if entity_id[0] != 1:
                    print("Malformed entity id in removal packet")
                    return 1
                int64 entity_index = 0
                while entity_index < tracked_entity_count:
                    if tracked_entity_ids[entity_index] == entity_id[1]:
                        int64 following = entity_index + 1
                        while following < tracked_entity_count:
                            tracked_entity_ids[following - 1] = tracked_entity_ids[following]
                            following = following + 1
                        tracked_entity_count = tracked_entity_count - 1
                        break
                    entity_index = entity_index + 1
                position = entity_id[2]
                index = index + 1
            if position != len(body):
                print("Unexpected data in entity-removal packet")
                return 1
            print(f"Entity removals processed; entity count: {tracked_entity_count}")
        elif packet_id[1] == 11:
            int64[] batch_size = decode_varint(body, packet_id[2])
            if batch_size[0] != 1 or batch_size[2] != len(body):
                print("Malformed chunk-batch-finished packet")
                return 1
            int64[] response_payload = new int64[4]
            response_payload[0] = 66
            response_payload[1] = 128
            response_payload[2] = 0
            response_payload[3] = 0
            int64[] response = encode_packet_frame(11, response_payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to acknowledge chunk batch")
                return 1
            print(f"Chunk batch {batch_size[1]} processed; tracked chunks: {tracked_chunk_count}")
        elif packet_id[1] == 124:
            if print_system_chat(body, packet_id[2]) != 0:
                return 1
        elif packet_id[1] == 66:
            print("Received player chat; signed-chat decoding and secure-session acknowledgements are not implemented")
        elif packet_id[1] == 33:
            print("Received disguised chat; this chat component format is not yet rendered")
        elif packet_id[1] == 16:
            print("Received the server command tree")
        elif packet_id[1] == 143:
            if handle_configuration_dialog(socket_handle, body, packet_id[2], true) != 0:
                print("Could not process the Play dialog")
                return 1
        elif packet_id[1] == 142:
            print("Server cleared the active Play dialog")
        elif packet_id[1] == 32:
            print("Server disconnected during Play")
            return 0
        elif packet_id[1] == 120:
            print("Server requested a return to Configuration; that transition is not implemented")
            return 1
        packet_count = packet_count + 1
    if not received_play_login:
        print("Play packet limit reached before Play login")
    else:
        print("Play packet limit reached")
    return 1


public def play_session(socket_handle: int64,
                        registry: VDimensionRegistry*) -> int:
    VWorld* world = vworld_new(1024, 0, 1,
                               registry.block_global_bits,
                               registry.biome_global_bits)
    int result = play_session_loop(socket_handle, world, registry)
    vworld_free(world)
    return result


public def handle_configuration(socket_handle: int64,
                                registry: VDimensionRegistry*) -> int:
    int64[] client_information = encode_config_client_information()
    if send_bytes(socket_handle, client_information) != 0:
        print("Failed to send configuration client information")
        return 1
    int64 packet_count = 0
    while packet_count < 512:
        int64[] incoming = read_packet_frame(socket_handle)
        if incoming[0] != 1:
            if incoming[0] == -5:
                print("Malformed or invalid compressed Configuration packet")
            else:
                print("Could not read the next configuration packet")
            return 1
        int64[] body = frame_body(incoming)
        int64[] packet_id = decode_varint(body, 0)
        if packet_id[0] != 1:
            print("Malformed configuration packet id")
            return 1
        if packet_id[1] == 3:
            if packet_id[2] != len(body):
                print("Malformed finish-configuration packet")
                return 1
            int64[] empty = new int64[0]
            int64[] acknowledgement = encode_packet_frame(3, empty)
            if send_bytes(socket_handle, acknowledgement) != 0:
                print("Failed to acknowledge configuration")
                return 1
            print("Configuration complete; entered the Play protocol state")
            return 0
        if packet_id[1] == 2:
            print("Server disconnected during configuration")
            return 1
        if packet_id[1] == 4:
            if len(body) != packet_id[2] + 8:
                print("Malformed configuration keep-alive")
                return 1
            int64[] response = encode_keepalive_response(4, body, packet_id[2])
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration keep-alive")
                return 1
        elif packet_id[1] == 5:
            if len(body) != packet_id[2] + 4:
                print("Malformed configuration ping")
                return 1
            int64[] payload = new int64[4]
            int64 index = 0
            while index < 4:
                payload[index] = body[packet_id[2] + index]
                index = index + 1
            int64[] response = encode_packet_frame(5, payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration ping")
                return 1
        elif packet_id[1] == 15:
            int64[] selection = new int64[1]
            selection[0] = 0
            int64[] response = encode_packet_frame(7, selection)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to known-pack selection")
                return 1
        elif packet_id[1] == 0:
            int64[] key = read_string_field(body, packet_id[2], 32767)
            if key[0] != 1 or key[2] + key[1] != len(body):
                print("Malformed configuration cookie request")
                return 1
            int64[] encoded_key_length = encode_varint(key[1])
            int64[] cookie_payload = new int64[len(encoded_key_length) + (key[1] + 1)]
            int64 index = 0
            while index < len(encoded_key_length):
                cookie_payload[index] = encoded_key_length[index]
                index = index + 1
            int64 payload_index = len(encoded_key_length)
            index = 0
            while index < key[1]:
                cookie_payload[payload_index + index] = body[key[2] + index]
                index = index + 1
            cookie_payload[len(cookie_payload) - 1] = 0
            int64[] response = encode_packet_frame(1, cookie_payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration cookie request")
                return 1
        elif packet_id[1] == 9:
            if packet_id[2] + 16 > len(body):
                print("Malformed configuration resource-pack request")
                return 1
            int64[] resource_pack_payload = new int64[17]
            int64 index = 0
            while index < 16:
                resource_pack_payload[index] = body[packet_id[2] + index]
                index = index + 1
            resource_pack_payload[16] = 1
            int64[] response = encode_packet_frame(6, resource_pack_payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to decline configuration resource pack")
                return 1
        elif packet_id[1] == 20:
            int64[] conduct = read_string_field(body, packet_id[2], 32767)
            if conduct[0] != 1 or conduct[2] + conduct[1] != len(body):
                print("Malformed server code of conduct")
                return 1
            print("Server code of conduct:")
            int64 index = conduct[2]
            while index < conduct[2] + conduct[1]:
                mc_write_byte(body[index])
                index = index + 1
            print("")
            print("Accept this code of conduct? (type yes to accept):")
            int64[] consent = read_dialog_line()
            if consent[0] != 1 or not dialog_line_equals(consent, "yes"):
                print("Code of conduct not accepted")
                return 1
            mc_stdin_line_done()
            int64[] consent_acknowledgement = new int64[0]
            int64[] response = encode_packet_frame(9, consent_acknowledgement)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to accept server code of conduct")
                return 1
        elif packet_id[1] == 19:
            if handle_configuration_dialog(socket_handle, body, packet_id[2], false) != 0:
                print("Could not process the server configuration dialog")
                return 1
        elif packet_id[1] == 7:
            if parse_configuration_registry(body, packet_id[2], registry) == 0:
                print("Malformed or unsupported configuration registry data")
                return 1
        elif packet_id[1] == 18:
            print("Server cleared the active configuration dialog")
        elif is_ignorable_configuration_packet(packet_id[1]):
            print(f"Received configuration data packet {packet_id[1]}")
        else:
            print(f"Unsupported configuration packet id {packet_id[1]}")
            return 1
        packet_count = packet_count + 1
    print("Too many configuration packets without finish")
    return 1

public def encode_login_start(username: str, username_length: int64) -> int64[]:
    int64[] body = encode_varint(0)
    body = append_varint(body, username_length)
    int64 index = 0
    while index < username_length:
        append(body, mc_string_byte(username, index))
        index = index + 1
    index = 0
    while index < 16:
        append(body, mc_offline_uuid_byte(username, index))
        index = index + 1
    int64[] frame = encode_varint(len(body))
    index = 0
    while index < len(body):
        append(frame, body[index])
        index = index + 1
    return frame

public def offline_login(host: str, port: int64, username: str) -> int:
    int64 host_length = mc_string_length(host)
    int64 username_length = mc_string_length(username)
    if host_length < 1 or host_length > 255:
        print("Invalid host: expected 1-255 UTF-8 bytes")
        return 1
    if username_length < 1 or username_length > 16:
        print("Invalid username: expected 1-16 ASCII characters")
        return 1
    if port < 1 or port > 65535:
        print("Invalid port: expected 1-65535")
        return 1
    int64 index = 0
    while index < username_length:
        int64 character = mc_string_byte(username, index)
        if not (character >= 48 and character <= 57 or (character >= 65 and character <= 90 or (character >= 97 and character <= 122 or character == 95))):
            print("Invalid username: use ASCII letters, numbers, and underscore")
            return 1
        index = index + 1
    int64[] host_bytes = new int64[host_length]
    index = 0
    while index < host_length:
        host_bytes[index] = mc_string_byte(host, index)
        index = index + 1
    int64 socket_handle = mc_tcp_connect(host, port)
    if socket_handle < 0:
        print(f"Could not connect to {host}")
        return 1
    int64[] handshake = encode_handshake(777, host_bytes, host_length, port, 2)
    if send_bytes(socket_handle, handshake) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send login handshake")
        return 1
    int64[] login_start = encode_login_start(username, username_length)
    if send_bytes(socket_handle, login_start) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send offline login start")
        return 1
    int64[] login_frame = read_packet_frame(socket_handle)
    if login_frame[0] != 1:
        mc_tcp_close(socket_handle)
        print("Could not read or decompress a valid login response")
        return 1
    int64[] login_body = read_login_response_body(socket_handle, login_frame)
    if len(login_body) < 1:
        mc_tcp_close(socket_handle)
        print("Could not process the login response")
        return 1
    int64[] packet_id = decode_varint(login_body, 0)
    if packet_id[0] != 1:
        mc_tcp_close(socket_handle)
        print("Malformed login response packet")
        return 1
    if packet_id[1] == 0:
        int64[] reason = read_string_field(login_body, packet_id[2], 262144)
        mc_tcp_close(socket_handle)
        if reason[0] == 1:
            print("Server rejected login:")
            index = reason[2]
            while index < reason[2] + reason[1]:
                mc_write_byte(login_body[index])
                index = index + 1
            print("")
        else:
            print("Server rejected login with an invalid reason")
        return 1
    if packet_id[1] == 1:
        mc_tcp_close(socket_handle)
        print("Server requires online-mode authentication; no credentials were sent")
        return 1
    if packet_id[1] == 4:
        mc_tcp_close(socket_handle)
        print("Server requested a login plugin/proxy query; this is not supported")
        return 1
    if packet_id[1] == 5:
        mc_tcp_close(socket_handle)
        print("Server requested a login cookie; cookie handling is not implemented")
        return 1
    if packet_id[1] != 2:
        mc_tcp_close(socket_handle)
        print("Unexpected login response packet")
        return 1
    int64 profile_start = packet_id[2]
    if profile_start + 16 > len(login_body):
        mc_tcp_close(socket_handle)
        print("Truncated login profile UUID")
        return 1
    index = 0
    while index < 16:
        if login_body[profile_start + index] != mc_offline_uuid_byte(username, index):
            mc_tcp_close(socket_handle)
            print("Login profile UUID does not match the offline username")
            return 1
        index = index + 1
    int64[] profile_name = read_string_field(login_body, profile_start + 16, 16)
    if profile_name[0] != 1 or profile_name[1] != username_length:
        mc_tcp_close(socket_handle)
        print("Malformed login profile name")
        return 1
    index = 0
    while index < username_length:
        if login_body[profile_name[2] + index] != mc_string_byte(username, index):
            mc_tcp_close(socket_handle)
            print("Login profile name does not match the requested username")
            return 1
        index = index + 1
    int64[] property_count = decode_varint(login_body, profile_name[2] + profile_name[1])
    if property_count[0] != 1 or (property_count[1] < 0 or property_count[1] > 1024):
        mc_tcp_close(socket_handle)
        print("Malformed login profile properties")
        return 1
    int64 property_position = property_count[2]
    index = 0
    while index < property_count[1]:
        int64[] property_name = read_string_field(login_body, property_position, 64)
        if property_name[0] != 1:
            mc_tcp_close(socket_handle)
            print("Malformed login profile property name")
            return 1
        int64[] property_value = read_string_field(login_body, property_name[2] + property_name[1], 32767)
        if property_value[0] != 1:
            mc_tcp_close(socket_handle)
            print("Malformed login profile property value")
            return 1
        property_position = property_value[2] + property_value[1]
        if property_position >= len(login_body):
            mc_tcp_close(socket_handle)
            print("Truncated login profile property")
            return 1
        int64 has_signature = login_body[property_position]
        property_position = property_position + 1
        if has_signature == 1:
            int64[] signature = read_string_field(login_body, property_position, 1024)
            if signature[0] != 1:
                mc_tcp_close(socket_handle)
                print("Malformed login profile signature")
                return 1
            property_position = signature[2] + signature[1]
        elif has_signature != 0:
            mc_tcp_close(socket_handle)
            print("Invalid login profile signature flag")
            return 1
        index = index + 1
    if property_position + 16 != len(login_body):
        mc_tcp_close(socket_handle)
        print("Unexpected bytes in login success packet")
        return 1
    int64[] empty = new int64[0]
    int64[] acknowledgement = encode_packet_frame(3, empty)
    if send_bytes(socket_handle, acknowledgement) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to acknowledge login success")
        return 1
    print(f"Offline login accepted for {username}")
    print("Login acknowledged; entering configuration")
    VDimensionRegistry* registry = vdimension_registry_new()
    int configuration_result = handle_configuration(socket_handle, registry)
    if configuration_result != 0:
        vdimension_registry_free(registry)
        mc_tcp_close(socket_handle)
        return configuration_result
    print("Entering Play packet exchange")
    int play_result = play_session(socket_handle, registry)
    vdimension_registry_free(registry)
    mc_tcp_close(socket_handle)
    return play_result

public def status_ping(host: str, port: int64) -> int:
    int64 host_length = mc_string_length(host)
    if host_length < 1:
        print("Invalid host: expected 1-255 UTF-8 bytes")
        return 1
    if host_length > 255:
        print("Invalid host: expected 1-255 UTF-8 bytes")
        return 1
    int64[] host_bytes = new int64[host_length]
    int64 index = 0
    while index < host_length:
        host_bytes[index] = mc_string_byte(host, index)
        index = index + 1
    if port < 1 or port > 65535:
        print("Invalid port: expected 1-65535")
        return 1
    int64 socket_handle = mc_tcp_connect(host, port)
    if socket_handle < 0:
        print(f"Could not connect to {host}")
        return 1
    int64[] handshake = encode_handshake(777, host_bytes, host_length, port, 1)
    if send_bytes(socket_handle, handshake) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send handshake")
        return 1
    int64[] request = encode_status_request()
    if send_bytes(socket_handle, request) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send status request")
        return 1
    int64[] status_frame = read_frame(socket_handle)
    if status_frame[0] != 1:
        mc_tcp_close(socket_handle)
        print("Could not read a valid status response")
        return 1
    int64[] status_body = new int64[status_frame[2]]
    int64 index = 0
    while index < status_frame[2]:
        status_body[index] = status_frame[3 + index]
        index = index + 1
    int64[] packet_id = decode_varint(status_body, 0)
    if packet_id[0] != 1 or packet_id[1] != 0:
        mc_tcp_close(socket_handle)
        print("Unexpected status response packet")
        return 1
    int64[] json_length = decode_varint(status_body, packet_id[2])
    if json_length[0] != 1 or json_length[1] < 0:
        mc_tcp_close(socket_handle)
        print("Malformed status JSON length")
        return 1
    int64 json_start = json_length[2]
    if json_start + json_length[1] > len(status_body):
        mc_tcp_close(socket_handle)
        print("Truncated status JSON")
        return 1
    print("Server status:")
    index = json_start
    while index < json_start + json_length[1]:
        mc_write_byte(status_body[index])
        index = index + 1
    print("")
    int64 ping_time = mc_time_millis()
    if ping_time < 0:
        mc_tcp_close(socket_handle)
        print("Could not read system clock")
        return 1
    int64[] ping_packet = encode_ping_request(ping_time)
    if send_bytes(socket_handle, ping_packet) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send ping")
        return 1
    int64[] pong_frame = read_frame(socket_handle)
    if pong_frame[0] != 1:
        mc_tcp_close(socket_handle)
        print("Could not read a valid pong")
        return 1
    int64[] pong_body = new int64[pong_frame[2]]
    index = 0
    while index < pong_frame[2]:
        pong_body[index] = pong_frame[3 + index]
        index = index + 1
    int64[] pong_id = decode_varint(pong_body, 0)
    if pong_id[0] != 1 or (pong_id[1] != 1 or len(pong_body) - pong_id[2] != 8):
        mc_tcp_close(socket_handle)
        print("Unexpected pong packet")
        return 1
    index = 0
    while index < 8:
        int64 expected = ping_time >> (7 - index) * 8 & 0xFF
        if pong_body[pong_id[2] + index] != expected:
            mc_tcp_close(socket_handle)
            print("Pong payload did not match ping")
            return 1
        index = index + 1
    int64 elapsed = mc_time_millis() - ping_time
    mc_tcp_close(socket_handle)
    print("Ping (ms):")
    print(elapsed)
    return 0


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


# ===== test_chunk_light.cpy =====

def build_chunk_packet(b: VBuf*, bad_mask: bool, truncated_light: bool,
                       with_entity: bool, boundary_light: bool) -> void:
    vbuf_put_i32_be(b, 0)
    vbuf_put_i32_be(b, 0)

    # No heightmaps.
    vbuf_put_varint(b, 0)

    # One section: zero non-air blocks, uniform block and biome containers.
    vbuf_put_varint(b, 6)
    vbuf_put_i16_be(b, 0)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_varint(b, 0)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_varint(b, 0)

    if with_entity:
        vbuf_put_varint(b, 1)
        vbuf_put_u8(b, (uint64)0)
        vbuf_put_i16_be(b, 5)
        vbuf_put_varint(b, 1)
        vbuf_put_u8(b, (uint64)10)
        vbuf_put_u8(b, (uint64)0)
    else:
        vbuf_put_varint(b, 0)

    # The only non-empty sky-light section is section index zero (mask bit 1).
    vbuf_put_varint(b, 1)
    if bad_mask:
        vbuf_put_i64_be(b, (int64)8)
    elif boundary_light:
        vbuf_put_i64_be(b, (int64)1)
    else:
        vbuf_put_i64_be(b, (int64)2)
    vbuf_put_varint(b, 0) # block-light mask
    vbuf_put_varint(b, 0) # empty sky-light mask
    vbuf_put_varint(b, 0) # empty block-light mask

    vbuf_put_varint(b, 1)
    vbuf_put_varint(b, 2048)
    int i = 0
    while i < 2048:
        int value = 0
        if i == 0:
            value = 33
        if truncated_light and i == 2047:
            break
        vbuf_put_u8(b, (uint64)value)
        i += 1
    vbuf_put_varint(b, 0) # no block-light arrays


def decode_fixture(bad_mask: bool, truncated_light: bool,
                   with_entity: bool, boundary_light: bool,
                   fails: int*) -> VWorld*:
    VBuf* b = vbuf_new(8192)
    build_chunk_packet(b, bad_mask, truncated_light, with_entity, boundary_light)
    int64[] body = new int64[b.len]
    int64 i = 0
    while i < b.len:
        body[i] = (int64)vbuf_at(b, (int)i)
        i += 1
    VWorld* world = vworld_new(2, 0, 1, 15, 6)
    int status = decode_chunk_sections(world, body, 0)
    if bad_mask or truncated_light:
        check_int("invalid chunk payload rejected", status, 1, fails)
        check_int("invalid chunk not installed", vworld_chunk_count(world), 0, fails)
    else:
        check_int("chunk with lighting decoded", status, 0, fails)
        check_int("decoded chunk installed", vworld_chunk_count(world), 1, fails)
        VSection* section = vworld_section(world, 0, 0, 0)
        check("chunk section available", section != null, fails)
        if section != null:
            int expected_low = 1
            int expected_high = 2
            if boundary_light:
                expected_low = 0
                expected_high = 0
            check_int("sky light low nibble", sec_sky_light_at(section, 0, 0, 0), expected_low, fails)
            check_int("sky light high nibble", sec_sky_light_at(section, 1, 0, 0), expected_high, fails)
            check_int("unset block light remains zero", sec_block_light_at(section, 0, 0, 0), 0, fails)
    vbuf_free(b)
    return world


def main() -> int:
    int fails = 0
    print("chunk packet light and block entities:")
    VWorld* world = decode_fixture(false, false, true, false, &fails)
    vworld_free(world)
    world = decode_fixture(true, false, false, false, &fails)
    vworld_free(world)
    world = decode_fixture(false, true, false, false, &fails)
    vworld_free(world)
    world = decode_fixture(false, false, false, true, &fails)
    vworld_free(world)
    return report("chunk light tests", fails)

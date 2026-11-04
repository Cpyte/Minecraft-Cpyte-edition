# Vortex engine - generated bundle. Do not edit: this file is assembled from
# the modules listed below by tools/bundle.py.
#
#   native.cpy, core.cpy, strings.cpy, vbuf.cpy, nbt.cpy, palette.cpy, harness.cpy, test_buf.cpy

import stdlib


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
def vcont_bits_for(needed: int, min_bits: int) -> int:
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


# How many distinct values `values` holds; counting each first appearance only
# keeps the loop free of `break`, which the compiler does not accept here.
def vcont_count_distinct(values: int*, count: int) -> int:
    int distinct = 0
    int probe = 0
    while probe < count:
        int candidate = vt_iget(values, probe)
        int first = 1
        int k = 0
        while k < probe:
            if vt_iget(values, k) == candidate:
                first = 0
            k += 1
        if first == 1:
            distinct += 1
        probe += 1
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


# ===== test_buf.cpy =====
# Vortex engine - codec smoke tests.
#
# Built as a bundle so the engine modules share one translation unit:
#   ./build.sh --run tests/buf.txt
# Assertions come from tests/harness.cpy; see docs/BUILD.md.


def test_strings(fails: int*) -> void:
    print("strings:")
    check_int("slice length", text_len(str_slice("abcdefgh", 2, 5)), 3, fails)
    check_str("slice content", str_slice("abcdefgh", 2, 5), "cde", fails)
    check_str("slice clamps", str_slice("abc", -3, 99), "abc", fails)
    check_str("trim", str_trim("  hi"), "hi", fails)
    check_int("find", str_find("potato", "ta"), 2, fails)
    check_int("find absent", str_find("potato", "xy"), -1, fails)
    check_str("field 0", str_field("a|bb||d", code_pipe(), 0), "a", fails)
    check_str("field 1", str_field("a|bb||d", code_pipe(), 1), "bb", fails)
    check_str("empty field kept", str_field("a|bb||d", code_pipe(), 2), "", fails)
    check_str("field past end empty", str_field("a|bb||d", code_pipe(), 9), "", fails)
    check_int("field count", str_field_count("a|bb||d", code_pipe()), 4, fails)
    check_int("code at", code_at("a|x", 1), code_pipe(), fails)
    check_int("parse int", parse_int("-123"), -123, fails)
    check_int("parse int spaces", parse_int(" 42 "), 42, fails)
    check_int("parse junk", parse_int("nope"), 0, fails)
    check("parse bool", parse_bool("true"), fails)

    int ok = 0
    check_int("parse int ok flag", parse_int_or("7", 99, &ok), 7, fails)
    check_int("parse int ok set", ok, 1, fails)
    check_int("parse int fail flag", parse_int_or("x", 99, &ok), 99, fails)
    check_int("parse int fail clears", ok, 0, fails)

    check("hash differs", str_hash("stone") != str_hash("wood"), fails)
    check("hash stable", str_hash("stone") == str_hash("stone"), fails)

    VStr* sink = vstr_new(4)
    int i = 0
    while i < 40:
        vstr_put(sink, code_at("vortex", i % 6))
        i += 1
    check_int("vstr length", sink.len, 40, fails)
    check("vstr grew", sink.cap >= 40, fails)
    check_str("vstr content head", str_slice(vstr_text(sink), 0, 6), "vortex", fails)
    vstr_free(sink)


def test_varint(fails: int*) -> void:
    print("varint:")
    VBuf* b = vbuf_new(16)

    # Group counts are the documented 1/2/5 boundaries for VarInt.
    vbuf_reset(b)
    vbuf_put_varint(b, 300)
    check_int("300 is two groups", b.len, 2, fails)
    check_int("300 round trip", vbuf_take_varint_unchecked(b), 300, fails)

    vbuf_reset(b)
    vbuf_put_varint(b, 0)
    check_int("zero is one group", b.len, 1, fails)
    check_int("zero round trip", vbuf_take_varint_unchecked(b), 0, fails)

    vbuf_reset(b)
    vbuf_put_varint(b, -1)
    check_int("minus one is five groups", b.len, 5, fails)
    check_int("minus one round trip", vbuf_take_varint_unchecked(b), -1, fails)

    vbuf_reset(b)
    vbuf_put_varint(b, i32_max())
    check_int("max int round trip", vbuf_take_varint_unchecked(b), i32_max(), fails)

    vbuf_reset(b)
    vbuf_put_varint(b, i32_min())
    check_int("min int round trip", vbuf_take_varint_unchecked(b), i32_min(), fails)

    # VarLong keeps the 64 bit form: 2^31 must not alias its own negation the
    # way a narrowed VarInt would.
    vbuf_reset(b)
    vbuf_put_varlong(b, (int64)2147483648)
    check_int("varlong five groups", b.len, 5, fails)
    check_int("varlong wide round trip", (int)vbuf_take_varlong_unchecked(b), -2147483648, fails)

    # A negative VarLong keeps its 64 bit form, so it always costs ten groups.
    vbuf_reset(b)
    vbuf_put_varlong(b, (int64)-1)
    check_int("minus one varlong is ten groups", b.len, 10, fails)
    check_int("minus one varlong round trip", (int)vbuf_take_varlong_unchecked(b), -1, fails)

    vbuf_reset(b)
    vbuf_put_varlong(b, (int64)-67230720)
    int ok = 0
    int64 back = vbuf_take_varlong(b, &ok)
    check("varlong negative ok", ok == 1, fails)
    check_int("varlong negative round trip", (int)back, -67230720, fails)

    # A truncated group must be reported, not silently returned.
    vbuf_reset(b)
    vbuf_put_u8(b, (uint64)128)
    int ok2 = 1
    vbuf_take_varint(b, &ok2)
    check("truncated varint flagged", ok2 == 0, fails)
    vbuf_free(b)


def test_fixed(fails: int*) -> void:
    print("fixed width:")
    VBuf* b = vbuf_new(16)

    vbuf_reset(b)
    vbuf_put_u32_be(b, (uint64)2596069104)
    check_int("be byte count", b.len, 4, fails)
    check_int("be writes high byte first", (int)vbuf_at(b, 0), 154, fails)
    check_int("be round trip", (int)vbuf_take_u32_be(b), -1698898192, fails)

    vbuf_reset(b)
    vbuf_put_u32_le(b, (uint64)2596069104)
    check_int("le writes low byte first", (int)vbuf_at(b, 0), 240, fails)
    check_int("le round trip", (int)vbuf_take_u32_le(b), -1698898192, fails)

    vbuf_reset(b)
    vbuf_put_i64_be(b, (int64)-1234567890123)
    check_int("i64 be round trip", (int)vbuf_take_i64_be(b), -1912276171, fails)

    vbuf_reset(b)
    vbuf_put_u64_be(b, (uint64)14695981039346656037)
    check_int("u64 be round trip", (int)vbuf_take_u64_be(b), -3750763034362895579, fails)

    vbuf_reset(b)
    vbuf_put_str_u16_be(b, "vortex")
    int str_ok = 0
    check_str("string round trip", vbuf_take_str_u16_be(b, &str_ok), "vortex", fails)
    check_int("string read was complete", str_ok, 1, fails)

    # A length prefix that outruns the data is an error, not NUL padding.
    vbuf_reset(b)
    vbuf_put_u16_be(b, (uint64)10)
    vbuf_put_bytes(b, vt_calloc_char(3), 3)
    int short_ok = 1
    vbuf_take_str_u16_be(b, &short_ok)
    check_int("overlong string flagged", short_ok, 0, fails)

    # Reads past the end must not run away from the buffer.
    vbuf_reset(b)
    check("empty read is zero", vbuf_take_u8(b) == (uint64)0, fails)
    check_int("empty read keeps pos", b.pos, 0, fails)
    vbuf_free(b)


def test_growth(fails: int*) -> void:
    print("growth:")
    VBuf* b = vbuf_new(8)
    int i = 0
    while i < 5000:
        vbuf_put_u8(b, (uint64)(i & 255))
        i += 1
    check_int("length after 5000", b.len, 5000, fails)
    check("capacity covers length", b.cap >= 5000, fails)
    check_int("doubling kept", b.cap, 8192, fails)
    b.pos = 4095
    check_int("spot check tail", (int)vbuf_take_u8(b), 255, fails)
    vbuf_free(b)


def main() -> int:
    print("vortex codec tests")
    int fails = 0
    test_strings(&fails)
    test_varint(&fails)
    test_fixed(&fails)
    test_growth(&fails)
    return report("vortex codec tests", fails)

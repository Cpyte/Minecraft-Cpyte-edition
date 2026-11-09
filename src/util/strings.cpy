# Vortex engine - text and numeric helpers.
#
# Every operation here delegates to the C layer in src/engine/native.cpy:
# Cpyte's own support stops at `+` on two strings and `len()`, a character
# literal is a string pointer rather than a byte, and text cannot be built by
# appending characters.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.

import stdlib


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


# Characters [from, to) of `text`, appended without producing a slice of their
# own. Table building and lookup run over tens of thousands of short ranges,
# and a `str_slice` per range is a per-row allocation that nothing can free
# until the whole registry is dropped.
public def vstr_put_slice(s: VStr*, text: str, from: int, to: int) -> void:
    int n = vt_strlen(text)
    if from < 0:
        from = 0
    if to > n:
        to = n
    int i = from
    while i < to:
        vstr_put(s, vt_at(text, i))
        i = i + 1


public def vstr_clear(s: VStr*) -> void:
    s.len = 0
    vt_put(s.data, 0, code_nul())


def text_is_blank(code: int) -> int:
    if code == 32 or code == 9 or code == 13 or code == 10:
        return 1
    return 0


# Characters [from, to) of `text`, with the blanks around them dropped. A table
# row has to lose its trailing carriage return before it can be parsed, and
# doing that with a trim over a slice allocates twice for every row.
public def vstr_put_trimmed_slice(s: VStr*, text: str, from: int, to: int) -> void:
    int n = vt_strlen(text)
    if from < 0:
        from = 0
    if to > n:
        to = n
    int begin = from
    int end = to
    while begin < end and text_is_blank(vt_at(text, begin)) == 1:
        begin = begin + 1
    while end > begin and text_is_blank(vt_at(text, end - 1)) == 1:
        end = end - 1
    int i = begin
    while i < end:
        vstr_put(s, vt_at(text, i))
        i = i + 1


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

# Vortex engine - growable byte buffer and the variable length integer
# encodings used by world data (chunk palettes, region files).
#
# The varint / varlong rules are the ones published by the community protocol
# references; no Mojang byte code or decompiled source was consulted.
# See docs/PARITY_BOUNDARY.md.
#
# Byte access goes through vt_at / vt_put rather than `b.data[i]`: the C layer
# is the only place the engine is known to index raw memory reliably.

import stdlib


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


# Cpyte cannot read through two levels of struct field in one expression, so
# callers that only hold a VWire use these instead of `w.b.pos`.
public def vbuf_pos(b: VBuf*) -> int:
    return b.pos


public def vbuf_len(b: VBuf*) -> int:
    return b.len


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

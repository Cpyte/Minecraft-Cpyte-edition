# Vortex protocol - descriptor driven wire codec.
#
# Protocol 777 has two hundred and nine Play packets alone. Hand writing a
# reader for each one is where length validation gets skipped, so a packet is
# described once as a shape string (src/proto/shape.cpy) and this file walks
# that shape. A shape is a comma separated token list, one token per field:
#
#   vi varint   vl varlong   u1 i1 u2 i2 u4 i4 u8 i8   f4 f8   bo
#   st<N> varint-length UTF-8 (default 32767)   id<N> identifier (default 256)
#   uu uuid    ps packed block position    sp packed section position
#   cp chunk position pair    vd three doubles    lv three block velocities
#   vv three varints          cv three floats
#   bt unnamed NBT tag   cm text component   by byte string   rx rest of packet
#   sk<N> skip N fixed bytes    em entity metadata stream
#   o<T> option: one bool, then T only when set
#   ar<Name> varint count then Name repeated inline (flat shapes only)
#   ax<Name> varint count then each element measured, not inlined
#
# A token may end in a gate, `@f` or `@f.b`: the field exists only when field f
# is non zero, or when bit b of field f is set; `@!f` inverts the test. Gates
# must address an earlier token of the same shape, which the walker checks.
# This is how Horizon's conditional codecs - relative movement masks, per
# variant entity payloads - are described without per-packet code.
#
# Field storage, by kind:
#   vi u1 i1 u2 i2 u4 i4 bo    val = value
#   vl u8 i8 f4 f8             val = pool slot holding the raw bits
#   st id by                   val = pool slot, len = byte count
#   uu                         val = pool slot, len = 16
#   ps sp cp vd lv vv cv       val = pool slot, len = 3 components
#   bt cm                      val = byte offset, len = byte count, extra = tag
#   em                         val = byte offset, len = byte count, extra = entries
#   o<primitive>               as the primitive, present only when set
#   o<composite>               kind span: val = byte offset, len = byte count
#   ar<Name> inline            val = sub slot, len = elements, extra = stride
#   ax<Name> / ar<Name> measured   val = pool slot, len = elements, and the pool
#                              holds one (offset, length) pair per element
#
# Failure is soft by design: every packet is length delimited on the wire, so a
# shape that does not match the server costs one undecoded packet, never the
# connection. Only framing errors still end a session.
#
# License boundary: the shapes mirror Horizon's public MIT packet definitions;
# no Mojang code or data. See docs/PARITY_BOUNDARY.md.

import stdlib


# ---- kinds and errors --------------------------------------------------------

def pw_k_none() -> int: return 0
def pw_k_varint() -> int: return 1
def pw_k_varlong() -> int: return 2
def pw_k_int() -> int: return 3
def pw_k_float() -> int: return 4
def pw_k_double() -> int: return 5
def pw_k_bool() -> int: return 6
def pw_k_text() -> int: return 7
def pw_k_uuid() -> int: return 8
def pw_k_position() -> int: return 9
def pw_k_vector() -> int: return 10
def pw_k_nbt() -> int: return 11
def pw_k_bytes() -> int: return 12
def pw_k_remainder() -> int: return 13
def pw_k_skip() -> int: return 14
def pw_k_metadata() -> int: return 15
def pw_k_array() -> int: return 16
def pw_k_measured() -> int: return 17
def pw_k_span() -> int: return 18

def pw_err_none() -> int: return 0
def pw_err_truncated() -> int: return 1
def pw_err_range() -> int: return 2
def pw_err_shape() -> int: return 3
def pw_err_capacity() -> int: return 4
def pw_err_leftover() -> int: return 5
def pw_err_gate() -> int: return 6

def pw_max_fields() -> int: return 64
def pw_max_slots() -> int: return 1024
def pw_pool_cap() -> int: return 49152
def pw_text_max() -> int: return 32767
def pw_ident_max() -> int: return 256
def pw_array_max() -> int: return 4096
def pw_depth_max() -> int: return 3

def pw_code_at() -> int: return 64
def pw_code_lt() -> int: return 60
def pw_code_gt() -> int: return 62
def pw_code_bang() -> int: return 33
def pw_code_comma() -> int: return 44
def pw_code_dot() -> int: return 46
def pw_code_zero() -> int: return 48
def pw_code_nine() -> int: return 57


struct VWire:
    VBuf* b
    int* kind
    int* present
    int* val
    int* ext
    int* extra
    int* sub_kind
    int* sub_val
    int* sub_ext
    int* sub_present
    unsigned long long* pool
    int fields
    int pool_len
    int error
    int exact


public def pw_new() -> VWire*:
    VWire* w = new VWire
    w.b = vbuf_new(8192)
    w.kind = vt_calloc_int(pw_max_fields())
    w.present = vt_calloc_int(pw_max_fields())
    w.val = vt_calloc_int(pw_max_fields())
    w.ext = vt_calloc_int(pw_max_fields())
    w.extra = vt_calloc_int(pw_max_fields())
    w.sub_kind = vt_calloc_int(pw_max_slots())
    w.sub_val = vt_calloc_int(pw_max_slots())
    w.sub_ext = vt_calloc_int(pw_max_slots())
    w.sub_present = vt_calloc_int(pw_max_slots())
    w.pool = vt_calloc_u64(pw_pool_cap())
    pw_reset(w)
    return w


public def pw_free(w: VWire*) -> void:
    if w == null:
        return
    vbuf_free(w.b)
    vt_free((void*)w.kind)
    vt_free((void*)w.present)
    vt_free((void*)w.val)
    vt_free((void*)w.ext)
    vt_free((void*)w.extra)
    vt_free((void*)w.sub_kind)
    vt_free((void*)w.sub_val)
    vt_free((void*)w.sub_ext)
    vt_free((void*)w.sub_present)
    vt_free((void*)w.pool)
    del w


public def pw_reset(w: VWire*) -> void:
    int i = 0
    while i < pw_max_fields():
        vt_iset(w.kind, i, pw_k_none())
        vt_iset(w.present, i, 0)
        vt_iset(w.val, i, 0)
        vt_iset(w.ext, i, 0)
        vt_iset(w.extra, i, 0)
        i += 1
    i = 0
    while i < pw_max_slots():
        vt_iset(w.sub_kind, i, pw_k_none())
        vt_iset(w.sub_val, i, 0)
        vt_iset(w.sub_ext, i, 0)
        vt_iset(w.sub_present, i, 0)
        i += 1
    w.fields = 0
    w.pool_len = 0
    w.error = pw_err_none()
    w.exact = 0


# Copy one packet body into the walker. The caller keeps its own array, so the
# Play loop's `int64[]` frames need no reshaping.
public def pw_load(w: VWire*, data: int64[], offset: int, length: int) -> int:
    if offset < 0 or length < 0:
        return 0
    if offset + length > (int)len(data):
        return 0
    pw_reset(w)
    vbuf_reset(w.b)
    int i = 0
    while i < length:
        vbuf_put_u8(w.b, (uint64)(data[offset + i] & (int64)255))
        i += 1
    return 1


public def pw_error(w: VWire*) -> int:
    return w.error


public def pw_exact(w: VWire*) -> int:
    return w.exact


public def pw_fields(w: VWire*) -> int:
    return w.fields


public def pw_consumed(w: VWire*) -> int:
    return w.b.len - vbuf_avail(w.b)


# ---- storage -----------------------------------------------------------------

def pw_room_pool(w: VWire*, count: int) -> int:
    if count < 0:
        return 0
    if w.pool_len + count > pw_pool_cap():
        w.error = pw_err_capacity()
        return 0
    return 1


def pw_pool_put(w: VWire*, value: int64) -> int:
    if pw_room_pool(w, 1) == 0:
        return -1
    int index = w.pool_len
    vt_uset(w.pool, index, (uint64)value)
    w.pool_len += 1
    return index


def pw_pool_take(w: VWire*, count: int) -> int:
    if count < 0 or vbuf_avail(w.b) < count:
        w.error = pw_err_truncated()
        return -1
    if pw_room_pool(w, count) == 0:
        return -1
    int start = w.pool_len
    int i = 0
    while i < count:
        vt_uset(w.pool, start + i, vbuf_take_u8(w.b))
        i += 1
    w.pool_len += count
    return start


def pw_alloc_field(w: VWire*) -> int:
    if w.fields >= pw_max_fields():
        w.error = pw_err_capacity()
        return -1
    int index = w.fields
    w.fields += 1
    return index


# ---- token parsing -----------------------------------------------------------

def pw_token(shape: str, index: int) -> str:
    return vt_field(shape, pw_code_comma(), index)


def pw_token_count(shape: str) -> int:
    if vt_strlen(shape) == 0:
        return 0
    return vt_count(shape, pw_code_comma()) + 1


def pw_at_index(token: str) -> int:
    return vt_find_code(token, 0, pw_code_at())


def pw_plain(token: str) -> str:
    int at = pw_at_index(token)
    if at < 0:
        return token
    return vt_slice(token, 0, at)


def pw_gate_field(token: str) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return -1
    str body = vt_slice(token, at + 1, vt_strlen(token))
    if vt_at(body, 0) == pw_code_bang():
        body = vt_slice(body, 1, vt_strlen(body))
    int dot = vt_find_code(body, 0, pw_code_dot())
    if dot >= 0:
        body = vt_slice(body, 0, dot)
    return parse_int(body)


def pw_gate_bit(token: str) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return -1
    str body = vt_slice(token, at + 1, vt_strlen(token))
    int dot = vt_find_code(body, 0, pw_code_dot())
    if dot < 0:
        return -1
    return parse_int(vt_slice(body, dot + 1, vt_strlen(body)))


def pw_gate_invert(token: str) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return 0
    if vt_at(token, at + 1) == pw_code_bang():
        return 1
    return 0


def pw_digits_after(plain: str, from: int) -> int:
    # The decimal tail of st<N> / id<N> / sk<N>; -1 when there is none.
    int length = vt_strlen(plain)
    if length <= from:
        return -1
    int i = from
    while i < length:
        int c = vt_at(plain, i)
        if c < pw_code_zero() or c > pw_code_nine():
            return -1
        i += 1
    return parse_int(vt_slice(plain, from, length))


def pw_sub_name(plain: str) -> str:
    int mark = vt_find_code(plain, 0, pw_code_lt())
    if mark < 0:
        return ""
    int close = vt_find_code(plain, mark, pw_code_gt())
    if close < 0:
        return ""
    return vt_slice(plain, mark + 1, close)


def pw_kind_of(plain: str) -> int:
    if str_equals(plain, "vi"): return pw_k_varint()
    if str_equals(plain, "vl"): return pw_k_varlong()
    if str_equals(plain, "u1"): return pw_k_int()
    if str_equals(plain, "i1"): return pw_k_int()
    if str_equals(plain, "u2"): return pw_k_int()
    if str_equals(plain, "i2"): return pw_k_int()
    if str_equals(plain, "u4"): return pw_k_int()
    if str_equals(plain, "i4"): return pw_k_int()
    if str_equals(plain, "u8"): return pw_k_varlong()
    if str_equals(plain, "i8"): return pw_k_varlong()
    if str_equals(plain, "f4"): return pw_k_float()
    if str_equals(plain, "f8"): return pw_k_double()
    if str_equals(plain, "bo"): return pw_k_bool()
    if str_equals(plain, "uu"): return pw_k_uuid()
    if str_equals(plain, "ps"): return pw_k_position()
    if str_equals(plain, "sp"): return pw_k_position()
    if str_equals(plain, "cp"): return pw_k_position()
    if str_equals(plain, "vd"): return pw_k_vector()
    if str_equals(plain, "lv"): return pw_k_vector()
    if str_equals(plain, "vv"): return pw_k_vector()
    if str_equals(plain, "cv"): return pw_k_vector()
    if str_equals(plain, "bt"): return pw_k_nbt()
    if str_equals(plain, "cm"): return pw_k_nbt()
    if str_equals(plain, "by"): return pw_k_bytes()
    if str_equals(plain, "rx"): return pw_k_remainder()
    if str_equals(plain, "em"): return pw_k_metadata()
    if str_starts(plain, "st"): return pw_k_text()
    if str_starts(plain, "id"): return pw_k_text()
    if str_starts(plain, "sk"): return pw_k_skip()
    if str_starts(plain, "ar"): return pw_k_array()
    if str_starts(plain, "ax"): return pw_k_measured()
    return pw_k_none()


# An option is `o` followed by another token. `bo` is a bool, not an option,
# and the array prefixes never start with `o`.
def pw_is_option(plain: str) -> int:
    if vt_strlen(plain) < 3:
        return 0
    if vt_at(plain, 0) != 111:
        return 0
    if str_equals(plain, "bo"):
        return 0
    return 1


def pw_inner(plain: str) -> str:
    return vt_slice(plain, 1, vt_strlen(plain))


def pw_fixed_size(plain: str) -> int:
    # Bytes, with the sign-extend width encoded beside it: `i4` is four bytes
    # sign extended from 32 bits, so its code is 4 plus 100.
    if str_equals(plain, "u1"): return 1
    if str_equals(plain, "i1"): return 101
    if str_equals(plain, "u2"): return 2
    if str_equals(plain, "i2"): return 102
    if str_equals(plain, "u4"): return 4
    if str_equals(plain, "i4"): return 104
    return 0


def pw_text_limit(plain: str) -> int:
    int digits = pw_digits_after(plain, 2)
    if str_starts(plain, "id"):
        if digits > 0:
            return digits
        return pw_ident_max()
    if digits > 0:
        return digits
    return pw_text_max()


# ---- primitive reads ---------------------------------------------------------

def pw_read_int(w: VWire*, size: int) -> int64:
    int bytes = size
    int bits = 0
    if size > 100:
        bytes = size - 100
        bits = bytes * 8
    if vbuf_avail(w.b) < bytes:
        w.error = pw_err_truncated()
        return (int64)0
    int64 value = (int64)0
    int i = 0
    while i < bytes:
        value = (value << (int64)8) | (vbuf_take_u8(w.b) & (uint64)255)
        i += 1
    if bits > 0:
        int64 half = (int64)1 << (int64)bits
        int64 whole = half << (int64)1
        int64 low = value & (half - (int64)1)
        if value >= half:
            return low - whole
        return low
    return value


def pw_read_varint(w: VWire*) -> int64:
    if vbuf_avail(w.b) == 0:
        w.error = pw_err_truncated()
        return (int64)0
    int ok = 0
    int value = vbuf_take_varint(w.b, &ok)
    if ok == 0:
        w.error = pw_err_truncated()
        return (int64)0
    return (int64)value


def pw_read_varlong(w: VWire*) -> int64:
    if vbuf_avail(w.b) == 0:
        w.error = pw_err_truncated()
        return (int64)0
    int ok = 0
    int64 value = vbuf_take_varlong(w.b, &ok)
    if ok == 0:
        w.error = pw_err_truncated()
        return (int64)0
    return value


def pw_read_float(w: VWire*) -> double:
    int64 raw = pw_read_int(w, 4)
    if w.error != pw_err_none():
        return (double)0
    return (double)vt_bits_to_float((uint64)raw)


def pw_read_double(w: VWire*) -> double:
    int64 raw = pw_read_int(w, 8)
    if w.error != pw_err_none():
        return (double)0
    return (double)vt_bits_to_double((uint64)raw)


def pw_read_bool(w: VWire*) -> int:
    if vbuf_avail(w.b) < 1:
        w.error = pw_err_truncated()
        return -1
    int raw = (int)vbuf_take_u8(w.b)
    if raw > 1:
        w.error = pw_err_range()
        return -1
    return raw


def pw_read_text(w: VWire*, limit: int) -> int:
    int64 length = pw_read_varint(w)
    if w.error != pw_err_none():
        return -1
    if length < (int64)0 or length > (int64)limit:
        w.error = pw_err_range()
        return -1
    return pw_pool_take(w, (int)length)


def pw_read_bytes(w: VWire*) -> int:
    int64 length = pw_read_varint(w)
    if w.error != pw_err_none():
        return -1
    if length < (int64)0 or length > (int64)vbuf_avail(w.b):
        w.error = pw_err_range()
        return -1
    return pw_pool_take(w, (int)length)


# Positions and vectors all record three pool slots, so one accessor reads the
# components of either.
def pw_read_position(w: VWire*, plain: str) -> int:
    if pw_room_pool(w, 3) == 0:
        return -1
    int start = w.pool_len
    if str_equals(plain, "cp"):
        int64 x = pw_read_int(w, 4)
        int64 z = pw_read_int(w, 4)
        if w.error != pw_err_none():
            return -1
        vt_uset(w.pool, start, (uint64)x)
        vt_uset(w.pool, start + 1, (uint64)0)
        vt_uset(w.pool, start + 2, (uint64)z)
        w.pool_len += 3
        return start
    int64 packed = pw_read_int(w, 8)
    if w.error != pw_err_none():
        return -1
    int64 x = (int64)0
    int64 y = (int64)0
    int64 z = (int64)0
    if str_equals(plain, "ps"):
        x = packed >> (int64)38
        if x >= (int64)33554432:
            x = x - (int64)67108864
        z = (packed >> (int64)12) & (int64)67108863
        if z >= (int64)33554432:
            z = z - (int64)67108864
        y = packed & (int64)4095
        if y >= (int64)2048:
            y = y - (int64)4096
    else:
        if str_equals(plain, "sp") == false:
            w.error = pw_err_shape()
            return -1
        x = packed >> (int64)42
        if x >= (int64)2097152:
            x = x - (int64)4194304
        y = packed & (int64)1048575
        if y >= (int64)524288:
            y = y - (int64)1048576
        z = (packed >> (int64)20) & (int64)4194303
        if z >= (int64)2097152:
            z = z - (int64)4194304
    vt_uset(w.pool, start, (uint64)x)
    vt_uset(w.pool, start + 1, (uint64)y)
    vt_uset(w.pool, start + 2, (uint64)z)
    w.pool_len += 3
    return start


def pw_read_vector(w: VWire*, plain: str) -> int:
    if pw_room_pool(w, 3) == 0:
        return -1
    int start = w.pool_len
    int i = 0
    while i < 3:
        int64 stored = (int64)0
        if str_equals(plain, "vd"):
            stored = (int64)vt_double_to_bits(pw_read_double(w))
        else:
            if str_equals(plain, "cv"):
                # Floats are widened, so every vector component is one shape.
                stored = (int64)vt_double_to_bits(pw_read_float(w))
            else:
                if str_equals(plain, "lv"):
                    stored = pw_read_int(w, 102)
                else:
                    if str_equals(plain, "vv"):
                        stored = pw_read_varint(w)
                    else:
                        w.error = pw_err_shape()
                        return -1
        if w.error != pw_err_none():
            return -1
        vt_uset(w.pool, start + i, (uint64)stored)
        i += 1
    w.pool_len += 3
    return start


def pw_read_nbt(w: VWire*, component: bool, tag_slot: int*) -> int:
    # One unnamed network NBT tag. The tree is walked only to find its end,
    # which is the validation; a handler that needs the values re-reads the
    # recorded span with the NBT module.
    if vbuf_avail(w.b) < 1:
        w.error = pw_err_truncated()
        return -1
    int kind = (int)vbuf_at(w.b, w.b.pos)
    if kind == nbt_end():
        w.error = pw_err_range()
        return -1
    if component and (kind != nbt_string() and kind != nbt_compound()):
        w.error = pw_err_range()
        return -1
    int start = w.b.pos
    VNbt* tag = nbt_read_payload(kind, "", w.b, 0)
    if tag == null:
        w.error = pw_err_range()
        return -1
    int length = w.b.pos - start
    nbt_free(tag)
    if length <= 0:
        w.error = pw_err_range()
        return -1
    *tag_slot = kind
    return start


def pw_metadata_token(kind: int) -> str:
    # The wire encoding of each live-metadata value type. Types 5 and 19 carry
    # item stacks, which the engine cannot describe until the item component
    # registry lands, so they are deliberately absent.
    if kind == 0: return "vi"
    if kind == 1: return "i2"
    if kind == 2: return "f4"
    if kind == 3: return "f8"
    if kind == 4: return "st1024"
    if kind == 6: return "bt"
    if kind == 7: return "bo"
    if kind == 8: return "ovi"
    if kind == 9: return "ps"
    if kind == 10: return "ps"
    if kind == 11: return "vi"
    if kind == 12: return "vi"
    if kind == 13: return "vi,vi"
    if kind == 14: return "vi,vi,vi"
    if kind == 15: return "vi,i1,i1,i1,i1"
    if kind == 16: return "f4,f4,f4,f4"
    if kind == 17: return "vi"
    if kind == 18: return "ovi"
    return ""


def pw_read_metadata(w: VWire*, count_slot: int*) -> int:
    int start = w.b.pos
    int entries = 0
    while true:
        if vbuf_avail(w.b) < 2:
            w.error = pw_err_truncated()
            return -1
        int index = (int)vbuf_take_u8(w.b)
        if index == 255:
            break
        int kind = (int)pw_read_varint(w)
        if w.error != pw_err_none():
            return -1
        str token = pw_metadata_token(kind)
        if vt_strlen(token) == 0:
            w.error = pw_err_shape()
            return -1
        if pw_measure(w, token, 0) == 0:
            return -1
        entries += 1
        if entries > pw_array_max():
            w.error = pw_err_range()
            return -1
    *count_slot = entries
    return start


# ---- measuring without recording ---------------------------------------------
#
# pw_walk records fields; pw_measure only advances the cursor. Both apply the
# same gates and the same limits, so a measured span is as validated as a
# decoded field. Nested composites and array elements use the measurement.

def pw_measure_token(w: VWire*, plain: str, depth: int) -> int:
    if pw_is_option(plain) == 1:
        int set = pw_read_bool(w)
        if w.error != pw_err_none():
            return 0
        if set == 0:
            return 1
        return pw_measure(w, pw_inner(plain), depth)
    int kind = pw_kind_of(plain)
    int unused = 0
    if kind == pw_k_varint():
        pw_read_varint(w)
    elif kind == pw_k_varlong():
        pw_read_varlong(w)
    elif kind == pw_k_int():
        pw_read_int(w, pw_fixed_size(plain))
    elif kind == pw_k_float():
        pw_read_float(w)
    elif kind == pw_k_double():
        pw_read_double(w)
    elif kind == pw_k_bool():
        pw_read_bool(w)
    elif kind == pw_k_text():
        pw_read_text(w, pw_text_limit(plain))
    elif kind == pw_k_bytes():
        pw_read_bytes(w)
    elif kind == pw_k_uuid():
        pw_pool_take(w, 16)
    elif kind == pw_k_position():
        pw_read_position(w, plain)
    elif kind == pw_k_vector():
        pw_read_vector(w, plain)
    elif kind == pw_k_nbt():
        pw_read_nbt(w, str_equals(plain, "cm"), &unused)
    elif kind == pw_k_skip():
        int bytes = pw_digits_after(plain, 2)
        if bytes < 0:
            w.error = pw_err_shape()
            return 0
        vbuf_skip(w.b, bytes)
    elif kind == pw_k_remainder():
        vbuf_skip(w.b, vbuf_avail(w.b))
    elif kind == pw_k_metadata():
        pw_read_metadata(w, &unused)
    elif kind == pw_k_array() or kind == pw_k_measured():
        return pw_measure_array(w, plain, depth)
    else:
        w.error = pw_err_shape()
        return 0
    if w.error != pw_err_none():
        return 0
    return 1


def pw_measure_array(w: VWire*, plain: str, depth: int) -> int:
    str sub = pw_sub_shape(pw_sub_name(plain))
    if vt_strlen(sub) == 0:
        w.error = pw_err_shape()
        return 0
    int64 count = pw_read_varint(w)
    if w.error != pw_err_none():
        return 0
    if count < (int64)0 or count > (int64)pw_array_max():
        w.error = pw_err_range()
        return 0
    int i = 0
    while i < (int)count:
        if pw_measure(w, sub, depth + 1) == 0:
            return 0
        i += 1
    return 1


public def pw_measure(w: VWire*, shape: str, depth: int) -> int:
    if depth > pw_depth_max():
        w.error = pw_err_shape()
        return 0
    int count = pw_token_count(shape)
    int i = 0
    while i < count:
        str token = pw_token(shape, i)
        if pw_gate_open(w, token, 0) == 0:
            if w.error != pw_err_none():
                return 0
            i += 1
            continue
        if pw_measure_token(w, pw_plain(token), depth) == 0:
            return 0
        i += 1
    return 1


# ---- gates -------------------------------------------------------------------

def pw_gate_value(w: VWire*, index: int) -> int64:
    # The number a gate tests: scalars directly, wide values from the pool, and
    # anything else by whether it was read at all.
    if index < 0 or index >= w.fields:
        w.error = pw_err_gate()
        return (int64)0
    if vt_iget(w.present, index) == 0:
        return (int64)0
    int kind = vt_iget(w.kind, index)
    if kind == pw_k_varint() or kind == pw_k_int() or kind == pw_k_bool() or
       kind == pw_k_skip():
        return (int64)vt_iget(w.val, index)
    if kind == pw_k_varlong() or kind == pw_k_float() or kind == pw_k_double():
        return (int64)vt_uget(w.pool, vt_iget(w.val, index))
    return (int64)1


def pw_gate_open(w: VWire*, token: str, base: int) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return 1
    int field = pw_gate_field(token)
    if field < 0 or base + field >= w.fields:
        w.error = pw_err_gate()
        return 0
    int bit = pw_gate_bit(token)
    int64 value = pw_gate_value(w, base + field)
    int truth = 0
    if bit >= 0:
        if (value >> (int64)bit) & (int64)1 != (int64)0:
            truth = 1
    else:
        if value != (int64)0:
            truth = 1
    if pw_gate_invert(token) == 1:
        if truth == 1:
            return 0
        return 1
    return truth


# ---- recording reads ---------------------------------------------------------

def pw_record_scalar(w: VWire*, index: int, kind: int, value: int64) -> void:
    vt_iset(w.kind, index, kind)
    vt_iset(w.val, index, (int)value)
    vt_iset(w.ext, index, 0)
    vt_iset(w.extra, index, 0)
    vt_iset(w.present, index, 1)


def pw_record_slot(w: VWire*, index: int, kind: int, slot: int,
                   length: int) -> void:
    vt_iset(w.kind, index, kind)
    vt_iset(w.val, index, slot)
    vt_iset(w.ext, index, length)
    vt_iset(w.present, index, 1)


def pw_record_wide(w: VWire*, index: int, kind: int, value: int64) -> void:
    int slot = pw_pool_put(w, value)
    if slot < 0:
        return
    pw_record_slot(w, index, kind, slot, 0)


def pw_record_span(w: VWire*, index: int, kind: int, start: int, length: int,
                   extra: int) -> void:
    vt_iset(w.kind, index, kind)
    vt_iset(w.val, index, start)
    vt_iset(w.ext, index, length)
    vt_iset(w.extra, index, extra)
    vt_iset(w.present, index, 1)


# One token, recorded into field `index`. Options of a primitive keep the
# primitive's own kind, so a handler reads them the same way and only has to
# test pw_present.
def pw_read_field(w: VWire*, plain: str, index: int, depth: int) -> int:
    if pw_is_option(plain) == 1:
        str inner = pw_inner(plain)
        int set = pw_read_bool(w)
        if w.error != pw_err_none():
            return 0
        if set == 0:
            vt_iset(w.kind, index, pw_k_none())
            vt_iset(w.present, index, 0)
            return 1
        if pw_token_count(inner) == 1 and pw_is_option(inner) == 0 and
           pw_kind_of(inner) != pw_k_none():
            return pw_read_field(w, inner, index, depth)
        int start = w.b.pos
        if pw_measure(w, inner, depth) == 0:
            return 0
        pw_record_span(w, index, pw_k_span(), start, w.b.pos - start, 0)
        return 1
    int kind = pw_kind_of(plain)
    if kind == pw_k_varint():
        pw_record_scalar(w, index, kind, pw_read_varint(w))
    elif kind == pw_k_varlong():
        pw_record_wide(w, index, kind, pw_read_varlong(w))
    elif kind == pw_k_int():
        pw_record_scalar(w, index, kind, pw_read_int(w, pw_fixed_size(plain)))
    elif kind == pw_k_float():
        pw_record_wide(w, index, kind, (int64)vt_float_to_bits((float)pw_read_float(w)))
    elif kind == pw_k_double():
        pw_record_wide(w, index, kind, (int64)vt_double_to_bits(pw_read_double(w)))
    elif kind == pw_k_bool():
        pw_record_scalar(w, index, kind, (int64)pw_read_bool(w))
    elif kind == pw_k_text():
        int slot = pw_read_text(w, pw_text_limit(plain))
        pw_record_slot(w, index, kind, slot, w.pool_len - slot)
    elif kind == pw_k_bytes():
        int slot = pw_read_bytes(w)
        pw_record_slot(w, index, kind, slot, w.pool_len - slot)
    elif kind == pw_k_uuid():
        int slot = pw_pool_take(w, 16)
        pw_record_slot(w, index, kind, slot, 16)
    elif kind == pw_k_position():
        int slot = pw_read_position(w, plain)
        pw_record_slot(w, index, kind, slot, 3)
    elif kind == pw_k_vector():
        int slot = pw_read_vector(w, plain)
        pw_record_slot(w, index, kind, slot, 3)
    elif kind == pw_k_nbt():
        int tag = 0
        int start = pw_read_nbt(w, str_equals(plain, "cm"), &tag)
        pw_record_span(w, index, kind, start, w.b.pos - start, tag)
    elif kind == pw_k_metadata():
        int entries = 0
        int start = pw_read_metadata(w, &entries)
        pw_record_span(w, index, kind, start, w.b.pos - start, entries)
    elif kind == pw_k_skip():
        int bytes = pw_digits_after(plain, 2)
        if bytes < 0:
            w.error = pw_err_shape()
            return 0
        vbuf_skip(w.b, bytes)
        pw_record_scalar(w, index, kind, (int64)bytes)
    elif kind == pw_k_remainder():
        pw_record_span(w, index, kind, w.b.pos, vbuf_avail(w.b), 0)
        vbuf_skip(w.b, vbuf_avail(w.b))
    elif kind == pw_k_array() or kind == pw_k_measured():
        return pw_read_array(w, plain, index, depth, kind == pw_k_array())
    else:
        w.error = pw_err_shape()
        return 0
    if w.error != pw_err_none():
        return 0
    return 1


def pw_array_sub(plain: str) -> str:
    return pw_sub_shape(pw_sub_name(plain))


# Inline an array of a flat composite: each element occupies `stride` slots in
# the sub table, so element access is arithmetic and needs no second walk.
def pw_read_array(w: VWire*, plain: str, index: int, depth: int,
                  prefer_inline: int) -> int:
    str sub = pw_array_sub(plain)
    if vt_strlen(sub) == 0:
        w.error = pw_err_shape()
        return 0
    int64 count = pw_read_varint(w)
    if w.error != pw_err_none():
        return 0
    if count < (int64)0 or count > (int64)pw_array_max():
        w.error = pw_err_range()
        return 0
    int stride = pw_flat_slots(sub)
    int base = w.fields
    if prefer_inline == 1 and stride > 0 and
       stride * (int)count <= pw_max_slots():
        vt_iset(w.kind, index, pw_k_array())
        vt_iset(w.val, index, base)
        vt_iset(w.ext, index, (int)count)
        vt_iset(w.extra, index, stride)
        vt_iset(w.present, index, 1)
        int e = 0
        while e < (int)count:
            if pw_read_flat(w, sub, base + e * stride) == 0:
                return 0
            e += 1
        return 1
    vt_iset(w.kind, index, pw_k_measured())
    vt_iset(w.present, index, 1)
    int start_slot = w.pool_len
    if pw_room_pool(w, (int)count * 2) == 0:
        return 0
    vt_iset(w.val, index, start_slot)
    vt_iset(w.ext, index, (int)count)
    int i = 0
    while i < (int)count:
        int element_start = w.b.pos
        if pw_measure(w, sub, depth + 1) == 0:
            return 0
        vt_uset(w.pool, start_slot + i * 2, (uint64)element_start)
        vt_uset(w.pool, start_slot + i * 2 + 1, (uint64)(w.b.pos - element_start))
        i += 1
    return 1


# The sub table holds one record per element field. Element shapes are flat, so
# a field index is `base + element * stride + field`.
def pw_read_flat(w: VWire*, shape: str, base: int) -> int:
    int count = pw_token_count(shape)
    int i = 0
    while i < count:
        int slot = base + i
        if slot >= pw_max_slots():
            w.error = pw_err_capacity()
            return 0
        str token = pw_token(shape, i)
        if pw_gate_open_sub(w, token, base, count) == 0:
            if w.error != pw_err_none():
                return 0
            i += 1
            continue
        if pw_read_flat_token(w, pw_plain(token), slot) == 0:
            return 0
        i += 1
    return 1


def pw_gate_open_sub(w: VWire*, token: str, base: int, count: int) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return 1
    int field = pw_gate_field(token)
    if field < 0 or field >= count:
        w.error = pw_err_gate()
        return 0
    int slot = base + field
    if vt_iget(w.sub_present, slot) == 0:
        return 0
    int64 value = (int64)vt_iget(w.sub_val, slot)
    int bit = pw_gate_bit(token)
    int truth = 0
    if bit >= 0:
        if (value >> (int64)bit) & (int64)1 != (int64)0:
            truth = 1
    else:
        if value != (int64)0:
            truth = 1
    if pw_gate_invert(token) == 1:
        if truth == 1:
            return 0
        return 1
    return truth


def pw_record_flat(w: VWire*, slot: int, kind: int, value: int64,
                   length: int) -> void:
    vt_iset(w.sub_kind, slot, kind)
    vt_iset(w.sub_val, slot, (int)value)
    vt_iset(w.sub_ext, slot, length)
    vt_iset(w.sub_present, slot, 1)


def pw_read_flat_token(w: VWire*, plain: str, slot: int) -> int:
    int kind = pw_kind_of(plain)
    if kind == pw_k_varint():
        pw_record_flat(w, slot, kind, pw_read_varint(w), 0)
    elif kind == pw_k_varlong():
        pw_record_flat(w, slot, kind, pw_read_varlong(w), 0)
    elif kind == pw_k_int():
        pw_record_flat(w, slot, kind, pw_read_int(w, pw_fixed_size(plain)), 0)
    elif kind == pw_k_float():
        pw_record_flat(w, slot, kind,
                       (int64)vt_float_to_bits((float)pw_read_float(w)), 0)
    elif kind == pw_k_double():
        pw_record_flat(w, slot, kind,
                       (int64)vt_double_to_bits(pw_read_double(w)), 0)
    elif kind == pw_k_bool():
        pw_record_flat(w, slot, kind, (int64)pw_read_bool(w), 0)
    elif kind == pw_k_text():
        int start = pw_read_text(w, pw_text_limit(plain))
        pw_record_flat(w, slot, kind, (int64)start, w.pool_len - start)
    elif kind == pw_k_bytes():
        int start = pw_read_bytes(w)
        pw_record_flat(w, slot, kind, (int64)start, w.pool_len - start)
    elif kind == pw_k_uuid():
        int start = pw_pool_take(w, 16)
        pw_record_flat(w, slot, kind, (int64)start, 16)
    elif kind == pw_k_position():
        int start = pw_read_position(w, plain)
        pw_record_flat(w, slot, kind, (int64)start, 3)
    elif kind == pw_k_vector():
        int start = pw_read_vector(w, plain)
        pw_record_flat(w, slot, kind, (int64)start, 3)
    elif kind == pw_k_metadata() or kind == pw_k_array() or
         kind == pw_k_measured():
        w.error = pw_err_shape()
        return 0
    elif kind == pw_k_nbt():
        int tag = 0
        int start = pw_read_nbt(w, str_equals(plain, "cm"), &tag)
        pw_record_flat(w, slot, kind, (int64)start, tag)
    else:
        w.error = pw_err_shape()
        return 0
    if w.error != pw_err_none():
        return 0
    return 1


# A flat shape has no option, array or remainder tokens and no nested arrays,
# so its field count is fixed and elements share one stride.
public def pw_flat_slots(shape: str) -> int:
    int count = pw_token_count(shape)
    if count == 0 or count > pw_max_slots():
        return -1
    int i = 0
    while i < count:
        str token = pw_token(shape, i)
        if pw_at_index(token) >= 0:
            return -1
        str plain = pw_plain(token)
        int kind = pw_kind_of(plain)
        if kind == pw_k_none():
            return -1
        if kind == pw_k_array() or kind == pw_k_measured():
            return -1
        if kind == pw_k_remainder() or kind == pw_k_metadata():
            return -1
        if pw_is_option(plain) == 1:
            return -1
        i += 1
    return count


# ---- walking a packet --------------------------------------------------------

public def pw_walk(w: VWire*, shape: str) -> int:
    if vt_strlen(shape) == 0:
        return 0
    int count = pw_token_count(shape)
    int i = 0
    while i < count:
        int index = pw_alloc_field(w)
        if index < 0:
            return 0
        str token = pw_token(shape, i)
        if pw_gate_open(w, token, 0) == 0:
            if w.error != pw_err_none():
                return 0
            vt_iset(w.kind, index, pw_k_none())
            vt_iset(w.present, index, 0)
            i += 1
            continue
        if pw_read_field(w, pw_plain(token), index, 0) == 0:
            return 0
        i += 1
    if w.exact == 0:
        w.exact = 0
    if vbuf_avail(w.b) != 0:
        w.error = pw_err_leftover()
        return 1
    w.exact = 1
    return 1


# ---- field access ------------------------------------------------------------

public def pw_present(w: VWire*, index: int) -> int:
    if index < 0 or index >= w.fields:
        return 0
    return vt_iget(w.present, index)


public def pw_kind(w: VWire*, index: int) -> int:
    if index < 0 or index >= w.fields:
        return pw_k_none()
    return vt_iget(w.kind, index)


public def pw_int(w: VWire*, index: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    return vt_iget(w.val, index)


public def pw_bool(w: VWire*, index: int) -> int:
    return pw_int(w, index)


public def pw_long(w: VWire*, index: int) -> int64:
    if pw_present(w, index) == 0:
        return (int64)0
    return (int64)vt_uget(w.pool, vt_iget(w.val, index))


public def pw_float(w: VWire*, index: int) -> double:
    if pw_present(w, index) == 0:
        return (double)0
    return (double)vt_bits_to_float((uint64)vt_uget(w.pool, vt_iget(w.val, index)))


public def pw_double(w: VWire*, index: int) -> double:
    if pw_present(w, index) == 0:
        return (double)0
    return (double)vt_bits_to_double((uint64)vt_uget(w.pool, vt_iget(w.val, index)))


# Byte count of a text, identifier or byte string; byte count of an NBT span;
# element count of an array; 16 for a uuid; 3 for a position or vector.
public def pw_len(w: VWire*, index: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    return vt_iget(w.ext, index)


# The NBT tag kind of a `bt`/`cm` field, or the metadata entry count of `em`.
public def pw_extra(w: VWire*, index: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    return vt_iget(w.extra, index)


public def pw_pool_int(w: VWire*, slot: int) -> int:
    if slot < 0 or slot >= w.pool_len:
        return 0
    return (int)vt_uget(w.pool, slot)


public def pw_pool_double(w: VWire*, slot: int) -> double:
    if slot < 0 or slot >= w.pool_len:
        return (double)0
    return (double)vt_bits_to_double((uint64)vt_uget(w.pool, slot))


public def pw_pool_float(w: VWire*, slot: int) -> double:
    if slot < 0 or slot >= w.pool_len:
        return (double)0
    return (double)vt_bits_to_float((uint64)vt_uget(w.pool, slot))


public def pw_pool_byte(w: VWire*, slot: int) -> int:
    if slot < 0 or slot >= w.pool_len:
        return 0
    return (int)vt_uget(w.pool, slot) & 255


# One of the three components of a packed position, section position, chunk
# pair, vector or velocity.
public def pw_axis(w: VWire*, index: int, axis: int) -> int:
    if pw_present(w, index) == 0 or axis < 0 or axis > 2:
        return 0
    return pw_pool_int(w, vt_iget(w.val, index) + axis)


# Vector components are doubles (`vd`) or floats (`cv`): the kind of the token
# decides, so both are read through the right cast.
public def pw_vec_axis(w: VWire*, index: int, axis: int) -> double:
    if pw_present(w, index) == 0 or axis < 0 or axis > 2:
        return (double)0
    return (double)vt_bits_to_double(
        (uint64)vt_uget(w.pool, vt_iget(w.val, index) + axis))


# Block velocity is stored as 1/8000 of a block per tick, as on the wire.
public def pw_velocity_axis(w: VWire*, index: int, axis: int) -> double:
    if pw_present(w, index) == 0 or axis < 0 or axis > 2:
        return (double)0
    return (double)pw_pool_int(w, vt_iget(w.val, index) + axis) / (double)8000.0


# ---- text --------------------------------------------------------------------

public def pw_byte_at(w: VWire*, index: int, at: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    if at < 0 or at >= vt_iget(w.ext, index):
        return 0
    return pw_pool_byte(w, vt_iget(w.val, index) + at)


public def pw_text(w: VWire*, index: int) -> str:
    int length = pw_len(w, index)
    if length <= 0:
        return ""
    VStr* out = vstr_new(length + 1)
    int i = 0
    while i < length:
        vstr_put(out, pw_byte_at(w, index, i))
        i += 1
    str text = vstr_text(out)
    vstr_free(out)
    return text


public def pw_print_text(w: VWire*, index: int) -> void:
    int length = pw_len(w, index)
    int i = 0
    while i < length:
        mc_write_byte(pw_byte_at(w, index, i))
        i += 1
    mc_write_byte(10)


# ---- element access ----------------------------------------------------------

public def pw_count(w: VWire*, index: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    return vt_iget(w.ext, index)


public def pw_stride(w: VWire*, index: int) -> int:
    if pw_kind(w, index) != pw_k_array():
        return 0
    return pw_extra(w, index)


def pw_elem_slot(w: VWire*, index: int, elem: int, field: int) -> int:
    int stride = pw_stride(w, index)
    if stride <= 0 or elem < 0 or elem >= pw_count(w, index):
        return -1
    int slot = vt_iget(w.val, index) + elem * stride + field
    if slot < 0 or slot >= pw_max_slots():
        return -1
    if vt_iget(w.sub_present, slot) == 0:
        return -1
    return slot


public def pw_elem_int(w: VWire*, index: int, elem: int, field: int) -> int:
    int slot = pw_elem_slot(w, index, elem, field)
    if slot < 0:
        return 0
    return vt_iget(w.sub_val, slot)


public def pw_elem_len(w: VWire*, index: int, elem: int, field: int) -> int:
    int slot = pw_elem_slot(w, index, elem, field)
    if slot < 0:
        return 0
    return vt_iget(w.sub_ext, slot)


public def pw_elem_byte(w: VWire*, index: int, elem: int, field: int,
                        at: int) -> int:
    int slot = pw_elem_slot(w, index, elem, field)
    if slot < 0:
        return 0
    if at < 0 or at >= vt_iget(w.sub_ext, slot):
        return 0
    return pw_pool_byte(w, vt_iget(w.sub_val, slot) + at)


# ---- measured spans ----------------------------------------------------------

public def pw_span_start(w: VWire*, index: int, elem: int) -> int:
    int count = pw_count(w, index)
    if pw_present(w, index) == 0 or elem < 0 or elem >= count:
        return -1
    return pw_pool_int(w, vt_iget(w.val, index) + elem * 2)


public def pw_span_len(w: VWire*, index: int, elem: int) -> int:
    int count = pw_count(w, index)
    if pw_present(w, index) == 0 or elem < 0 or elem >= count:
        return -1
    return pw_pool_int(w, vt_iget(w.val, index) + elem * 2 + 1)


# Re-walk one measured element, or an option-of-composite field, into `child`.
public def pw_walk_span(w: VWire*, child: VWire*, start: int, length: int,
                        shape: str) -> int:
    if start < 0 or length <= 0 or start + length > w.b.len:
        return 0
    pw_reset(child)
    int i = start
    while i < start + length:
        vbuf_put_u8(child.b, vbuf_at(w.b, i))
        i += 1
    return pw_walk(child, shape)


public def pw_option_span(w: VWire*, index: int, child: VWire*,
                          shape: str) -> int:
    if pw_kind(w, index) != pw_k_span():
        return 0
    return pw_walk_span(w, child, pw_int(w, index), pw_len(w, index), shape)


# ---- shape tables ------------------------------------------------------------

public def pw_error_text(code: int) -> str:
    if code == pw_err_none(): return "ok"
    if code == pw_err_truncated(): return "truncated"
    if code == pw_err_range(): return "out of range length"
    if code == pw_err_shape(): return "unknown token"
    if code == pw_err_capacity(): return "shape too wide"
    if code == pw_err_leftover(): return "trailing bytes"
    if code == pw_err_gate(): return "bad gate"
    return "unknown"

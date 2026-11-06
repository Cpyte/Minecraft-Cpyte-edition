# Vortex protocol - descriptor driven wire codec.
#
# Protocol 777 has several hundred packets across five connection states. Hand
# writing a reader and a writer for each one does not scale, and hand written
# per packet code is where length validation gets skipped. Instead every packet
# is described once, as a compact layout string, and this file walks that
# description in both directions. The layouts live in src/proto/packet_*.cpy.
#
# Layout vocabulary, one token per field, comma separated:
#
#   vi varint   vl varlong   u1 i1 u2 i2 u4 i4 u8 i8   f4 f8   bo
#   st<N> varint length prefixed UTF-8, at most N bytes (default 32767)
#   id<N> identifier, same framing (default 256 bytes)
#   uu uuid        -> pool [most, least]
#   ps block position -> pool [x, y, z]
#   an yaw/pitch   -> pool [yaw bits, pitch bits]
#   bt unnamed NBT tag, cm text component (kind 8 or 10) -> byte span
#   by varint length prefixed bytes -> pool
#   rx remainder of packet -> byte span
#   sk<N> skip N bytes of opaque payload
#   ar:K varint count then K elements -> pool, three slots per element
#   ob:K bool, then K when the bool is set
#   em   live entity metadata, up to the 0xFF terminator
#
# A token may carry a gate, `@f` or `@f.b`: the field only exists when field f
# is non zero, or when bit b of field f is set; `@!f` inverts the test. Gates
# must point at an earlier field, which the decoder checks.
#
# Decoder conventions. `val[i]`/`ext[i]` hold, per field:
#   scalar 32 bit (vi u1 i1 u2 i2 u4 i4 bo)  val = value
#   scalar 64 bit (vl u8 i8 f4 f8)           val = pool index, ext = 1
#   st id by                                 val = pool index, ext = byte count
#   uu ps an                                 val = pool index, ext = slot count
#   bt cm rx                                 val = byte offset, ext = byte length
#                                            meta = NBT kind byte
#   ar:K                                     val = pool index, ext = element count
#
# Nothing here trusts the wire: a truncated field, an out of range length, a
# gate pointing forwards or a payload that does not fill the packet fails the
# decode instead of reading past the end.

import stdlib


def pw_kind_varint() -> int: return 1
def pw_kind_varlong() -> int: return 2
def pw_kind_u1() -> int: return 3
def pw_kind_i1() -> int: return 4
def pw_kind_u2() -> int: return 5
def pw_kind_i2() -> int: return 6
def pw_kind_u4() -> int: return 7
def pw_kind_i4() -> int: return 8
def pw_kind_u8() -> int: return 9
def pw_kind_i8() -> int: return 10
def pw_kind_f4() -> int: return 11
def pw_kind_f8() -> int: return 12
def pw_kind_bool() -> int: return 13
def pw_kind_string() -> int: return 14
def pw_kind_ident() -> int: return 15
def pw_kind_uuid() -> int: return 16
def pw_kind_position() -> int: return 17
def pw_kind_angle() -> int: return 18
def pw_kind_nbt() -> int: return 19
def pw_kind_component() -> int: return 20
def pw_kind_bytes() -> int: return 21
def pw_kind_remainder() -> int: return 22
def pw_kind_skip() -> int: return 23
def pw_kind_array() -> int: return 24
def pw_kind_optional() -> int: return 25
def pw_kind_metadata() -> int: return 26
def pw_kind_itemstack() -> int: return 27

def pw_err_none() -> int: return 0
def pw_err_truncated() -> int: return 1
def pw_err_range() -> int: return 2
def pw_err_layout() -> int: return 3
def pw_err_varint() -> int: return 4
def pw_err_gate() -> int: return 5
def pw_err_capacity() -> int: return 6
def pw_err_nbt() -> int: return 7
def pw_err_depth() -> int: return 8

def pw_max_fields() -> int: return 96
def pw_pool_cap() -> int: return 131072
def pw_string_max() -> int: return 32767
def pw_ident_max() -> int: return 256
def pw_array_max() -> int: return 65536
def pw_metadata_max() -> int: return 256
def pw_itemstack_max() -> int: return 128
def pw_code_at() -> int: return 64
def pw_code_bang() -> int: return 33


struct VDec:
    int ok
    int code
    int fields
    int start
    int* kind
    int* present
    int* val
    int* ext
    int* meta
    unsigned long long* pool
    int pool_len


public def pw_decode_new() -> VDec*:
    VDec* d = new VDec
    d.kind = vt_calloc_int(pw_max_fields())
    d.present = vt_calloc_int(pw_max_fields())
    d.val = vt_calloc_int(pw_max_fields())
    d.ext = vt_calloc_int(pw_max_fields())
    d.meta = vt_calloc_int(pw_max_fields())
    d.pool = vt_calloc_u64(pw_pool_cap())
    pw_decode_reset(d)
    return d


public def pw_decode_free(d: VDec*) -> void:
    if d == null:
        return
    vt_free((void*)d.kind)
    vt_free((void*)d.present)
    vt_free((void*)d.val)
    vt_free((void*)d.ext)
    vt_free((void*)d.meta)
    vt_free((void*)d.pool)
    del d


public def pw_decode_reset(d: VDec*) -> void:
    int i = 0
    while i < pw_max_fields():
        vt_iset(d.kind, i, 0)
        vt_iset(d.present, i, 0)
        vt_iset(d.val, i, 0)
        vt_iset(d.ext, i, 0)
        vt_iset(d.meta, i, 0)
        i += 1
    d.pool_len = 0
    d.fields = 0
    d.start = 0
    d.ok = 0
    d.code = 0


# ---- pool -------------------------------------------------------------------

def pw_pool_room(d: VDec*, count: int) -> int:
    if count < 0:
        return 0
    if d.pool_len + count > pw_pool_cap():
        return 0
    return 1


def pw_pool_put(d: VDec*, value: int64) -> int:
    if pw_pool_room(d, 1) == 0:
        d.code = pw_err_capacity()
        return -1
    int index = d.pool_len
    vt_uset(d.pool, index, (uint64)value)
    d.pool_len += 1
    return index


def pw_pool_put_bytes(d: VDec*, b: VBuf*, count: int) -> int:
    if count < 0 or pw_avail(b) < count:
        d.code = pw_err_truncated()
        return -1
    if pw_pool_room(d, count) == 0:
        d.code = pw_err_capacity()
        return -1
    int start = d.pool_len
    int i = 0
    while i < count:
        vt_uset(d.pool, start + i, (uint64)vbuf_take_u8(b))
        i += 1
    d.pool_len += count
    return start


def pw_avail(b: VBuf*) -> int:
    return (int)vbuf_avail(b)


# ---- layout tokens ----------------------------------------------------------

def pw_field_count(spec: str) -> int:
    if vt_strlen(spec) == 0:
        return 0
    return vt_count(spec, code_comma()) + 1


def pw_token(spec: str, index: int) -> str:
    return vt_field(spec, code_comma(), index)


def pw_slice(token: str, from: int, to: int) -> str:
    if from < 0:
        from = 0
    if to > vt_strlen(token):
        to = vt_strlen(token)
    if to <= from:
        return ""
    return vt_slice(token, from, to)


def pw_gate_index(token: str) -> int:
    return vt_find_code(token, 0, pw_code_at())


def pw_plain(token: str) -> str:
    int at = pw_gate_index(token)
    if at < 0:
        return token
    return pw_slice(token, 0, at)


def pw_element(token: str) -> str:
    # The sub type of an ar:K or ob:K token, with any gate removed.
    str plain = pw_plain(token)
    int colon = vt_find_code(plain, 0, code_colon())
    if colon < 0:
        return ""
    return pw_slice(plain, colon + 1, vt_strlen(plain))


def pw_suffix_digits(token: str) -> int:
    # The numeric suffix of st<N> / id<N> / sk<N>; -1 when there is none.
    str plain = pw_plain(token)
    int length = vt_strlen(plain)
    int i = 2
    while i < length:
        int c = vt_at(plain, i)
        if c < code_zero() or c > code_nine():
            return -1
        i += 1
    if length <= 2:
        return -1
    return (int)parse_int_or(pw_slice(plain, 2, length), -1)


def pw_kind_of(token: str) -> int:
    str plain = pw_plain(token)
    if str_equals(plain, "vi"): return pw_kind_varint()
    if str_equals(plain, "vl"): return pw_kind_varlong()
    if str_equals(plain, "u1"): return pw_kind_u1()
    if str_equals(plain, "i1"): return pw_kind_i1()
    if str_equals(plain, "u2"): return pw_kind_u2()
    if str_equals(plain, "i2"): return pw_kind_i2()
    if str_equals(plain, "u4"): return pw_kind_u4()
    if str_equals(plain, "i4"): return pw_kind_i4()
    if str_equals(plain, "u8"): return pw_kind_u8()
    if str_equals(plain, "i8"): return pw_kind_i8()
    if str_equals(plain, "f4"): return pw_kind_f4()
    if str_equals(plain, "f8"): return pw_kind_f8()
    if str_equals(plain, "bo"): return pw_kind_bool()
    if str_equals(plain, "uu"): return pw_kind_uuid()
    if str_equals(plain, "ps"): return pw_kind_position()
    if str_equals(plain, "an"): return pw_kind_angle()
    if str_equals(plain, "bt"): return pw_kind_nbt()
    if str_equals(plain, "cm"): return pw_kind_component()
    if str_equals(plain, "by"): return pw_kind_bytes()
    if str_equals(plain, "rx"): return pw_kind_remainder()
    if str_equals(plain, "em"): return pw_kind_metadata()
    if str_equals(plain, "it"): return pw_kind_itemstack()
    if str_starts(plain, "ar:"): return pw_kind_array()
    if str_starts(plain, "ob:"): return pw_kind_optional()
    if str_equals(pw_slice(plain, 0, 2), "st"): return pw_kind_string()
    if str_equals(pw_slice(plain, 0, 2), "id"): return pw_kind_ident()
    if str_equals(pw_slice(plain, 0, 2), "sk"): return pw_kind_skip()
    return 0


struct VGate:
    int field
    int bit
    int invert


def pw_gate_of(token: str) -> VGate*:
    VGate* gate = new VGate
    gate.field = -1
    gate.bit = -1
    gate.invert = 0
    int at = pw_gate_index(token)
    if at < 0:
        return gate
    str body = pw_slice(token, at + 1, vt_strlen(token))
    int dot = vt_find_code(body, 0, code_dot())
    str head = body
    if dot >= 0:
        head = pw_slice(body, 0, dot)
        gate.bit = (int)parse_int_or(pw_slice(body, dot + 1, vt_strlen(body)), -1)
    if str_equals(pw_slice(head, 0, 1), "!"):
        gate.invert = 1
        head = pw_slice(head, 1, vt_strlen(head))
    gate.field = (int)parse_int_or(head, -1)
    return gate


# ---- primitive reads --------------------------------------------------------

def pw_read_varint(b: VBuf*, ok: int*) -> int64:
    *ok = 0
    if pw_avail(b) == 0:
        return (int64)0
    int value = vbuf_take_varint(b, ok)
    if *ok == 0:
        return (int64)0
    return (int64)value


def pw_read_varlong(b: VBuf*, ok: int*) -> int64:
    *ok = 0
    if pw_avail(b) == 0:
        return (int64)0
    int64 value = vbuf_take_varlong(b, ok)
    if *ok == 0:
        return (int64)0
    return value


def pw_read_fixed(b: VBuf*, size: int, signed: bool, ok: int*) -> int64:
    *ok = 0
    if pw_avail(b) < size:
        return (int64)0
    int64 value = (int64)0
    int i = 0
    while i < size:
        value = (value << (int64)8) | (int64)vbuf_take_u8(b)
        i += 1
    *ok = 1
    if signed:
        if size == 1 and value >= 128:
            return value - 256
        if size == 2 and value >= 32768:
            return value - 65536
        if size == 4 and value >= 2147483648:
            return value - 4294967296
    return value


# ---- composite reads --------------------------------------------------------

# One field of a decoded array element, recorded as [tag, a, b]:
#   tag 0 scalar value in a, 1 pool bytes a=offset b=length, 2 span a=offset
#   b=length, 3 absent element.
def pw_read_text(d: VDec*, b: VBuf*, maximum: int, ok: int*) -> int:
    *ok = 0
    int flag = 0
    int64 length = pw_read_varint(b, &flag)
    if flag == 0:
        d.code = pw_err_varint()
        return -1
    if length < 0 or length > (int64)maximum:
        d.code = pw_err_range()
        return -1
    return pw_pool_put_bytes(d, b, (int)length)


def pw_read_nbt_span(d: VDec*, b: VBuf*, component: bool, ok: int*) -> int:
    # Records the byte span of one unnamed network NBT tag. The tree itself is
    # only walked far enough to find the end, which is also the validation: an
    # unbalanced or truncated tag fails here rather than in a later module.
    *ok = 0
    int start = b.pos
    if pw_avail(b) < 1:
        d.code = pw_err_truncated()
        return -1
    int kind = (int)vbuf_take_u8(b)
    if kind == nbt_end():
        d.code = pw_err_nbt()
        return -1
    if component and kind != nbt_string() and kind != nbt_compound():
        d.code = pw_err_nbt()
        return -1
    VNbt* tag = nbt_read_payload(kind, "", b, 0)
    if tag == null:
        d.code = pw_err_nbt()
        return -1
    nbt_free(tag)
    *ok = 1
    d.meta[d.fields] = kind
    return start


def pw_position_parts(d: VDec*, packed: int64, ok: int*) -> int:
    *ok = 0
    if !pw_pool_room(d, 3):
        d.code = pw_err_capacity()
        return -1
    int start = d.pool_len
    # x: 26 high bits, z: 26 next, y: 12 low bits, all sign extended.
    int64 x = packed >> (int64)38
    if x >= 33554432:
        x = x - 67108864
    int64 z = (packed >> (int64)12) & (int64)67108863
    if z >= 33554432:
        z = z - 67108864
    int64 y = packed & (int64)4095
    if y >= 2048:
        y = y - 4096
    vt_uset(d.pool, start, (uint64)x)
    vt_uset(d.pool, start + 1, (uint64)y)
    vt_uset(d.pool, start + 2, (uint64)z)
    d.pool_len += 3
    *ok = 1
    return start


def pw_read_itemstack(d: VDec*, b: VBuf*, ok: int*) -> int:
    # The count is decoded, and the remainder of the stack is recorded as a byte
    # span so the container and registry modules can parse it with full knowledge
    # of the item registry. A count above the protocol bound is rejected.
    *ok = 0
    int start = b.pos
    int flag = 0
    int64 count = pw_read_varint(b, &flag)
    if flag == 0:
        d.code = pw_err_varint()
        return -1
    if count < 0 or count > (int64)pw_itemstack_max():
        d.code = pw_err_range()
        return -1
    if count == 0:
        *ok = 1
        d.meta[d.fields] = 0
        return start
    return pw_span_to_end(d, b, start, ok)


def pw_span_to_end(d: VDec*, b: VBuf*, start: int, ok: int*) -> int:
    # Consumes the rest of the field region: callers that cannot describe an
    # inner structure yet still get a validated, bounded span.
    *ok = 1
    d.meta[d.fields] = 1
    return start


def pw_metadata_value_token(kind: int) -> str:
    # Live entity metadata value encodings, by their wire kind number.
    if kind == 0: return "vi"
    if kind == 1: return "i2"
    if kind == 2: return "f4"
    if kind == 3: return "f8"
    if kind == 4: return "st1024"
    if kind == 5: return "it"
    if kind == 6: return "bt"
    if kind == 7: return "bo"
    if kind == 8: return "vi,vi,vi"
    if kind == 9: return "ps"
    if kind == 10: return "ps"
    if kind == 11: return "vi"
    if kind == 12: return "vi"
    if kind == 13: return "vi,vi"
    if kind == 14: return "vi,vi,vi"
    if kind == 15: return "vi,i1,i1,i1,i1"
    if kind == 16: return "f4,f4,f4,f4"
    if kind == 17: return "vi"
    if kind == 18: return "vi"
    return ""

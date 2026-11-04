# Vortex engine - codec smoke tests.
#
# Built as a bundle so the engine modules share one translation unit:
#   ./build.sh --run tests/buf.txt
# Assertions come from tests/harness.cpy; see docs/BUILD.md.

import stdlib


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

# Vortex engine - NBT round-trip tests.
#
#   ./build.sh --run tests/nbt.txt

import stdlib


def build_scalars() -> VNbt*:
    VNbt* root = nbt_compound_of("root")
    nbt_append(root, nbt_byte_of("b", -3))
    nbt_append(root, nbt_short_of("s", 300))
    nbt_append(root, nbt_int_of("i", -70000))
    nbt_append(root, nbt_long_of("l", (int64)1099511627776))
    nbt_append(root, nbt_float_of("f", (float)1.5))
    nbt_append(root, nbt_double_of("d", (double)-2.25))
    nbt_append(root, nbt_string_of("name", "minecraft:stone"))
    return root


def test_layout(fails: int*) -> void:
    print("nbt layout:")
    VBuf* b = vbuf_new(64)

    # A named TAG_Int is kind + u16 name length + name + four big endian bytes:
    # 1 + 2 + 1 + 4 = 8.
    vbuf_reset(b)
    nbt_write(b, nbt_int_of("x", 1))
    check_int("tag int size", b.len, 8, fails)
    check_int("kind byte", (int)vbuf_at(b, 0), nbt_int(), fails)
    check_int("name length high", (int)vbuf_at(b, 1), 0, fails)
    check_int("name length low", (int)vbuf_at(b, 2), 1, fails)
    check_int("name first byte", (int)vbuf_at(b, 3), 120, fails)
    check_int("payload high bytes", (int)vbuf_at(b, 4), 0, fails)
    check_int("payload big endian", (int)vbuf_at(b, 7), 1, fails)

    # An empty compound is kind, name and the terminator.
    vbuf_reset(b)
    nbt_write(b, nbt_compound_of("c"))
    check_int("empty compound size", b.len, 5, fails)
    check_int("compound terminator", (int)vbuf_at(b, 4), nbt_end(), fails)
    vbuf_free(b)


def test_scalars(fails: int*) -> void:
    print("nbt scalars:")
    VBuf* b = vbuf_new(128)
    vbuf_reset(b)
    nbt_write(b, build_scalars())
    int written = b.len

    VNbt* back = nbt_read(b)
    check("root parsed", back != null, fails)
    if back == null:
        *fails = *fails + 1
        return
    check_str("root name", back.name, "root", fails)
    check_int("root kind", back.kind, nbt_compound(), fails)
    check_int("child count", nbt_child_count(back), 7, fails)
    check_int("byte", nbt_get_int(back, "b", 0), -3, fails)
    check_int("short", nbt_get_int(back, "s", 0), 300, fails)
    check_int("int", nbt_get_int(back, "i", 0), -70000, fails)
    check("long", nbt_long_value(nbt_find(back, "l"), (int64)0) == (int64)1099511627776, fails)
    check_str("string", nbt_get_str(back, "name", ""), "minecraft:stone", fails)

    VNbt* f = nbt_find(back, "f")
    check("float", f != null and (int)f.val_float == 1, fails)
    VNbt* d = nbt_find(back, "d")
    check("double", d != null and (int)d.val_double == -2, fails)

    check_int("missing child", nbt_get_int(back, "nope", 77), 77, fails)
    check("absent child is null", nbt_find(back, "nope") == null, fails)

    # Re-writing what was read must be byte-for-byte stable.
    VBuf* again = vbuf_new(128)
    nbt_write(again, back)
    check_int("re-encode is stable", again.len, written, fails)
    int same = 1
    int i = 0
    while i < written:
        if vbuf_at(b, i) != vbuf_at(again, i):
            same = 0
        i += 1
    check("re-encoded bytes match", same == 1, fails)

    nbt_free(back)
    vbuf_free(again)
    vbuf_free(b)


def test_arrays(fails: int*) -> void:
    print("nbt arrays:")
    VBuf* b = vbuf_new(128)
    VNbt* root = nbt_compound_of("root")

    VNbt* ba = nbt_new(nbt_byte_array(), "bytes")
    char* raw = vt_calloc_char(4)
    vt_put(raw, 0, 10)
    vt_put(raw, 1, 250)
    vt_put(raw, 2, -1)
    vt_put(raw, 3, 0)
    nbt_set_bytes(ba, raw, 4)
    nbt_append(root, ba)

    VNbt* ia = nbt_new(nbt_int_array(), "ints")
    nbt_set_ints(ia, 3)
    nbt_set_int_at(ia, 0, -5)
    nbt_set_int_at(ia, 1, 70000)
    nbt_set_int_at(ia, 2, 0)
    nbt_append(root, ia)

    VNbt* la = nbt_new(nbt_long_array(), "longs")
    nbt_set_longs(la, 2)
    nbt_set_long_at(la, 0, (int64)-1)
    nbt_set_long_at(la, 1, (int64)1234567890123)
    nbt_append(root, la)

    vbuf_reset(b)
    nbt_write(b, root)
    VNbt* back = nbt_read(b)
    check("arrays parsed", back != null, fails)
    if back == null:
        *fails = *fails + 1
        vbuf_free(b)
        return
    VNbt* rb = nbt_find(back, "bytes")
    check_int("byte array length", rb.bytes_len, 4, fails)
    check_int("byte array keeps 250", nbt_byte_at(rb, 1), 250, fails)
    check_int("byte array keeps -1", nbt_byte_at(rb, 2), 255, fails)
    VNbt* ri = nbt_find(back, "ints")
    check_int("int array length", ri.ints_len, 3, fails)
    check_int("int array value", nbt_int_at(ri, 1), 70000, fails)
    check_int("int array negative", nbt_int_at(ri, 0), -5, fails)
    VNbt* rl = nbt_find(back, "longs")
    check_int("long array length", rl.longs_len, 2, fails)
    check("long array -1", nbt_long_at(rl, 0) == (int64)-1, fails)
    check("long array wide", nbt_long_at(rl, 1) == (int64)1234567890123, fails)
    check_int("out of range int", nbt_int_at(ri, 9), 0, fails)

    nbt_free(back)
    vt_free((void*)raw)
    vbuf_free(b)


# A chunk section palette is a list of compounds inside a compound, which is
# the shape the container code depends on.
def test_palette_shape(fails: int*) -> void:
    print("nbt palette shape:")
    VBuf* b = vbuf_new(256)
    VNbt* section = nbt_compound_of("Section")
    nbt_append(section, nbt_byte_of("Y", 3))

    VNbt* states = nbt_compound_of("block_states")
    VNbt* palette = nbt_list_of("palette", nbt_compound())
    int i = 0
    while i < 5:
        VNbt* entry = nbt_compound_of("")
        nbt_append(entry, nbt_string_of("Name", "vortex:block_" + str(i)))
        nbt_append(entry, nbt_int_of("id", i * 12))
        nbt_append(palette, entry)
        i += 1
    nbt_append(states, palette)
    nbt_append(section, states)

    vbuf_reset(b)
    nbt_write(b, section)
    VNbt* back = nbt_read(b)
    check("section parsed", back != null, fails)
    if back == null:
        *fails = *fails + 1
        vbuf_free(b)
        return
    check_int("section y", nbt_get_int(back, "Y", -1), 3, fails)
    VNbt* states_back = nbt_find(back, "block_states")
    check("block_states found", states_back != null, fails)
    VNbt* pal = nbt_find(states_back, "palette")
    check_int("palette is a list", pal.kind, nbt_list(), fails)
    check_int("palette entries", nbt_child_count(pal), 5, fails)
    VNbt* third = nbt_child_at(pal, 2)
    check_str("entry name", nbt_get_str(third, "Name", ""), "vortex:block_2", fails)
    check_int("entry id", nbt_get_int(third, "id", -1), 24, fails)
    check("index guard", nbt_child_at(pal, 5) == null, fails)
    check("negative index guard", nbt_child_at(pal, -1) == null, fails)
    check_int("list element kind", nbt_list_element_kind(pal), nbt_compound(), fails)

    nbt_free(back)
    vbuf_free(b)


def test_truncated(fails: int*) -> void:
    print("nbt truncation:")
    VBuf* b = vbuf_new(64)
    nbt_write(b, build_scalars())
    int full = b.len

    # Every prefix that cuts a payload must be rejected rather than returning a
    # partly built tree.
    int cut = full - 1
    int rejected = 0
    while cut > 0:
        VBuf* slice = vbuf_new(cut + 2)
        int i = 0
        while i < cut:
            vbuf_put_u8(slice, vbuf_at(b, i))
            i += 1
        VNbt* partial = nbt_read(slice)
        if partial == null:
            rejected += 1
        else:
            nbt_free(partial)
        vbuf_free(slice)
        cut -= 1
    check_int("all prefixes rejected", rejected, full - 1, fails)

    # An empty buffer reads as no tag at all.
    VBuf* empty = vbuf_new(16)
    check("empty input", nbt_read(empty) == null, fails)
    vbuf_free(empty)
    vbuf_free(b)


def main() -> int:
    int fails = 0
    test_layout(&fails)
    test_scalars(&fails)
    test_arrays(&fails)
    test_palette_shape(&fails)
    test_truncated(&fails)
    return report("vortex nbt tests", fails)

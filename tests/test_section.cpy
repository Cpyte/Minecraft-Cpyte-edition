# Vortex engine - chunk section tests.
#
#   ./build.sh --run tests/section.txt

import stdlib


# Twenty block states, one in the far corner, eight biomes and a light pattern
# that touches both nibbles of several bytes. The expected arrays record what
# was written, in flat index order.
def fill(s: VSection*, want_block: int*, want_biome: int*, want_light: int*, want_sky: int*) -> void:
    int i = 0
    while i < 20:
        int ax = i % 16
        int ay = i / 16
        int az = (i * 3) % 16
        sec_block_set(s, ax, ay, az, i + 1)
        vt_iset(want_block, sec_block_index(ax, ay, az), i + 1)
        i += 1
    sec_block_set(s, 15, 15, 15, 77)
    vt_iset(want_block, 4095, 77)

    int j = 0
    while j < 8:
        sec_biome_set(s, j % 4, j / 4, j % 4, j + 1)
        vt_iset(want_biome, sec_biome_index(j % 4, j / 4, j % 4), j + 1)
        j += 1

    int k = 0
    while k < 4096:
        int bx = k % 16
        int by = k / 256
        int bz = (k / 16) % 16
        if k % 3 == 0:
            sec_block_light_set(s, bx, by, bz, k % 15)
            vt_iset(want_light, k, k % 15)
        if k % 5 == 0:
            sec_sky_light_set(s, bx, by, bz, (k / 2) % 16)
            vt_iset(want_sky, k, (k / 2) % 16)
        k += 1
    return


def test_index_layout(fails: int*) -> void:
    print("index layout:")
    check_int("block origin", sec_block_index(0, 0, 0), 0, fails)
    check_int("block x", sec_block_index(1, 0, 0), 1, fails)
    check_int("block z", sec_block_index(0, 0, 1), 16, fails)
    check_int("block y", sec_block_index(0, 1, 0), 256, fails)
    check_int("block corner", sec_block_index(15, 15, 15), 4095, fails)
    check_int("biome origin", sec_biome_index(0, 0, 0), 0, fails)
    check_int("biome x", sec_biome_index(1, 0, 0), 1, fails)
    check_int("biome z", sec_biome_index(0, 0, 1), 4, fails)
    check_int("biome y", sec_biome_index(0, 1, 0), 16, fails)
    check_int("biome corner", sec_biome_index(3, 3, 3), 63, fails)


def test_access(fails: int*) -> void:
    print("access:")
    VSection* s = sec_new(-1)
    check_int("empty section", sec_block_at(s, 0, 0, 0), 0, fails)
    check_int("empty biome", sec_biome_at(s, 0, 0, 0), 0, fails)
    sec_block_set(s, 3, 7, 11, 42)
    check_int("stored state", sec_block_at(s, 3, 7, 11), 42, fails)
    check_int("stored at flat index", vcont_at(s.blocks, sec_block_index(3, 7, 11)), 42, fails)
    check_int("neighbour untouched", sec_block_at(s, 3, 7, 12), 0, fails)

    # Out of range coordinates are ignored rather than wrapping into the array.
    sec_block_set(s, 16, 0, 0, 99)
    sec_block_set(s, -1, 0, 0, 99)
    sec_block_set(s, 0, 16, 0, 99)
    sec_block_set(s, 0, 0, 16, 99)
    check_int("state survived rejected writes", sec_block_at(s, 3, 7, 11), 42, fails)
    check_int("origin still empty", sec_block_at(s, 0, 0, 0), 0, fails)
    check_int("out of range read", sec_block_at(s, 16, 0, 0), 0, fails)
    sec_biome_set(s, 4, 0, 0, 99)
    sec_biome_set(s, 0, 0, -1, 99)
    check_int("biome out of range read", sec_biome_at(s, 4, 0, 0), 0, fails)
    check_int("biome origin still empty", sec_biome_at(s, 0, 0, 0), 0, fails)
    sec_free(s)


def test_light_packing(fails: int*) -> void:
    print("light nibbles:")
    char* light = vt_calloc_char(2048)
    sec_light_set(light, 0, 5)
    sec_light_set(light, 1, 11)
    int byte0 = ((int)vt_at(light, 0)) & 255
    check_int("low nibble", byte0 & 15, 5, fails)
    check_int("high nibble", byte0 >> 4, 11, fails)
    check_int("read back even", sec_light_at(light, 0), 5, fails)
    check_int("read back odd", sec_light_at(light, 1), 11, fails)
    sec_light_set(light, 0, 2)
    check_int("pair neighbour kept", sec_light_at(light, 1), 11, fails)
    check_int("pair rewritten", sec_light_at(light, 0), 2, fails)

    sec_light_set(light, 4095, 15)
    int last = ((int)vt_at(light, 2047)) & 255
    check_int("last byte low nibble", last & 15, 0, fails)
    check_int("last byte high nibble", last >> 4, 15, fails)
    check_int("beyond the array", sec_light_at(light, 4096), 0, fails)
    sec_light_set(light, 4096, 9)
    vt_free((void*)light)


def test_uniform_tag(fails: int*) -> void:
    print("uniform section tag:")
    VSection* s = sec_new(4)
    VNbt* root = sec_to_nbt(s, "")
    check_int("root kind", root.kind, nbt_compound(), fails)
    VNbt* blocks = nbt_find(root, "block_states")
    check_int("block states", blocks.kind, nbt_compound(), fails)
    VNbt* palette = nbt_find(blocks, "palette")
    check_int("palette is a list", palette.kind, nbt_list(), fails)
    check_int("one entry", nbt_child_count(palette), 1, fails)
    check_int("entry kind", nbt_list_element_kind(palette), nbt_int(), fails)
    check_int("entry value", nbt_int_value(nbt_child_at(palette, 0), -1), 0, fails)

    # A uniform container records no data words, so the tag carries no array.
    check("no data array", nbt_find(blocks, "data") == null, fails)
    check_int("Y written", nbt_get_int(root, "Y", 99), 4, fails)
    check_int("section index", s.y, 4, fails)
    VNbt* light = nbt_find(root, "AltValues")
    check_int("light kind", light.kind, nbt_long_array(), fails)
    check_int("light words", nbt_long_len(light), 256, fails)
    nbt_free(root)
    sec_free(s)


def test_tag_width(fails: int*) -> void:
    print("palette width in the tag:")
    VSection* s = sec_new(0)
    int i = 0
    while i < 40:
        sec_block_set(s, i % 16, i / 16, (i * 3) % 16, i + 1)
        i += 1
    VNbt* root = sec_to_nbt(s, "")
    VNbt* blocks = nbt_find(root, "block_states")
    VNbt* palette = nbt_find(blocks, "palette")
    VNbt* data = nbt_find(blocks, "data")
    check_int("41 palette entries", nbt_child_count(palette), 41, fails)
    # Forty one slots need six index bits, and six bits over 4096 entries is
    # 410 padded words.
    check_int("6 bits", vcont_bits_for(41, sec_blocks_min_bits()), 6, fails)
    check_int("data words", nbt_long_len(data), 410, fails)
    check("uniform biome has no data", nbt_find(nbt_find(root, "biomes"), "data") == null, fails)
    nbt_free(root)
    sec_free(s)


def test_nbt_round_trip(fails: int*) -> void:
    print("section nbt round trip:")
    int* want_block = vt_calloc_int(4096)
    int* want_biome = vt_calloc_int(64)
    int* want_light = vt_calloc_int(4096)
    int* want_sky = vt_calloc_int(4096)

    VSection* s = sec_new(3)
    fill(s, want_block, want_biome, want_light, want_sky)
    sec_compact(s)

    check_int("block bits", vcont_bits(s.blocks), 5, fails)
    check_int("biome global width", vcont_bits(s.biomes), 7, fails)
    check_int("biome direct mode", vcont_mode(s.biomes), vcont_direct_mode(), fails)
    check_int("block palette", vcont_palette_len(s.blocks), 22, fails)
    check_int("biome direct palette", vcont_palette_len(s.biomes), 0, fails)

    VNbt* root = sec_to_nbt(s, "")
    VBuf* b = vbuf_new(4096)
    nbt_write(b, root)
    int bytes = b.len
    check("section serialised", bytes > 4096, fails)

    VBuf* read_back = vbuf_new(bytes)
    vbuf_put_bytes(read_back, b.data, bytes)
    VNbt* tag = nbt_read(read_back)
    check_int("root read", tag.kind, nbt_compound(), fails)
    VSection* t = sec_from_nbt(tag, 3)
    check("section rebuilt", t != null, fails)
    check_int("y kept", t.y, 3, fails)
    check_int("blocks not uniform again", vcont_is_uniform(t.blocks), 0, fails)

    int bad_blocks = 0
    int bad_light = 0
    int bad_sky = 0
    int k = 0
    while k < 4096:
        if vcont_at(t.blocks, k) != vt_iget(want_block, k):
            bad_blocks += 1
        if sec_light_at(t.block_light, k) != vt_iget(want_light, k):
            bad_light += 1
        if sec_light_at(t.sky_light, k) != vt_iget(want_sky, k):
            bad_sky += 1
        k += 1
    check_int("block mismatches", bad_blocks, 0, fails)
    check_int("block light mismatches", bad_light, 0, fails)
    check_int("sky light mismatches", bad_sky, 0, fails)

    int bad_biomes = 0
    int j = 0
    while j < 64:
        if vcont_at(t.biomes, j) != vt_iget(want_biome, j):
            bad_biomes += 1
        j += 1
    check_int("biome mismatches", bad_biomes, 0, fails)

    # The corner cell and the last column come back through the coordinate
    # accessors as well, which is how the rest of the engine reads a section.
    check_int("corner state", sec_block_at(t, 15, 15, 15), 77, fails)
    check_int("corner light", sec_block_light_at(t, 15, 15, 15), vt_iget(want_light, 4095), fails)

    nbt_free(tag)
    nbt_free(root)
    vbuf_free(read_back)
    vbuf_free(b)
    sec_free(s)
    sec_free(t)
    vt_free((void*)want_block)
    vt_free((void*)want_biome)
    vt_free((void*)want_light)
    vt_free((void*)want_sky)


def main() -> int:
    int fails = 0
    test_index_layout(&fails)
    test_access(&fails)
    test_light_packing(&fails)
    test_uniform_tag(&fails)
    test_tag_width(&fails)
    test_nbt_round_trip(&fails)
    return report("vortex section tests", fails)

# Vortex engine - paletted container tests.
#
#   ./build.sh --run tests/palette.txt

import stdlib


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

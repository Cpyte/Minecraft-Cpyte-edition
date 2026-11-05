import stdlib


def write_local_blocks(b: VBuf*) -> void:
    vbuf_put_u8(b, (uint64)4)
    vbuf_put_varint(b, 2)
    vbuf_put_varint(b, 0)
    vbuf_put_varint(b, 5)
    int i = 0
    while i < 256:
        int64 word = (int64)0
        if i == 0:
            word = (int64)1
        vbuf_put_i64_be(b, word)
        i += 1


def write_global_blocks(b: VBuf*) -> void:
    vbuf_put_u8(b, (uint64)15)
    int i = 0
    while i < 1024:
        uint64 word = (uint64)0
        if i == 0:
            word = (uint64)257 | ((uint64)300 << (uint64)45)
        vbuf_put_i64_be(b, (int64)word)
        i += 1


def write_local_biomes(b: VBuf*) -> void:
    vbuf_put_u8(b, (uint64)1)
    vbuf_put_varint(b, 2)
    vbuf_put_varint(b, 3)
    vbuf_put_varint(b, 7)
    vbuf_put_i64_be(b, (int64)1)


def write_global_biomes(b: VBuf*) -> void:
    vbuf_put_u8(b, (uint64)4)
    int i = 0
    while i < 8:
        uint64 word = (uint64)0
        if i == 0:
            word = (uint64)5 | ((uint64)3 << (uint64)7)
        vbuf_put_i64_be(b, (int64)word)
        i += 1


def test_local_containers(fails: int*) -> void:
    print("wire local palettes:")
    VBuf* b = vbuf_new(4096)
    vbuf_put_i16_be(b, 1)
    write_local_blocks(b)
    write_local_biomes(b)
    b.pos = 0
    int ok = 0
    char* sections = sec_read_wire_sections(b, 1, -4, 15, 7, &ok)
    check_int("decoded local section", ok, 1, fails)
    check("section allocated", sections != null, fails)
    if sections != null:
        VSection* section = (VSection*)vt_ptr_get(sections, 0)
        check_int("section Y", section.y, -4, fails)
        check_int("non-empty count", section.non_empty, 1, fails)
        check_int("local block id", sec_block_at(section, 0, 0, 0), 5, fails)
        check_int("air palette id", sec_block_at(section, 1, 0, 0), 0, fails)
        check_int("local biome id", sec_biome_at(section, 0, 0, 0), 7, fails)
        check_int("other biome id", sec_biome_at(section, 1, 0, 0), 3, fails)
        VWorld* world = vworld_new(2, -4, 1, 16, 7)
        check_int("column stored", vworld_replace_sections(world, -1, 2, sections), 1, fails)
        check_int("negative world coordinate lookup", vworld_block_at(world, -16, -64, 32), 5, fails)
        check_int("world biome lookup", vworld_biome_at(world, -16, -64, 32), 7, fails)
        check_int("column count", vworld_chunk_count(world), 1, fails)
        check_int("column unload", vworld_unload_chunk(world, -1, 2), 1, fails)
        check_int("unloaded block reads as air", vworld_block_at(world, -16, -64, 32), 0, fails)
        vworld_free(world)
    vbuf_free(b)


def test_global_containers(fails: int*) -> void:
    print("wire global palettes:")
    VBuf* b = vbuf_new(9000)
    vbuf_put_i16_be(b, 3)
    write_global_blocks(b)
    write_global_biomes(b)
    b.pos = 0
    int ok = 0
    char* sections = sec_read_wire_sections(b, 1, -4, 15, 7, &ok)
    check_int("decoded global section", ok, 1, fails)
    check("section allocated", sections != null, fails)
    if sections != null:
        VSection* section = (VSection*)vt_ptr_get(sections, 0)
        check_int("global block id", sec_block_at(section, 0, 0, 0), 257, fails)
        check_int("global block id at index 3", sec_block_at(section, 3, 0, 0), 300, fails)
        check_int("global biome id", sec_biome_at(section, 0, 0, 0), 5, fails)
        check_int("second global biome id", sec_biome_at(section, 1, 0, 0), 3, fails)
        check_int("direct block mode", vcont_mode(section.blocks), vcont_direct_mode(), fails)
        check_int("direct biome mode", vcont_mode(section.biomes), vcont_direct_mode(), fails)
        vworld_free_column(sections, 1)
    vbuf_free(b)


def test_truncated_section(fails: int*) -> void:
    print("wire truncation:")
    VBuf* b = vbuf_new(32)
    vbuf_put_i16_be(b, 0)
    vbuf_put_u8(b, (uint64)4)
    b.pos = 0
    int ok = 1
    char* sections = sec_read_wire_sections(b, 1, -4, 15, 7, &ok)
    check_int("truncated section rejected", ok, 0, fails)
    check("no partial section returned", sections == null, fails)
    vbuf_free(b)


def test_dimension_registry(fails: int*) -> void:
    print("dynamic dimension registry:")
    VDimensionRegistry* registry = vdimension_registry_new()
    check_int("overworld registry entry", vdimension_registry_add_dimension(registry, 0, -64, 384), 1, fails)
    check_int("custom dimension registry entry", vdimension_registry_add_dimension(registry, 1, 0, 256), 1, fails)
    check_int("dimension registry complete", vdimension_registry_finish_dimensions(registry, 2), 1, fails)
    check_int("biome count accepted", vdimension_registry_set_biome_count(registry, 70), 1, fails)
    int64[] dimension = vdimension_registry_dimension(registry, 1)
    check_int("dimension minimum section", (int)dimension[1], 0, fails)
    check_int("dimension section count", (int)dimension[2], 16, fails)
    check_int("custom biome width", registry.biome_global_bits, 7, fails)
    check_int("unaligned dimension rejected", vdimension_registry_add_dimension(registry, 2, -63, 256), 0, fails)

    VWorld* world = vworld_new(2, 0, 1, registry.block_global_bits,
                               registry.biome_global_bits)
    check_int("world dimension updated", vworld_set_dimension(
        world, (int)dimension[1], (int)dimension[2],
        registry.block_global_bits, registry.biome_global_bits), 1, fails)
    check_int("world section origin", world.min_section, 0, fails)
    check_int("world section count", world.section_count, 16, fails)
    vworld_free(world)
    vdimension_registry_free(registry)


def main() -> int:
    int fails = 0
    test_local_containers(&fails)
    test_global_containers(&fails)
    test_truncated_section(&fails)
    test_dimension_registry(&fails)
    return report("wire chunk tests", fails)

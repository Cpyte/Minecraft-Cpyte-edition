# Vortex engine - Anvil region tests.
#
#   ./build.sh --run tests/anvil.txt
#
# Region files are written under build/ while the suite runs, so nothing is
# committed and each run starts from a directory the save code creates itself.

import stdlib


public def anvil_test_base() -> str:
    return "build/anvil_test"


# One column with a block, a light level and a biome in a pattern that reaches
# both halves of every palette stride. `seed` shifts the values so two chunks
# in the same region cannot share a byte pattern by accident.
def anvil_fill_column(world: VWorld*, chunk_x: int, chunk_z: int,
                      seed: int) -> void:
    char* sections = vt_calloc_ptrs(world.section_count)
    int i = 0
    while i < world.section_count:
        vt_ptr_set(sections, i, (void*)sec_new(world.min_section + i))
        i = i + 1
    vworld_replace_sections(world, chunk_x, chunk_z, sections)

    i = 0
    while i < 24:
        int local_x = i % 16
        int section = i / 16
        int local_z = (i * 5) % 16
        VSection* s = vworld_section(world, chunk_x, chunk_z, world.min_section + section)
        if s != null:
            sec_block_set(s, local_x, 3, local_z, 40 + i + seed * 100)
            sec_block_light_set(s, local_x, 3, local_z, (i % 14) + 1)
            sec_biome_set(s, local_x / 4, 1, local_z / 4, (i % 9) + 1)
        i = i + 1

    VSection* top = vworld_section(world, chunk_x, chunk_z,
                                   world.min_section + world.section_count - 1)
    if top != null:
        sec_block_set(top, 15, 15, 15, 900 + seed)
    return


def anvil_expect_column(world: VWorld*, chunk_x: int, chunk_z: int, seed: int,
                        label: str, fails: int*) -> void:
    int blocks_bad = 0
    int light_bad = 0
    int biomes_bad = 0
    int i = 0
    while i < 24:
        int local_x = i % 16
        int section = i / 16
        int local_z = (i * 5) % 16
        int world_x = chunk_x * 16 + local_x
        int world_z = chunk_z * 16 + local_z
        if vworld_block_at(world, world_x, section * 16 + 3, world_z) != 40 + i + seed * 100:
            blocks_bad = blocks_bad + 1
        if vworld_light_at(world, world_x, section * 16 + 3, world_z) != (i % 14) + 1:
            light_bad = light_bad + 1
        if vworld_biome_at(world, world_x, section * 16 + 4, world_z) != (i % 9) + 1:
            biomes_bad = biomes_bad + 1
        i = i + 1
    check_int(label + " block values", blocks_bad, 0, fails)
    check_int(label + " light values", light_bad, 0, fails)
    check_int(label + " biome values", biomes_bad, 0, fails)

    VSection* top = vworld_section(world, chunk_x, chunk_z,
                                   world.min_section + world.section_count - 1)
    check(label + " top section installed", top != null, fails)
    if top != null:
        check_int(label + " corner state", sec_block_at(top, 15, 15, 15), 900 + seed,
                  fails)


def build_pair() -> VWorld*:
    VWorld* world = vworld_new(4, 0, 2, 15, 6)
    anvil_fill_column(world, 0, 17, 0)
    anvil_fill_column(world, 33, -23, 1)
    return world


def test_roundtrip(fails: int*) -> void:
    print("anvil region round trip:")
    VAnvil* a = anvil_new()
    anvil_set_data_version(a, (int64)4500)
    anvil_set_status(a, anvil_status_full())

    # gzip is what the game writes, so it is the default path.
    VWorld* world = build_pair()
    check_int("columns loaded before saving", vworld_chunk_count(world), 2, fails)
    check_int("gzip save wrote two chunks",
              anvil_save_world(a, world, anvil_test_base(), ""), 2, fails)
    vworld_free(world)

    VWorld* back = vworld_new(4, 0, 2, 15, 6)
    int loaded = anvil_load_region(a, back, anvil_test_base(), "", 0, 0)
    loaded = loaded + anvil_load_region(a, back, anvil_test_base(), "", 1, -1)
    check_int("gzip chunks read back", loaded, 2, fails)
    check_int("gzip columns installed", vworld_chunk_count(back), 2, fails)
    anvil_expect_column(back, 0, 17, 0, "gzip", fails)
    anvil_expect_column(back, 33, -23, 1, "gzip", fails)
    vworld_free(back)

    # The same world stored without a compression codec, which goes down the
    # sector packing with a different record length.
    anvil_set_compression(a, anvil_comp_none(), 0)
    VWorld* plain = build_pair()
    check_int("stored save wrote two chunks",
              anvil_save_world(a, plain, anvil_test_base(), ""), 2, fails)
    vworld_free(plain)

    VWorld* plain_back = vworld_new(4, 0, 2, 15, 6)
    check_int("stored chunks read back",
              anvil_load_region(a, plain_back, anvil_test_base(), "", 0, 0) +
              anvil_load_region(a, plain_back, anvil_test_base(), "", 1, -1), 2, fails)
    anvil_expect_column(plain_back, 0, 17, 0, "stored", fails)
    anvil_expect_column(plain_back, 33, -23, 1, "stored", fails)
    vworld_free(plain_back)

    # A region file is a whole number of sectors: two kibibytes of tables plus
    # the chunk payloads, rounded up.
    int64 size = vt_file_size(anvil_region_path(anvil_test_base(), "", 1, -1))
    check_int("region file is sector aligned", (int)(size % 4096), 0, fails)
    check("region file has content", size > 8192, fails)
    anvil_free(a)


def test_palette_fallback(fails: int*) -> void:
    print("numeric palettes:")
    VAnvil* a = anvil_new()
    check_int("no table means no rows", anvil_registry_rows(a), 0, fails)
    VWorld* world = vworld_new(1, 0, 2, 15, 6)
    # A region no other case writes to, so the save starts from an empty file
    # and the load below counts exactly the chunk this case wrote.
    anvil_fill_column(world, 500, -500, 0)
    check_int("numeric save succeeds",
              anvil_save_world(a, world, anvil_test_base(), ""), 1, fails)
    check_int("plain numeric palettes are not a loss", anvil_lossy_palettes(a), 0, fails)
    VWorld* back = vworld_new(1, 0, 2, 15, 6)
    check_int("numeric chunk reads back",
              anvil_load_region(a, back, anvil_test_base(), "", 15, -16), 1, fails)
    anvil_expect_column(back, 500, -500, 0, "numeric", fails)
    vworld_free(back)
    vworld_free(world)
    anvil_free(a)


def main() -> int:
    int fails = 0
    test_roundtrip(&fails)
    test_palette_fallback(&fails)
    return report("anvil tests", fails)

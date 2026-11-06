# Vortex engine - chunk heightmap tests: the 9-bit packing, column storage and
# the anonymous NBT compound inside a chunk packet.
#
#   ./build.sh --run tests/heightmap.txt

import stdlib


def motion_height(i: int) -> int:
    return 64 + i % 200


def surface_height(i: int) -> int:
    return 100 + i


def fill(values: int*, kind: int) -> void:
    int i = 0
    while i < 256:
        if kind == hm_motion_blocking():
            hm_set(values, kind, i % 16, i / 16, motion_height(i))
        else:
            hm_set(values, kind, i % 16, i / 16, surface_height(i))
        i += 1


def write_packed(b: VBuf*, values: int*, kind: int) -> void:
    int64[] longs = new int64[hm_long_count()]
    hm_pack(values, kind, longs)
    int i = 0
    while i < hm_long_count():
        vbuf_put_i64_be(b, longs[i])
        i += 1


def write_heightmap_entry(b: VBuf*, type_id: int, values: int*, kind: int,
                          long_count: int) -> void:
    vbuf_put_varint(b, type_id)
    vbuf_put_varint(b, long_count)
    if long_count == hm_long_count():
        write_packed(b, values, kind)
    else:
        int i = 0
        while i < long_count:
            vbuf_put_i64_be(b, (int64)0)
            i += 1


# One chunk packet body for chunk (-1, 2): the given heightmap entries, one
# empty section and a light tail that ends exactly at the buffer.
def build_chunk_body(b: VBuf*, motion: int*, surface: int*, mode: int) -> void:
    vbuf_put_i32_be(b, -1)
    vbuf_put_i32_be(b, 2)

    int entries = 1
    if mode == 0 or mode == 1:
        entries += 1
    vbuf_put_varint(b, entries)
    if mode == 3:
        write_heightmap_entry(b, (int)hm_wire_motion_blocking(), motion,
                              hm_motion_blocking(), 35)
    else:
        write_heightmap_entry(b, (int)hm_wire_motion_blocking(), motion,
                              hm_motion_blocking(), hm_long_count())
    if mode == 1:
        write_heightmap_entry(b, 3, surface, hm_world_surface(), hm_long_count())
    if mode == 0:
        write_heightmap_entry(b, (int)hm_wire_world_surface(), surface,
                              hm_world_surface(), hm_long_count())

    vbuf_put_varint(b, 6)
    vbuf_put_i16_be(b, 0)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_varint(b, 0)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_varint(b, 0)

    vbuf_put_varint(b, 0) # no block entities
    vbuf_put_varint(b, 0) # four empty light masks
    vbuf_put_varint(b, 0)
    vbuf_put_varint(b, 0)
    vbuf_put_varint(b, 0)
    vbuf_put_varint(b, 0) # sky-light arrays
    vbuf_put_varint(b, 0) # block-light arrays


def body_of(b: VBuf*) -> int64[]:
    int64[] body = new int64[b.len]
    int64 index = 0
    while index < b.len:
        body[index] = (int64)vbuf_at(b, (int)index)
        index += 1
    return body


def test_packing(fails: int*) -> void:
    print("heightmap packing:")
    int* values = hm_new()
    int* other = hm_new()
    int64[] longs = new int64[hm_long_count()]
    check_int("longs per kind", hm_long_count(), 36, fails)
    check_int("values per column", hm_values(), 512, fails)

    int i = 0
    while i < 256:
        hm_set(values, hm_motion_blocking(), i % 16, i / 16, i * 2 % 512)
        i += 1
    check_int("packed", hm_pack(values, hm_motion_blocking(), longs), 1, fails)
    check_int("unpacked", hm_unpack(longs, hm_motion_blocking(), other), 1, fails)
    int mismatch = 0
    i = 0
    while i < 256:
        if hm_get(other, hm_motion_blocking(), i % 16, i / 16) != i * 2 % 512:
            mismatch += 1
        i += 1
    check_int("round trip is exact", mismatch, 0, fails)
    check_int("field across the first word",
              hm_get(other, hm_motion_blocking(), 7, 0), 14, fails)
    check_int("last field", hm_get(other, hm_motion_blocking(), 15, 15), 510, fails)

    hm_set(values, hm_world_surface(), 0, 0, 700)
    hm_pack(values, hm_world_surface(), longs)
    hm_unpack(longs, hm_world_surface(), other)
    check_int("nine bit field truncates", hm_get(other, hm_world_surface(), 0, 0),
              700 % 512, fails)
    check_int("kind is not shared", hm_get(other, hm_motion_blocking(), 0, 0), 0, fails)

    check_int("kind out of range", hm_index(hm_kind_count(), 0, 0), -1, fails)
    check_int("coordinate out of range", hm_index(hm_motion_blocking(), 16, 0), -1, fails)
    check_int("out of range read", hm_get(values, hm_motion_blocking(), -1, 0), -1, fails)
    hm_free(values)
    hm_free(other)


def test_world_storage(fails: int*) -> void:
    print("heightmap storage:")
    VWorld* world = vworld_new(2, 0, 1, 15, 6)
    int* values = hm_new()
    hm_set(values, hm_motion_blocking(), 15, 0, 90)
    hm_set(values, hm_world_surface(), 0, 15, 120)
    check_int("height before load", vworld_height_at(world, hm_motion_blocking(), 0, 0),
              -1, fails)
    check_int("column inserted", vworld_set_heightmaps(world, -1, 2, values), 1, fails)
    check_int("chunk count", vworld_chunk_count(world), 1, fails)
    check_int("negative coordinate lookup",
              vworld_height_at(world, hm_motion_blocking(), -1, 32), 90, fails)
    check_int("second kind lookup", vworld_height_at(world, hm_world_surface(), -16, 47),
              120, fails)
    check_int("unloaded chunk reads -1", vworld_height_at(world, hm_motion_blocking(), 0, 0),
              -1, fails)
    check_int("sections still absent", vworld_block_at(world, -1, 0, 32), 0, fails)

    int* replacement = hm_new()
    hm_set(replacement, hm_motion_blocking(), 15, 0, 91)
    check_int("heightmap replaced", vworld_set_heightmaps(world, -1, 2, replacement), 1, fails)
    check_int("replacement wins", vworld_height_at(world, hm_motion_blocking(), -1, 32),
              91, fails)
    check_int("unload", vworld_unload_chunk(world, -1, 2), 1, fails)
    check_int("gone after unload", vworld_height_at(world, hm_motion_blocking(), -1, 32),
              -1, fails)

    VWorld* full = vworld_new(1, 0, 1, 15, 6)
    check_int("capacity reached", vworld_set_heightmaps(full, 5, 5, hm_new()), 1, fails)
    check_int("no room for another", vworld_set_heightmaps(full, 6, 5, hm_new()), 0, fails)
    vworld_free(full)
    vworld_free(world)


def test_packet_heightmaps(fails: int*) -> void:
    print("chunk packet heightmaps:")
    int* motion = hm_new()
    int* surface = hm_new()
    fill(motion, hm_motion_blocking())
    fill(surface, hm_world_surface())

    VBuf* b = vbuf_new(16384)
    build_chunk_body(b, motion, surface, 0)
    VWorld* world = vworld_new(2, 0, 1, 15, 6)
    check_int("chunk decoded", decode_chunk_sections(world, body_of(b), 0), 0, fails)
    check_int("motion blocking corner",
              vworld_height_at(world, hm_motion_blocking(), -1, 32), motion_height(15), fails)
    check_int("field across words",
              vworld_height_at(world, hm_motion_blocking(), -9, 42), motion_height(167), fails)
    check_int("surface corner", vworld_height_at(world, hm_world_surface(), -1, 47),
              surface_height(255), fails)
    check_int("sections decoded too", vworld_block_at(world, -1, 0, 32), 0, fails)
    vworld_free(world)
    vbuf_free(b)

    b = vbuf_new(16384)
    build_chunk_body(b, motion, surface, 1)
    world = vworld_new(2, 0, 1, 15, 6)
    check_int("chunk with unknown kind decoded",
              decode_chunk_sections(world, body_of(b), 0), 0, fails)
    check_int("absent kind stays zero",
              vworld_height_at(world, hm_world_surface(), -1, 32), 0, fails)
    check_int("present kind kept", vworld_height_at(world, hm_motion_blocking(), -1, 32),
              motion_height(15), fails)
    vworld_free(world)
    vbuf_free(b)

    b = vbuf_new(16384)
    build_chunk_body(b, motion, surface, 2)
    world = vworld_new(2, 0, 1, 15, 6)
    check_int("chunk without surface decoded",
              decode_chunk_sections(world, body_of(b), 0), 0, fails)
    check_int("surface absent reads zero",
              vworld_height_at(world, hm_world_surface(), -16, 32), 0, fails)
    check_int("motion blocking still read",
              vworld_height_at(world, hm_motion_blocking(), -16, 32), motion_height(0), fails)
    vworld_free(world)
    vbuf_free(b)

    b = vbuf_new(16384)
    build_chunk_body(b, motion, surface, 3)
    world = vworld_new(2, 0, 1, 15, 6)
    check_int("wrong long count rejected", decode_chunk_sections(world, body_of(b), 0), 1, fails)
    check_int("nothing stored", vworld_chunk_count(world), 0, fails)
    vworld_free(world)
    vbuf_free(b)
    hm_free(motion)
    hm_free(surface)


def main() -> int:
    int fails = 0
    test_packing(&fails)
    test_world_storage(&fails)
    test_packet_heightmaps(&fails)
    return report("heightmap tests", fails)

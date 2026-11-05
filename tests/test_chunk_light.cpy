import stdlib


def build_chunk_packet(b: VBuf*, bad_mask: bool, truncated_light: bool,
                       with_entity: bool, boundary_light: bool) -> void:
    vbuf_put_i32_be(b, 0)
    vbuf_put_i32_be(b, 0)

    # Empty anonymous heightmap compound.
    vbuf_put_u8(b, (uint64)10)
    vbuf_put_u8(b, (uint64)0)

    # One section: zero non-air blocks, uniform block and biome containers.
    vbuf_put_varint(b, 6)
    vbuf_put_i16_be(b, 0)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_varint(b, 0)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_varint(b, 0)

    if with_entity:
        vbuf_put_varint(b, 1)
        vbuf_put_u8(b, (uint64)0)
        vbuf_put_i16_be(b, 5)
        vbuf_put_varint(b, 1)
        vbuf_put_u8(b, (uint64)10)
        vbuf_put_u8(b, (uint64)0)
    else:
        vbuf_put_varint(b, 0)

    # The only non-empty sky-light section is section index zero (mask bit 1).
    vbuf_put_varint(b, 1)
    if bad_mask:
        vbuf_put_i64_be(b, (int64)8)
    elif boundary_light:
        vbuf_put_i64_be(b, (int64)1)
    else:
        vbuf_put_i64_be(b, (int64)2)
    vbuf_put_varint(b, 0) # block-light mask
    vbuf_put_varint(b, 0) # empty sky-light mask
    vbuf_put_varint(b, 0) # empty block-light mask

    vbuf_put_varint(b, 1)
    vbuf_put_varint(b, 2048)
    int i = 0
    while i < 2048:
        int value = 0
        if i == 0:
            value = 33
        if truncated_light and i == 2047:
            break
        vbuf_put_u8(b, (uint64)value)
        i += 1
    vbuf_put_varint(b, 0) # no block-light arrays


def decode_fixture(bad_mask: bool, truncated_light: bool,
                   with_entity: bool, boundary_light: bool,
                   fails: int*) -> VWorld*:
    VBuf* b = vbuf_new(8192)
    build_chunk_packet(b, bad_mask, truncated_light, with_entity, boundary_light)
    int64[] body = new int64[b.len]
    int64 i = 0
    while i < b.len:
        body[i] = (int64)vbuf_at(b, (int)i)
        i += 1
    VWorld* world = vworld_new(2, 0, 1, 15, 6)
    int status = decode_chunk_sections(world, body, 0)
    if bad_mask or truncated_light:
        check_int("invalid chunk payload rejected", status, 1, fails)
        check_int("invalid chunk not installed", vworld_chunk_count(world), 0, fails)
    else:
        check_int("chunk with lighting decoded", status, 0, fails)
        check_int("decoded chunk installed", vworld_chunk_count(world), 1, fails)
        VSection* section = vworld_section(world, 0, 0, 0)
        check("chunk section available", section != null, fails)
        if section != null:
            int expected_low = 1
            int expected_high = 2
            if boundary_light:
                expected_low = 0
                expected_high = 0
            check_int("sky light low nibble", sec_sky_light_at(section, 0, 0, 0), expected_low, fails)
            check_int("sky light high nibble", sec_sky_light_at(section, 1, 0, 0), expected_high, fails)
            check_int("unset block light remains zero", sec_block_light_at(section, 0, 0, 0), 0, fails)
    vbuf_free(b)
    return world


def main() -> int:
    int fails = 0
    print("chunk packet light and block entities:")
    VWorld* world = decode_fixture(false, false, true, false, &fails)
    vworld_free(world)
    world = decode_fixture(true, false, false, false, &fails)
    vworld_free(world)
    world = decode_fixture(false, true, false, false, &fails)
    vworld_free(world)
    world = decode_fixture(false, false, false, true, &fails)
    vworld_free(world)
    return report("chunk light tests", fails)

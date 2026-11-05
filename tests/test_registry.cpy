import stdlib


def append_protocol_string(b: VBuf*, value: str) -> void:
    int64 length = mc_string_length(value)
    vbuf_put_varint(b, (int)length)
    int64 i = 0
    while i < length:
        vbuf_put_u8(b, (uint64)mc_string_byte(value, i))
        i += 1


def append_nbt_int(b: VBuf*, name: str, value: int64) -> void:
    vbuf_put_u8(b, (uint64)3)
    int64 length = mc_string_length(name)
    vbuf_put_u8(b, (uint64)(length >> 8))
    vbuf_put_u8(b, (uint64)(length & 255))
    int64 i = 0
    while i < length:
        vbuf_put_u8(b, (uint64)mc_string_byte(name, i))
        i += 1
    vbuf_put_i32_be(b, (int)value)


def buffer_to_array(b: VBuf*) -> int64[]:
    int64[] body = new int64[b.len]
    int i = 0
    while i < b.len:
        body[i] = (int64)vt_at(b.data, i)
        i += 1
    return body


def make_dimension_registry_packet() -> int64[]:
    VBuf* b = vbuf_new(512)
    append_protocol_string(b, "minecraft:dimension_type")
    vbuf_put_varint(b, 2)

    append_protocol_string(b, "minecraft:overworld")
    vbuf_put_u8(b, (uint64)1)
    vbuf_put_u8(b, (uint64)10)
    append_nbt_int(b, "min_y", -64)
    append_nbt_int(b, "height", 384)
    vbuf_put_u8(b, (uint64)0)

    append_protocol_string(b, "minecraft:the_nether")
    vbuf_put_u8(b, (uint64)1)
    vbuf_put_u8(b, (uint64)10)
    append_nbt_int(b, "min_y", 0)
    append_nbt_int(b, "height", 256)
    vbuf_put_u8(b, (uint64)0)
    int64[] body = buffer_to_array(b)
    vbuf_free(b)
    return body


def make_biome_registry_packet() -> int64[]:
    VBuf* b = vbuf_new(1024)
    append_protocol_string(b, "minecraft:worldgen/biome")
    vbuf_put_varint(b, 70)
    int i = 0
    while i < 70:
        append_protocol_string(b, "minecraft:plains")
        vbuf_put_u8(b, (uint64)0)
        i += 1
    int64[] body = buffer_to_array(b)
    vbuf_free(b)
    return body


def make_play_login_body() -> int64[]:
    VBuf* b = vbuf_new(128)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_u8(b, (uint64)1)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_varint(b, 1)
    append_protocol_string(b, "minecraft:overworld")
    vbuf_put_varint(b, 20)
    vbuf_put_varint(b, 10)
    vbuf_put_varint(b, 10)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_u8(b, (uint64)1)
    vbuf_put_u8(b, (uint64)0)
    vbuf_put_varint(b, 1)
    int64[] body = buffer_to_array(b)
    vbuf_free(b)
    return body


def test_registry_dimensions(fails: int*) -> void:
    print("configuration dimension registry:")
    VDimensionRegistry* registry = vdimension_registry_new()
    int parsed = parse_configuration_registry(make_dimension_registry_packet(), 0, registry)
    check_int("dimension registry parsed", parsed, 1, fails)
    check_int("dimension registry marked", registry.dimension_registry_seen, 1, fails)
    int64[] overworld = vdimension_registry_dimension(registry, 0)
    check_int("overworld entry valid", (int)overworld[0], 1, fails)
    check_int("overworld minimum section", (int)overworld[1], -4, fails)
    check_int("overworld section count", (int)overworld[2], 24, fails)
    int64[] nether = vdimension_registry_dimension(registry, 1)
    check_int("nether minimum section", (int)nether[1], 0, fails)
    check_int("nether section count", (int)nether[2], 16, fails)

    int biome_parsed = parse_configuration_registry(make_biome_registry_packet(), 0, registry)
    check_int("biome registry parsed", biome_parsed, 1, fails)
    check_int("biome global width derived", registry.biome_global_bits, 7, fails)
    check_int("block global profile width", registry.block_global_bits, 15, fails)

    int64[] join = make_play_login_body()
    int64[] dimension_type = read_play_login_dimension(join, 0)
    check_int("join packet dimension type", (int)dimension_type[1], 1, fails)
    VWorld* world = vworld_new(2, 0, 1, registry.block_global_bits,
                               registry.biome_global_bits)
    check_int("world adopts dimension", vworld_set_dimension(
        world, (int)nether[1], (int)nether[2],
        registry.block_global_bits, registry.biome_global_bits), 1, fails)
    check_int("world section origin updated", world.min_section, 0, fails)
    check_int("world section count updated", world.section_count, 16, fails)
    vworld_free(world)
    vdimension_registry_free(registry)


def main() -> int:
    int fails = 0
    test_registry_dimensions(&fails)
    return report("dimension registry tests", fails)

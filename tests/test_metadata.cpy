# Vortex engine - entity metadata serializer tests.
#
#   ./build.sh --run tests/metadata.txt
#
# Streams are assembled the way a 26.3 server sends them: a varint header of
# (serializer << 7) | field, the value that serializer names, then one more
# field before the 255 terminator. A guessed size misreads the next header, so
# every case here is a synchronisation test as much as a value test.

import stdlib


def meta_push(out: int64[], at: int64, value: int64) -> int64:
    out[at] = value
    return at + 1


def meta_push_varint(out: int64[], at: int64, value: int64) -> int64:
    int64[] bytes = encode_varint(value)
    int64 i = 0
    while i < len(bytes):
        out[at + i] = bytes[i]
        i = i + 1
    return at + len(bytes)


def meta_push_field(out: int64[], at: int64, field: int,
                    serializer: int) -> int64:
    return meta_push_varint(out, at, (int64)(serializer * 128 + field))


def meta_push_raw(out: int64[], at: int64, size: int64) -> int64:
    int64 i = 0
    while i < size:
        out[at + i] = i + 1
        i = i + 1
    return at + size


def meta_terminator(out: int64[], at: int64) -> int64:
    return meta_push_varint(out, at, (int64)pl_metadata_terminator())


# One value per family: byte, boolean, the varint ordinals, fixed-width float
# runs, and both flavours of optional record.
def test_shapes(fails: int*) -> void:
    VEntities* table = ventities_new()
    ventities_touch(table, 7)
    int64[] stream = new int64[256]
    int64 at = 0

    at = meta_push_field(stream, at, 0, 0)
    at = meta_push(stream, at, 3)
    at = meta_push_field(stream, at, 12, 8)
    at = meta_push(stream, at, 1)
    at = meta_terminator(stream, at)
    check_int("byte then boolean", pl_decode_entity_metadata(table, 7, stream, 0), 0, fails)
    check_int("byte value", (int)ventities_value(table, 7, 0), 3, fails)
    check_int("boolean value", (int)ventities_value(table, 7, 12), 1, fails)

    at = meta_push_field(stream, 0, 15, 14)
    at = meta_push_varint(stream, at, 4096)
    at = meta_push_field(stream, at, 2, 19)
    at = meta_push_varint(stream, at, 7)
    at = meta_push_field(stream, at, 3, 43)
    at = meta_push_varint(stream, at, 1)
    at = meta_terminator(stream, at)
    check_int("varint family", pl_decode_entity_metadata(table, 7, stream, 0), 0, fails)
    check_int("block state id", (int)ventities_value(table, 7, 15), 4096, fails)
    check_int("dye colour", (int)ventities_value(table, 7, 3), 1, fails)

    # Rotations is three floats, so the quaternion after it only reaches the
    # terminator when exactly twelve bytes were skipped.
    at = meta_push_field(stream, 0, 1, 9)
    at = meta_push_raw(stream, at, 12)
    at = meta_push_field(stream, at, 2, 40)
    at = meta_push_raw(stream, at, 16)
    at = meta_push_field(stream, at, 3, 39)
    at = meta_push_raw(stream, at, 12)
    at = meta_push_field(stream, at, 4, 10)
    at = meta_push_raw(stream, at, 8)
    at = meta_terminator(stream, at)
    check_int("fixed-width runs", pl_decode_entity_metadata(table, 7, stream, 0), 0, fails)

    # An absent optional block position carries no payload at all, and a
    # present living entity reference is a UUID rather than an entity id.
    at = meta_push_field(stream, 0, 6, 11)
    at = meta_push(stream, at, 0)
    at = meta_push_field(stream, at, 7, 13)
    at = meta_push(stream, at, 1)
    at = meta_push_raw(stream, at, 16)
    at = meta_push_field(stream, at, 8, 42)
    at = meta_push_varint(stream, at, 1)
    at = meta_terminator(stream, at)
    check_int("optional records", pl_decode_entity_metadata(table, 7, stream, 0), 0, fails)
    check_int("arm after uuid", (int)ventities_value(table, 7, 8), 1, fails)

    # A global position is a dimension registry id and a packed position, so
    # the dimension-name string the older client read would desynchronise here.
    at = meta_push_field(stream, 0, 4, 33)
    at = meta_push(stream, at, 1)
    at = meta_push_varint(stream, at, 1)
    at = meta_push_raw(stream, at, 8)
    at = meta_push_field(stream, at, 5, 12)
    at = meta_push_varint(stream, at, 3)
    at = meta_terminator(stream, at)
    check_int("optional global position", pl_decode_entity_metadata(table, 7, stream, 0), 0, fails)
    check_int("direction after position", (int)ventities_value(table, 7, 5), 3, fails)

    ventities_free(table)


# A particle is an id plus whatever that id carries: bare emitters stop at the
# id, blockstate particles add one more varint, and a list is a count followed
# by that many records. Villager data is three varints in a row.
def test_particles(fails: int*) -> void:
    VEntities* table = ventities_new()
    ventities_touch(table, 3)
    int64[] stream = new int64[256]
    int64 at = 0

    at = meta_push_field(stream, at, 0, 16)
    at = meta_push_varint(stream, at, 5)
    at = meta_push_field(stream, at, 1, 16)
    at = meta_push_varint(stream, at, (int64)vparts_kind_block())
    at = meta_push_varint(stream, at, 4096)
    at = meta_push_field(stream, at, 2, 17)
    at = meta_push_varint(stream, at, 3)
    at = meta_push_varint(stream, at, 5)
    at = meta_push_varint(stream, at, (int64)vparts_kind_block())
    at = meta_push_varint(stream, at, 12)
    at = meta_push_varint(stream, at, 5)
    at = meta_push_field(stream, at, 3, 18)
    at = meta_push_varint(stream, at, 1)
    at = meta_push_varint(stream, at, 2)
    at = meta_push_varint(stream, at, 3)
    at = meta_terminator(stream, at)
    check_int("particle payloads", pl_decode_entity_metadata(table, 3, stream, 0), 0, fails)

    # An id above the registry's own maximum is a dialect this client has not
    # read, so the walk stops instead of treating it as a bare emitter.
    at = meta_push_field(stream, 0, 0, 16)
    at = meta_push_varint(stream, at, (int64)vparts_kind_max() + 1)
    at = meta_terminator(stream, at)
    check_int("unknown particle id", pl_decode_entity_metadata(table, 3, stream, 0), 1, fails)

    ventities_free(table)


# An ordinal outside the registry, a shape the client does not model, and a
# value cut short all stop the walk instead of reading past the payload.
def test_refusals(fails: int*) -> void:
    VEntities* table = ventities_new()
    ventities_touch(table, 1)
    int64[] stream = new int64[64]

    int64 at = meta_push_field(stream, 0, 0, pl_metadata_serializer_count())
    at = meta_terminator(stream, at)
    check_int("ordinal outside the registry", pl_decode_entity_metadata(table, 1, stream, 0), 1, fails)

    at = meta_push_field(stream, 0, 0, 41)
    at = meta_push(stream, at, 0)
    at = meta_terminator(stream, at)
    check_int("resolvable profile", pl_decode_entity_metadata(table, 1, stream, 0), 1, fails)

    int64[] tight = new int64[4]
    at = meta_push_field(tight, 0, 0, 9)
    at = meta_push(tight, at, 0)
    at = meta_push(tight, at, 0)
    check_int("truncated rotations", pl_decode_entity_metadata(table, 1, tight, 0), 1, fails)

    ventities_free(table)


def main() -> int:
    int fails = 0
    test_shapes(&fails)
    test_particles(&fails)
    test_refusals(&fails)
    return report("metadata", fails)

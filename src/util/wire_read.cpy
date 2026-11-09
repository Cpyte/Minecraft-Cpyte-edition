# Vortex engine - the shared big-endian readers every protocol walker uses.
#
# These live ahead of the world and protocol modules so both the item stack
# reader and the Play handlers can call one implementation. Each returns either
# a plain value or a {status, value, next} triple, where status 1 means the
# field was read, and `next` is the offset the caller continues from.

import stdlib


public def decode_result(status: int64, value: int64, position: int64) -> int64[]:
    int64[] decoded = new int64[3]
    decoded[0] = status
    decoded[1] = value
    decoded[2] = position
    return decoded


public def decode_varint(data: int64[], offset: int64) -> int64[]:
    int64 value = 0
    int64 position = offset
    int64 shift = 0
    if offset < 0:
        return decode_result(-3, 0, offset)
    while shift < 35:
        if position >= len(data):
            return decode_result(-1, 0, position)
        int64 current = data[position]
        if current < 0 or current > 255:
            return decode_result(-3, 0, position)
        if shift == 28 and current > 15:
            return decode_result(-2, 0, position)
        value = value | (current & 0x7F) << shift
        position = position + 1
        if (current & 0x80) == 0:
            if value >= 0x80000000:
                value = value - 0x100000000
            return decode_result(1, value, position)
        shift = shift + 7
    return decode_result(-2, 0, position)


public def decode_be_int32(data: int64[], offset: int64) -> int64:
    int64 value = data[offset] << 24 | (data[offset + 1] << 16 | (data[offset + 2] << 8 | data[offset + 3]))
    if value >= 0x80000000:
        value = value - 0x100000000
    return value


public def read_string_field(data: int64[], offset: int64, maximum: int64) -> int64[]:
    int64[] length = decode_varint(data, offset)
    if length[0] != 1 or (length[1] < 0 or length[1] > maximum):
        return decode_result(-1, 0, offset)
    if length[2] + length[1] > len(data):
        return decode_result(-1, 0, offset)
    return decode_result(1, length[1], length[2])


# Bounds check for a fixed-width field: the offset after `count` bytes, or -1
# when the packet does not have them. Every walker uses it rather than reading
# past the end and decoding whatever the buffer's padding was.
public def pl_take(body: int64[], cursor: int64, count: int64) -> int64:
    if cursor < 0 or cursor + count > len(body):
        return (int64)-1
    return cursor + count


public def read_nbt_string(data: int64[], offset: int64) -> int64[]:
    if offset < 0 or offset + 2 > len(data):
        return decode_result(-1, 0, offset)
    int64 length = data[offset] << 8 | data[offset + 1]
    if length < 0 or offset + (2 + length) > len(data):
        return decode_result(-1, 0, offset)
    return decode_result(1, length, offset + 2)


public def skip_nbt_payload(data: int64[], tag_type: int64, offset: int64, depth: int64) -> int64[]:
    if offset < 0 or depth > 64:
        return decode_result(-1, 0, offset)
    if tag_type == 0:
        return decode_result(1, 0, offset)
    if tag_type == 1:
        return decode_result(1, 0, offset + 1)
    if tag_type == 2:
        return decode_result(1, 0, offset + 2)
    if tag_type == 3 or tag_type == 5:
        return decode_result(1, 0, offset + 4)
    if tag_type == 4 or tag_type == 6:
        return decode_result(1, 0, offset + 8)
    if tag_type == 8:
        int64[] value = read_nbt_string(data, offset)
        if value[0] != 1:
            return value
        return decode_result(1, 0, value[2] + value[1])
    if tag_type == 7 or (tag_type == 11 or tag_type == 12):
        if offset + 4 > len(data):
            return decode_result(-1, 0, offset)
        int64 count = decode_be_int32(data, offset)
        int64 bytes_per_item = 1
        if tag_type == 11:
            bytes_per_item = 4
        if tag_type == 12:
            bytes_per_item = 8
        if count < 0 or (count > len(data) or offset + (4 + count * bytes_per_item) > len(data)):
            return decode_result(-1, 0, offset)
        return decode_result(1, 0, offset + (4 + count * bytes_per_item))
    if tag_type == 9:
        if offset + 5 > len(data):
            return decode_result(-1, 0, offset)
        int64 element_type = data[offset]
        int64 count = decode_be_int32(data, offset + 1)
        if count < 0 or count > len(data):
            return decode_result(-1, 0, offset)
        int64 position = offset + 5
        int64 index = 0
        while index < count:
            int64[] element = skip_nbt_payload(data, element_type, position, depth + 1)
            if element[0] != 1 or element[2] <= position:
                return decode_result(-1, 0, position)
            position = element[2]
            index = index + 1
        return decode_result(1, 0, position)
    if tag_type == 10:
        int64 position = offset
        while position < len(data):
            int64 child_type = data[position]
            position = position + 1
            if child_type == 0:
                return decode_result(1, 0, position)
            int64[] name = read_nbt_string(data, position)
            if name[0] != 1:
                return decode_result(-1, 0, position)
            position = name[2] + name[1]
            int64[] child = skip_nbt_payload(data, child_type, position, depth + 1)
            if child[0] != 1 or child[2] <= position:
                return decode_result(-1, 0, position)
            position = child[2]
        return decode_result(-1, 0, position)
    return decode_result(-1, 0, offset)
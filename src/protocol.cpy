import "network.c"

public def decode_result(status: int64, value: int64, position: int64) -> int64[]:
    int64[] decoded = new int64[3]
    decoded[0] = status
    decoded[1] = value
    decoded[2] = position
    return decoded

public def encode_varint(value: int64) -> int64[]:
    int64[] encoded = new int64[0]
    int64 remaining = value & 0xFFFFFFFF
    while remaining > 127:
        append(encoded, remaining & 0x7F | 0x80)
        remaining = remaining >> 7
    append(encoded, remaining)
    return encoded

public def encode_wire_frame(body: int64[]) -> int64[]:
    int64[] frame = encode_varint(len(body))
    int64 index = 0
    while index < len(body):
        append(frame, body[index])
        index = index + 1
    return frame

public def make_packet_frame(body: int64[]) -> int64[]:
    int64 compression_threshold = mc_get_compression_threshold()
    if compression_threshold < 0:
        return encode_wire_frame(body)
    if compression_threshold >= 0:
        if len(body) >= compression_threshold:
            mc_codec_reset()
            int64 index = 0
            while index < len(body):
                if mc_codec_input_byte(body[index]) != 0:
                    return new int64[0]
                index = index + 1
            if mc_codec_run(0, 0) != 0:
                print("Could not compress outbound packet")
                return new int64[0]
            int64 compressed_length = mc_codec_output_length()
            int64[] data_length = encode_varint(len(body))
            int64[] frame = encode_varint(len(data_length) + compressed_length)
            index = 0
            while index < len(data_length):
                append(frame, data_length[index])
                index = index + 1
            index = 0
            while index < compressed_length:
                append(frame, mc_codec_output_byte(index))
                index = index + 1
            return frame
        else:
            int64[] frame = encode_varint(len(body) + 1)
            append(frame, 0)
            int64 index = 0
            while index < len(body):
                append(frame, body[index])
                index = index + 1
            return frame
    return new int64[0]

public def append_varint(target: int64[], value: int64) -> int64[]:
    int64 remaining = value & 0xFFFFFFFF
    while remaining > 127:
        append(target, remaining & 0x7F | 0x80)
        remaining = remaining >> 7
    append(target, remaining)
    return target

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

public def encode_packet_frame(packet_id: int64, payload: int64[]) -> int64[]:
    int64[] packet = encode_varint(packet_id)
    int64 index = 0
    while index < len(payload):
        append(packet, payload[index])
        index = index + 1
    return make_packet_frame(packet)

public def decode_frame_header(data: int64[]) -> int64[]:
    int64 length = 0
    int64 index = 0
    while index < 3:
        if index >= len(data):
            return decode_result(-1, 0, index)
        int64 current = data[index]
        if current < 0 or current > 255:
            return decode_result(-3, 0, index)
        length = length | (current & 0x7F) << index * 7
        if (current & 0x80) == 0:
            if length == 0 or length > 2097151:
                return decode_result(-2, 0, index + 1)
            return decode_result(1, length, index + 1)
        index = index + 1
    return decode_result(-2, 0, index)

public def decode_frame(data: int64[]) -> int64[]:
    int64[] header = decode_frame_header(data)
    if header[0] != 1:
        return decode_result(header[0], header[1], header[2])
    int64 body_length = header[1]
    int64 header_length = header[2]
    int64 consumed = header_length + body_length
    if len(data) < consumed:
        return decode_result(-1, consumed, 0)
    int64[] decoded = new int64[3 + body_length]
    decoded[0] = 1
    decoded[1] = consumed
    decoded[2] = body_length
    int64 index = 0
    while index < body_length:
        decoded[3 + index] = data[header_length + index]
        index = index + 1
    return decoded

public def encode_handshake(protocol_version: int64, host: int64[], host_length: int64, port: int64, intent: int64) -> int64[]:
    int64[] body = encode_varint(0)
    body = append_varint(body, protocol_version)
    body = append_varint(body, host_length)
    int64 index = 0
    while index < host_length:
        append(body, host[index])
        index = index + 1
    append(body, port >> 8 & 0xFF)
    append(body, port & 0xFF)
    body = append_varint(body, intent)
    int64[] frame = encode_varint(len(body))
    index = 0
    while index < len(body):
        append(frame, body[index])
        index = index + 1
    return frame

public def encode_status_request() -> int64[]:
    int64[] empty = new int64[0]
    return encode_packet_frame(0, empty)

public def encode_ping_request(time: int64) -> int64[]:
    int64[] ping = new int64[8]
    int64 index = 0
    while index < 8:
        ping[index] = time >> (7 - index) * 8 & 0xFF
        index = index + 1
    return encode_packet_frame(1, ping)

public def send_bytes(socket_handle: int64, data: int64[]) -> int64:
    if len(data) == 0:
        return -1
    mc_tcp_send_begin(socket_handle)
    int64 index = 0
    while index < len(data):
        if mc_tcp_send_byte(data[index]) != 0:
            return -1
        index = index + 1
    return mc_tcp_send_end()

public def read_frame(socket_handle: int64) -> int64[]:
    int64[] prefix = new int64[0]
    int64[] header = decode_frame_header(prefix)
    while header[0] == -1:
        int64 byte = mc_tcp_recv_byte(socket_handle)
        if byte < 0:
            return decode_result(-4, 0, len(prefix))
        append(prefix, byte)
        header = decode_frame_header(prefix)
    if header[0] != 1:
        return decode_result(-2, 0, len(prefix))
    int64[] frame = new int64[header[1] + header[2]]
    int64 index = 0
    while index < header[2]:
        frame[index] = prefix[index]
        index = index + 1
    while index < len(frame):
        int64 byte = mc_tcp_recv_byte(socket_handle)
        if byte < 0:
            return decode_result(-4, 0, index)
        frame[index] = byte
        index = index + 1
    return decode_frame(frame)

public def packet_body_result(packet_body: int64[]) -> int64[]:
    int64[] decoded = new int64[len(packet_body) + 3]
    decoded[0] = 1
    decoded[1] = len(packet_body)
    decoded[2] = len(packet_body)
    int64 index = 0
    while index < len(packet_body):
        decoded[index + 3] = packet_body[index]
        index = index + 1
    return decoded

public def read_packet_frame(socket_handle: int64) -> int64[]:
    int64[] incoming = read_frame(socket_handle)
    int64 compression_threshold = mc_get_compression_threshold()
    if incoming[0] != 1 or compression_threshold < 0:
        return incoming
    int64[] wire_body = new int64[incoming[2]]
    int64 copy_index = 0
    while copy_index < incoming[2]:
        wire_body[copy_index] = incoming[copy_index + 3]
        copy_index = copy_index + 1
    int64[] data_length = decode_varint(wire_body, 0)
    if data_length[0] != 1 or data_length[1] < 0:
        return decode_result(-5, 0, 0)
    int64 data_start = data_length[2]
    if data_length[1] == 0:
        int64 packet_length = len(wire_body) - data_start
        if packet_length >= compression_threshold:
            return decode_result(-5, 0, 0)
        int64[] packet_body = new int64[packet_length]
        int64 index = 0
        while index < packet_length:
            packet_body[index] = wire_body[data_start + index]
            index = index + 1
        return packet_body_result(packet_body)
    else:
        if data_length[1] < compression_threshold or data_length[1] > 2097151:
            return decode_result(-5, 0, 0)
        mc_codec_reset()
        int64 index = data_start
        while index < len(wire_body):
            if mc_codec_input_byte(wire_body[index]) != 0:
                return decode_result(-5, 0, 0)
            index = index + 1
        if mc_codec_run(1, data_length[1]) != 0:
            return decode_result(-5, 0, 0)
        int64[] compressed_packet_body = new int64[data_length[1]]
        index = 0
        while index < data_length[1]:
            compressed_packet_body[index] = mc_codec_output_byte(index)
            index = index + 1
        return packet_body_result(compressed_packet_body)

public def parse_port(text: str) -> int64[]:
    int64 length = mc_string_length(text)
    if length < 0:
        return decode_result(-1, 0, 0)
    if length == 0:
        return decode_result(1, 25565, 0)
    if length > 5:
        return decode_result(-1, 0, 0)
    int64 port = 0
    int64 index = 0
    while index < length:
        int64 digit = mc_string_byte(text, index)
        if digit < 48 or digit > 57:
            return decode_result(-1, 0, index)
        port = port * 10 + (digit - 48)
        if port > 65535:
            return decode_result(-1, 0, index)
        index = index + 1
    if port < 1:
        return decode_result(-1, 0, index)
    return decode_result(1, port, index)

public def read_string_field(data: int64[], offset: int64, maximum: int64) -> int64[]:
    int64[] length = decode_varint(data, offset)
    if length[0] != 1 or (length[1] < 0 or length[1] > maximum):
        return decode_result(-1, 0, offset)
    if length[2] + length[1] > len(data):
        return decode_result(-1, 0, offset)
    return decode_result(1, length[1], length[2])

public def frame_body(frame: int64[]) -> int64[]:
    if frame[0] != 1 or frame[2] < 1:
        return new int64[0]
    int64[] body = new int64[frame[2]]
    int64 index = 0
    while index < frame[2]:
        body[index] = frame[index + 3]
        index = index + 1
    return body

public def read_login_response_body(socket_handle: int64, frame: int64[]) -> int64[]:
    int64[] body = frame_body(frame)
    int64[] packet_id = decode_varint(body, 0)
    if packet_id[0] != 1:
        print("Malformed login response packet id")
        return new int64[0]
    if packet_id[1] != 3:
        return body
    int64[] threshold = decode_varint(body, packet_id[2])
    if threshold[0] != 1 or (threshold[1] < 0 or (threshold[1] > 2097151 or threshold[2] != len(body))):
        print("Malformed login compression threshold")
        return new int64[0]
    if mc_set_compression_threshold(threshold[1]) != 0:
        print("Could not enable packet compression")
        return new int64[0]
    print(f"Login compression enabled at threshold {threshold[1]}")
    int64[] compressed_frame = read_packet_frame(socket_handle)
    if compressed_frame[0] != 1:
        print("Could not read the next login packet or decompress it")
        return new int64[0]
    int64[] compressed_body = frame_body(compressed_frame)
    return compressed_body

public def encode_config_client_information() -> int64[]:
    int64[] payload = new int64[14]
    payload[0] = 5
    payload[1] = 101
    payload[2] = 110
    payload[3] = 95
    payload[4] = 117
    payload[5] = 115
    payload[6] = 12
    payload[7] = 0
    payload[8] = 1
    payload[9] = 127
    payload[10] = 1
    payload[11] = 0
    payload[12] = 1
    payload[13] = 0
    return encode_packet_frame(0, payload)

public def decode_be_int32(data: int64[], offset: int64) -> int64:
    int64 value = data[offset] << 24 | (data[offset + 1] << 16 | (data[offset + 2] << 8 | data[offset + 3]))
    if value >= 0x80000000:
        value = value - 0x100000000
    return value

public def decode_be_int64(data: int64[], offset: int64) -> double:
    return mc_double_from_be(data[offset], data[offset + 1], data[offset + 2], data[offset + 3], data[offset + 4], data[offset + 5], data[offset + 6], data[offset + 7])

public def decode_be_float(data: int64[], offset: int64) -> double:
    return mc_float_from_be(data[offset], data[offset + 1], data[offset + 2], data[offset + 3])

public def encode_keepalive_response(packet_id: int64, body: int64[], offset: int64) -> int64[]:
    int64[] payload = new int64[8]
    int64 index = 0
    while index < 8:
        payload[index] = body[offset + index]
        index = index + 1
    return encode_packet_frame(packet_id, payload)

public def is_ignorable_configuration_packet(packet_id: int64) -> bool:
    if packet_id == 1:
        return true
    if packet_id == 6:
        return true
    if packet_id == 8:
        return true
    if packet_id == 10:
        return true
    if packet_id == 11:
        return true
    if packet_id == 13:
        return true
    if packet_id == 14:
        return true
    if packet_id == 16:
        return true
    if packet_id == 17:
        return true
    if packet_id == 18:
        return true
    return false

public def read_nbt_string(data: int64[], offset: int64) -> int64[]:
    if offset < 0 or offset + 2 > len(data):
        return decode_result(-1, 0, offset)
    int64 length = data[offset] << 8 | data[offset + 1]
    if length < 0 or offset + (2 + length) > len(data):
        return decode_result(-1, 0, offset)
    return decode_result(1, length, offset + 2)

public def nbt_string_equals(data: int64[], value: int64[], expected: str) -> bool:
    int64 expected_length = mc_string_length(expected)
    if value[0] != 1 or value[1] != expected_length:
        return false
    int64 index = 0
    while index < expected_length:
        if data[value[2] + index] != mc_string_byte(expected, index):
            return false
        index = index + 1
    return true

public def read_dialog_line() -> int64[]:
    int64 line_length = mc_stdin_read_line()
    if line_length < 0:
        return decode_result(line_length, 0, 0)
    int64[] line = new int64[line_length + 2]
    line[0] = 1
    line[1] = line_length
    int64 index = 0
    while index < line_length:
        line[index + 2] = mc_stdin_line_byte(index)
        index = index + 1
    return line

public def dialog_line_equals(line: int64[], expected: str) -> bool:
    int64 expected_length = mc_string_length(expected)
    if line[0] != 1 or line[1] != expected_length:
        return false
    int64 index = 0
    while index < expected_length:
        if line[index + 2] != mc_string_byte(expected, index):
            return false
        index = index + 1
    return true

public def parse_dialog_choice(line: int64[]) -> int64[]:
    if line[0] != 1 or (line[1] < 1 or line[1] > 3):
        return decode_result(-1, 0, 0)
    int64 value = 0
    int64 index = 0
    while index < line[1]:
        int64 digit = line[index + 2]
        if digit < 48 or digit > 57:
            return decode_result(-1, 0, index)
        value = value * 10 + (digit - 48)
        index = index + 1
    if value < 1 or value > 65535:
        return decode_result(-1, 0, index)
    return decode_result(1, value, index)

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

public def find_nbt_field(data: int64[], compound_offset: int64, field_name: str) -> int64[]:
    int64 position = compound_offset
    int64 name_length = mc_string_length(field_name)
    while position < len(data):
        int64 tag_type = data[position]
        position = position + 1
        if tag_type == 0:
            return decode_result(0, 0, position)
        int64[] name = read_nbt_string(data, position)
        if name[0] != 1:
            return decode_result(-1, 0, position)
        position = name[2] + name[1]
        bool matches = name[1] == name_length
        int64 index = 0
        while matches and index < name_length:
            if data[name[2] + index] != mc_string_byte(field_name, index):
                matches = false
            index = index + 1
        if matches:
            return decode_result(1, tag_type, position)
        int64[] child = skip_nbt_payload(data, tag_type, position, 0)
        if child[0] != 1 or child[2] <= position:
            return decode_result(-1, 0, position)
        position = child[2]
    return decode_result(-1, 0, position)

public def nbt_int_field(data: int64[], compound_offset: int64,
                         field_name: str) -> int64[]:
    int64[] field = find_nbt_field(data, compound_offset, field_name)
    if field[0] != 1 or field[1] != 3 or field[2] + 4 > len(data):
        return decode_result(-1, 0, compound_offset)
    return decode_result(1, decode_be_int32(data, field[2]), field[2] + 4)

public def parse_dimension_type_entry(data: int64[], nbt_offset: int64,
                                      registry: VDimensionRegistry*,
                                      entry_index: int64) -> int:
    if nbt_offset < 0 or nbt_offset >= len(data) or data[nbt_offset] != 10:
        return 0
    int64 root = nbt_offset + 1
    int64[] min_y = nbt_int_field(data, root, "min_y")
    int64[] height = nbt_int_field(data, root, "height")
    if min_y[0] != 1 or height[0] != 1:
        int64[] element = find_nbt_field(data, root, "element")
        if element[0] != 1 or element[1] != 10:
            return 0
        min_y = nbt_int_field(data, element[2], "min_y")
        height = nbt_int_field(data, element[2], "height")
    if min_y[0] != 1 or height[0] != 1:
        return 0
    return vdimension_registry_add_dimension(registry, (int)entry_index,
                                              (int)min_y[1], (int)height[1])

public def parse_configuration_registry(body: int64[], packet_offset: int64,
                                        registry: VDimensionRegistry*) -> int:
    int64[] key = read_string_field(body, packet_offset, 32767)
    if key[0] != 1:
        return 0
    int64[] entry_count = decode_varint(body, key[2] + key[1])
    if entry_count[0] != 1 or entry_count[1] < 0 or entry_count[1] > 65536:
        return 0
    bool dimensions = nbt_string_equals(body, key, "minecraft:dimension_type")
    bool biomes = nbt_string_equals(body, key, "minecraft:worldgen/biome")
    if (dimensions or biomes) and entry_count[1] < 1:
        return 0
    if dimensions and entry_count[1] > 256:
        return 0

    int64 position = entry_count[2]
    int64 index = 0
    while index < entry_count[1]:
        int64[] name = read_string_field(body, position, 32767)
        if name[0] != 1:
            return 0
        position = name[2] + name[1]
        if position >= len(body) or (body[position] != 0 and body[position] != 1):
            return 0
        int64 has_data = body[position]
        position += 1
        if has_data == 1:
            if position >= len(body) or body[position] != 10:
                return 0
            if dimensions and parse_dimension_type_entry(body, position, registry, index) == 0:
                return 0
            int64[] end = skip_nbt_payload(body, 10, position + 1, 0)
            if end[0] != 1 or end[2] <= position:
                return 0
            position = end[2]
        index += 1
    if position != len(body):
        return 0
    if dimensions and vdimension_registry_finish_dimensions(registry, (int)entry_count[1]) == 0:
        return 0
    if biomes and vdimension_registry_set_biome_count(registry, (int)entry_count[1]) == 0:
        return 0
    return 1

public def print_nbt_text_depth(data: int64[], tag_type: int64, offset: int64, depth: int64) -> int:
    if depth > 64:
        print("[component nesting limit]")
        return 0
    if tag_type == 8:
        int64[] value = read_nbt_string(data, offset)
        if value[0] != 1:
            return 1
        int64 index = value[2]
        while index < value[2] + value[1]:
            mc_write_byte(data[index])
            index = index + 1
        return 0
    if tag_type == 10:
        int64[] text_field = find_nbt_field(data, offset, "text")
        if text_field[0] == 1:
            if print_nbt_text_depth(data, text_field[1], text_field[2], depth + 1) != 0:
                return 1
        else:
            int64[] translate_field = find_nbt_field(data, offset, "translate")
            if translate_field[0] == 1:
                print("[translation: ")
                if print_nbt_text_depth(data, translate_field[1], translate_field[2], depth + 1) != 0:
                    return 1
                print("]")
            else:
                print("[component]")
        int64[] extra = find_nbt_field(data, offset, "extra")
        if extra[0] == 1 and (extra[1] == 9 and extra[2] + 5 <= len(data)):
            int64 element_type = data[extra[2]]
            int64 count = decode_be_int32(data, extra[2] + 1)
            if count < 0 or count > 256:
                print("[component extras omitted]")
                return 0
            int64 position = extra[2] + 5
            int64 index = 0
            while index < count:
                if print_nbt_text_depth(data, element_type, position, depth + 1) != 0:
                    return 1
                int64[] element_end = skip_nbt_payload(data, element_type, position, 0)
                if element_end[0] != 1:
                    return 1
                position = element_end[2]
                index = index + 1
        return 0
    print("[unsupported component]")
    return 0

public def print_nbt_text(data: int64[], tag_type: int64, offset: int64) -> int:
    return print_nbt_text_depth(data, tag_type, offset, 0)

public def append_nbt_string_field(data: int64[], position: int64, key: int64[], key_length: int64, value: str, value_length: int64) -> int64:
    data[position] = 8
    position = position + 1
    data[position] = key_length >> 8 & 0xFF
    data[position + 1] = key_length & 0xFF
    position = position + 2
    int64 index = 0
    while index < key_length:
        data[position + index] = key[index]
        index = index + 1
    position = position + key_length
    data[position] = value_length >> 8 & 0xFF
    data[position + 1] = value_length & 0xFF
    position = position + 2
    index = 0
    while index < value_length:
        data[position + index] = mc_string_byte(value, index)
        index = index + 1
    return position + value_length

public def append_nbt_string_bytes(data: int64[], position: int64, key: int64[], key_length: int64, value: int64[], value_offset: int64, value_length: int64) -> int64:
    data[position] = 8
    position = position + 1
    data[position] = key_length >> 8 & 0xFF
    data[position + 1] = key_length & 0xFF
    position = position + 2
    int64 index = 0
    while index < key_length:
        data[position + index] = key[index]
        index = index + 1
    position = position + key_length
    data[position] = value_length >> 8 & 0xFF
    data[position + 1] = value_length & 0xFF
    position = position + 2
    index = 0
    while index < value_length:
        data[position + index] = value[value_offset + index]
        index = index + 1
    return position + value_length

public def append_nbt_byte_field(data: int64[], position: int64, key: int64[], key_length: int64, value: int64) -> int64:
    data[position] = 1
    position = position + 1
    data[position] = key_length >> 8 & 0xFF
    data[position + 1] = key_length & 0xFF
    position = position + 2
    int64 index = 0
    while index < key_length:
        data[position + index] = key[index]
        index = index + 1
    data[position + key_length] = value & 0xFF
    return position + (key_length + 1)

public def append_nbt_float_field(data: int64[], position: int64, key: int64[], key_length: int64, value: double) -> int64:
    data[position] = 5
    position = position + 1
    data[position] = key_length >> 8 & 0xFF
    data[position + 1] = key_length & 0xFF
    position = position + 2
    int64 index = 0
    while index < key_length:
        data[position + index] = key[index]
        index = index + 1
    position = position + key_length
    index = 0
    while index < 4:
        data[position + index] = mc_float_be_byte(value, index)
        index = index + 1
    return position + 4

public def encode_dialog_click(packet_id: int64, action_id: int64[], action_id_length: int64, tag_payload: int64[], tag_payload_length: int64) -> int64[]:
    int64[] id_length = encode_varint(action_id_length)
    int64[] tag_length = encode_varint(tag_payload_length)
    int64[] payload = new int64[len(id_length) + (action_id_length + (len(tag_length) + tag_payload_length))]
    int64 index = 0
    while index < len(id_length):
        payload[index] = id_length[index]
        index = index + 1
    int64 position = len(id_length)
    index = 0
    while index < action_id_length:
        payload[position + index] = action_id[index]
        index = index + 1
    position = position + action_id_length
    index = 0
    while index < len(tag_length):
        payload[position + index] = tag_length[index]
        index = index + 1
    position = position + len(tag_length)
    index = 0
    while index < tag_payload_length:
        payload[position + index] = tag_payload[index]
        index = index + 1
    return encode_packet_frame(packet_id, payload)

public def print_dialog_body_entry(body: int64[], entry_offset: int64) -> int:
    int64[] body_type = find_nbt_field(body, entry_offset, "type")
    if body_type[0] != 1 or body_type[1] != 8:
        print("Dialog body entry has no supported type")
        return 1
    int64[] kind = read_nbt_string(body, body_type[2])
    if nbt_string_equals(body, kind, "minecraft:plain_message") or nbt_string_equals(body, kind, "plain_message"):
        int64[] contents = find_nbt_field(body, entry_offset, "contents")
        if contents[0] != 1:
            print("Dialog message has no contents")
            return 1
        if print_nbt_text(body, contents[1], contents[2]) != 0:
            print("Could not decode dialog message")
            return 1
        print("")
        return 0
    if nbt_string_equals(body, kind, "minecraft:item") or nbt_string_equals(body, kind, "item"):
        int64[] description = find_nbt_field(body, entry_offset, "description")
        if description[0] == 1:
            if print_nbt_text(body, description[1], description[2]) != 0:
                print("Could not decode dialog item description")
                return 1
        else:
            print("[item]")
        print("")
        return 0
    print("[unsupported dialog body element]")
    return 0

public def print_dialog_body(body: int64[], body_field: int64[]) -> int:
    if body_field[0] != 1:
        return 0
    if body_field[1] == 10:
        return print_dialog_body_entry(body, body_field[2])
    if body_field[1] != 9 or body_field[2] + 5 > len(body):
        print("Dialog body list is malformed")
        return 1
    int64 element_type = body[body_field[2]]
    int64 count = decode_be_int32(body, body_field[2] + 1)
    if count < 0 or count > 128:
        print("Dialog has too many body elements")
        return 1
    int64 position = body_field[2] + 5
    int64 index = 0
    while index < count:
        if element_type == 10:
            if print_dialog_body_entry(body, position) != 0:
                return 1
            int64[] element_end = skip_nbt_payload(body, element_type, position, 0)
            if element_end[0] != 1:
                print("Malformed dialog body element")
                return 1
            position = element_end[2]
        else:
            int64[] element_end = skip_nbt_payload(body, element_type, position, 0)
            if element_end[0] != 1:
                print("Malformed dialog body element")
                return 1
            print("[unsupported dialog body element]")
            position = element_end[2]
        index = index + 1
    return 0

public def handle_configuration_dialog(socket_handle: int64, body: int64[], packet_offset: int64, play_state: bool) -> int:
    int64 root_offset = packet_offset
    if play_state:
        int64[] holder_id = decode_varint(body, packet_offset)
        if holder_id[0] != 1:
            print("Malformed Play dialog holder")
            return 1
        if holder_id[1] != 0:
            print(f"Dialog references an unavailable registry entry {holder_id[1] - 1}")
            return 1
        root_offset = holder_id[2]
    if root_offset >= len(body) or body[root_offset] != 10:
        print("Malformed configuration dialog: expected a compound NBT root")
        return 1
    int64 root = root_offset + 1
    int64[] title = find_nbt_field(body, root, "title")
    print("Server dialog:")
    if title[0] == 1:
        print("Title: ")
        if print_nbt_text(body, title[1], title[2]) != 0:
            print("Could not decode dialog title")
            return 1
        print("")
    int64[] dialog_body = find_nbt_field(body, root, "body")
    if dialog_body[0] == 1:
        print("Message:")
        if print_dialog_body(body, dialog_body) != 0:
            return 1
    int64[] input_list = find_nbt_field(body, root, "inputs")
    int64[] input_values = new int64[65536]
    int64 value_position = 1
    if input_list[0] == 1:
        if input_list[1] != 9 or input_list[2] + 5 > len(body):
            print("Unsupported or malformed dialog input list")
            return 1
        int64 element_type = body[input_list[2]]
        int64 input_count = decode_be_int32(body, input_list[2] + 1)
        if element_type != 10 or (input_count < 0 or input_count > 32):
            print("Unsupported dialog inputs; expected at most 32 input controls")
            return 1
        int64 position = input_list[2] + 5
        int64 input_index = 0
        while input_index < input_count:
            int64[] key = find_nbt_field(body, position, "key")
            int64[] control_type = find_nbt_field(body, position, "type")
            int64[] label = find_nbt_field(body, position, "label")
            if key[0] != 1 or (key[1] != 8 or (control_type[0] != 1 or control_type[1] != 8)):
                print("Malformed or unsupported dialog input control")
                return 1
            int64[] key_value = read_nbt_string(body, key[2])
            int64[] kind_value = read_nbt_string(body, control_type[2])
            if key_value[0] != 1 or kind_value[0] != 1:
                print("Malformed dialog input name")
                return 1
            int64 key_bytes_length = key_value[1]
            int64[] key_bytes = new int64[key_bytes_length]
            int64 copy_index = 0
            while copy_index < key_bytes_length:
                key_bytes[copy_index] = body[key_value[2] + copy_index]
                copy_index = copy_index + 1
            print("Input ")
            if label[0] == 1 and print_nbt_text(body, label[1], label[2]) != 0:
                print("Could not decode dialog input label")
                return 1
            print(":")
            if nbt_string_equals(body, kind_value, "minecraft:text") or nbt_string_equals(body, kind_value, "text"):
                int64[] value = read_dialog_line()
                int64 value_length = value[1]
                if value[0] != 1 or (value_length > 4096 or value_position + (key_value[1] + (value_length + 5)) > 65535):
                    print("Dialog input is too long")
                    return 1
                value_position = append_nbt_string_bytes(input_values, value_position, key_bytes, key_bytes_length, value, 2, value_length)
                mc_stdin_line_done()
            elif nbt_string_equals(body, kind_value, "minecraft:boolean") or nbt_string_equals(body, kind_value, "boolean"):
                print("Enter true or false:")
                int64[] boolean_text = read_dialog_line()
                if boolean_text[0] != 1:
                    print("Could not read the boolean dialog input")
                    return 1
                int64 boolean_value = 0
                if dialog_line_equals(boolean_text, "true") or (dialog_line_equals(boolean_text, "yes") or dialog_line_equals(boolean_text, "1")):
                    boolean_value = 1
                elif not dialog_line_equals(boolean_text, "false") and (not dialog_line_equals(boolean_text, "no") and not dialog_line_equals(boolean_text, "0")):
                    print("Expected true/false, yes/no, or 1/0")
                    return 1
                value_position = append_nbt_byte_field(input_values, value_position, key_bytes, key_bytes_length, boolean_value)
                mc_stdin_line_done()
            elif nbt_string_equals(body, kind_value, "minecraft:single_option") or nbt_string_equals(body, kind_value, "single_option"):
                int64[] options = find_nbt_field(body, position, "options")
                if options[0] != 1 or (options[1] != 9 or options[2] + 5 > len(body)):
                    print("Dialog single-option input has no valid option list")
                    return 1
                int64 option_type = body[options[2]]
                int64 option_count = decode_be_int32(body, options[2] + 1)
                if option_count < 1 or (option_count > 128 or option_type != 8 and option_type != 10):
                    print("Dialog option list is unsupported or malformed")
                    return 1
                int64 option_position = options[2] + 5
                int64[] option_offsets = new int64[128]
                int64[] option_lengths = new int64[128]
                int64 option_index = 0
                while option_index < option_count:
                    int64 option_start = option_position
                    if option_type == 10:
                        int64[] option_id = find_nbt_field(body, option_position, "id")
                        if option_id[0] != 1 or option_id[1] != 8:
                            print("Dialog option entry has no string id")
                            return 1
                        int64[] option_string = read_nbt_string(body, option_id[2])
                        option_offsets[option_index] = option_string[2]
                        option_lengths[option_index] = option_string[1]
                    else:
                        int64[] option_string = read_nbt_string(body, option_position)
                        if option_string[0] != 1:
                            print("Malformed dialog option")
                            return 1
                        option_offsets[option_index] = option_string[2]
                        option_lengths[option_index] = option_string[1]
                    print(option_index + 1)
                    print(": ")
                    int64 display_offset = option_offsets[option_index]
                    int64 display_length = option_lengths[option_index]
                    if option_type == 10:
                        int64[] option_label = find_nbt_field(body, option_start, "display")
                        if option_label[0] == 1:
                            if print_nbt_text(body, option_label[1], option_label[2]) != 0:
                                print("Could not decode dialog option label")
                                return 1
                        else:
                            int64 display_index = 0
                            while display_index < display_length:
                                mc_write_byte(body[display_offset + display_index])
                                display_index = display_index + 1
                    else:
                        int64 display_index = 0
                        while display_index < display_length:
                            mc_write_byte(body[display_offset + display_index])
                            display_index = display_index + 1
                    print("")
                    if option_type == 10:
                        int64[] option_end = skip_nbt_payload(body, 10, option_start, 0)
                        if option_end[0] != 1:
                            print("Malformed dialog option entry")
                            return 1
                        option_position = option_end[2]
                    else:
                        option_position = option_offsets[option_index] + option_lengths[option_index]
                    option_index = option_index + 1
                print("Select an option by number:")
                int64[] option_choice_text = read_dialog_line()
                int64[] option_choice = parse_dialog_choice(option_choice_text)
                if option_choice[0] != 1 or option_choice[1] > option_count:
                    print("Invalid dialog option selection")
                    return 1
                mc_stdin_line_done()
                int64 selected = option_choice[1] - 1
                value_position = append_nbt_string_bytes(input_values, value_position, key_bytes, key_bytes_length, body, option_offsets[selected], option_lengths[selected])
            elif nbt_string_equals(body, kind_value, "minecraft:number_range") or nbt_string_equals(body, kind_value, "number_range"):
                int64[] range_start = find_nbt_field(body, position, "start")
                int64[] range_end = find_nbt_field(body, position, "end")
                if range_start[0] != 1 or (range_end[0] != 1 or (range_start[1] != 5 or (range_end[1] != 5 or (range_start[2] + 4 > len(body) or range_end[2] + 4 > len(body))))):
                    print("Dialog number range is malformed or unsupported")
                    return 1
                double minimum = decode_be_float(body, range_start[2])
                double maximum = decode_be_float(body, range_end[2])
                double midpoint = (minimum + maximum) / 2.0
                print(f"Enter a number from {minimum} to {maximum} (default {midpoint}):")
                int64[] number_text = read_dialog_line()
                if number_text[0] != 1:
                    print("Could not read the number-range dialog input")
                    return 1
                double numeric_value = midpoint
                if number_text[1] > 0:
                    numeric_value = mc_parse_finite_stdin_line()
                mc_stdin_line_done()
                if mc_is_finite_double(numeric_value) == 0 or (numeric_value < minimum or numeric_value > maximum):
                    print("Number is invalid or outside the dialog\'s allowed range")
                    return 1
                value_position = append_nbt_float_field(input_values, value_position, key_bytes, key_bytes_length, numeric_value)
            else:
                print("Unsupported dialog input control type")
                return 1
            int64[] input_end = skip_nbt_payload(body, 10, position, 0)
            if input_end[0] != 1:
                print("Malformed dialog input entry")
                return 1
            position = input_end[2]
            input_index = input_index + 1
    input_values[0] = 10
    input_values[value_position] = 0
    int64 values_length = value_position + 1
    int64[] actions = find_nbt_field(body, root, "actions")
    int64[] action_offsets = new int64[64]
    int64 action_count = 0
    int64 action_position = 0
    int64[] dialog_type_field = find_nbt_field(body, root, "type")
    int64[] dialog_type = read_nbt_string(body, dialog_type_field[2])
    if actions[0] == 1:
        if actions[1] != 9 or (actions[2] + 5 > len(body) or body[actions[2]] != 10):
            print("Unsupported or malformed dialog action list")
            return 1
        action_count = decode_be_int32(body, actions[2] + 1)
        if action_count < 0 or action_count > 64:
            print("Dialog has too many actions")
            return 1
        action_position = actions[2] + 5
    elif nbt_string_equals(body, dialog_type, "minecraft:confirmation") or nbt_string_equals(body, dialog_type, "confirmation"):
        int64[] yes_action = find_nbt_field(body, root, "yes")
        int64[] no_action = find_nbt_field(body, root, "no")
        if yes_action[0] == 1 and (yes_action[1] == 10 and (no_action[0] == 1 and no_action[1] == 10)):
            action_count = 2
            action_offsets[0] = yes_action[2]
            action_offsets[1] = no_action[2]
    else:
        int64[] single_action = find_nbt_field(body, root, "action")
        if single_action[0] != 1 or single_action[1] != 10:
            single_action = find_nbt_field(body, root, "exit_action")
        if single_action[0] == 1 and single_action[1] == 10:
            action_count = 1
            action_offsets[0] = single_action[2]
    if action_count == 0:
        if nbt_string_equals(body, dialog_type, "minecraft:notice") or nbt_string_equals(body, dialog_type, "notice"):
            print("Notice dialog has no server action; acknowledged locally")
            return 0
        print("This dialog has no selectable actions")
        return 1
    int64 action_index = 0
    while action_index < action_count:
        if actions[0] == 1:
            action_offsets[action_index] = action_position
        int64[] label = find_nbt_field(body, action_offsets[action_index], "label")
        print(action_index + 1)
        print(": ")
        if label[0] == 1 and print_nbt_text(body, label[1], label[2]) != 0:
            print("Could not decode dialog action label")
            return 1
        print("")
        if actions[0] == 1:
            int64[] action_end = skip_nbt_payload(body, 10, action_position, 0)
            if action_end[0] != 1:
                print(f"Malformed dialog action entry at {action_position}, status {action_end[0]}, offset {action_end[2]}")
                return 1
            action_position = action_end[2]
        action_index = action_index + 1
    print("Choose a dialog action by number:")
    int64[] choice_text = read_dialog_line()
    int64[] choice = parse_dialog_choice(choice_text)
    mc_stdin_line_done()
    if choice[0] != 1 or choice[1] > action_count:
        print(f"Invalid dialog action selection: status {choice[0]}, value {choice[1]}, actions {action_count}")
        return 1
    int64[] action = find_nbt_field(body, action_offsets[choice[1] - 1], "action")
    if action[0] == 0:
        print("Selected dialog action has no server-side action")
        return 0
    if action[0] != 1 or action[1] != 10:
        print("Selected dialog action has a malformed response")
        return 1
    int64[] action_type = find_nbt_field(body, action[2], "type")
    int64[] action_id = find_nbt_field(body, action[2], "id")
    if action_type[0] != 1 or (action_type[1] != 8 or (action_id[0] != 1 or action_id[1] != 8)):
        print("Selected dialog action has no supported custom-action id")
        return 1
    int64[] type_value = read_nbt_string(body, action_type[2])
    int64[] id_value = read_nbt_string(body, action_id[2])
    if type_value[0] != 1 or id_value[0] != 1:
        print("Malformed custom dialog action")
        return 1
    if not nbt_string_equals(body, type_value, "minecraft:dynamic/custom") and (not nbt_string_equals(body, type_value, "dynamic/custom") and (not nbt_string_equals(body, type_value, "minecraft:custom") and not nbt_string_equals(body, type_value, "custom"))):
        print("Selected dialog action type cannot be sent during Configuration; only custom click actions are supported")
        return 1
    int64 id_length = id_value[1]
    int64[] encoded_id = new int64[id_length]
    int64 index = 0
    while index < id_length:
        encoded_id[index] = body[id_value[2] + index]
        index = index + 1
    int64[] click_payload = new int64[65536]
    int64 click_payload_length = values_length
    index = 0
    while index < values_length:
        click_payload[index] = input_values[index]
        index = index + 1
    if nbt_string_equals(body, type_value, "minecraft:dynamic/custom") or nbt_string_equals(body, type_value, "dynamic/custom"):
        int64[] additions = find_nbt_field(body, action[2], "additions")
        int64 additions_fields_length = 0
        if additions[0] == 1 and additions[1] == 10:
            int64[] additions_end = skip_nbt_payload(body, 10, additions[2], 0)
            if additions_end[0] != 1:
                print("Malformed custom dialog action additions")
                return 1
            additions_fields_length = additions_end[2] - (additions[2] + 1)
        int64 input_fields_length = value_position - 1
        if additions_fields_length + (input_fields_length + 2) > 65536:
            print("Custom dialog response exceeds the protocol payload limit")
            return 1
        click_payload_length = additions_fields_length + (input_fields_length + 2)
        click_payload[0] = 10
        int64 payload_position = 1
        if additions[0] == 1 and additions[1] == 10:
            index = additions[2]
            while index < additions[2] + additions_fields_length:
                click_payload[payload_position] = body[index]
                payload_position = payload_position + 1
                index = index + 1
        index = 1
        while index < value_position:
            click_payload[payload_position] = input_values[index]
            payload_position = payload_position + 1
            index = index + 1
        click_payload[payload_position] = 0
    elif nbt_string_equals(body, type_value, "minecraft:custom") or nbt_string_equals(body, type_value, "custom"):
        int64[] custom_payload = find_nbt_field(body, action[2], "payload")
        if custom_payload[0] == 1:
            if custom_payload[1] == 0:
                click_payload[0] = 0
                click_payload_length = 1
            else:
                int64[] payload_end = skip_nbt_payload(body, custom_payload[1], custom_payload[2], 0)
                if payload_end[0] != 1:
                    print("Malformed custom dialog action payload")
                    return 1
                click_payload_length = payload_end[2] - (custom_payload[2] - 1)
                click_payload[0] = custom_payload[1]
                index = 1
                while index < click_payload_length:
                    click_payload[index] = body[custom_payload[2] + (index - 1)]
                    index = index + 1
        else:
            click_payload[0] = 0
            click_payload_length = 1
    int64 click_packet_id = 8
    if play_state:
        click_packet_id = 68
    int64[] click = encode_dialog_click(click_packet_id, encoded_id, id_length, click_payload, click_payload_length)
    if send_bytes(socket_handle, click) != 0:
        print("Failed to send custom dialog action")
        return 1
    print("Custom dialog response sent")
    return 0

public def encode_chat_message(message: int64[], message_length: int64, timestamp: int64) -> int64[]:
    int64[] encoded_length = encode_varint(message_length)
    int64 payload_length = len(encoded_length) + (message_length + 22)
    int64[] payload = new int64[payload_length]
    int64 index = 0
    while index < len(encoded_length):
        payload[index] = encoded_length[index]
        index = index + 1
    int64 position = len(encoded_length)
    index = 0
    while index < message_length:
        payload[position + index] = message[index]
        index = index + 1
    position = position + message_length
    index = 0
    while index < 8:
        payload[position + index] = timestamp >> (7 - index) * 8 & 0xFF
        payload[position + (8 + index)] = 0
        index = index + 1
    position = position + 16
    payload[position] = 0
    payload[position + 1] = 0
    payload[position + 2] = 0
    payload[position + 3] = 0
    payload[position + 4] = 0
    payload[position + 5] = 0
    return encode_packet_frame(9, payload)

public def encode_chat_command(command: int64[], command_length: int64) -> int64[]:
    int64[] encoded_length = encode_varint(command_length)
    int64[] payload = new int64[len(encoded_length) + command_length]
    int64 index = 0
    while index < len(encoded_length):
        payload[index] = encoded_length[index]
        index = index + 1
    index = 0
    while index < command_length:
        payload[len(encoded_length) + index] = command[index + 1]
        index = index + 1
    return encode_packet_frame(7, payload)

public def print_system_chat(body: int64[], offset: int64) -> int:
    if offset >= len(body):
        print("Received an empty system chat packet")
        return 1
    int64 tag_type = body[offset]
    if tag_type == 8:
        int64[] text = read_nbt_string(body, offset + 1)
        if text[0] != 1:
            print("Received a malformed system chat component")
            return 1
        print("Server:")
        int64 index = text[2]
        while index < text[2] + text[1]:
            mc_write_byte(body[index])
            index = index + 1
        print("")
        return 0
    if tag_type == 10:
        int64 position = offset + 1
        while position < len(body):
            int64 field_type = body[position]
            position = position + 1
            if field_type == 0:
                break
            int64[] name = read_nbt_string(body, position)
            if name[0] != 1:
                print("Received a malformed system chat component")
                return 1
            position = name[2] + name[1]
            if field_type != 8:
                print("Received a structured system chat component that cannot be rendered")
                return 0
            int64[] value = read_nbt_string(body, position)
            if value[0] != 1:
                print("Received a malformed system chat component")
                return 1
            if name[1] == 4 and (body[name[2]] == 116 and (body[name[2] + 1] == 101 and (body[name[2] + 2] == 120 and body[name[2] + 3] == 116))):
                print("Server:")
                int64 index = value[2]
                while index < value[2] + value[1]:
                    mc_write_byte(body[index])
                    index = index + 1
                print("")
                return 0
            if name[1] == 9 and (body[name[2]] == 116 and (body[name[2] + 1] == 114 and (body[name[2] + 2] == 97 and (body[name[2] + 3] == 110 and (body[name[2] + 4] == 115 and (body[name[2] + 5] == 108 and (body[name[2] + 6] == 97 and (body[name[2] + 7] == 116 and body[name[2] + 8] == 101)))))))):
                print("Server (untranslated):")
                int64 index = value[2]
                while index < value[2] + value[1]:
                    mc_write_byte(body[index])
                    index = index + 1
                print("")
                return 0
            position = value[2] + value[1]
        print("Received a system chat component without a plain-text field")
        return 0
    print("Received a system chat component in an unsupported format")
    return 0

def chunk_light_mask_has_bit(data: int64[], words_offset: int64,
                             word_count: int64, bit: int64) -> bool:
    if bit < 0 or bit / 64 >= word_count:
        return false
    int64 byte_offset = words_offset + (bit / 64) * 8 + 7 - (bit % 64) / 8
    int64 bit_in_byte = bit % 8
    return (data[byte_offset] & (1 << bit_in_byte)) != 0


def chunk_read_light_mask(data: int64[], offset: int64,
                          bit_limit: int64) -> int64[]:
    int64[] mask = new int64[4]
    int64[] count = decode_varint(data, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > (bit_limit + 63) / 64:
        return mask
    if count[2] + count[1] * 8 > len(data):
        return mask
    int64 bit = bit_limit
    while bit < count[1] * 64:
        if chunk_light_mask_has_bit(data, count[2], count[1], bit):
            return mask
        bit += 1
    mask[0] = 1
    mask[1] = count[2]
    mask[2] = count[1]
    mask[3] = count[2] + count[1] * 8
    return mask


def chunk_mask_bit_count(data: int64[], words_offset: int64,
                         word_count: int64, bit_limit: int64) -> int64:
    int64 total = 0
    int64 bit = 0
    while bit < bit_limit:
        if chunk_light_mask_has_bit(data, words_offset, word_count, bit):
            total += 1
        bit += 1
    return total


def chunk_masks_overlap(data: int64[], first_offset: int64,
                        first_words: int64, second_offset: int64,
                        second_words: int64, bit_limit: int64) -> bool:
    int64 bit = 0
    while bit < bit_limit:
        if chunk_light_mask_has_bit(data, first_offset, first_words, bit) and chunk_light_mask_has_bit(data, second_offset, second_words, bit):
            return true
        bit += 1
    return false


def chunk_skip_block_entities(data: int64[], offset: int64) -> int64[]:
    int64[] result = decode_result(-1, 0, offset)
    int64[] count = decode_varint(data, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > 4096:
        return result
    int64 position = count[2]
    int64 index = 0
    while index < count[1]:
        if position + 3 > len(data) or data[position] < 0 or data[position] > 255:
            return result
        position += 3
        int64[] entity_type = decode_varint(data, position)
        if entity_type[0] != 1 or entity_type[1] < 0:
            return result
        position = entity_type[2]
        if position >= len(data) or data[position] != 10:
            return result
        int64[] nbt_end = skip_nbt_payload(data, 10, position + 1, 0)
        if nbt_end[0] != 1 or nbt_end[2] <= position:
            return result
        position = nbt_end[2]
        index += 1
    return decode_result(1, count[1], position)


def chunk_read_light_arrays(data: int64[], offset: int64,
                            mask_offset: int64, mask_words: int64,
                            bit_limit: int64, sections: char*,
                            sky_light: bool) -> int64[]:
    int64[] failure = decode_result(-1, 0, offset)
    int64[] count = decode_varint(data, offset)
    if count[0] != 1 or count[1] != chunk_mask_bit_count(
        data, mask_offset, mask_words, bit_limit):
        return failure
    int64 position = count[2]
    int64 bit = 0
    while bit < bit_limit:
        if chunk_light_mask_has_bit(data, mask_offset, mask_words, bit):
            int64[] length = decode_varint(data, position)
            if length[0] != 1 or length[1] != 2048 or length[2] + 2048 > len(data):
                return failure
            if bit > 0 and bit < bit_limit - 1:
                VSection* section = (VSection*)vt_ptr_get(sections, (int)(bit - 1))
                char* target = section.block_light
                if sky_light:
                    target = section.sky_light
                int64 byte = 0
                while byte < 2048:
                    if data[length[2] + byte] < 0 or data[length[2] + byte] > 255:
                        return failure
                    vt_put(target, (int)(byte), (int)data[length[2] + byte])
                    byte += 1
            position = length[2] + 2048
        bit += 1
    return decode_result(1, count[1], position)


def chunk_decode_light_and_entities(world: VWorld*, body: int64[],
                                    offset: int64, sections: char*) -> int:
    int64[] entities = chunk_skip_block_entities(body, offset)
    if entities[0] != 1:
        print("Malformed chunk block-entity data")
        return 1
    int64 bit_limit = world.section_count + 2
    int64 position = entities[2]
    int64[] sky_mask = chunk_read_light_mask(body, position, bit_limit)
    if sky_mask[0] != 1:
        print("Malformed chunk sky-light mask")
        return 1
    position = sky_mask[3]
    int64[] block_mask = chunk_read_light_mask(body, position, bit_limit)
    if block_mask[0] != 1:
        print("Malformed chunk block-light mask")
        return 1
    position = block_mask[3]
    int64[] empty_sky_mask = chunk_read_light_mask(body, position, bit_limit)
    if empty_sky_mask[0] != 1:
        print("Malformed chunk empty-sky-light mask")
        return 1
    position = empty_sky_mask[3]
    int64[] empty_block_mask = chunk_read_light_mask(body, position, bit_limit)
    if empty_block_mask[0] != 1:
        print("Malformed chunk empty-block-light mask")
        return 1
    position = empty_block_mask[3]
    if chunk_masks_overlap(body, sky_mask[1], sky_mask[2],
                           empty_sky_mask[1], empty_sky_mask[2], bit_limit):
        print("Chunk sky-light masks overlap")
        return 1
    if chunk_masks_overlap(body, block_mask[1], block_mask[2],
                           empty_block_mask[1], empty_block_mask[2], bit_limit):
        print("Chunk block-light masks overlap")
        return 1
    int64[] sky_arrays = chunk_read_light_arrays(
        body, position, sky_mask[1], sky_mask[2], bit_limit, sections, true)
    if sky_arrays[0] != 1:
        print("Malformed chunk sky-light arrays")
        return 1
    position = sky_arrays[2]
    int64[] block_arrays = chunk_read_light_arrays(
        body, position, block_mask[1], block_mask[2], bit_limit, sections, false)
    if block_arrays[0] != 1 or block_arrays[2] != len(body):
        print("Malformed chunk block-light arrays or trailing data")
        return 1
    return 0


# Chunk heightmaps: a varint count of entries, each one a varint heightmap
# type id followed by a varint-counted big endian long array of 256 nine-bit
# absolute heights. Types the engine does not store are still walked, so a
# server that sends ocean floor data does not break the chunk, but a known
# type with the wrong number of longs is rejected rather than misread.
def chunk_heightmap_kind(type_id: int64) -> int:
    if type_id == hm_wire_motion_blocking():
        return hm_motion_blocking()
    if type_id == hm_wire_world_surface():
        return hm_world_surface()
    return -1


public def chunk_read_heightmaps(data: int64[], offset: int64,
                                 values: int*) -> int64[]:
    if values == null or offset < 0:
        return decode_result(-1, 0, offset)
    int64[] count = decode_varint(data, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > hm_wire_kind_count():
        return decode_result(-1, 0, offset)
    int64 position = count[2]
    int64 index = 0
    while index < count[1]:
        int64[] type_id = decode_varint(data, position)
        if type_id[0] != 1 or type_id[1] < 0:
            return decode_result(-1, index, position)
        position = type_id[2]
        int64[] longs = decode_varint(data, position)
        int64 packed_bytes = hm_long_count() * 8
        if longs[0] != 1 or longs[1] != hm_long_count() or longs[2] + packed_bytes > len(data):
            return decode_result(-1, index, position)
        position = longs[2]
        int64[] words = new int64[hm_long_count()]
        int64 word_index = 0
        while word_index < hm_long_count():
            int64 word = 0
            int64 byte_index = 0
            while byte_index < 8:
                word = word << 8 | data[position + word_index * 8 + byte_index]
                byte_index = byte_index + 1
            words[word_index] = word
            word_index = word_index + 1
        position = position + packed_bytes
        int kind = chunk_heightmap_kind(type_id[1])
        if kind >= 0 and hm_unpack(words, kind, values) == 0:
            return decode_result(-1, index, position)
        index = index + 1
    return decode_result(1, index, position)


public def decode_chunk_sections(world: VWorld*, body: int64[],
                                 packet_offset: int64) -> int:
    if world == null or packet_offset < 0 or packet_offset + 8 > len(body):
        return 1
    int64 chunk_x = decode_be_int32(body, packet_offset)
    int64 chunk_z = decode_be_int32(body, packet_offset + 4)
    int64 heightmaps_offset = packet_offset + 8
    int* heights = hm_new()
    int64[] heightmaps = chunk_read_heightmaps(body, heightmaps_offset, heights)
    if heightmaps[0] != 1:
        print("Malformed chunk heightmaps")
        hm_free(heights)
        return 1
    int64[] data_length = decode_varint(body, heightmaps[2])
    if data_length[0] != 1 or data_length[1] < 0 or data_length[2] + data_length[1] > len(body):
        print("Malformed chunk section-data length")
        hm_free(heights)
        return 1
    VBuf* section_data = vbuf_new((int)data_length[1])
    int64 index = 0
    while index < data_length[1]:
        vbuf_put_u8(section_data, (uint64)body[data_length[2] + index])
        index += 1
    section_data.pos = 0
    int sections_ok = 0
    char* sections = sec_read_wire_sections(
        section_data, world.section_count, world.min_section,
        world.block_global_bits, world.biome_global_bits, &sections_ok)
    vbuf_free(section_data)
    if sections_ok == 0 or sections == null:
        print("Malformed or unsupported chunk section palettes")
        hm_free(heights)
        return 1
    int64 tail_offset = data_length[2] + data_length[1]
    if chunk_decode_light_and_entities(world, body, tail_offset, sections) != 0:
        vworld_free_column(sections, world.section_count)
        hm_free(heights)
        return 1
    if vworld_replace_sections(world, (int)chunk_x, (int)chunk_z, sections) == 0:
        vworld_free_column(sections, world.section_count)
        hm_free(heights)
        print("Loaded chunk capacity reached")
        return 1
    if vworld_set_heightmaps(world, (int)chunk_x, (int)chunk_z, heights) == 0:
        hm_free(heights)
    print(f"Decoded chunk ({chunk_x}, {chunk_z}) into {world.section_count} sections with lighting")
    return 0


public def read_play_login_dimension(body: int64[],
                                     packet_offset: int64) -> int64[]:
    if packet_offset < 0 or packet_offset + 5 > len(body):
        return decode_result(-1, 0, packet_offset)
    int64 position = packet_offset + 4
    position += 1
    int64[] dimension_count = decode_varint(body, position)
    if dimension_count[0] != 1 or dimension_count[1] < 1 or dimension_count[1] > 1024:
        return decode_result(-1, 0, position)
    position = dimension_count[2]
    int64 index = 0
    while index < dimension_count[1]:
        int64[] name = read_string_field(body, position, 32767)
        if name[0] != 1:
            return decode_result(-1, 0, position)
        position = name[2] + name[1]
        index += 1
    index = 0
    while index < 3:
        int64[] value = decode_varint(body, position)
        if value[0] != 1 or value[1] < 0:
            return decode_result(-1, 0, position)
        position = value[2]
        index += 1
    if position + 3 > len(body):
        return decode_result(-1, 0, position)
    position += 3
    int64[] dimension_type = decode_varint(body, position)
    if dimension_type[0] != 1 or dimension_type[1] < 0:
        return decode_result(-1, 0, position)
    return dimension_type


public def play_session_loop(socket_handle: int64, world: VWorld*,
                             registry: VDimensionRegistry*) -> int:
    int64[] tracked_chunks_x = new int64[8192]
    int64[] tracked_chunks_z = new int64[8192]
    int64 tracked_chunk_count = 0
    int64[] tracked_entity_ids = new int64[8192]
    int64 tracked_entity_count = 0
    int64 packet_count = 0
    bool received_play_login = false
    while packet_count < 1000000:
        int64 events = mc_poll_events(socket_handle)
        if events < 0:
            print("Could not poll Play socket and terminal input")
            return 1
        if events & 2 and received_play_login:
            int64 line_length = mc_stdin_line_length()
            if line_length < 0:
                print("Could not read terminal input")
                return 1
            if line_length == 5 and (mc_stdin_line_byte(0) == 47 and (mc_stdin_line_byte(1) == 113 and (mc_stdin_line_byte(2) == 117 and (mc_stdin_line_byte(3) == 105 and mc_stdin_line_byte(4) == 116)))):
                mc_stdin_line_done()
                print("Leaving Play session")
                return 0
            if line_length > 256:
                print("Chat and command input is limited to 256 UTF-8 bytes")
            elif line_length > 0 and mc_stdin_line_byte(0) == 47:
                if line_length == 1:
                    print("Command cannot be empty")
                else:
                    int64[] command_line = new int64[line_length]
                    int64 index = 0
                    while index < line_length:
                        command_line[index] = mc_stdin_line_byte(index)
                        index = index + 1
                    int64[] command_packet = encode_chat_command(command_line, line_length - 1)
                    if send_bytes(socket_handle, command_packet) != 0:
                        print("Failed to send chat command")
                        return 1
                    print("Command sent")
            elif line_length > 0:
                int64[] chat_line = new int64[line_length]
                int64 index = 0
                while index < line_length:
                    chat_line[index] = mc_stdin_line_byte(index)
                    index = index + 1
                int64 timestamp = mc_time_millis()
                if timestamp < 0:
                    print("Could not read system clock for chat message")
                    return 1
                int64[] chat_packet = encode_chat_message(chat_line, line_length, timestamp)
                if send_bytes(socket_handle, chat_packet) != 0:
                    print("Failed to send chat message")
                    return 1
                print("Chat message sent without a secure-chat signature")
            mc_stdin_line_done()
        if (events & 1) == 0:
            continue
        int64[] incoming = read_packet_frame(socket_handle)
        if incoming[0] != 1:
            if incoming[0] == -5:
                print("Malformed or invalid compressed Play packet")
            else:
                print("Play connection ended or packet framing failed")
            return 1
        int64[] body = frame_body(incoming)
        int64[] packet_id = decode_varint(body, 0)
        if packet_id[0] != 1:
            print("Malformed Play packet id")
            return 1
        if packet_id[1] == 50:
            int64[] dimension_type = read_play_login_dimension(body, packet_id[2])
            if dimension_type[0] != 1:
                print("Malformed Play login dimension metadata")
                return 1
            int64[] dimension = vdimension_registry_dimension(registry, (int)dimension_type[1])
            if registry.dimension_registry_seen == 0 or registry.biome_registry_seen == 0 or dimension[0] == 0:
                print("Configuration did not provide the active dimension and biome registries")
                return 1
            if vworld_set_dimension(world, dimension[1], dimension[2],
                                    registry.block_global_bits,
                                    registry.biome_global_bits) == 0:
                print("Could not configure world for the server dimension")
                return 1
            print(f"Configured dimension sections: min={world.min_section}, count={world.section_count}, block bits={world.block_global_bits}, biome bits={world.biome_global_bits}")
            received_play_login = true
            int64[] player_loaded = new int64[0]
            int64[] response = encode_packet_frame(44, player_loaded)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to acknowledge Play login")
                return 1
            print("Play login accepted; type chat, /command, or /quit")
        elif packet_id[1] == 45:
            if len(body) != packet_id[2] + 8:
                print("Malformed Play keep-alive")
                return 1
            int64[] response = encode_keepalive_response(28, body, packet_id[2])
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to Play keep-alive")
                return 1
        elif packet_id[1] == 62:
            if len(body) != packet_id[2] + 4:
                print("Malformed Play ping")
                return 1
            int64[] pong = new int64[4]
            int64 index = 0
            while index < 4:
                pong[index] = body[packet_id[2] + index]
                index = index + 1
            int64[] response = encode_packet_frame(45, pong)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to answer Play ping")
                return 1
        elif packet_id[1] == 73:
            int64[] teleport_id = decode_varint(body, packet_id[2])
            int64 position_start = teleport_id[2]
            if teleport_id[0] != 1 or position_start + 60 != len(body):
                print("Malformed Play player-position update")
                return 1
            double x = decode_be_int64(body, position_start)
            double y = decode_be_int64(body, position_start + 8)
            double z = decode_be_int64(body, position_start + 16)
            double yaw = decode_be_float(body, position_start + 48)
            double pitch = decode_be_float(body, position_start + 52)
            int64[] encoded_id = encode_varint(teleport_id[1])
            int64[] payload = new int64[len(encoded_id) + 32]
            int64 index = 0
            while index < len(encoded_id):
                payload[index] = encoded_id[index]
                index = index + 1
            int64 output_index = len(encoded_id)
            index = 0
            while index < 8:
                payload[output_index + index] = mc_double_be_byte(x, index)
                payload[output_index + (8 + index)] = mc_double_be_byte(y, index)
                payload[output_index + (16 + index)] = mc_double_be_byte(z, index)
                index = index + 1
            index = 0
            while index < 4:
                payload[output_index + (24 + index)] = mc_float_be_byte(yaw, index)
                index = index + 1
            index = 0
            while index < 4:
                payload[output_index + (28 + index)] = mc_float_be_byte(pitch, index)
                index = index + 1
            int64[] response = encode_packet_frame(0, payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to acknowledge player teleport")
                return 1
        elif packet_id[1] == 46:
            if packet_id[2] + 8 > len(body):
                print("Truncated chunk-with-light packet")
                return 1
            int64 chunk_x = decode_be_int32(body, packet_id[2])
            int64 chunk_z = decode_be_int32(body, packet_id[2] + 4)
            if decode_chunk_sections(world, body, packet_id[2]) != 0:
                print("Could not decode incoming chunk data")
                return 1
            bool found_chunk = false
            int64 index = 0
            while index < tracked_chunk_count:
                if tracked_chunks_x[index] == chunk_x and tracked_chunks_z[index] == chunk_z:
                    found_chunk = true
                    break
                index = index + 1
            if not found_chunk and tracked_chunk_count < 8192:
                tracked_chunks_x[tracked_chunk_count] = chunk_x
                tracked_chunks_z[tracked_chunk_count] = chunk_z
                tracked_chunk_count = tracked_chunk_count + 1
            if not found_chunk:
                print(f"Stored chunk ({chunk_x}, {chunk_z}); loaded chunk count: {tracked_chunk_count}")
        elif packet_id[1] == 38:
            if packet_id[2] + 8 > len(body):
                print("Truncated chunk-unload packet")
                return 1
            int64 chunk_x = decode_be_int32(body, packet_id[2])
            int64 chunk_z = decode_be_int32(body, packet_id[2] + 4)
            int64 index = 0
            while index < tracked_chunk_count:
                if tracked_chunks_x[index] == chunk_x and tracked_chunks_z[index] == chunk_z:
                    int64 source_index = index + 1
                    while source_index < tracked_chunk_count:
                        tracked_chunks_x[source_index - 1] = tracked_chunks_x[source_index]
                        tracked_chunks_z[source_index - 1] = tracked_chunks_z[source_index]
                        source_index = source_index + 1
                    tracked_chunk_count = tracked_chunk_count - 1
                    break
                index = index + 1
            vworld_unload_chunk(world, (int)chunk_x, (int)chunk_z)
            print(f"Forgot chunk ({chunk_x}, {chunk_z})")
        elif packet_id[1] == 1:
            int64[] entity_id = decode_varint(body, packet_id[2])
            if entity_id[0] != 1:
                print("Malformed entity spawn packet")
                return 1
            bool found_entity = false
            int64 index = 0
            while index < tracked_entity_count:
                if tracked_entity_ids[index] == entity_id[1]:
                    found_entity = true
                    break
                index = index + 1
            if not found_entity and tracked_entity_count < 8192:
                tracked_entity_ids[tracked_entity_count] = entity_id[1]
                tracked_entity_count = tracked_entity_count + 1
                print(f"Tracked entity {entity_id[1]}; entity count: {tracked_entity_count}")
        elif packet_id[1] == 78:
            int64[] count = decode_varint(body, packet_id[2])
            if count[0] != 1 or (count[1] < 0 or count[1] > 8192):
                print("Malformed entity-removal packet")
                return 1
            int64 position = count[2]
            int64 index = 0
            while index < count[1]:
                int64[] entity_id = decode_varint(body, position)
                if entity_id[0] != 1:
                    print("Malformed entity id in removal packet")
                    return 1
                int64 entity_index = 0
                while entity_index < tracked_entity_count:
                    if tracked_entity_ids[entity_index] == entity_id[1]:
                        int64 following = entity_index + 1
                        while following < tracked_entity_count:
                            tracked_entity_ids[following - 1] = tracked_entity_ids[following]
                            following = following + 1
                        tracked_entity_count = tracked_entity_count - 1
                        break
                    entity_index = entity_index + 1
                position = entity_id[2]
                index = index + 1
            if position != len(body):
                print("Unexpected data in entity-removal packet")
                return 1
            print(f"Entity removals processed; entity count: {tracked_entity_count}")
        elif packet_id[1] == 11:
            int64[] batch_size = decode_varint(body, packet_id[2])
            if batch_size[0] != 1 or batch_size[2] != len(body):
                print("Malformed chunk-batch-finished packet")
                return 1
            int64[] response_payload = new int64[4]
            response_payload[0] = 66
            response_payload[1] = 128
            response_payload[2] = 0
            response_payload[3] = 0
            int64[] response = encode_packet_frame(11, response_payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to acknowledge chunk batch")
                return 1
            print(f"Chunk batch {batch_size[1]} processed; tracked chunks: {tracked_chunk_count}")
        elif packet_id[1] == 124:
            if print_system_chat(body, packet_id[2]) != 0:
                return 1
        elif packet_id[1] == 66:
            print("Received player chat; signed-chat decoding and secure-session acknowledgements are not implemented")
        elif packet_id[1] == 33:
            print("Received disguised chat; this chat component format is not yet rendered")
        elif packet_id[1] == 16:
            print("Received the server command tree")
        elif packet_id[1] == 143:
            if handle_configuration_dialog(socket_handle, body, packet_id[2], true) != 0:
                print("Could not process the Play dialog")
                return 1
        elif packet_id[1] == 142:
            print("Server cleared the active Play dialog")
        elif packet_id[1] == 32:
            print("Server disconnected during Play")
            return 0
        elif packet_id[1] == 120:
            print("Server requested a return to Configuration; that transition is not implemented")
            return 1
        packet_count = packet_count + 1
    if not received_play_login:
        print("Play packet limit reached before Play login")
    else:
        print("Play packet limit reached")
    return 1


public def play_session(socket_handle: int64,
                        registry: VDimensionRegistry*) -> int:
    VWorld* world = vworld_new(1024, 0, 1,
                               registry.block_global_bits,
                               registry.biome_global_bits)
    int result = play_session_loop(socket_handle, world, registry)
    vworld_free(world)
    return result


public def handle_configuration(socket_handle: int64,
                                registry: VDimensionRegistry*) -> int:
    int64[] client_information = encode_config_client_information()
    if send_bytes(socket_handle, client_information) != 0:
        print("Failed to send configuration client information")
        return 1
    int64 packet_count = 0
    while packet_count < 512:
        int64[] incoming = read_packet_frame(socket_handle)
        if incoming[0] != 1:
            if incoming[0] == -5:
                print("Malformed or invalid compressed Configuration packet")
            else:
                print("Could not read the next configuration packet")
            return 1
        int64[] body = frame_body(incoming)
        int64[] packet_id = decode_varint(body, 0)
        if packet_id[0] != 1:
            print("Malformed configuration packet id")
            return 1
        if packet_id[1] == 3:
            if packet_id[2] != len(body):
                print("Malformed finish-configuration packet")
                return 1
            int64[] empty = new int64[0]
            int64[] acknowledgement = encode_packet_frame(3, empty)
            if send_bytes(socket_handle, acknowledgement) != 0:
                print("Failed to acknowledge configuration")
                return 1
            print("Configuration complete; entered the Play protocol state")
            return 0
        if packet_id[1] == 2:
            print("Server disconnected during configuration")
            return 1
        if packet_id[1] == 4:
            if len(body) != packet_id[2] + 8:
                print("Malformed configuration keep-alive")
                return 1
            int64[] response = encode_keepalive_response(4, body, packet_id[2])
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration keep-alive")
                return 1
        elif packet_id[1] == 5:
            if len(body) != packet_id[2] + 4:
                print("Malformed configuration ping")
                return 1
            int64[] payload = new int64[4]
            int64 index = 0
            while index < 4:
                payload[index] = body[packet_id[2] + index]
                index = index + 1
            int64[] response = encode_packet_frame(5, payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration ping")
                return 1
        elif packet_id[1] == 15:
            int64[] selection = new int64[1]
            selection[0] = 0
            int64[] response = encode_packet_frame(7, selection)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to known-pack selection")
                return 1
        elif packet_id[1] == 0:
            int64[] key = read_string_field(body, packet_id[2], 32767)
            if key[0] != 1 or key[2] + key[1] != len(body):
                print("Malformed configuration cookie request")
                return 1
            int64[] encoded_key_length = encode_varint(key[1])
            int64[] cookie_payload = new int64[len(encoded_key_length) + (key[1] + 1)]
            int64 index = 0
            while index < len(encoded_key_length):
                cookie_payload[index] = encoded_key_length[index]
                index = index + 1
            int64 payload_index = len(encoded_key_length)
            index = 0
            while index < key[1]:
                cookie_payload[payload_index + index] = body[key[2] + index]
                index = index + 1
            cookie_payload[len(cookie_payload) - 1] = 0
            int64[] response = encode_packet_frame(1, cookie_payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration cookie request")
                return 1
        elif packet_id[1] == 9:
            if packet_id[2] + 16 > len(body):
                print("Malformed configuration resource-pack request")
                return 1
            int64[] resource_pack_payload = new int64[17]
            int64 index = 0
            while index < 16:
                resource_pack_payload[index] = body[packet_id[2] + index]
                index = index + 1
            resource_pack_payload[16] = 1
            int64[] response = encode_packet_frame(6, resource_pack_payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to decline configuration resource pack")
                return 1
        elif packet_id[1] == 20:
            int64[] conduct = read_string_field(body, packet_id[2], 32767)
            if conduct[0] != 1 or conduct[2] + conduct[1] != len(body):
                print("Malformed server code of conduct")
                return 1
            print("Server code of conduct:")
            int64 index = conduct[2]
            while index < conduct[2] + conduct[1]:
                mc_write_byte(body[index])
                index = index + 1
            print("")
            print("Accept this code of conduct? (type yes to accept):")
            int64[] consent = read_dialog_line()
            if consent[0] != 1 or not dialog_line_equals(consent, "yes"):
                print("Code of conduct not accepted")
                return 1
            mc_stdin_line_done()
            int64[] consent_acknowledgement = new int64[0]
            int64[] response = encode_packet_frame(9, consent_acknowledgement)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to accept server code of conduct")
                return 1
        elif packet_id[1] == 19:
            if handle_configuration_dialog(socket_handle, body, packet_id[2], false) != 0:
                print("Could not process the server configuration dialog")
                return 1
        elif packet_id[1] == 7:
            if parse_configuration_registry(body, packet_id[2], registry) == 0:
                print("Malformed or unsupported configuration registry data")
                return 1
        elif packet_id[1] == 18:
            print("Server cleared the active configuration dialog")
        elif is_ignorable_configuration_packet(packet_id[1]):
            print(f"Received configuration data packet {packet_id[1]}")
        else:
            print(f"Unsupported configuration packet id {packet_id[1]}")
            return 1
        packet_count = packet_count + 1
    print("Too many configuration packets without finish")
    return 1

public def encode_login_start(username: str, username_length: int64) -> int64[]:
    int64[] body = encode_varint(0)
    body = append_varint(body, username_length)
    int64 index = 0
    while index < username_length:
        append(body, mc_string_byte(username, index))
        index = index + 1
    index = 0
    while index < 16:
        append(body, mc_offline_uuid_byte(username, index))
        index = index + 1
    int64[] frame = encode_varint(len(body))
    index = 0
    while index < len(body):
        append(frame, body[index])
        index = index + 1
    return frame

public def offline_login(host: str, port: int64, username: str) -> int:
    int64 host_length = mc_string_length(host)
    int64 username_length = mc_string_length(username)
    if host_length < 1 or host_length > 255:
        print("Invalid host: expected 1-255 UTF-8 bytes")
        return 1
    if username_length < 1 or username_length > 16:
        print("Invalid username: expected 1-16 ASCII characters")
        return 1
    if port < 1 or port > 65535:
        print("Invalid port: expected 1-65535")
        return 1
    int64 index = 0
    while index < username_length:
        int64 character = mc_string_byte(username, index)
        if not (character >= 48 and character <= 57 or (character >= 65 and character <= 90 or (character >= 97 and character <= 122 or character == 95))):
            print("Invalid username: use ASCII letters, numbers, and underscore")
            return 1
        index = index + 1
    int64[] host_bytes = new int64[host_length]
    index = 0
    while index < host_length:
        host_bytes[index] = mc_string_byte(host, index)
        index = index + 1
    int64 socket_handle = mc_tcp_connect(host, port)
    if socket_handle < 0:
        print(f"Could not connect to {host}")
        return 1
    int64[] handshake = encode_handshake(777, host_bytes, host_length, port, 2)
    if send_bytes(socket_handle, handshake) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send login handshake")
        return 1
    int64[] login_start = encode_login_start(username, username_length)
    if send_bytes(socket_handle, login_start) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send offline login start")
        return 1
    int64[] login_frame = read_packet_frame(socket_handle)
    if login_frame[0] != 1:
        mc_tcp_close(socket_handle)
        print("Could not read or decompress a valid login response")
        return 1
    int64[] login_body = read_login_response_body(socket_handle, login_frame)
    if len(login_body) < 1:
        mc_tcp_close(socket_handle)
        print("Could not process the login response")
        return 1
    int64[] packet_id = decode_varint(login_body, 0)
    if packet_id[0] != 1:
        mc_tcp_close(socket_handle)
        print("Malformed login response packet")
        return 1
    if packet_id[1] == 0:
        int64[] reason = read_string_field(login_body, packet_id[2], 262144)
        mc_tcp_close(socket_handle)
        if reason[0] == 1:
            print("Server rejected login:")
            index = reason[2]
            while index < reason[2] + reason[1]:
                mc_write_byte(login_body[index])
                index = index + 1
            print("")
        else:
            print("Server rejected login with an invalid reason")
        return 1
    if packet_id[1] == 1:
        mc_tcp_close(socket_handle)
        print("Server requires online-mode authentication; no credentials were sent")
        return 1
    if packet_id[1] == 4:
        mc_tcp_close(socket_handle)
        print("Server requested a login plugin/proxy query; this is not supported")
        return 1
    if packet_id[1] == 5:
        mc_tcp_close(socket_handle)
        print("Server requested a login cookie; cookie handling is not implemented")
        return 1
    if packet_id[1] != 2:
        mc_tcp_close(socket_handle)
        print("Unexpected login response packet")
        return 1
    int64 profile_start = packet_id[2]
    if profile_start + 16 > len(login_body):
        mc_tcp_close(socket_handle)
        print("Truncated login profile UUID")
        return 1
    index = 0
    while index < 16:
        if login_body[profile_start + index] != mc_offline_uuid_byte(username, index):
            mc_tcp_close(socket_handle)
            print("Login profile UUID does not match the offline username")
            return 1
        index = index + 1
    int64[] profile_name = read_string_field(login_body, profile_start + 16, 16)
    if profile_name[0] != 1 or profile_name[1] != username_length:
        mc_tcp_close(socket_handle)
        print("Malformed login profile name")
        return 1
    index = 0
    while index < username_length:
        if login_body[profile_name[2] + index] != mc_string_byte(username, index):
            mc_tcp_close(socket_handle)
            print("Login profile name does not match the requested username")
            return 1
        index = index + 1
    int64[] property_count = decode_varint(login_body, profile_name[2] + profile_name[1])
    if property_count[0] != 1 or (property_count[1] < 0 or property_count[1] > 1024):
        mc_tcp_close(socket_handle)
        print("Malformed login profile properties")
        return 1
    int64 property_position = property_count[2]
    index = 0
    while index < property_count[1]:
        int64[] property_name = read_string_field(login_body, property_position, 64)
        if property_name[0] != 1:
            mc_tcp_close(socket_handle)
            print("Malformed login profile property name")
            return 1
        int64[] property_value = read_string_field(login_body, property_name[2] + property_name[1], 32767)
        if property_value[0] != 1:
            mc_tcp_close(socket_handle)
            print("Malformed login profile property value")
            return 1
        property_position = property_value[2] + property_value[1]
        if property_position >= len(login_body):
            mc_tcp_close(socket_handle)
            print("Truncated login profile property")
            return 1
        int64 has_signature = login_body[property_position]
        property_position = property_position + 1
        if has_signature == 1:
            int64[] signature = read_string_field(login_body, property_position, 1024)
            if signature[0] != 1:
                mc_tcp_close(socket_handle)
                print("Malformed login profile signature")
                return 1
            property_position = signature[2] + signature[1]
        elif has_signature != 0:
            mc_tcp_close(socket_handle)
            print("Invalid login profile signature flag")
            return 1
        index = index + 1
    if property_position + 16 != len(login_body):
        mc_tcp_close(socket_handle)
        print("Unexpected bytes in login success packet")
        return 1
    int64[] empty = new int64[0]
    int64[] acknowledgement = encode_packet_frame(3, empty)
    if send_bytes(socket_handle, acknowledgement) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to acknowledge login success")
        return 1
    print(f"Offline login accepted for {username}")
    print("Login acknowledged; entering configuration")
    VDimensionRegistry* registry = vdimension_registry_new()
    int configuration_result = handle_configuration(socket_handle, registry)
    if configuration_result != 0:
        vdimension_registry_free(registry)
        mc_tcp_close(socket_handle)
        return configuration_result
    print("Entering Play packet exchange")
    int play_result = play_session(socket_handle, registry)
    vdimension_registry_free(registry)
    mc_tcp_close(socket_handle)
    return play_result

public def status_ping(host: str, port: int64) -> int:
    int64 host_length = mc_string_length(host)
    if host_length < 1:
        print("Invalid host: expected 1-255 UTF-8 bytes")
        return 1
    if host_length > 255:
        print("Invalid host: expected 1-255 UTF-8 bytes")
        return 1
    int64[] host_bytes = new int64[host_length]
    int64 index = 0
    while index < host_length:
        host_bytes[index] = mc_string_byte(host, index)
        index = index + 1
    if port < 1 or port > 65535:
        print("Invalid port: expected 1-65535")
        return 1
    int64 socket_handle = mc_tcp_connect(host, port)
    if socket_handle < 0:
        print(f"Could not connect to {host}")
        return 1
    int64[] handshake = encode_handshake(777, host_bytes, host_length, port, 1)
    if send_bytes(socket_handle, handshake) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send handshake")
        return 1
    int64[] request = encode_status_request()
    if send_bytes(socket_handle, request) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send status request")
        return 1
    int64[] status_frame = read_frame(socket_handle)
    if status_frame[0] != 1:
        mc_tcp_close(socket_handle)
        print("Could not read a valid status response")
        return 1
    int64[] status_body = new int64[status_frame[2]]
    int64 index = 0
    while index < status_frame[2]:
        status_body[index] = status_frame[3 + index]
        index = index + 1
    int64[] packet_id = decode_varint(status_body, 0)
    if packet_id[0] != 1 or packet_id[1] != 0:
        mc_tcp_close(socket_handle)
        print("Unexpected status response packet")
        return 1
    int64[] json_length = decode_varint(status_body, packet_id[2])
    if json_length[0] != 1 or json_length[1] < 0:
        mc_tcp_close(socket_handle)
        print("Malformed status JSON length")
        return 1
    int64 json_start = json_length[2]
    if json_start + json_length[1] > len(status_body):
        mc_tcp_close(socket_handle)
        print("Truncated status JSON")
        return 1
    print("Server status:")
    index = json_start
    while index < json_start + json_length[1]:
        mc_write_byte(status_body[index])
        index = index + 1
    print("")
    int64 ping_time = mc_time_millis()
    if ping_time < 0:
        mc_tcp_close(socket_handle)
        print("Could not read system clock")
        return 1
    int64[] ping_packet = encode_ping_request(ping_time)
    if send_bytes(socket_handle, ping_packet) != 0:
        mc_tcp_close(socket_handle)
        print("Failed to send ping")
        return 1
    int64[] pong_frame = read_frame(socket_handle)
    if pong_frame[0] != 1:
        mc_tcp_close(socket_handle)
        print("Could not read a valid pong")
        return 1
    int64[] pong_body = new int64[pong_frame[2]]
    index = 0
    while index < pong_frame[2]:
        pong_body[index] = pong_frame[3 + index]
        index = index + 1
    int64[] pong_id = decode_varint(pong_body, 0)
    if pong_id[0] != 1 or (pong_id[1] != 1 or len(pong_body) - pong_id[2] != 8):
        mc_tcp_close(socket_handle)
        print("Unexpected pong packet")
        return 1
    index = 0
    while index < 8:
        int64 expected = ping_time >> (7 - index) * 8 & 0xFF
        if pong_body[pong_id[2] + index] != expected:
            mc_tcp_close(socket_handle)
            print("Pong payload did not match ping")
            return 1
        index = index + 1
    int64 elapsed = mc_time_millis() - ping_time
    mc_tcp_close(socket_handle)
    print("Ping (ms):")
    print(elapsed)
    return 0

import "network.c"

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

# --- Serverbound payload builders ---
#
# The remaining serverbound packets are lists of strings, packed positions and
# optional fields, so they are grown with append instead of being laid out in a
# fixed-size array. Every builder returns the buffer: append writes the possibly
# moved pointer back into its own lvalue, so a helper that swallowed the result
# would leave the caller holding a freed allocation.

def sb_byte(target: int64[], value: int64) -> int64[]:
    append(target, value & 0xFF)
    return target


def sb_bool(target: int64[], value: bool) -> int64[]:
    append(target, (int64)(1 if value else 0))
    return target


def sb_i32(target: int64[], value: int64) -> int64[]:
    int index = 0
    while index < 4:
        append(target, value >> (3 - index) * 8 & 0xFF)
        index = index + 1
    return target


def sb_i64(target: int64[], value: int64) -> int64[]:
    int index = 0
    while index < 8:
        append(target, value >> (7 - index) * 8 & 0xFF)
        index = index + 1
    return target


def sb_f32(target: int64[], value: double) -> int64[]:
    int index = 0
    while index < 4:
        append(target, mc_float_be_byte(value, index))
        index = index + 1
    return target


def sb_f64(target: int64[], value: double) -> int64[]:
    int index = 0
    while index < 8:
        append(target, mc_double_be_byte(value, index))
        index = index + 1
    return target


# VarLong is unsigned, so the shift has to be logical: an arithmetic shift would
# sign-extend a negative seed and never terminate.
def sb_varlong(target: int64[], value: int64) -> int64[]:
    uint64 remaining = (uint64)value
    while remaining > (uint64)127:
        int64 low = (int64)(remaining & (uint64)0x7F)
        append(target, low | 0x80)
        remaining = remaining >> (uint64)7
    append(target, (int64)remaining)
    return target


def sb_bytes(target: int64[], source: int64[], start: int64,
             length: int64) -> int64[]:
    int64 index = 0
    while index < length:
        append(target, source[start + index] & 0xFF)
        index = index + 1
    return target


def sb_text(target: int64[], source: int64[], start: int64,
            length: int64) -> int64[]:
    target = append_varint(target, length)
    return sb_bytes(target, source, start, length)


# A negative id or length means the optional field is absent.
def sb_opt_vi(target: int64[], value: int64) -> int64[]:
    if value < 0:
        return sb_bool(target, false)
    target = sb_bool(target, true)
    return append_varint(target, value)


def sb_opt_text(target: int64[], source: int64[], start: int64,
                length: int64) -> int64[]:
    if length < 0:
        return sb_bool(target, false)
    target = sb_bool(target, true)
    return sb_text(target, source, start, length)


def pl_pack_block_pos(x: int64, y: int64, z: int64) -> int64:
    return (x & 0x3FFFFFF) << 38 | (y & 0xFFF) << 26 | (z & 0x3FFFFFF)


def sb_pos(target: int64[], x: int64, y: int64, z: int64) -> int64[]:
    return sb_i64(target, pl_pack_block_pos(x, y, z))


def sb_uuid(target: int64[], source: int64[], start: int64) -> int64[]:
    return sb_bytes(target, source, start, 16)


# BitSet.toByteArray is little-endian: byte k carries bits 8k through 8k+7.
def sb_bitset20(target: int64[], mask: int64) -> int64[]:
    int index = 0
    while index < 3:
        append(target, mask >> index * 8 & 0xFF)
        index = index + 1
    return target


# A nameless NBT string payload: unsigned-short byte count then the bytes. This
# is the StringTag form, not the VarInt-prefixed protocol string.
def sb_nbt_string(target: int64[], source: int64[], start: int64,
                  length: int64) -> int64[]:
    target = sb_byte(target, length >> 8)
    target = sb_byte(target, length)
    return sb_bytes(target, source, start, length)


# The backend has no locale picker, so both client-information packets advertise
# en_us: 101 110 95 117 115.
def sb_default_language() -> int64[]:
    int64[] language = new int64[5]
    language[0] = 101
    language[1] = 110
    language[2] = 95
    language[3] = 117
    language[4] = 115
    return language


# ClientInformation has an identical body in Configuration and Play; only the
# packet id differs.
def sb_client_information(language: int64[], language_start: int64,
                          language_length: int64, view_distance: int,
                          chat_visibility: int, chat_colors: bool,
                          model_customisation: int, main_hand: int,
                          text_filtering: bool, allows_listing: bool,
                          particle_status: int) -> int64[]:
    int64[] body = new int64[0]
    body = sb_text(body, language, language_start, language_length)
    body = sb_byte(body, (int64)view_distance)
    body = append_varint(body, (int64)chat_visibility)
    body = sb_bool(body, chat_colors)
    body = sb_byte(body, (int64)model_customisation)
    body = append_varint(body, (int64)main_hand)
    body = sb_bool(body, text_filtering)
    body = sb_bool(body, allows_listing)
    return append_varint(body, (int64)particle_status)


# 64-bit sibling of decode_varint: up to ten continuation bytes, with the same
# overflow rejection so a truncated or overlong encoding can never shift past
# the sign bit.
public def decode_varlong(data: int64[], offset: int64) -> int64[]:
    int64 value = 0
    int64 position = offset
    int64 shift = 0
    if offset < 0:
        return decode_result(-3, 0, offset)
    while shift < 70:
        if position >= len(data):
            return decode_result(-1, 0, position)
        int64 current = data[position]
        if current < 0 or current > 255:
            return decode_result(-3, 0, position)
        if shift == 63 and current > 1:
            return decode_result(-2, 0, position)
        value = value | (current & 0x7F) << shift
        position = position + 1
        if (current & 0x80) == 0:
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
    int64[] body = encode_varint(pid_hs_s_intention())
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
    return encode_packet_frame(pid_st_s_status_request(), empty)

public def encode_ping_request(time: int64) -> int64[]:
    int64[] ping = new int64[8]
    int64 index = 0
    while index < 8:
        ping[index] = time >> (7 - index) * 8 & 0xFF
        index = index + 1
    return encode_packet_frame(pid_st_s_ping_request(), ping)

public def send_bytes(socket_handle: int64, data: int64[]) -> int64:
    if len(data) == 0:
        return i64_failed()
    mc_tcp_send_begin(socket_handle)
    int64 index = 0
    while index < len(data):
        if mc_tcp_send_byte(data[index]) != 0:
            return i64_failed()
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

# Resolves a server address the way the Minecraft client does: an explicit
# ":port" suffix wins; otherwise the SRV record _minecraft._tcp.<host> supplies
# the target host and port; with no SRV record the default port 25565 is used.
# Returns the host to connect to (the SRV target when present) and writes the
# port through port_out. A malformed explicit port writes -1 so the caller can
# reject it.
public def resolve_address(address: str, port_out: int64*) -> str:
    int colon = str_find_code(address, 0, 58)
    if colon >= 0:
        str host_part = str_slice(address, 0, colon)
        str port_part = str_slice(address, colon + 1, text_len(address))
        int64[] explicit_port = parse_port(port_part)
        if explicit_port[0] == 1:
            port_out[0] = explicit_port[1]
            return host_part
        port_out[0] = (int64)-1
        return host_part
    str target = vt_calloc_char(512)
    int64 srv_port = 0
    if mc_resolve_srv(address, target, 512, &srv_port) == 1:
        if srv_port >= 1 and srv_port <= 65535:
            port_out[0] = srv_port
            return target
    vt_free((void*)target)
    port_out[0] = 25565
    return address

public def frame_body(frame: int64[]) -> int64[]:
    if frame[0] != 1 or frame[2] < 1:
        return new int64[0]
    int64[] body = new int64[frame[2]]
    int64 index = 0
    while index < frame[2]:
        body[index] = frame[index + 3]
        index = index + 1
    return body


# A prefixed array of bytes: the count is a varint, the payload is opaque.
def pl_take_byte_array(body: int64[], cursor: int64, limit: int64) -> int64:
    int64[] size = decode_varint(body, cursor)
    if size[0] != 1 or size[1] < 0 or size[1] > limit:
        return (int64)-1
    return pl_take(body, size[2], size[1])

public def read_login_response_body(socket_handle: int64, frame: int64[]) -> int64[]:
    int64[] body = frame_body(frame)
    int64[] packet_id = decode_varint(body, 0)
    if packet_id[0] != 1:
        print("Malformed login response packet id")
        return new int64[0]
    if packet_id[1] != pid_lg_c_login_compression():
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
    int64[] language = sb_default_language()
    int64[] payload = sb_client_information(language, 0, 5, 12, 0, true, 127,
                                            1, false, true, 0)
    return encode_packet_frame(pid_cfg_s_client_information(), payload)

public def decode_be_int64(data: int64[], offset: int64) -> double:
    return mc_double_from_be(data[offset], data[offset + 1], data[offset + 2], data[offset + 3], data[offset + 4], data[offset + 5], data[offset + 6], data[offset + 7])

def pl_decode_be_int16(data: int64[], offset: int64) -> int64:
    if offset + 2 > len(data):
        return (int64)-1
    int64 value = (data[offset] << 8) | data[offset + 1]
    if value >= 32768:
        value = value - 65536
    return value


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

# A registry packet is the one place where a wrong guess costs the whole
# session, so the walk reports what it was looking at: the registry name, the
# element it stopped on, and the bytes it could not place. Without this the
# only signal is "malformed" and there is no way to tell a server that sends a
# different layout from a client that misreads one.
def pl_note_bytes(data: int64[], start: int64, length: int64) -> void:
    int64 index = start
    while index < start + length and index < len(data):
        mc_write_byte(data[index])
        index = index + 1


def pl_note_failure(reason: str, body: int64[], name_start: int64,
                    name_length: int64, index: int64,
                    offset: int64) -> void:
    print("Registry ")
    pl_note_bytes(body, name_start, name_length)
    print(f" failed at element {index}")
    print(f"  reason: {reason}")
    print(f"  offset {offset} in {len(body)} body bytes")
    int64 shown = 0
    int64 limit = 16
    if offset + limit > len(body):
        limit = len(body) - offset
    while shown < limit:
        int64 byte = body[offset + shown] & 0xFF
        int64 high = (byte >> 4) + 48
        int64 low = (byte & 15) + 48
        if high > 57:
            high = high + 7
        if low > 57:
            low = low + 7
        mc_write_byte(32)
        mc_write_byte(high)
        mc_write_byte(low)
        shown = shown + 1
    print("")


# One registry's elements: each is a name and an optional payload of any tag
# type. The dimension type is the only registry this client reads rather than
# skips, so its elements are the only ones that can fail structurally in two
# ways. `quiet` is set while a candidate layout is being tried: reporting every
# rejected guess would bury the one message that matters.
def pl_registry_elements(body: int64[], cursor: int64, count: int64,
                         registry: VDimensionRegistry*, dimensions: bool,
                         biomes: bool, name_start: int64,
                         name_length: int64, quiet: bool) -> int64:
    int64 position = cursor
    int64 index = 0
    while index < count:
        int64[] name = read_string_field(body, position, 32767)
        if name[0] != 1:
            if not quiet:
                pl_note_failure("no element name", body, name_start,
                                name_length, index, position)
            return (int64)-1
        position = name[2] + name[1]
        if position >= len(body) or (body[position] != 0 and body[position] != 1):
            if not quiet:
                pl_note_failure("element value is not an optional tag", body,
                                name_start, name_length, index, position)
            return (int64)-1
        int64 has_data = body[position]
        position = position + 1
        if has_data == 1:
            if position >= len(body):
                if not quiet:
                    pl_note_failure("element value has no payload", body,
                                    name_start, name_length, index, position)
                return (int64)-1
            int64 tag = body[position]
            if tag < 1 or tag > 12:
                if not quiet:
                    pl_note_failure("element payload has an unknown tag", body,
                                    name_start, name_length, index, position)
                return (int64)-1
            # Only the dimension type is read, and its elements are the only
            # payload this client insists is a compound. The rest arrive in
            # whatever shape their data has: `block_transformer` elements are
            # lists, `entity_type` elements are compounds holding a string.
            if dimensions:
                if tag != 10:
                    if not quiet:
                        pl_note_failure("element payload is not a compound",
                                        body, name_start, name_length, index,
                                        position)
                    return (int64)-1
                if parse_dimension_type_entry(body, position, registry, index) == 0:
                    if not quiet:
                        pl_note_failure("dimension fields are not where they should be",
                                        body, name_start, name_length, index,
                                        position)
                    return (int64)-1
            int64[] end = skip_nbt_payload(body, tag, position + 1, 0)
            if end[0] != 1 or end[2] <= position:
                if not quiet:
                    pl_note_failure("element payload does not end", body,
                                    name_start, name_length, index, position)
                return (int64)-1
            position = end[2]
        index = index + 1
    if dimensions and vdimension_registry_finish_dimensions(registry, (int)count) == 0:
        if not quiet:
            pl_note_failure("dimension table rejected the set", body,
                            name_start, name_length, index, position)
        return (int64)-1
    if biomes and vdimension_registry_set_biome_count(registry, (int)count) == 0:
        if not quiet:
            pl_note_failure("biome count rejected", body, name_start,
                            name_length, index, position)
        return (int64)-1
    return position


# Layout A, documented for 26.1: one registry per packet, named first.
def pl_registry_holder(body: int64[], packet_offset: int64,
                       registry: VDimensionRegistry*,
                       quiet: bool) -> int:
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
    int64 done = pl_registry_elements(body, entry_count[2], entry_count[1],
                                     registry, dimensions, biomes, key[2],
                                     key[1], quiet)
    if done < 0 or done != len(body):
        return 0
    return 1


# Layout B, what a server that batches its registries sends: a count of
# holders, each with its own name and element list. Tried only when layout A
# cannot place the packet, and accepted only when it consumes it exactly.
def pl_registry_array(body: int64[], packet_offset: int64,
                      registry: VDimensionRegistry*) -> int:
    int64[] holder_count = decode_varint(body, packet_offset)
    if holder_count[0] != 1 or holder_count[1] < 1 or holder_count[1] > 512:
        return 0
    int64 cursor = holder_count[2]
    int64 index = 0
    while index < holder_count[1]:
        int64[] key = read_string_field(body, cursor, 32767)
        if key[0] != 1:
            return 0
        cursor = key[2] + key[1]
        int64[] entry_count = decode_varint(body, cursor)
        if entry_count[0] != 1 or entry_count[1] < 0 or entry_count[1] > 65536:
            return 0
        bool dimensions = nbt_string_equals(body, key,
                                            "minecraft:dimension_type")
        bool biomes = nbt_string_equals(body, key, "minecraft:worldgen/biome")
        if dimensions and entry_count[1] > 256:
            return 0
        cursor = pl_registry_elements(body, entry_count[2], entry_count[1],
                                      registry, dimensions, biomes, key[2],
                                      key[1], true)
        if cursor < 0:
            return 0
        index = index + 1
    if cursor != len(body):
        return 0
    return 1


public def parse_configuration_registry(body: int64[], packet_offset: int64,
                                        registry: VDimensionRegistry*) -> int:
    if pl_registry_holder(body, packet_offset, registry, false) == 1:
        return 1
    if pl_registry_array(body, packet_offset, registry) == 1:
        print("Registry data arrived as a multi-registry packet")
        return 1
    int64[] key = read_string_field(body, packet_offset, 32767)
    if key[0] == 1:
        pl_note_failure("no registry layout fits", body, key[2], key[1], 0,
                        key[2] + key[1])
    else:
        pl_note_failure("no registry layout fits", body, packet_offset, 16, 0,
                        packet_offset)
    return 0


# Whether the packet that failed names a registry the client cannot do without.
# The dimension type carries the height limits the chunk decoder and the respawn
# packet are written against, so continuing without it produces a world that is
# wrong in a way the player cannot see; an enchantment or instrument registry is
# only information the terminal never shows, so its loss is a warning.
def pl_registry_is_required(body: int64[], packet_offset: int64) -> int:
    int64[] key = read_string_field(body, packet_offset, 32767)
    if key[0] != 1:
        return 0
    if nbt_string_equals(body, key, "minecraft:dimension_type"):
        return 1
    if nbt_string_equals(body, key, "minecraft:worldgen/biome"):
        return 1
    return 0

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
    return encode_packet_frame(pid_pl_s_chat(), payload)

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
    return encode_packet_frame(pid_pl_s_chat_command(), payload)

# A chat line goes to the terminal as bytes and, in the same pass, into the
# engine's message ring so a render window can show what the session printed.
# `label` is the vanilla prefix ("Server:") and may be empty; the terminal keeps
# its existing two-line shape while the ring gets the single line it renders.
def pl_chat_text(label: str, body: int64[], start: int64, length: int64) -> void:
    vt_chat_begin()
    vt_chat_text(label)
    if text_len(label) > 0:
        vt_chat_byte(32)
    int64 shown = length
    if shown > 4096:
        shown = 4096
    int64 index = 0
    while index < shown:
        mc_write_byte(body[start + index])
        vt_chat_byte(body[start + index])
        index = index + 1
    vt_chat_end()


# The same ring line for text the client already holds in a decoded array, used
# for the echo of a message the player typed, which the terminal prints as it
# reads from stdin rather than as a packet.
def pl_chat_tee(label: str, data: int64[], length: int64) -> void:
    vt_chat_begin()
    vt_chat_text(label)
    if text_len(label) > 0:
        vt_chat_byte(32)
    int64 shown = length
    if shown > 4096:
        shown = 4096
    int64 index = 0
    while index < shown:
        vt_chat_byte(data[index])
        index = index + 1
    vt_chat_end()


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
        pl_chat_text("Server:", body, text[2], text[1])
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
                pl_chat_text("Server:", body, value[2], value[1])
                print("")
                return 0
            if name[1] == 9 and (body[name[2]] == 116 and (body[name[2] + 1] == 114 and (body[name[2] + 2] == 97 and (body[name[2] + 3] == 110 and (body[name[2] + 4] == 115 and (body[name[2] + 5] == 108 and (body[name[2] + 6] == 97 and (body[name[2] + 7] == 116 and body[name[2] + 8] == 101)))))))):
                print("Server (untranslated):")
                pl_chat_text("Server (untranslated):", body, value[2], value[1])
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


public def decode_be_i64(data: int64[], offset: int64) -> int64:
    if offset < 0 or offset + 8 > len(data):
        return (int64)0
    int64 value = (int64)0
    int64 index = 0
    while index < 8:
        value = (value << 8) | data[offset + index]
        index = index + 1
    return value


# Block Update (0x08): packed block position, then the new state id.
public def handle_block_update(world: VWorld*, body: int64[],
                               offset: int64) -> int:
    if offset < 0 or offset + 9 > len(body):
        return 1
    int64 packed = decode_be_i64(body, offset)
    int64[] state = decode_varint(body, offset + 8)
    if state[0] != 1 or state[1] < 0 or state[1] > 2147483647 or state[2] != len(body):
        return 1
    int* position = vt_calloc_int(3)
    vt_unpack_block_pos(packed, position)
    int result = vworld_set_block_at(world, vt_iget(position, 0),
                                     vt_iget(position, 1), vt_iget(position, 2),
                                     (int)state[1])
    vt_free((void*)position)
    if result == 0:
        return 0
    return 0


# Section Blocks Update (0x56): section position, non-air count, then
# (index delta, state id) pairs for the blocks that changed.
public def handle_section_blocks_update(world: VWorld*, body: int64[],
                                        offset: int64) -> int:
    if offset < 0 or offset + 8 > len(body):
        return 1
    int64 packed = decode_be_i64(body, offset)
    int* position = vt_calloc_int(3)
    vt_unpack_section_pos(packed, position)
    int section_x = vt_iget(position, 0)
    int section_y = vt_iget(position, 1)
    int section_z = vt_iget(position, 2)
    vt_free((void*)position)
    int64[] count = decode_varint(body, offset + 8)
    if count[0] != 1 or count[1] < 0 or count[1] > 4096:
        return 1
    VSection* section = vworld_section(world, section_x, section_z, section_y)
    int64 cursor = count[2]
    int64 index = 0
    int64 slot = 0
    while index < count[1]:
        int64[] delta = decode_varint(body, cursor)
        if delta[0] != 1 or delta[1] < 0:
            return 1
        int64[] state = decode_varint(body, delta[2])
        if state[0] != 1 or state[1] < 0 or state[1] > 2147483647:
            return 1
        slot += delta[1]
        if slot >= 4096:
            return 1
        if section != null:
            sec_block_set(section, (int)(slot % 16), (int)(slot / 256),
                          (int)((slot / 16) % 16), (int)state[1])
        cursor = state[2]
        index += 1
    if cursor != len(body):
        return 1
    return 0


# Light Update (0x31): chunk coordinates, the four masks, then the non-empty
# sky and block light arrays for the sections the masks select.
public def handle_light_update(world: VWorld*, body: int64[],
                               offset: int64) -> int:
    int64[] chunk_x = decode_varint(body, offset)
    if chunk_x[0] != 1:
        return 1
    int64[] chunk_z = decode_varint(body, chunk_x[2])
    if chunk_z[0] != 1:
        return 1
    int64 column = 0
    char* sections = (char*)0
    while column < world.count:
        if vt_iget(world.chunk_x, (int)column) == chunk_x[1] and vt_iget(world.chunk_z, (int)column) == chunk_z[1]:
            sections = (char*)vt_ptr_get(world.columns, (int)column)
            break
        column += 1
    int64 position = chunk_z[2]
    int64 bit_limit = world.section_count + 2
    int64[] sky_mask = chunk_read_light_mask(body, position, bit_limit)
    if sky_mask[0] != 1:
        return 1
    position = sky_mask[3]
    int64[] block_mask = chunk_read_light_mask(body, position, bit_limit)
    if block_mask[0] != 1:
        return 1
    position = block_mask[3]
    int64[] empty_sky = chunk_read_light_mask(body, position, bit_limit)
    if empty_sky[0] != 1:
        return 1
    position = empty_sky[3]
    int64[] empty_block = chunk_read_light_mask(body, position, bit_limit)
    if empty_block[0] != 1:
        return 1
    position = empty_block[3]
    if chunk_masks_overlap(body, sky_mask[1], sky_mask[2],
                           empty_sky[1], empty_sky[2], bit_limit):
        return 1
    if chunk_masks_overlap(body, block_mask[1], block_mask[2],
                           empty_block[1], empty_block[2], bit_limit):
        return 1
    if sections != null:
        int64[] sky_arrays = chunk_read_light_arrays(
            body, position, sky_mask[1], sky_mask[2], bit_limit, sections, true)
        if sky_arrays[0] != 1:
            return 1
        int64[] block_arrays = chunk_read_light_arrays(
            body, sky_arrays[2], block_mask[1], block_mask[2], bit_limit,
            sections, false)
        if block_arrays[0] != 1 or block_arrays[2] != len(body):
            return 1
    return 0


# --- Configuration-state packet handlers ---
#
# Each of these decodes the fields a vanilla server actually sends rather than
# treating the packet as opaque, so a real configuration phase leaves a
# readable trace and malformed data is rejected instead of ignored.

def pl_print_bytes(data: int64[], start: int64, length: int64) -> void:
    int64 print_index = start
    while print_index < start + length:
        mc_write_byte(data[print_index])
        print_index = print_index + 1


def cfg_handle_custom_payload(body: int64[], offset: int64) -> int:
    int64[] channel = read_string_field(body, offset, 32767)
    if channel[0] != 1:
        print("Malformed configuration plugin channel")
        return 1
    print("Configuration plugin message on ")
    pl_print_bytes(body, channel[2], channel[1])
    print(f" ({len(body) - channel[2]} payload bytes)")
    return 0


def cfg_handle_store_cookie(body: int64[], offset: int64) -> int:
    int64[] key = read_string_field(body, offset, 32767)
    if key[0] != 1:
        print("Malformed configuration cookie store key")
        return 1
    print("Server stored cookie ")
    pl_print_bytes(body, key[2], key[1])
    print(f" ({len(body) - key[2]} bytes)")
    return 0


def cfg_handle_transfer(body: int64[], offset: int64) -> int:
    int64[] host = read_string_field(body, offset, 32767)
    if host[0] != 1 or host[2] + host[1] + 4 > len(body):
        print("Malformed configuration transfer request")
        return 1
    int64 _port = decode_be_int32(body, host[2] + host[1])
    print("Configuration transfer requested to ")
    pl_print_bytes(body, host[2], host[1])
    print(f":{_port} (offline mode does not follow redirects)")
    return 0


def cfg_handle_feature_updates(body: int64[], offset: int64,
                               label: str) -> int:
    int64[] count = decode_varint(body, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > 65536:
        print(f"Malformed {label} count")
        return 1
    print(f"{label}: {count[1]} entries")
    int64 cursor = count[2]
    int64 index = 0
    while index < count[1]:
        int64[] entry = read_string_field(body, cursor, 32767)
        if entry[0] != 1:
            return 0
        if index < 16:
            pl_print_bytes(body, entry[2], entry[1])
            print("")
        cursor = entry[2] + entry[1]
        index = index + 1
    return 0


# Update Tags: registry type name, then for each tag its name and the numeric
# ids of its members. The ids index the matching registry, which this client has
# not imported, so the tags are counted rather than resolved: knowing that a
# server publishes 15 tag types is enough to tell a vanilla world from a modded
# one, and nothing in the renderer needs the membership lists.
def cfg_handle_tags(body: int64[], offset: int64) -> int:
    int64[] registry_count = decode_varint(body, offset)
    if registry_count[0] != 1 or registry_count[1] < 0 or registry_count[1] > 512:
        print("Malformed tag registry count")
        return 1
    int64 cursor = registry_count[2]
    int64 registry_index = 0
    int tags_reported = 0
    while registry_index < registry_count[1]:
        int64[] registry = read_string_field(body, cursor, 32767)
        if registry[0] != 1:
            print("Malformed tag registry name")
            return 1
        cursor = registry[2] + registry[1]
        int64[] tag_count = decode_varint(body, cursor)
        if tag_count[0] != 1 or tag_count[1] < 0 or tag_count[1] > 65536:
            print("Malformed tag count")
            return 1
        cursor = tag_count[2]
        if tags_reported < 4:
            print("Tags for ")
            pl_note_bytes(body, registry[2], registry[1])
            print(f": {tag_count[1]} tags")
            tags_reported = tags_reported + 1
        int64 tag_index = 0
        while tag_index < tag_count[1]:
            int64[] tag = read_string_field(body, cursor, 32767)
            if tag[0] != 1:
                print("Malformed tag name")
                return 1
            cursor = tag[2] + tag[1]
            int64[] member_count = decode_varint(body, cursor)
            if member_count[0] != 1 or member_count[1] < 0 or member_count[1] > 1048576:
                print("Malformed tag member count")
                return 1
            cursor = member_count[2]
            int64 member = 0
            while member < member_count[1]:
                int64[] member_id = decode_varint(body, cursor)
                if member_id[0] != 1:
                    print("Malformed tag member id")
                    return 1
                cursor = member_id[2]
                member = member + 1
            tag_index = tag_index + 1
        registry_index = registry_index + 1
    if cursor != len(body):
        print(f"Tag registry has {len(body) - cursor} bytes left over")
        return 1
    return 0


def cfg_handle_resource_pack_pop(body: int64[], offset: int64) -> int:
    if offset >= len(body):
        print("Server popped all resource packs")
        return 0
    int64[] count = decode_varint(body, offset)
    if count[0] != 1 or count[1] < 0 or count[1] * 16 > len(body) - count[2]:
        print("Malformed resource-pack pop list")
        return 1
    print(f"Server popped {count[1]} resource packs")
    return 0


def cfg_handle_component_text(body: int64[], offset: int64, label: str) -> int:
    if offset >= len(body):
        print(f"Malformed {label} component")
        return 1
    int tag_type = (int) body[offset]
    print(f"{label}: ")
    print_nbt_text(body, tag_type, offset)
    print("")
    return 0


def cfg_handle_server_links(body: int64[], offset: int64) -> int:
    int64[] count = decode_varint(body, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > 1024:
        print("Malformed server link count")
        return 1
    print(f"Server links: {count[1]} entries")
    int64 cursor = count[2]
    int64 link_index = 0
    while link_index < count[1]:
        int64[] title = read_string_field(body, cursor, 32767)
        if title[0] != 1:
            return 0
        int64[] url = read_string_field(body, title[2] + title[1], 2048)
        if url[0] != 1:
            return 0
        pl_print_bytes(body, title[2], title[1])
        print(" -> ")
        pl_print_bytes(body, url[2], url[1])
        print("")
        cursor = url[2] + url[1]
        link_index = link_index + 1
    return 0


# Live decode -> palette -> light -> mesh path. The native worker pool reads the
# decoded sections through the C-callable accessors and writes malloc'd
# vertex/index buffers; the batch is run and freed on the main thread so the GC
# never sees a worker stack. mesh_chunk_native meshes a whole loaded column,
# remesh_section_native re-meshes a section plus its six face neighbours after an
# edit so boundary faces stay correct.
def mesh_chunk_native(world: VWorld*, chunk_x: int, chunk_z: int) -> void:
    char* batch = vmesh_native_batch_new()
    if batch == null:
        return
    vmesh_native_add_chunk(batch, world, chunk_x, chunk_z,
                           world.min_section, world.section_count)
    if vmesh_native_run(batch) != 0:
        print(f"Meshing chunk ({chunk_x}, {chunk_z}) failed")
        vmesh_native_batch_free(batch)
        return
    int sections = vmesh_native_sections(batch)
    int64 quads = vmesh_native_quad_count(batch)
    int64 vertices = 0
    int slot = 0
    while slot < sections:
        vertices += vmesh_native_vertex_count(batch, slot, 0)
        vertices += vmesh_native_vertex_count(batch, slot, 1)
        slot += 1
    print(f"Meshed chunk ({chunk_x}, {chunk_z}): {quads} quads, {vertices} vertices across {sections} sections")
    vmesh_publish(batch)


def remesh_section_native(world: VWorld*, chunk_x: int, section_y: int,
                          chunk_z: int) -> void:
    char* batch = vmesh_native_batch_new()
    if batch == null:
        return
    vmesh_native_add_neighborhood(batch, world, chunk_x, section_y, chunk_z)
    if vmesh_native_run(batch) != 0:
        vmesh_native_batch_free(batch)
        return
    int64 quads = vmesh_native_quad_count(batch)
    print(f"Re-meshed section ({chunk_x}, {section_y}, {chunk_z}): {quads} quads")
    vmesh_publish(batch)


# Block Update carries a world block position; floor-divide to the section the
# way vworld_block_at does so the neighbourhood matches the stored column.
def remesh_block_position(world: VWorld*, packed: int64) -> void:
    int* position = vt_calloc_int(3)
    vt_unpack_block_pos(packed, position)
    int bx = vt_iget(position, 0)
    int by = vt_iget(position, 1)
    int bz = vt_iget(position, 2)
    vt_free((void*)position)
    int chunk_x = bx / 16
    if bx % 16 < 0:
        chunk_x -= 1
    int chunk_z = bz / 16
    if bz % 16 < 0:
        chunk_z -= 1
    int section_y = by / 16
    if by % 16 < 0:
        section_y -= 1
    remesh_section_native(world, chunk_x, section_y, chunk_z)


def remesh_section_position(world: VWorld*, packed: int64) -> void:
    int* position = vt_calloc_int(3)
    vt_unpack_section_pos(packed, position)
    int sx = vt_iget(position, 0)
    int sy = vt_iget(position, 1)
    int sz = vt_iget(position, 2)
    vt_free((void*)position)
    remesh_section_native(world, sx, sy, sz)


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
        if packet_id[1] == pid_cfg_c_finish_configuration():
            if packet_id[2] != len(body):
                print("Malformed finish-configuration packet")
                return 1
            int64[] empty = new int64[0]
            int64[] acknowledgement = encode_packet_frame(pid_cfg_s_finish_configuration(), empty)
            if send_bytes(socket_handle, acknowledgement) != 0:
                print("Failed to acknowledge configuration")
                return 1
            print("Configuration complete; entered the Play protocol state")
            return 0
        if packet_id[1] == pid_cfg_c_disconnect():
            print("Server disconnected during configuration")
            return 1
        if packet_id[1] == pid_cfg_c_keep_alive():
            if len(body) != packet_id[2] + 8:
                print("Malformed configuration keep-alive")
                return 1
            int64[] response = encode_keepalive_response(pid_cfg_s_keep_alive(), body, packet_id[2])
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration keep-alive")
                return 1
        elif packet_id[1] == pid_cfg_c_ping():
            if len(body) != packet_id[2] + 4:
                print("Malformed configuration ping")
                return 1
            int64[] payload = new int64[4]
            int64 index = 0
            while index < 4:
                payload[index] = body[packet_id[2] + index]
                index = index + 1
            int64[] response = encode_packet_frame(pid_cfg_s_pong(), payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration ping")
                return 1
        elif packet_id[1] == pid_cfg_c_select_known_packs():
            int64[] selection = new int64[1]
            selection[0] = 0
            int64[] response = encode_packet_frame(pid_cfg_s_select_known_packs(), selection)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to known-pack selection")
                return 1
        elif packet_id[1] == pid_cfg_c_cookie_request():
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
            int64[] response = encode_packet_frame(pid_cfg_s_cookie_response(), cookie_payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to respond to configuration cookie request")
                return 1
        elif packet_id[1] == pid_cfg_c_resource_pack_push():
            if packet_id[2] + 16 > len(body):
                print("Malformed configuration resource-pack request")
                return 1
            int64[] resource_pack_payload = new int64[17]
            int64 index = 0
            while index < 16:
                resource_pack_payload[index] = body[packet_id[2] + index]
                index = index + 1
            resource_pack_payload[16] = 1
            int64[] response = encode_packet_frame(pid_cfg_s_resource_pack(), resource_pack_payload)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to decline configuration resource pack")
                return 1
        elif packet_id[1] == pid_cfg_c_code_of_conduct():
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
            int64[] response = encode_packet_frame(pid_cfg_s_accept_code_of_conduct(), consent_acknowledgement)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to accept server code of conduct")
                return 1
        elif packet_id[1] == pid_cfg_c_show_dialog():
            if handle_configuration_dialog(socket_handle, body, packet_id[2], false) != 0:
                print("Could not process the server configuration dialog")
                return 1
        elif packet_id[1] == pid_cfg_c_registry_data():
            if parse_configuration_registry(body, packet_id[2], registry) == 0:
                if pl_registry_is_required(body, packet_id[2]) != 0:
                    print("Malformed or unsupported configuration registry data")
                    return 1
                print("Continuing: this client does not use that registry")
        elif packet_id[1] == pid_cfg_c_clear_dialog():
            print("Server cleared the active configuration dialog")
        elif packet_id[1] == pid_cfg_c_transfer():
            if cfg_handle_transfer(body, packet_id[2]) != 0:
                return 1
        elif packet_id[1] == pid_cfg_c_custom_payload():
            if cfg_handle_custom_payload(body, packet_id[2]) != 0:
                return 1
        elif packet_id[1] == pid_cfg_c_store_cookie():
            if cfg_handle_store_cookie(body, packet_id[2]) != 0:
                return 1
        elif packet_id[1] == pid_cfg_c_resource_pack_pop():
            if cfg_handle_resource_pack_pop(body, packet_id[2]) != 0:
                return 1
        elif packet_id[1] == pid_cfg_c_update_enabled_features():
            if cfg_handle_feature_updates(body, packet_id[2],
                                          "Enabled features") != 0:
                return 1
        elif packet_id[1] == pid_cfg_c_update_tags():
            if cfg_handle_tags(body, packet_id[2]) != 0:
                print("Continuing: the tag registry is not used for rendering")
        elif packet_id[1] == pid_cfg_c_server_links():
            if cfg_handle_server_links(body, packet_id[2]) != 0:
                return 1
        elif packet_id[1] == pid_cfg_c_post_effects():
            if cfg_handle_component_text(body, packet_id[2],
                                         "Post effects") != 0:
                return 1
        elif packet_id[1] == pid_cfg_c_custom_report_details():
            if cfg_handle_component_text(body, packet_id[2],
                                         "Custom report details") != 0:
                return 1
        elif packet_id[1] == pid_cfg_c_reset_chat():
            print("Server reset the secure chat chain")
        elif is_ignorable_configuration_packet(packet_id[1]):
            print(f"Received configuration data packet {packet_id[1]}")
        else:
            print(f"Ignoring unsupported configuration packet id {packet_id[1]}")
        packet_count = packet_count + 1
    print("Too many configuration packets without finish")
    return 1


# --- VPlayState: tracks the client's view of the player and world ---

struct VPlayState:
    double x
    double y
    double z
    double yaw
    double pitch
    double health
    double food
    double saturation
    double xp_progress
    int xp_level
    int xp_total
    int game_mode
    int held_slot
    int abilities_flags
    double flying_speed
    double fov_modifier
    int teleport_id
    bool on_ground
    bool vertical
    int64 world_time
    int dimension
    int view_distance
    int simulation_distance
    int64 next_chat_seq
    VEntities* entities
    VBossBars* boss_bars
    VScoreboard* scoreboard
    VCommandTree* commands
    VEffects* effects
    VAttributes* attributes
    VPlayers* players
    VBlockEntities* block_entities
    VParticles* particles
    VInventory* inventory
    VBorder* border
    VRecipes* recipes
    VTags* tags
    VAdvancements* advancements
    VServerMeta* meta
    VDebug* debug
    int camera_id
    int difficulty
    bool difficulty_locked
    double tick_rate
    bool tick_frozen


# --- Serverbound packet encoders (protocol 777 Play) ---

def pl_encode_move_flags(on_ground: bool, vertical: bool, horizontal: bool,
                          teleport_id: int64) -> int64:
    int64 flags = 0
    if on_ground:
        flags = flags | 1
    if vertical:
        flags = flags | 2
    if horizontal:
        flags = flags | 4
    if teleport_id >= 0:
        flags = flags | 8
    return flags


public def encode_move_player_pos(x: double, y: double, z: double,
                                   yaw: double, pitch: double,
                                   on_ground: bool, vertical: bool,
                                   teleport_id: int64) -> int64[]:
    int64 flags = pl_encode_move_flags(on_ground, vertical, false, teleport_id)
    int64[] tid = encode_varint(teleport_id)
    int64[] payload = new int64[33 + len(tid) + 8]
    int index = 0
    while index < 8:
        payload[index] = mc_double_be_byte(x, index)
        payload[8 + index] = mc_double_be_byte(y, index)
        payload[16 + index] = mc_double_be_byte(z, index)
        index = index + 1
    payload[24] = mc_float_be_byte(yaw, 0)
    payload[25] = mc_float_be_byte(yaw, 1)
    payload[26] = mc_float_be_byte(yaw, 2)
    payload[27] = mc_float_be_byte(yaw, 3)
    payload[28] = mc_float_be_byte(pitch, 0)
    payload[29] = mc_float_be_byte(pitch, 1)
    payload[30] = mc_float_be_byte(pitch, 2)
    payload[31] = mc_float_be_byte(pitch, 3)
    payload[32] = flags
    index = 0
    while index < len(tid):
        payload[33 + index] = tid[index]
        index = index + 1
    while index < 8:
        payload[33 + len(tid) + index] = 0
        index = index + 1
    return encode_packet_frame(pid_pl_s_move_player_pos(), payload)


public def encode_move_player_pos_rot(x: double, y: double, z: double,
                                       yaw: double, pitch: double,
                                       on_ground: bool, vertical: bool,
                                       teleport_id: int64) -> int64[]:
    int64 flags = pl_encode_move_flags(on_ground, vertical, true, teleport_id)
    int64[] tid = encode_varint(teleport_id)
    int64[] payload = new int64[33 + len(tid) + 8]
    int index = 0
    while index < 8:
        payload[index] = mc_double_be_byte(x, index)
        payload[8 + index] = mc_double_be_byte(y, index)
        payload[16 + index] = mc_double_be_byte(z, index)
        index = index + 1
    payload[24] = mc_float_be_byte(yaw, 0)
    payload[25] = mc_float_be_byte(yaw, 1)
    payload[26] = mc_float_be_byte(yaw, 2)
    payload[27] = mc_float_be_byte(yaw, 3)
    payload[28] = mc_float_be_byte(pitch, 0)
    payload[29] = mc_float_be_byte(pitch, 1)
    payload[30] = mc_float_be_byte(pitch, 2)
    payload[31] = mc_float_be_byte(pitch, 3)
    payload[32] = flags
    index = 0
    while index < len(tid):
        payload[33 + index] = tid[index]
        index = index + 1
    while index < 8:
        payload[33 + len(tid) + index] = 0
        index = index + 1
    return encode_packet_frame(pid_pl_s_move_player_pos_rot(), payload)


public def encode_move_player_rot(yaw: double, pitch: double,
                                   on_ground: bool) -> int64[]:
    int64 flags = pl_encode_move_flags(on_ground, false, false, -1)
    int64[] payload = new int64[10]
    payload[0] = mc_float_be_byte(yaw, 0)
    payload[1] = mc_float_be_byte(yaw, 1)
    payload[2] = mc_float_be_byte(yaw, 2)
    payload[3] = mc_float_be_byte(yaw, 3)
    payload[4] = mc_float_be_byte(pitch, 0)
    payload[5] = mc_float_be_byte(pitch, 1)
    payload[6] = mc_float_be_byte(pitch, 2)
    payload[7] = mc_float_be_byte(pitch, 3)
    payload[8] = flags
    payload[9] = 0
    return encode_packet_frame(pid_pl_s_move_player_rot(), payload)


public def encode_move_player_status_only(on_ground: bool,
                                           teleport_id: int64) -> int64[]:
    int64 flags = pl_encode_move_flags(on_ground, false, false, teleport_id)
    int64[] encoded_tid = encode_varint(teleport_id)
    int64[] payload = new int64[1 + len(encoded_tid) + 8]
    payload[0] = flags
    int index = 0
    while index < len(encoded_tid):
        payload[1 + index] = encoded_tid[index]
        index = index + 1
    while index < 8:
        payload[1 + len(encoded_tid) + index] = 0
        index = index + 1
    return encode_packet_frame(pid_pl_s_move_player_status_only(), payload)


public def encode_use_item(hand: int, sequence: int64) -> int64[]:
    int64[] seq = encode_varint(sequence)
    int64[] payload = new int64[1 + len(seq)]
    payload[0] = hand
    int index = 0
    while index < len(seq):
        payload[1 + index] = seq[index]
        index = index + 1
    return encode_packet_frame(pid_pl_s_use_item(), payload)


public def encode_player_command_header() -> int64[]:
    return encode_varint(pid_pl_s_player_command())


public def encode_player_command(action: int, extra: int64) -> int64[]:
    int64[] action_bytes = new int64[4]
    action_bytes[0] = action >> 24 & 0xFF
    action_bytes[1] = action >> 16 & 0xFF
    action_bytes[2] = action >> 8 & 0xFF
    action_bytes[3] = action & 0xFF
    int64[] extra_bytes = new int64[4]
    extra_bytes[0] = (extra >> 24) & 0xFF
    extra_bytes[1] = (extra >> 16) & 0xFF
    extra_bytes[2] = (extra >> 8) & 0xFF
    extra_bytes[3] = extra & 0xFF
    int64[] payload = new int64[8]
    int index = 0
    while index < 4:
        payload[index] = action_bytes[index]
        payload[4 + index] = extra_bytes[index]
        index = index + 1
    return encode_packet_frame(pid_pl_s_player_command(), payload)


public def encode_set_carried_item(slot: int) -> int64[]:
    int64[] payload = new int64[2]
    payload[0] = slot >> 8 & 0xFF
    payload[1] = slot & 0xFF
    return encode_packet_frame(pid_pl_s_set_carried_item(), payload)


# --- Serverbound container packets ---

# HashedSlot: the client's echo of a slot it thinks changed. Components travel
# as (type, hash) pairs rather than payloads, so the server can compare without
# resending them. `types` and `hashes` are parallel arrays of `components` rows.
def pl_append_hashed_slot(body: int64[], item: int64, count: int64,
                          types: int64[], hashes: int64[],
                          components: int64, removed: int64[],
                          removed_count: int64) -> int64[]:
    body = append_varint(body, item)
    body = append_varint(body, count)
    body = append_varint(body, components)
    int64 index = 0
    while index < components:
        body = append_varint(body, types[index])
        append(body, hashes[index] >> 24 & 0xFF)
        append(body, hashes[index] >> 16 & 0xFF)
        append(body, hashes[index] >> 8 & 0xFF)
        append(body, hashes[index] & 0xFF)
        index = index + 1
    body = append_varint(body, removed_count)
    index = 0
    while index < removed_count:
        body = append_varint(body, removed[index])
        index = index + 1
    return body


# UntrustedSlot: the creative-mode stack. Component payloads are opaque byte
# arrays here because the server treats a creative stack as untrusted input and
# decodes them itself. `payloads` holds one byte blob per added component.
def pl_append_untrusted_slot(body: int64[], item: int64, count: int64,
                             types: int64[], payloads: int64[],
                             payload_starts: int64[], payload_lengths: int64[],
                             components: int64, removed: int64[],
                             removed_count: int64) -> int64[]:
    body = append_varint(body, count)
    if count == (int64)0:
        return body
    body = append_varint(body, item)
    body = append_varint(body, components)
    body = append_varint(body, removed_count)
    int64 index = 0
    while index < components:
        body = append_varint(body, types[index])
        body = append_varint(body, payload_lengths[index])
        int64 at = payload_starts[index]
        int64 end = at + payload_lengths[index]
        while at < end:
            append(body, payloads[at])
            at = at + 1
        index = index + 1
    index = 0
    while index < removed_count:
        body = append_varint(body, removed[index])
        index = index + 1
    return body


public def encode_container_close(window_id: int64) -> int64[]:
    int64[] body = new int64[0]
    body = append_varint(body, window_id)
    return encode_packet_frame(pid_pl_s_container_close(), body)


public def encode_container_button_click(window_id: int64,
                                         button: int64) -> int64[]:
    int64[] body = new int64[0]
    body = append_varint(body, window_id)
    body = append_varint(body, button)
    return encode_packet_frame(pid_pl_s_container_button_click(), body)


public def encode_container_slot_state_changed(slot_id: int64, window_id: int64,
                                               open: bool) -> int64[]:
    int64[] body = new int64[0]
    body = append_varint(body, slot_id)
    body = append_varint(body, window_id)
    if open:
        append(body, 1)
    else:
        append(body, 0)
    return encode_packet_frame(pid_pl_s_container_slot_state_changed(), body)


# Container click. `locations`, `items` and `counts` are parallel arrays of
# `changed_rows` slots the client believes differ from the server's view; an
# empty list means the prediction matched. Component hashes are not tracked by
# VInventory, so the echoed slots carry none and the server resyncs any slot
# whose components it finds changed.
public def encode_container_click(window_id: int64, state_id: int64, slot: int,
                                  button: int, mode: int64,
                                  locations: int64[], items: int64[],
                                  counts: int64[], changed_rows: int64,
                                  carried_present: bool, carried_item: int64,
                                  carried_count: int64) -> int64[]:
    int64[] body = new int64[0]
    int64[] none = new int64[0]
    body = append_varint(body, window_id)
    body = append_varint(body, state_id)
    append(body, slot >> 8 & 0xFF)
    append(body, slot & 0xFF)
    append(body, button & 0xFF)
    body = append_varint(body, mode)
    body = append_varint(body, changed_rows)
    int64 index = 0
    while index < changed_rows:
        append(body, locations[index] >> 8 & 0xFF)
        append(body, locations[index] & 0xFF)
        append(body, 1)
        body = pl_append_hashed_slot(body, items[index], counts[index],
                                     none, none, 0, none, 0)
        index = index + 1
    if carried_present:
        append(body, 1)
        body = pl_append_hashed_slot(body, carried_item, carried_count,
                                     none, none, 0, none, 0)
    else:
        append(body, 0)
    return encode_packet_frame(pid_pl_s_container_click(), body)


public def encode_set_creative_mode_slot(slot: int, item: int64,
                                         count: int64) -> int64[]:
    int64[] body = new int64[0]
    int64[] none = new int64[0]
    append(body, slot >> 8 & 0xFF)
    append(body, slot & 0xFF)
    body = pl_append_untrusted_slot(body, item, count, none, none, none, none,
                                    0, none, 0)
    return encode_packet_frame(pid_pl_s_set_creative_mode_slot(), body)


public def encode_select_bundle_item(slot_id: int64,
                                     selected_index: int64) -> int64[]:
    int64[] body = new int64[0]
    body = append_varint(body, slot_id)
    body = append_varint(body, selected_index)
    return encode_packet_frame(pid_pl_s_bundle_item_selected(), body)


public def encode_select_trade(slot: int64) -> int64[]:
    int64[] body = new int64[0]
    body = append_varint(body, slot)
    return encode_packet_frame(pid_pl_s_select_trade(), body)


public def encode_craft_recipe_request(window_id: int64, recipe_id: int64,
                                       make_all: bool) -> int64[]:
    int64[] body = new int64[0]
    body = append_varint(body, window_id)
    body = append_varint(body, recipe_id)
    if make_all:
        append(body, 1)
    else:
        append(body, 0)
    return encode_packet_frame(pid_pl_s_place_recipe(), body)


public def encode_recipe_book(book_id: int64, book_open: bool,
                              filter_active: bool) -> int64[]:
    int64[] body = new int64[0]
    body = append_varint(body, book_id)
    if book_open:
        append(body, 1)
    else:
        append(body, 0)
    if filter_active:
        append(body, 1)
    else:
        append(body, 0)
    return encode_packet_frame(pid_pl_s_recipe_book_change_settings(), body)


public def encode_displayed_recipe(recipe_id: int64) -> int64[]:
    int64[] body = new int64[0]
    body = append_varint(body, recipe_id)
    return encode_packet_frame(pid_pl_s_recipe_book_seen_recipe(), body)


public def encode_player_abilities_server(flags: int, flying_speed: double,
                                           fov_modifier: double) -> int64[]:
    int64[] payload = new int64[1 + 4 + 4]
    payload[0] = flags
    int index = 0
    double fs = flying_speed
    while index < 4:
        payload[1 + index] = mc_float_be_byte(fs, index)
        payload[5 + index] = mc_float_be_byte(fov_modifier, index)
        index = index + 1
    return encode_packet_frame(pid_pl_s_player_abilities(), payload)


public def encode_client_command_settings(view_distance: int,
                                           chat_mode: int) -> int64[]:
    int64[] vd = encode_varint(view_distance)
    int64[] payload = new int64[len(vd) + 1 + 1 + 1 + 4 + 1]
    int index = 0
    while index < len(vd):
        payload[index] = vd[index]
        index = index + 1
    payload[index] = 1
    index += 1
    payload[index] = chat_mode
    index += 1
    payload[index] = 0
    index += 1
    payload[index] = 0xFF
    payload[index + 1] = 0xFF
    payload[index + 2] = 0xFF
    payload[index + 3] = 0xFF
    index += 4
    payload[index] = 0
    return encode_packet_frame(pid_pl_s_client_command(), payload)


public def encode_interact(entity_id: int64, action: int,
                            x: double, y: double, z: double,
                            face: int, inside: bool, hand: int) -> int64[]:
    int64[] eid = encode_varint(entity_id)
    int64 head_len = len(eid) + 1
    if action == 0 or action == 2:
        head_len += 4 + 4 + 4 + 1 + 1 + 1
    int64[] payload = new int64[head_len]
    int index = 0
    while index < len(eid):
        payload[index] = eid[index]
        index = index + 1
    payload[index] = action
    index += 1
    if action == 0 or action == 2:
        int sub = 0
        while sub < 4:
            payload[index + sub] = mc_float_be_byte(x, sub)
            payload[index + 4 + sub] = mc_float_be_byte(y, sub)
            payload[index + 8 + sub] = mc_float_be_byte(z, sub)
            sub = sub + 1
        payload[index + 12] = face
        payload[index + 13] = (int64)(1 if inside else 0)
        payload[index + 14] = hand
    return encode_packet_frame(pid_pl_s_interact(), payload)


public def encode_attack(target_id: int64) -> int64[]:
    int64[] eid = encode_varint(target_id)
    int64[] payload = new int64[len(eid)]
    int index = 0
    while index < len(eid):
        payload[index] = eid[index]
        index = index + 1
    return encode_packet_frame(pid_pl_s_attack(), payload)


public def encode_chat_ack(offset: int64,
                            acknowledgement: int64) -> int64[]:
    int64[] off = encode_varint(offset)
    int64[] ack = encode_varint(acknowledgement)
    int64[] payload = new int64[len(off) + len(ack)]
    int index = 0
    while index < len(off):
        payload[index] = off[index]
        index = index + 1
    index = 0
    while index < len(ack):
        payload[len(off) + index] = ack[index]
        index = index + 1
    return encode_packet_frame(pid_pl_s_chat_ack(), payload)


public def encode_player_action(status: int, packed_pos: int64,
                                 face: int, sequence: int64) -> int64[]:
    int64[] pos_bytes = new int64[8]
    int i = 0
    while i < 8:
        pos_bytes[i] = packed_pos >> (7 - i) * 8 & 0xFF
        i = i + 1
    int64[] seq = encode_varint(sequence)
    int64[] payload = new int64[1 + 8 + 1 + len(seq)]
    payload[0] = status
    i = 0
    while i < 8:
        payload[1 + i] = pos_bytes[i]
        i = i + 1
    payload[9] = face
    i = 0
    while i < len(seq):
        payload[10 + i] = seq[i]
        i = i + 1
    return encode_packet_frame(pid_pl_s_player_action(), payload)


# --- Serverbound Play encoders: tick, input and movement ---

public def encode_client_tick_end() -> int64[]:
    return encode_packet_frame(pid_pl_s_client_tick_end(), new int64[0])


public def encode_punch() -> int64[]:
    return encode_packet_frame(pid_pl_s_punch(), new int64[0])


public def encode_play_ping_request(time: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_i64(payload, time)
    return encode_packet_frame(pid_pl_s_ping_request(), payload)


# One byte of flags: forward 1, backward 2, left 4, right 8, jump 16, shift 32,
# sprint 64.
public def encode_player_input(flags: int) -> int64[]:
    int64[] payload = new int64[1]
    payload[0] = (int64)(flags & 0x7F)
    return encode_packet_frame(pid_pl_s_player_input(), payload)


public def encode_paddle_boat(left: bool, right: bool) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_bool(payload, left)
    payload = sb_bool(payload, right)
    return encode_packet_frame(pid_pl_s_paddle_boat(), payload)


public def encode_lock_difficulty(locked: bool) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_bool(payload, locked)
    return encode_packet_frame(pid_pl_s_lock_difficulty(), payload)


public def encode_change_difficulty(difficulty: int) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, (int64)difficulty)
    return encode_packet_frame(pid_pl_s_change_difficulty(), payload)


public def encode_change_game_mode(mode: int) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, (int64)mode)
    return encode_packet_frame(pid_pl_s_change_game_mode(), payload)


# A vehicle reports an absolute position and rotation, unlike the player
# movement packets which send deltas.
public def encode_move_vehicle(x: double, y: double, z: double,
                               yaw: double, pitch: double,
                               on_ground: bool) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_f64(payload, x)
    payload = sb_f64(payload, y)
    payload = sb_f64(payload, z)
    payload = sb_f32(payload, yaw)
    payload = sb_f32(payload, pitch)
    payload = sb_bool(payload, on_ground)
    return encode_packet_frame(pid_pl_s_move_vehicle(), payload)


# A negative entity id leaves the optional spectate target absent, which asks
# the server to stop spectating.
public def encode_spectator_action(entity_id: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_opt_vi(payload, entity_id)
    return encode_packet_frame(pid_pl_s_spectator_action(), payload)


public def encode_teleport_to_entity(uuid: int64[], start: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_uuid(payload, uuid, start)
    return encode_packet_frame(pid_pl_s_teleport_to_entity(), payload)


# --- Serverbound Play encoders: queries, picking and block interaction ---

public def encode_entity_tag_query(transaction: int64,
                                   entity_id: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, transaction)
    payload = append_varint(payload, entity_id)
    return encode_packet_frame(pid_pl_s_entity_tag_query(), payload)


public def encode_block_entity_tag_query(transaction: int64, x: int64,
                                         y: int64, z: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, transaction)
    payload = sb_pos(payload, x, y, z)
    return encode_packet_frame(pid_pl_s_block_entity_tag_query(), payload)


public def encode_pick_item_from_block(x: int64, y: int64, z: int64,
                                       include_data: bool) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_pos(payload, x, y, z)
    payload = sb_bool(payload, include_data)
    return encode_packet_frame(pid_pl_s_pick_item_from_block(), payload)


public def encode_pick_item_from_entity(entity_id: int64,
                                        include_data: bool) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, entity_id)
    payload = sb_bool(payload, include_data)
    return encode_packet_frame(pid_pl_s_pick_item_from_entity(), payload)


# BlockHitResult sends the hit location relative to the block origin as three
# floats, then the inside and world-border flags. `face` is a Direction id:
# down 0, up 1, north 2, south 3, west 4, east 5.
public def encode_use_item_on(hand: int, x: int64, y: int64, z: int64,
                              face: int, click_x: double, click_y: double,
                              click_z: double, inside: bool,
                              world_border: bool, sequence: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, (int64)hand)
    payload = sb_pos(payload, x, y, z)
    payload = append_varint(payload, (int64)face)
    payload = sb_f32(payload, click_x)
    payload = sb_f32(payload, click_y)
    payload = sb_f32(payload, click_z)
    payload = sb_bool(payload, inside)
    payload = sb_bool(payload, world_border)
    payload = append_varint(payload, sequence)
    return encode_packet_frame(pid_pl_s_use_item_on(), payload)


public def encode_command_suggestion(transaction: int64, command: int64[],
                                     start: int64, length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, transaction)
    payload = sb_text(payload, command, start, length)
    return encode_packet_frame(pid_pl_s_command_suggestion(), payload)


# The DEBUG_SUBSCRIPTION registry is frozen at bootstrap, so the request is a
# plain list of registry ids bounded at 32 entries.
public def encode_debug_subscription_request(ids: int64[],
                                             count: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, count)
    int64 index = 0
    while index < count:
        payload = append_varint(payload, ids[index])
        index = index + 1
    return encode_packet_frame(pid_pl_s_debug_subscription_request(), payload)


# Action 0 (opened tab) names the tab; action 1 (closed screen) carries nothing.
public def encode_seen_advancements(action: int, tab: int64[], start: int64,
                                    length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, (int64)action)
    if action == 0:
        payload = sb_text(payload, tab, start, length)
    return encode_packet_frame(pid_pl_s_seen_advancements(), payload)


# --- Serverbound Play encoders: text, channels and client settings ---

public def encode_rename_item(name: int64[], start: int64,
                              length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_text(payload, name, start, length)
    return encode_packet_frame(pid_pl_s_rename_item(), payload)


# Only minecraft:brand has a vanilla serverbound codec, and it carries a
# protocol string rather than raw bytes. Every other channel is an opaque
# DiscardedPayload bounded at 32767 bytes, so its payload is passed through
# already serialised by whatever defines the channel. The body is identical in
# Configuration and Play; only the packet id differs.
public def encode_common_client_brand(packet_id: int64, brand: int64[],
                                      start: int64, length: int64) -> int64[]:
    str channel_name = "minecraft:brand"
    int64 channel_length = mc_string_length(channel_name)
    int64[] channel = new int64[channel_length]
    int64 index = 0
    while index < channel_length:
        channel[index] = mc_string_byte(channel_name, index)
        index = index + 1
    int64[] payload = new int64[0]
    payload = sb_text(payload, channel, 0, channel_length)
    payload = sb_text(payload, brand, start, length)
    return encode_packet_frame(packet_id, payload)


public def encode_client_brand(brand: int64[], start: int64,
                               length: int64) -> int64[]:
    return encode_common_client_brand(pid_pl_s_custom_payload(), brand, start,
                                      length)


public def encode_config_client_brand(brand: int64[], start: int64,
                                      length: int64) -> int64[]:
    return encode_common_client_brand(pid_cfg_s_custom_payload(), brand, start,
                                      length)


public def encode_common_custom_payload(packet_id: int64, channel: int64[],
                                        channel_start: int64,
                                        channel_length: int64, data: int64[],
                                        data_start: int64,
                                        data_length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_text(payload, channel, channel_start, channel_length)
    payload = sb_bytes(payload, data, data_start, data_length)
    return encode_packet_frame(packet_id, payload)


public def encode_custom_payload(channel: int64[], channel_start: int64,
                                 channel_length: int64, data: int64[],
                                 data_start: int64,
                                 data_length: int64) -> int64[]:
    return encode_common_custom_payload(pid_pl_s_custom_payload(), channel,
                                        channel_start, channel_length, data,
                                        data_start, data_length)


public def encode_config_custom_payload(channel: int64[], channel_start: int64,
                                        channel_length: int64, data: int64[],
                                        data_start: int64,
                                        data_length: int64) -> int64[]:
    return encode_common_custom_payload(pid_cfg_s_custom_payload(), channel,
                                        channel_start, channel_length, data,
                                        data_start, data_length)


# The payload is an optional Tag inside a VarInt length prefix. An absent tag
# still writes one byte (TAG_End), so the prefix is 1 rather than 0. A present
# tag is passed as a complete nameless NBT document, type byte included.
public def encode_common_custom_click_action(packet_id: int64, id: int64[],
                                             id_start: int64, id_length: int64,
                                             tag: int64[], tag_start: int64,
                                             tag_length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_text(payload, id, id_start, id_length)
    if tag_length <= 0:
        payload = append_varint(payload, 1)
        payload = sb_byte(payload, 0)
        return encode_packet_frame(packet_id, payload)
    payload = append_varint(payload, tag_length)
    payload = sb_bytes(payload, tag, tag_start, tag_length)
    return encode_packet_frame(packet_id, payload)


public def encode_custom_click_action(id: int64[], id_start: int64,
                                      id_length: int64, tag: int64[],
                                      tag_start: int64,
                                      tag_length: int64) -> int64[]:
    return encode_common_custom_click_action(pid_pl_s_custom_click_action(),
                                             id, id_start, id_length, tag,
                                             tag_start, tag_length)


public def encode_config_custom_click_action(id: int64[], id_start: int64,
                                             id_length: int64, tag: int64[],
                                             tag_start: int64,
                                             tag_length: int64) -> int64[]:
    return encode_common_custom_click_action(pid_cfg_s_custom_click_action(),
                                             id, id_start, id_length, tag,
                                             tag_start, tag_length)


# A cookie response names the key and optionally carries up to 5120 bytes. A
# negative payload length answers "I do not have that cookie", which is the
# correct reply for a key the client was never given. Login, Configuration and
# Play share the body.
public def encode_cookie_response(packet_id: int64, key: int64[],
                                  key_start: int64, key_length: int64,
                                  data: int64[], data_start: int64,
                                  data_length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_text(payload, key, key_start, key_length)
    if data_length < 0:
        payload = sb_bool(payload, false)
        return encode_packet_frame(packet_id, payload)
    payload = sb_bool(payload, true)
    payload = sb_text(payload, data, data_start, data_length)
    return encode_packet_frame(packet_id, payload)


# A login plugin/proxy query is answered with the transaction id and a nullable
# opaque payload. This backend understands no proxy channel, so it answers with
# no payload - the same reply the vanilla client gives for an unknown query -
# and lets the server decide whether to continue.
public def encode_login_custom_query_answer(transaction: int64, data: int64[],
                                            start: int64,
                                            length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, transaction)
    if length < 0:
        payload = sb_bool(payload, false)
        return encode_packet_frame(pid_lg_s_custom_query_answer(), payload)
    payload = sb_bool(payload, true)
    payload = sb_bytes(payload, data, start, length)
    return encode_packet_frame(pid_lg_s_custom_query_answer(), payload)


public def encode_client_information(language: int64[], language_start: int64,
                                     language_length: int64,
                                     view_distance: int, chat_visibility: int,
                                     chat_colors: bool,
                                     model_customisation: int, main_hand: int,
                                     text_filtering: bool,
                                     allows_listing: bool,
                                     particle_status: int) -> int64[]:
    int64[] payload = sb_client_information(language, language_start,
                                            language_length, view_distance,
                                            chat_visibility, chat_colors,
                                            model_customisation, main_hand,
                                            text_filtering, allows_listing,
                                            particle_status)
    return encode_packet_frame(pid_pl_s_client_information(), payload)


# --- Serverbound Play encoders: block and item editors ---

# Four lines with no count prefix, then the text slot: back 0, front 1.
public def encode_sign_update(x: int64, y: int64, z: int64, lines: int64[],
                              starts: int64[], lengths: int64[],
                              slot: int) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_pos(payload, x, y, z)
    int index = 0
    while index < 4:
        payload = sb_text(payload, lines, starts[index], lengths[index])
        index = index + 1
    payload = append_varint(payload, (int64)slot)
    return encode_packet_frame(pid_pl_s_sign_update(), payload)


# A negative title length leaves the optional title absent, which is how an
# unsigned book is sent.
public def encode_edit_book(slot: int64, pages: int64[], starts: int64[],
                            lengths: int64[], page_count: int64,
                            title: int64[], title_start: int64,
                            title_length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, slot)
    payload = append_varint(payload, page_count)
    int64 index = 0
    while index < page_count:
        payload = sb_text(payload, pages, starts[index], lengths[index])
        index = index + 1
    payload = sb_opt_text(payload, title, title_start, title_length)
    return encode_packet_frame(pid_pl_s_edit_book(), payload)


# Mode is the CommandBlockEntity ordinal: sequence 0, auto 1, redstone 2. Flags
# are track output 1, conditional 2, automatic 4.
public def encode_set_command_block(x: int64, y: int64, z: int64,
                                    command: int64[], start: int64,
                                    length: int64, mode: int,
                                    flags: int) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_pos(payload, x, y, z)
    payload = sb_text(payload, command, start, length)
    payload = append_varint(payload, (int64)mode)
    payload = sb_byte(payload, (int64)flags)
    return encode_packet_frame(pid_pl_s_set_command_block(), payload)


public def encode_set_command_minecart(entity_id: int64, command: int64[],
                                       start: int64, length: int64,
                                       track_output: bool) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, entity_id)
    payload = sb_text(payload, command, start, length)
    payload = sb_bool(payload, track_output)
    return encode_packet_frame(pid_pl_s_set_command_minecart(), payload)


# `joint` is the JointType serialised name ("rollable" or "aligned"), not an id.
public def encode_set_jigsaw_block(x: int64, y: int64, z: int64,
                                   name: int64[], name_start: int64,
                                   name_length: int64, target: int64[],
                                   target_start: int64, target_length: int64,
                                   pool: int64[], pool_start: int64,
                                   pool_length: int64, final_state: int64[],
                                   state_start: int64, state_length: int64,
                                   joint: int64[], joint_start: int64,
                                   joint_length: int64,
                                   selection_priority: int64,
                                   placement_priority: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_pos(payload, x, y, z)
    payload = sb_text(payload, name, name_start, name_length)
    payload = sb_text(payload, target, target_start, target_length)
    payload = sb_text(payload, pool, pool_start, pool_length)
    payload = sb_text(payload, final_state, state_start, state_length)
    payload = sb_text(payload, joint, joint_start, joint_length)
    payload = append_varint(payload, selection_priority)
    payload = append_varint(payload, placement_priority)
    return encode_packet_frame(pid_pl_s_set_jigsaw_block(), payload)


# UpdateType ordinals are update-data 0, save 1, load 2, scan 3; StructureMode
# ordinals are save 0, load 1, corner 2, data 3. Mirror ordinals are none 0,
# left-right 1, front-back 2 and Rotation ids run 0..3. Offsets and sizes are
# single bytes the server clamps to -48..48 and 0..48. Flags are ignore entities
# 1, show air 2, show bounding box 4, strict 8.
public def encode_set_structure_block(x: int64, y: int64, z: int64,
                                      update_type: int, mode: int,
                                      name: int64[], name_start: int64,
                                      name_length: int64, offset_x: int,
                                      offset_y: int, offset_z: int,
                                      size_x: int, size_y: int, size_z: int,
                                      mirror: int, rotation: int,
                                      data: int64[], data_start: int64,
                                      data_length: int64, integrity: double,
                                      seed: int64, flags: int) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_pos(payload, x, y, z)
    payload = append_varint(payload, (int64)update_type)
    payload = append_varint(payload, (int64)mode)
    payload = sb_text(payload, name, name_start, name_length)
    payload = sb_byte(payload, (int64)offset_x)
    payload = sb_byte(payload, (int64)offset_y)
    payload = sb_byte(payload, (int64)offset_z)
    payload = sb_byte(payload, (int64)size_x)
    payload = sb_byte(payload, (int64)size_y)
    payload = sb_byte(payload, (int64)size_z)
    payload = append_varint(payload, (int64)mirror)
    payload = append_varint(payload, (int64)rotation)
    payload = sb_text(payload, data, data_start, data_length)
    payload = sb_f32(payload, integrity)
    payload = sb_varlong(payload, seed)
    payload = sb_byte(payload, (int64)flags)
    return encode_packet_frame(pid_pl_s_set_structure_block(), payload)


# TestBlockMode ids are start 0, log 1, fail 2, accept 3.
public def encode_set_test_block(x: int64, y: int64, z: int64, mode: int,
                                 message: int64[], start: int64,
                                 length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_pos(payload, x, y, z)
    payload = append_varint(payload, (int64)mode)
    payload = sb_text(payload, message, start, length)
    return encode_packet_frame(pid_pl_s_set_test_block(), payload)


# Each entry is a GAME_RULE registry key (an identifier string) and its value.
public def encode_set_game_rule(names: int64[], name_starts: int64[],
                                name_lengths: int64[], values: int64[],
                                value_starts: int64[],
                                value_lengths: int64[],
                                count: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = append_varint(payload, count)
    int64 index = 0
    while index < count:
        payload = sb_text(payload, names, name_starts[index],
                          name_lengths[index])
        payload = sb_text(payload, values, value_starts[index],
                          value_lengths[index])
        index = index + 1
    return encode_packet_frame(pid_pl_s_set_game_rule(), payload)


# Negative effect ids leave the optional primary or secondary absent.
public def encode_set_beacon(primary: int64, secondary: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_opt_vi(payload, primary)
    payload = sb_opt_vi(payload, secondary)
    return encode_packet_frame(pid_pl_s_set_beacon(), payload)


public def encode_jigsaw_generate(x: int64, y: int64, z: int64, levels: int64,
                                  keep_jigsaws: bool) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_pos(payload, x, y, z)
    payload = append_varint(payload, levels)
    payload = sb_bool(payload, keep_jigsaws)
    return encode_packet_frame(pid_pl_s_jigsaw_generate(), payload)


# Action ids are init 0, query 1, set 2, reset 3, save 4, export 5, run 6; Status
# ids are cleared 0, running 1, finished 2. Data is an optional TEST_INSTANCE
# key, a VarInt Vec3i size, a Rotation id, the ignore-entities flag, a Status id
# and an optional error component. Negative lengths leave the key or the
# component absent; a present error is written as a nameless NBT StringTag.
public def encode_test_instance_block_action(x: int64, y: int64, z: int64,
                                             action: int, test: int64[],
                                             test_start: int64,
                                             test_length: int64,
                                             size_x: int64, size_y: int64,
                                             size_z: int64, rotation: int,
                                             ignore_entities: bool,
                                             status: int, error: int64[],
                                             error_start: int64,
                                             error_length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_pos(payload, x, y, z)
    payload = append_varint(payload, (int64)action)
    payload = sb_opt_text(payload, test, test_start, test_length)
    payload = append_varint(payload, size_x)
    payload = append_varint(payload, size_y)
    payload = append_varint(payload, size_z)
    payload = append_varint(payload, (int64)rotation)
    payload = sb_bool(payload, ignore_entities)
    payload = append_varint(payload, (int64)status)
    if error_length < 0:
        payload = sb_bool(payload, false)
        return encode_packet_frame(pid_pl_s_test_instance_block_action(),
                                   payload)
    payload = sb_bool(payload, true)
    payload = sb_byte(payload, 8)
    payload = sb_nbt_string(payload, error, error_start, error_length)
    return encode_packet_frame(pid_pl_s_test_instance_block_action(), payload)


# --- Serverbound Play encoders: chat signing ---
#
# Both packets are structurally complete, but a local account has no
# Mojang-issued profile key, so the offline client never sends them. Signature
# and key bytes are parameters rather than something this backend invents.

# ArgumentSignatures is a list of at most 8 entries, each a name and a raw
# 256-byte MessageSignature. LastSeenMessages.Update is an offset, a fixed
# 20-bit acknowledgement set (3 bytes) and a checksum byte; 0 ignores it.
public def encode_chat_command_signed(command: int64[], command_start: int64,
                                      command_length: int64, timestamp: int64,
                                      salt: int64, names: int64[],
                                      name_starts: int64[],
                                      name_lengths: int64[],
                                      signatures: int64[],
                                      signature_starts: int64[],
                                      argument_count: int64,
                                      last_seen_offset: int64,
                                      acknowledged: int64,
                                      checksum: int) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_text(payload, command, command_start, command_length)
    payload = sb_i64(payload, timestamp)
    payload = sb_i64(payload, salt)
    payload = append_varint(payload, argument_count)
    int64 index = 0
    while index < argument_count:
        payload = sb_text(payload, names, name_starts[index],
                          name_lengths[index])
        payload = sb_bytes(payload, signatures, signature_starts[index], 256)
        index = index + 1
    payload = append_varint(payload, last_seen_offset)
    payload = sb_bitset20(payload, acknowledged)
    payload = sb_byte(payload, (int64)checksum)
    return encode_packet_frame(pid_pl_s_chat_command_signed(), payload)


# RemoteChatSession.Data: a session UUID then ProfilePublicKey.Data, which is an
# expiry instant, a VarInt-prefixed encoded public key and a VarInt-prefixed
# Mojang signature over it.
public def encode_chat_session_update(session: int64[], session_start: int64,
                                      expires_at: int64, public_key: int64[],
                                      key_start: int64, key_length: int64,
                                      key_signature: int64[],
                                      signature_start: int64,
                                      signature_length: int64) -> int64[]:
    int64[] payload = new int64[0]
    payload = sb_uuid(payload, session, session_start)
    payload = sb_i64(payload, expires_at)
    payload = sb_text(payload, public_key, key_start, key_length)
    payload = sb_text(payload, key_signature, signature_start,
                      signature_length)
    return encode_packet_frame(pid_pl_s_chat_session_update(), payload)


# --- Clientbound packet handlers ---

public def pl_handle_set_health(socket_handle: int64, body: int64[],
                                 offset: int64, state: VPlayState*) -> int:
    if offset + 12 > len(body):
        print("Malformed set-health packet")
        return 1
    state.health = decode_be_float(body, offset)
    state.food = decode_be_float(body, offset + 4)
    state.saturation = decode_be_float(body, offset + 8)
    print(f"Health: {state.health}, food: {state.food}, saturation: {state.saturation}")
    return 0


public def pl_handle_set_experience(socket_handle: int64, body: int64[],
                                     offset: int64, state: VPlayState*) -> int:
    if offset + 4 > len(body):
        print("Malformed set-experience packet")
        return 1
    state.xp_progress = decode_be_float(body, offset)
    int64[] level = decode_varint(body, offset + 4)
    if level[0] != 1:
        return 1
    int64[] total = decode_varint(body, level[2])
    if total[0] != 1:
        return 1
    state.xp_level = (int)level[1]
    state.xp_total = (int)total[1]
    print(f"Experience: level {state.xp_level}, total {state.xp_total}, progress {state.xp_progress}")
    return 0


public def pl_handle_player_abilities(socket_handle: int64, body: int64[],
                                       offset: int64, state: VPlayState*) -> int:
    if offset + 9 > len(body):
        return 1
    state.abilities_flags = (int)body[offset]
    state.flying_speed = decode_be_float(body, offset + 1)
    state.fov_modifier = decode_be_float(body, offset + 5)
    return 0


public def pl_handle_set_held_slot(socket_handle: int64, body: int64[],
                                     offset: int64, state: VPlayState*) -> int:
    int64[] slot = decode_varint(body, offset)
    if slot[0] != 1 or slot[2] != len(body):
        return 1
    if vinv_set_held(state.inventory, (int)slot[1]) != 0:
        return 1
    state.held_slot = (int)slot[1]
    return 0


public def pl_handle_set_time(socket_handle: int64, body: int64[],
                               offset: int64, state: VPlayState*) -> int:
    if offset + 8 > len(body):
        return 1
    state.world_time = decode_be_i64(body, offset)
    return 0


public def pl_handle_respawn(socket_handle: int64, body: int64[],
                              offset: int64, state: VPlayState*,
                              registry: VDimensionRegistry*) -> int:
    if offset >= len(body):
        return 1
    int64[] dim = decode_varint(body, offset)
    if dim[0] != 1:
        return 1
    int64[] game_mode = decode_varint(body, dim[2])
    if game_mode[0] != 1:
        return 1
    int64[] hash_field = decode_varint(body, game_mode[2])
    if hash_field[0] != 1:
        return 1
    int64 after_hash = hash_field[2] + 8
    int64[] read_only = decode_varint(body, after_hash)
    if read_only[0] != 1:
        return 1
    int64[] light = decode_varint(body, read_only[2])
    if light[0] != 1:
        return 1
    state.game_mode = (int)game_mode[1]
    print(f"Respawn: dimension {dim[1]}, game mode {state.game_mode}")
    return 0


public def pl_handle_game_event(socket_handle: int64, body: int64[],
                                 offset: int64) -> int:
    if offset < 0 or offset + 5 > len(body):
        print("Truncated game event packet")
        return 1
    int event = (int)body[offset] & 0xFF
    double value = decode_be_float(body, offset + 1)
    print(f"Game event {event} value {value}")
    return 0


public def pl_handle_simulation_distance(socket_handle: int64, body: int64[],
                                          offset: int64, state: VPlayState*) -> int:
    if offset >= len(body):
        return 1
    int64[] view = decode_varint(body, offset)
    if view[0] != 1:
        return 1
    int64[] sim = decode_varint(body, view[2])
    if sim[0] != 1:
        return 1
    state.view_distance = (int)view[1]
    state.simulation_distance = (int)sim[1]
    return 0


# A chat component travels as a nameless NBT document: one tag-type byte then
# that type's payload, with no name field. Type 0 is the null component, type 8
# a plain string and type 10 the styled compound. Every other tag type is still
# walked so an unexpected component cannot desynchronise the rest of the packet.
public def pl_component_end(body: int64[], offset: int64) -> int64:
    if offset >= len(body):
        return (int64)-1
    int64 marker = body[offset]
    if marker < 0 or marker > 12:
        return (int64)-1
    int64[] payload = skip_nbt_payload(body, marker, offset + 1, 0)
    if payload[0] != 1:
        return (int64)-1
    return payload[2]


def pl_component_text(body: int64[], offset: int64, out: int64[]) -> int:
    if offset >= len(body) or body[offset] != 8:
        return 0
    int64[] text = read_nbt_string(body, offset + 1)
    if text[0] != 1 or text[1] > 32:
        return 0
    int64 index = 0
    while index < text[1]:
        out[index] = body[text[2] + index]
        index = index + 1
    out[text[1]] = 0
    return (int)text[1]


# The pair the two reads need in one result: status, the flattened length and
# where the component ended.
def pl_component_flat(body: int64[], offset: int64, out: int64[]) -> int64[]:
    int64 end = pl_component_end(body, offset)
    if end < 0:
        return decode_result(-1, 0, offset)
    return decode_result(1, pl_component_text(body, offset, out), end)


# Player Info Update: an action mask, then a list of uuids each carrying the
# fields the mask names. The fields come in declaration order, which is not the
# order the bits are numbered in: the list-order priority is written before the
# hat flag even though the hat owns the lower bit.
#
# Only the add action creates a row. Every other action against a uuid the
# client has never been introduced to is walked and dropped, because inventing
# a tab entry from a latency update would show a player nobody named.
public def pl_handle_player_info_update(socket_handle: int64, body: int64[],
                                        offset: int64, table: VPlayers*,
                                        text: int64[]) -> int:
    if offset + 2 > len(body):
        print("Truncated player info update")
        return 1
    int mask = (int)body[offset] & 0xFF
    if mask == 0:
        print("Player info update names no actions")
        return 1
    int64[] size = decode_varint(body, offset + 1)
    if size[0] != 1 or size[1] < 0 or size[1] > 512:
        print("Malformed player info entry count")
        return 1
    int64 cursor = size[2]
    int64 index = 0
    int added = 0
    while index < size[1]:
        if cursor + 16 > len(body):
            print("Truncated player info entry")
            return 1
        int uuid_at = (int)cursor
        cursor = cursor + 16
        if (mask & vplayers_action_add()) != 0:
            int name_start = (int)cursor
            int64[] name = read_string_field(body, cursor, 32)
            if name[0] != 1:
                print("Malformed player name")
                return 1
            int name_length = (int)name[1]
            cursor = pl_take(body, name[2], name[1])
            if cursor < 0:
                print("Truncated player name")
                return 1
            int64[] property_count = decode_varint(body, cursor)
            if property_count[0] != 1 or property_count[1] < 0 or property_count[1] > 16:
                print("Malformed skin property count")
                return 1
            cursor = property_count[2]
            int64 walked = 0
            while walked < property_count[1]:
                int64[] property_name = read_string_field(body, cursor, 512)
                if property_name[0] != 1:
                    print("Malformed skin property name")
                    return 1
                cursor = pl_take(body, property_name[2], property_name[1])
                if cursor < 0:
                    print("Truncated skin property name")
                    return 1
                int64[] property_value = read_string_field(body, cursor, 65536)
                if property_value[0] != 1:
                    print("Malformed skin property value")
                    return 1
                cursor = pl_take(body, property_value[2], property_value[1])
                if cursor < 0:
                    print("Truncated skin property value")
                    return 1
                if cursor >= len(body):
                    print("Truncated skin property signature")
                    return 1
                int signed = (int)body[cursor] & 0xFF
                cursor = cursor + 1
                if signed != 0:
                    int64[] signature = read_string_field(body, cursor, 65536)
                    if signature[0] != 1:
                        print("Malformed skin property signature")
                        return 1
                    cursor = pl_take(body, signature[2], signature[1])
                    if cursor < 0:
                        print("Truncated skin property signature")
                        return 1
                walked = walked + 1
            if vplayers_set_add(table, body, uuid_at, name_start + 1,
                               name_length, (int)property_count[1], 0,
                               0) == 0:
                print("Player list is full")
                return 1
            if added < 4:
                print("Player joined the list: ")
                pl_note_bytes(body, name[2], name[1])
                print(f" ({(int)property_count[1]} skin properties)")
            added = added + 1
        if (mask & vplayers_action_chat()) != 0:
            if cursor >= len(body):
                print("Truncated chat session flag")
                return 1
            int has_session = (int)body[cursor] & 0xFF
            cursor = cursor + 1
            if has_session != 0:
                cursor = pl_take(body, cursor, 24)
                if cursor < 0:
                    print("Truncated chat session")
                    return 1
                cursor = pl_take_byte_array(body, cursor, 65536)
                if cursor < 0:
                    print("Truncated chat session key")
                    return 1
                cursor = pl_take_byte_array(body, cursor, 65536)
                if cursor < 0:
                    print("Truncated chat session signature")
                    return 1
            vplayers_set_chat(table, body, uuid_at, has_session)
        if (mask & vplayers_action_game_mode()) != 0:
            int64[] mode = decode_varint(body, cursor)
            if mode[0] != 1 or mode[1] < 0 or mode[1] > 4:
                print("Malformed player game mode")
                return 1
            cursor = mode[2]
            vplayers_set_game_mode(table, body, uuid_at, (int)mode[1])
        if (mask & vplayers_action_listed()) != 0:
            int64[] shown = decode_varint(body, cursor)
            if shown[0] != 1:
                print("Malformed player list flag")
                return 1
            cursor = shown[2]
            vplayers_set_listed(table, body, uuid_at, (int)shown[1])
        if (mask & vplayers_action_latency()) != 0:
            int64[] ping = decode_varint(body, cursor)
            if ping[0] != 1 or ping[1] < 0 or ping[1] > 1000000:
                print("Malformed player latency")
                return 1
            cursor = ping[2]
            vplayers_set_latency(table, body, uuid_at, (int)ping[1])
        if (mask & vplayers_action_display()) != 0:
            if cursor >= len(body):
                print("Truncated display name flag")
                return 1
            int has_display = (int)body[cursor] & 0xFF
            cursor = cursor + 1
            if has_display != 0:
                int64[] display = pl_component_flat(body, cursor, text)
                if display[0] != 1:
                    print("Malformed display name component")
                    return 1
                if display[1] > 0:
                    vplayers_set_display(table, body, uuid_at, text, display[1])
                cursor = display[2]
        if (mask & vplayers_action_priority()) != 0:
            int64[] order = decode_varint(body, cursor)
            if order[0] != 1:
                print("Malformed player list order")
                return 1
            cursor = order[2]
            vplayers_set_priority(table, body, uuid_at, (int)order[1])
        if (mask & vplayers_action_hat()) != 0:
            if cursor >= len(body):
                print("Truncated hat visibility flag")
                return 1
            int hat = (int)body[cursor] & 0xFF
            cursor = cursor + 1
            vplayers_set_hat(table, body, uuid_at, hat)
        index = index + 1
    if cursor != len(body):
        print(f"Player info update has {len(body) - cursor} bytes left over")
        return 1
    print(f"Player info update: {size[1]} entries, {added} added")
    return 0


public def pl_handle_set_default_spawn(socket_handle: int64, body: int64[],
                                        offset: int64) -> int:
    int64[] dim = decode_varint(body, offset)
    if dim[0] != 1:
        return 1
    int64[] pos = read_string_field(body, dim[2], 128)
    if pos[0] != 1:
        return 1
    print(f"Default spawn: dimension {dim[1]} position {pos[1]} bytes")
    return 0


# 26.3 movement. The delta packets carry a packed properties varint (bit 0 is
# on-ground, the rest is a step count) followed by a VecDelta: three i16 deltas
# when the step count is zero, otherwise that many {ticks varint, three i16}
# records whose deltas compose. 0 = vehicle, 1 = delta position, 2 = delta
# position and rotation, 3 = teleport, 4 = position sync.
# Absolute angles arrive as degrees in the teleport and sync packets, but the
# entity table keeps the wire's 256-step byte so every source agrees.
def pl_angle_byte(degrees: double) -> int:
    int raw = (int)(degrees * 256.0 / 360.0)
    return raw & 0xFF


def pl_read_vec_delta(body: int64[], cursor: int64, steps: int64,
                      out: int64[]) -> int64:
    out[0] = 0
    out[1] = 0
    out[2] = 0
    if steps == (int64)0:
        if cursor + 6 > len(body):
            return (int64)-1
        out[0] = pl_decode_be_int16(body, cursor)
        out[1] = pl_decode_be_int16(body, cursor + 2)
        out[2] = pl_decode_be_int16(body, cursor + 4)
        return cursor + 6
    if steps > (int64)4096:
        return (int64)-1
    int64 index = 0
    while index < steps:
        int64[] ticks = decode_varint(body, cursor)
        if ticks[0] != 1 or ticks[2] + 6 > len(body):
            return (int64)-1
        out[0] = out[0] + pl_decode_be_int16(body, ticks[2])
        out[1] = out[1] + pl_decode_be_int16(body, ticks[2] + 2)
        out[2] = out[2] + pl_decode_be_int16(body, ticks[2] + 4)
        cursor = ticks[2] + 6
        index = index + 1
    return cursor


# PositionPath: a varint discriminator, then either an absolute Vec3 or a list
# of {Vec3, tick offset varint} steps. Only the end position matters here.
def pl_read_position_path(body: int64[], cursor: int64, out: int64[]) -> int64:
    int64[] kind = decode_varint(body, cursor)
    if kind[0] != 1 or (kind[1] != 0 and kind[1] != 1):
        return (int64)-1
    cursor = kind[2]
    int64 steps = 1
    if kind[1] == (int64)1:
        int64[] count = decode_varint(body, cursor)
        if count[0] != 1 or (count[1] < 1 or count[1] > 4096):
            return (int64)-1
        steps = count[1]
        cursor = count[2]
    int64 index = 0
    while index < steps:
        if cursor + 24 > len(body):
            return (int64)-1
        out[0] = vt_double_to_bits(decode_be_int64(body, cursor))
        out[1] = vt_double_to_bits(decode_be_int64(body, cursor + 8))
        out[2] = vt_double_to_bits(decode_be_int64(body, cursor + 16))
        cursor += 24
        if kind[1] == (int64)1:
            int64[] ticks = decode_varint(body, cursor)
            if ticks[0] != 1:
                return (int64)-1
            cursor = ticks[2]
        index = index + 1
    return cursor


public def pl_handle_entity_position(socket_handle: int64, body: int64[],
                                      offset: int64, mode: int,
                                      table: VEntities*) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1 or id[1] < 0:
        return 1
    int entity_id = (int)id[1]
    int64 cursor = id[2]
    int64[] xyz = new int64[3]
    if mode == 0:
        # Vehicle move is client-authoritative: absolute position and floats.
        if cursor + 32 > len(body):
            return 1
        ventities_set_position(table, entity_id,
                               decode_be_int64(body, cursor),
                               decode_be_int64(body, cursor + 8),
                               decode_be_int64(body, cursor + 16))
        ventities_set_angle(table, entity_id, 0,
                            pl_angle_byte(decode_be_float(body, cursor + 24)))
        ventities_set_angle(table, entity_id, 1,
                            pl_angle_byte(decode_be_float(body, cursor + 28)))
        return 0
    if mode == 3:
        # Teleport: position, known movement, yaw, pitch, a relative-flags int
        # and the on-ground byte.
        if cursor + 61 > len(body):
            return 1
        double x = decode_be_int64(body, cursor)
        double y = decode_be_int64(body, cursor + 8)
        double z = decode_be_int64(body, cursor + 16)
        int64 relatives = decode_be_int32(body, cursor + 56)
        if relatives != (int64)0:
            if (relatives & 1) != 0:
                x = x + ventities_position(table, entity_id, 0)
            if (relatives & 2) != 0:
                y = y + ventities_position(table, entity_id, 1)
            if (relatives & 4) != 0:
                z = z + ventities_position(table, entity_id, 2)
        ventities_set_position(table, entity_id, x, y, z)
        ventities_set_angle(table, entity_id, 0,
                            pl_angle_byte(decode_be_float(body, cursor + 48)))
        ventities_set_angle(table, entity_id, 1,
                            pl_angle_byte(decode_be_float(body, cursor + 52)))
        ventities_set_flag(table, entity_id, vent_flag_on_ground(),
                           body[cursor + 60] != 0)
        return 0
    if mode == 4:
        cursor = pl_read_position_path(body, cursor, xyz)
        if cursor < 0 or cursor + 9 > len(body):
            return 1
        ventities_set_position(table, entity_id,
                               vt_bits_to_double(xyz[0]),
                               vt_bits_to_double(xyz[1]),
                               vt_bits_to_double(xyz[2]))
        ventities_set_angle(table, entity_id, 0,
                            pl_angle_byte(decode_be_float(body, cursor)))
        ventities_set_angle(table, entity_id, 1,
                            pl_angle_byte(decode_be_float(body, cursor + 4)))
        ventities_set_flag(table, entity_id, vent_flag_on_ground(),
                           body[cursor + 8] != 0)
        return 0
    int64[] properties = decode_varint(body, cursor)
    if properties[0] != 1 or properties[1] < 0:
        return 1
    int64 steps = properties[1] >> 1
    cursor = pl_read_vec_delta(body, properties[2], steps, xyz)
    if cursor < 0:
        return 1
    ventities_move_by(table, entity_id, (double)xyz[0] / 4096.0,
                      (double)xyz[1] / 4096.0, (double)xyz[2] / 4096.0)
    ventities_set_flag(table, entity_id, vent_flag_on_ground(),
                       (properties[1] & 1) != 0)
    if mode == 2:
        if cursor + 2 > len(body):
            return 1
        ventities_set_angle(table, entity_id, 0, (int)body[cursor])
        ventities_set_angle(table, entity_id, 1, (int)body[cursor + 1])
        cursor += 2
    if cursor != len(body):
        return 1
    return 0


# Rotation-only movement. 26.3 puts the on-ground byte before the angle bytes.
public def pl_handle_move_entity_rot(body: int64[], offset: int64,
                                     table: VEntities*) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1 or id[1] < 0 or id[2] + 3 != len(body):
        return 1
    int entity_id = (int)id[1]
    ventities_set_flag(table, entity_id, vent_flag_on_ground(),
                       body[id[2]] != 0)
    ventities_set_angle(table, entity_id, 0, (int)body[id[2] + 1])
    ventities_set_angle(table, entity_id, 1, (int)body[id[2] + 2])
    return 0


public def pl_handle_rotate_head(socket_handle: int64, body: int64[],
                                  offset: int64, table: VEntities*) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1 or id[1] < 0:
        return 1
    if id[2] + 1 > len(body):
        return 1
    ventities_set_angle(table, (int)id[1], 2, (int)body[id[2]])
    return 0


public def pl_handle_block_event(socket_handle: int64, body: int64[],
                                  offset: int64) -> int:
    if offset < 0 or offset + 10 > len(body):
        return 1
    int _type_id = (int)body[offset]
    int64 cursor = offset + 5
    int64[] pos = decode_varint(body, cursor)
    if pos[0] != 1:
        return 1
    cursor = pos[2]
    if cursor >= len(body):
        return 1
    int _data = (int)body[cursor]
    int64[] _state_id = decode_varint(body, cursor + 1)
    if _state_id[0] != 1:
        return 1
    print(f"Block event type {_type_id} data {_data} state {_state_id[1]}")
    return 0

public def pl_handle_set_entity_motion(socket_handle: int64, body: int64[],
                                        offset: int64, table: VEntities*) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1 or id[1] < 0:
        return 1
    if id[2] + 6 > len(body):
        return 1
    # Velocity shorts are in 1/8000th-of-a-block-per-tick, a different scale
    # from the 1/4096th used by movement deltas.
    double vx = (double)(int)pl_decode_be_int16(body, id[2]) / 8000.0
    double vy = (double)(int)pl_decode_be_int16(body, id[2] + 2) / 8000.0
    double vz = (double)(int)pl_decode_be_int16(body, id[2] + 4) / 8000.0
    ventities_set_motion(table, (int)id[1], vx, vy, vz)
    return 0


# Relations themselves are not modelled yet; the list is still walked in full so
# a truncated or overlong passenger packet is reported instead of accepted.
public def pl_handle_set_passengers(socket_handle: int64, body: int64[],
                                     offset: int64, table: VEntities*) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1 or id[1] < 0:
        return 1
    int64[] count = decode_varint(body, id[2])
    if count[0] != 1 or count[1] < 0 or count[1] > 1024:
        return 1
    int64 cursor = count[2]
    int64 rider = 0
    while rider < count[1]:
        int64[] rider_id = decode_varint(body, cursor)
        if rider_id[0] != 1 or rider_id[1] < 0:
            return 1
        ventities_touch(table, (int)rider_id[1])
        cursor = rider_id[2]
        rider = rider + 1
    return 0


public def pl_handle_swing_animation(socket_handle: int64, body: int64[],
                                      offset: int64) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1:
        return 1
    if id[2] >= len(body):
        return 1
    int _hand = (int)body[id[2]]
    print(f"Entity {id[1]} swings {_hand}")
    return 0


public def pl_handle_explode(socket_handle: int64, body: int64[],
                              offset: int64, world: VWorld*) -> int:
    if offset + 16 > len(body):
        return 1
    double _x = decode_be_float(body, offset)
    double _y = decode_be_float(body, offset + 4)
    double _z = decode_be_float(body, offset + 8)
    double _radius = decode_be_float(body, offset + 12)
    if offset + 16 >= len(body):
        return 1
    int64[] count = decode_varint(body, offset + 16)
    if count[0] != 1 or count[1] < 0 or count[1] > 2048:
        return 1
    int64 cursor = count[2] + count[1] * 4
    if cursor + 24 > len(body):
        return 1
    print(f"Explosion at ({_x}, {_y}, {_z}) radius {_radius}, {count[1]} blocks")
    return 0


public def pl_handle_title(socket_handle: int64, body: int64[],
                            offset: int64, label: str) -> int:
    if offset >= len(body):
        return 1
    int tag_type = (int)body[offset]
    int result = print_nbt_text(body, tag_type, offset)
    if label != "":
        print(f"{label}:")
    return result


# Player List Header And Footer: two chat components and nothing else - the
# action varint older revisions used is gone. The pair is stored on the list
# itself because it belongs to the tab rather than to any row, and a component
# that flattens to no text clears the slot.
public def pl_handle_tab_list(socket_handle: int64, body: int64[], offset: int64,
                              table: VPlayers*, header: int64[],
                              footer: int64[]) -> int:
    int64[] shown = pl_component_flat(body, offset, header)
    if shown[0] != 1:
        print("Malformed tab list header")
        return 1
    int64[] last = pl_component_flat(body, shown[2], footer)
    if last[0] != 1:
        print("Malformed tab list footer")
        return 1
    if last[2] != len(body):
        print(f"Tab list packet has {len(body) - last[2]} bytes left over")
        return 1
    vplayers_set_header(table, header, shown[1])
    vplayers_set_footer(table, footer, last[1])
    if shown[1] > 0:
        print("Tab list header: ")
        pl_note_bytes(header, 0, shown[1])
        print("")
    else:
        print("Tab list header cleared")
    if last[1] > 0:
        print("Tab list footer: ")
        pl_note_bytes(footer, 0, last[1])
        print("")
    else:
        print("Tab list footer cleared")
    return 0


public def pl_handle_update_attributes(socket_handle: int64, body: int64[],
                                        offset: int64,
                                        table: VAttributes*) -> int:
    int64[] entity_id = decode_varint(body, offset)
    if entity_id[0] != 1 or entity_id[1] < 0:
        print("Malformed attribute entity id")
        return 1
    int read = vat_parse(table, body, offset)
    if read < 0:
        print(f"Attribute packet for entity {entity_id[1]} is not in the layout this client parses")
        return 1
    print(f"Attributes for entity {entity_id[1]}: {read} properties")
    return 0


# Change Difficulty carries the level and whether the server has locked it,
# and the lock is what decides whether the player's own difficulty setting is
# honoured, so both halves are kept.
public def pl_handle_change_difficulty(socket_handle: int64, body: int64[],
                                       offset: int64,
                                       state: VPlayState*) -> int:
    int64[] level = decode_varint(body, offset)
    if level[0] != 1 or level[1] < 0 or level[1] > 3:
        print("Malformed difficulty")
        return 1
    if level[2] >= len(body):
        print("Difficulty packet has no lock flag")
        return 1
    if level[2] + 1 != len(body):
        print(f"Difficulty packet has {len(body) - level[2] - 1} bytes left over")
        return 1
    bool locked = ((int)body[level[2]] & 0xFF) != 0
    state.difficulty = (int)level[1]
    state.difficulty_locked = locked
    if locked:
        print(f"Difficulty {state.difficulty} changed and locked")
    else:
        print(f"Difficulty {state.difficulty} changed")
    return 0


public def pl_handle_transfer(socket_handle: int64, body: int64[],
                               offset: int64) -> int:
    int64[] host_len = decode_varint(body, offset)
    if host_len[0] != 1:
        return 1
    print("Server requested a transfer (ignored)")
    return 0


# Set Camera names the camera entity the renderer should follow. There is no
# payload beyond the id, so the check is that the packet stops exactly there.
public def pl_handle_set_camera(socket_handle: int64, body: int64[],
                                 offset: int64, state: VPlayState*) -> int:
    int64[] camera_id = decode_varint(body, offset)
    if camera_id[0] != 1 or camera_id[1] < 0:
        print("Malformed camera id")
        return 1
    if camera_id[2] != len(body):
        print(f"Camera packet has {len(body) - camera_id[2]} bytes left over")
        return 1
    state.camera_id = (int)camera_id[1]
    print(f"Camera set to {state.camera_id}")
    return 0


# Set Ticking State is the gamespeed control: the rate the server is running
# at and whether the level is frozen. The client cannot tick the world, but a
# renderer that animates water or fire on its own clock has to respect both.
public def pl_handle_set_ticking_state(socket_handle: int64, body: int64[],
                                       offset: int64,
                                       state: VPlayState*) -> int:
    if offset + 5 > len(body):
        print("Truncated ticking state packet")
        return 1
    double rate = decode_be_float(body, offset)
    bool frozen = ((int)body[offset + 4] & 0xFF) != 0
    if offset + 5 != len(body):
        print(f"Ticking state packet has {len(body) - offset - 5} bytes left over")
        return 1
    state.tick_rate = rate
    state.tick_frozen = frozen
    if frozen:
        print(f"Ticking state: frozen at rate {rate}")
    else:
        print(f"Ticking state: rate {rate}")
    return 0


# --- Item stacks, containers, and chat ---

# One network item stack. `out` receives {present, item id, count} and the
# return value is the offset after the stack, or -1 when the packet is
# malformed. The envelope and all 110 component payloads are walked by
# src/proto/slot.cpy, which is the only place that knows their lengths.
public def pl_read_item_stack(body: int64[], offset: int64,
                              out: int64[]) -> int64:
    return sl_read(body, offset, out)



# --- Particles ---

# The emitter description in front of the particle id is fixed width: two
# flags, a double position, three float spreads, a float velocity and an
# integer block count.
def pl_particle_prefix_length() -> int64:
    return 46


# The payload words are stored by value, not by wire width: an integer keeps
# its own value and a float is widened to the double it denotes, so a renderer
# reading word N does not have to know whether the protocol sent it as f32 or
# f64. `count` is the running record length, written through the array.
def pl_particle_u32(body: int64[], cursor: int64, payload: int64[],
                    count: int64[]) -> int64:
    if cursor + 4 > len(body):
        return i64_failed()
    payload[(int)count[0]] = decode_be_int32(body, cursor)
    count[0] = count[0] + 1
    return cursor + 4


def pl_particle_f32(body: int64[], cursor: int64, payload: int64[],
                    count: int64[]) -> int64:
    if cursor + 4 > len(body):
        return i64_failed()
    payload[(int)count[0]] = (int64)vt_double_to_bits(
        decode_be_float(body, cursor))
    count[0] = count[0] + 1
    return cursor + 4


def pl_particle_f64(body: int64[], cursor: int64, payload: int64[],
                    count: int64[]) -> int64:
    if cursor + 8 > len(body):
        return i64_failed()
    payload[(int)count[0]] = (int64)vt_double_to_bits(
        decode_be_int64(body, cursor))
    count[0] = count[0] + 1
    return cursor + 8


def pl_particle_varint(body: int64[], cursor: int64, payload: int64[],
                      count: int64[]) -> int64:
    int64[] value = decode_varint(body, cursor)
    if value[0] != 1:
        return i64_failed()
    payload[(int)count[0]] = value[1]
    count[0] = count[0] + 1
    return value[2]


# The particle id selects the record that follows it. The 26.3 registry has
# twelve shapes that carry anything at all; every other id is a bare emitter,
# which is why the fall-through is the common case rather than an error.
def pl_particle_payload(body: int64[], cursor: int64, kind: int64,
                        payload: int64[], count: int64[]) -> int64:
    if vparts_kind_is_blockstate((int)kind) == 1:
        return pl_particle_varint(body, cursor, payload, count)
    if kind == vparts_kind_dust():
        cursor = pl_particle_u32(body, cursor, payload, count)
        if cursor < 0:
            return i64_failed()
        return pl_particle_f32(body, cursor, payload, count)
    if kind == vparts_kind_dust_color_transition():
        cursor = pl_particle_u32(body, cursor, payload, count)
        if cursor < 0:
            return i64_failed()
        cursor = pl_particle_u32(body, cursor, payload, count)
        if cursor < 0:
            return i64_failed()
        return pl_particle_f32(body, cursor, payload, count)
    if kind == vparts_kind_entity_effect():
        return pl_particle_u32(body, cursor, payload, count)
    if kind == vparts_kind_tinted_leaves():
        return pl_particle_u32(body, cursor, payload, count)
    if kind == vparts_kind_flash():
        return pl_particle_u32(body, cursor, payload, count)
    if kind == vparts_kind_sculk_charge():
        return pl_particle_f32(body, cursor, payload, count)
    if kind == vparts_kind_dragon_breath():
        return pl_particle_f32(body, cursor, payload, count)
    if kind == vparts_kind_effect():
        cursor = pl_particle_u32(body, cursor, payload, count)
        if cursor < 0:
            return i64_failed()
        return pl_particle_f32(body, cursor, payload, count)
    if kind == vparts_kind_instant_effect():
        cursor = pl_particle_u32(body, cursor, payload, count)
        if cursor < 0:
            return i64_failed()
        return pl_particle_f32(body, cursor, payload, count)
    if kind == vparts_kind_shriek():
        return pl_particle_varint(body, cursor, payload, count)
    if kind == vparts_kind_item():
        int64[] stack = new int64[3]
        cursor = pl_read_item_stack(body, cursor, stack)
        if cursor < 0:
            return i64_failed()
        payload[(int)count[0]] = stack[1]
        count[0] = count[0] + 1
        payload[(int)count[0]] = stack[2]
        count[0] = count[0] + 1
        return cursor
    if kind == vparts_kind_vibration():
        int64[] target = decode_varint(body, cursor)
        if target[0] != 1 or target[1] < 0 or target[1] > (int64)vparts_vibration_entity():
            return i64_failed()
        payload[(int)count[0]] = target[1]
        count[0] = count[0] + 1
        cursor = target[2]
        if target[1] == (int64)vparts_vibration_position():
            if cursor + 8 > len(body):
                return i64_failed()
            payload[(int)count[0]] = decode_be_i64(body, cursor)
            count[0] = count[0] + 1
            cursor = cursor + 8
        else:
            cursor = pl_particle_varint(body, cursor, payload, count)
            if cursor < 0:
                return i64_failed()
            cursor = pl_particle_f32(body, cursor, payload, count)
            if cursor < 0:
                return i64_failed()
        return pl_particle_varint(body, cursor, payload, count)
    if kind == vparts_kind_trail():
        int64 axis = 0
        while axis < 3:
            cursor = pl_particle_f64(body, cursor, payload, count)
            if cursor < 0:
                return i64_failed()
            axis = axis + 1
        cursor = pl_particle_u32(body, cursor, payload, count)
        if cursor < 0:
            return i64_failed()
        return pl_particle_varint(body, cursor, payload, count)
    return cursor


public def pl_handle_level_particles(socket_handle: int64, body: int64[],
                                     offset: int64,
                                     table: VParticles*) -> int:
    int64 prefix = pl_particle_prefix_length()
    if offset + prefix >= len(body):
        print("Truncated particle emitter packet")
        return 1
    int64 cursor = offset + prefix
    bool long_distance = ((int)body[offset] & 0xFF) != 0
    bool always_show = ((int)body[offset + 1] & 0xFF) != 0
    double x = decode_be_int64(body, offset + 2)
    double y = decode_be_int64(body, offset + 10)
    double z = decode_be_int64(body, offset + 18)
    double spread_x = decode_be_float(body, offset + 26)
    double spread_y = decode_be_float(body, offset + 30)
    double spread_z = decode_be_float(body, offset + 34)
    double velocity = decode_be_float(body, offset + 38)
    int64 amount = decode_be_int32(body, offset + 42)
    if amount < 0:
        print("Particle amount is negative")
        return 1
    int64[] particle_id = decode_varint(body, cursor)
    if particle_id[0] != 1 or particle_id[1] < 0 or particle_id[1] > (int64)vparts_kind_max():
        print("Malformed particle id")
        return 1
    int64[] payload = new int64[vparts_payload_stride()]
    int64[] stored = new int64[1]
    int64 payload_end = pl_particle_payload(body, particle_id[2],
                                           particle_id[1], payload, stored)
    if payload_end < 0:
        print(f"Malformed payload for particle kind {particle_id[1]}")
        return 1
    if payload_end != len(body):
        print(f"Particle packet has {len(body) - payload_end} bytes left over")
        return 1
    int flags = 0
    if long_distance:
        flags = flags | vparts_flag_long_distance()
    if always_show:
        flags = flags | vparts_flag_always_show()
    if vparts_push(table, (int)particle_id[1], x, y, z,
                   vparts_quantise(spread_x), vparts_quantise(spread_y),
                   vparts_quantise(spread_z), vparts_quantise(velocity),
                   (int)amount, flags, payload, (int)stored[0]) < 0:
        print("Particle payload does not fit the queue")
        return 1
    print(f"Particles: kind {particle_id[1]} amount {amount} at ({x}, {y}, {z})")
    return 0


# --- Entity registry integration ---

# Since 1.20.2 one metadata entry header carries both halves of the address:
# the low seven bits name the field and the bits above it select a serializer
# from the entity-data registry, which is why the terminator is a plain 255
# rather than a field id.
def pl_metadata_terminator() -> int:
    return 255


# The shared entity flags byte (field 0) is the one field every entity has; the
# rest are entity-specific, so only these bits become registry flags.
def pl_apply_entity_flag_byte(table: VEntities*, id: int, value: int64) -> void:
    ventities_set_flag(table, id, vent_flag_on_fire(), (value & 1) != 0)
    ventities_set_flag(table, id, vent_flag_sneaking(), (value & 2) != 0)
    ventities_set_flag(table, id, vent_flag_glowing(), (value & 8) != 0)
    ventities_set_flag(table, id, vent_flag_invisible(), (value & 32) != 0)


# The registry has forty-four entries in 26.3, so these names are what the
# printed diagnostics mean; the wire shapes live in pl_meta_payload.
public def pl_metadata_serializer_count() -> int:
    return 44


public def pl_metadata_serializer_name(serializer: int) -> str:
    if serializer == 0:
        return "byte"
    if serializer == 1:
        return "varint"
    if serializer == 2:
        return "varlong"
    if serializer == 3:
        return "float"
    if serializer == 4:
        return "string"
    if serializer == 5:
        return "component"
    if serializer == 6:
        return "optional component"
    if serializer == 7:
        return "item stack"
    if serializer == 8:
        return "boolean"
    if serializer == 9:
        return "rotations"
    if serializer == 10:
        return "block position"
    if serializer == 11:
        return "optional block position"
    if serializer == 12:
        return "direction"
    if serializer == 13:
        return "optional living entity reference"
    if serializer == 14:
        return "block state"
    if serializer == 15:
        return "optional block state"
    if serializer == 16:
        return "particle"
    if serializer == 17:
        return "particles"
    if serializer == 18:
        return "villager data"
    if serializer == 19:
        return "optional unsigned int"
    if serializer == 20:
        return "pose"
    if serializer == 21:
        return "cat variant"
    if serializer == 22:
        return "cat sound variant"
    if serializer == 23:
        return "chicken variant"
    if serializer == 24:
        return "chicken sound variant"
    if serializer == 25:
        return "cow variant"
    if serializer == 26:
        return "cow sound variant"
    if serializer == 27:
        return "wolf variant"
    if serializer == 28:
        return "wolf sound variant"
    if serializer == 29:
        return "frog variant"
    if serializer == 30:
        return "pig variant"
    if serializer == 31:
        return "pig sound variant"
    if serializer == 32:
        return "zombie nautilus variant"
    if serializer == 33:
        return "optional global position"
    if serializer == 34:
        return "painting variant"
    if serializer == 35:
        return "sniffer state"
    if serializer == 36:
        return "armadillo state"
    if serializer == 37:
        return "copper golem state"
    if serializer == 38:
        return "weathering copper state"
    if serializer == 39:
        return "vector3"
    if serializer == 40:
        return "quaternion"
    if serializer == 41:
        return "resolvable profile"
    if serializer == 42:
        return "humanoid arm"
    if serializer == 43:
        return "dye color"
    return "unknown"


# Everything the registry calls a Holder or an enum is sent as its registry id,
# which is a varint, so one branch covers the ordinal, direction, pose, variant
# and state families alike.
def pl_meta_is_varint(serializer: int) -> int:
    if serializer == 1:
        return 1
    if serializer == 12:
        return 1
    if serializer == 14:
        return 1
    if serializer == 15:
        return 1
    if serializer == 19:
        return 1
    if serializer == 20:
        return 1
    if serializer == 42:
        return 1
    if serializer == 43:
        return 1
    if serializer >= 21:
        if serializer <= 32:
            return 1
    if serializer >= 34:
        if serializer <= 38:
            return 1
    return 0


def pl_meta_varint(body: int64[], cursor: int64, table: VEntities*, id: int,
                   field: int) -> int64:
    int64[] value = decode_varint(body, cursor)
    if value[0] != 1:
        return i64_failed()
    ventities_set_value(table, id, field, value[1])
    return value[2]


def pl_meta_fixed(body: int64[], cursor: int64, size: int64) -> int64:
    if cursor + size > len(body):
        return i64_failed()
    return cursor + size


# Boolean-prefixed records: the flag is consumed here and the caller decides
# whether the absent case needs anything else.
def pl_meta_present(body: int64[], cursor: int64) -> int64[]:
    int64[] out = new int64[2]
    if cursor + 1 > len(body):
        out[0] = i64_failed()
        return out
    out[0] = body[cursor] & 1
    out[1] = cursor + 1
    return out


# A particle is an id plus whatever that id's shape carries, so the length is
# only knowable through the same table the emitter packet uses. The values are
# discarded because metadata only needs the stream to stay aligned.
def pl_meta_particle(body: int64[], cursor: int64) -> int64:
    int64[] kind = decode_varint(body, cursor)
    if kind[0] != 1:
        return i64_failed()
    if kind[1] < 0 or kind[1] > (int64)vparts_kind_max():
        return i64_failed()
    int64[] scratch = new int64[vparts_payload_stride()]
    int64[] stored = new int64[1]
    return pl_particle_payload(body, kind[2], kind[1], scratch, stored)


def pl_meta_particles(body: int64[], cursor: int64) -> int64:
    int64[] count = decode_varint(body, cursor)
    if count[0] != 1:
        return i64_failed()
    if count[1] < 0 or count[1] > (int64)vparts_payload_stride() * 256:
        return i64_failed()
    int64 index = 0
    while index < count[1]:
        cursor = pl_meta_particle(body, count[2])
        if cursor < 0:
            return i64_failed()
        count[2] = cursor
        index = index + 1
    return cursor


# Reads one value and returns the cursor after it, or a negative cursor when
# the shape is not modelled. RESOLVABLE_PROFILE (41) is the one entry left out:
# it is an either-discriminated profile whose property list and skin-patch
# records are not decoded anywhere else, so guessing its length would shift
# every field that follows.
def pl_meta_payload(body: int64[], cursor: int64, table: VEntities*, id: int,
                    field: int, serializer: int) -> int64:
    if serializer == 0:
        if cursor + 1 > len(body):
            return i64_failed()
        int64 raw = body[cursor]
        ventities_set_value(table, id, field, raw - 256 if raw >= 128 else raw)
        if field == 0:
            pl_apply_entity_flag_byte(table, id, body[cursor])
        return cursor + 1
    if pl_meta_is_varint(serializer) == 1:
        return pl_meta_varint(body, cursor, table, id, field)
    if serializer == 2:
        int64[] value = decode_varlong(body, cursor)
        if value[0] != 1:
            return i64_failed()
        ventities_set_value(table, id, field, value[1])
        return value[2]
    if serializer == 3:
        if cursor + 4 > len(body):
            return i64_failed()
        ventities_set_value(table, id, field,
                            (int64)(int)(decode_be_float(body, cursor) * 1000000.0))
        return cursor + 4
    if serializer == 4:
        int64[] text = read_string_field(body, cursor, 262144)
        if text[0] != 1:
            return i64_failed()
        return text[2] + text[1]
    if serializer == 5:
        return pl_component_end(body, cursor)
    if serializer == 6:
        int64[] flag = pl_meta_present(body, cursor)
        if flag[0] < 0:
            return i64_failed()
        if flag[0] == 0:
            return flag[1]
        int64 after = pl_component_end(body, flag[1])
        if after < 0:
            return i64_failed()
        int64[] name = new int64[33]
        int name_length = pl_component_text(body, flag[1], name)
        if name_length > 0:
            ventities_set_name(table, id, name, name_length)
        return after
    if serializer == 7:
        int64[] stack = new int64[3]
        return pl_read_item_stack(body, cursor, stack)
    if serializer == 8:
        if cursor + 1 > len(body):
            return i64_failed()
        ventities_set_value(table, id, field, body[cursor] & 1)
        return cursor + 1
    if serializer == 9:
        return pl_meta_fixed(body, cursor, 12)
    if serializer == 10:
        return pl_meta_fixed(body, cursor, 8)
    if serializer == 11:
        int64[] flag = pl_meta_present(body, cursor)
        if flag[0] < 0:
            return i64_failed()
        if flag[0] == 0:
            return flag[1]
        return pl_meta_fixed(body, flag[1], 8)
    if serializer == 13:
        int64[] flag = pl_meta_present(body, cursor)
        if flag[0] < 0:
            return i64_failed()
        if flag[0] == 0:
            return flag[1]
        return pl_meta_fixed(body, flag[1], 16)
    if serializer == 16:
        return pl_meta_particle(body, cursor)
    if serializer == 17:
        return pl_meta_particles(body, cursor)
    if serializer == 18:
        int64 index = 0
        while index < 3:
            cursor = pl_meta_varint(body, cursor, table, id, field)
            if cursor < 0:
                return i64_failed()
            index = index + 1
        return cursor
    if serializer == 33:
        int64[] flag = pl_meta_present(body, cursor)
        if flag[0] < 0:
            return i64_failed()
        if flag[0] == 0:
            return flag[1]
        int64[] dimension = decode_varint(body, flag[1])
        if dimension[0] != 1:
            return i64_failed()
        return pl_meta_fixed(body, dimension[2], 8)
    if serializer == 39:
        return pl_meta_fixed(body, cursor, 12)
    if serializer == 40:
        return pl_meta_fixed(body, cursor, 16)
    return i64_failed()


# Walks a metadata stream and merges it into the registry. An unmodelled
# serializer is a hard stop rather than a guess: inventing a size would
# desynchronise every later field of every later entity on the connection,
# and the printed name is what identifies the registry entry to add.
public def pl_decode_entity_metadata(table: VEntities*, id: int, body: int64[],
                                     offset: int64) -> int:
    int64 cursor = offset
    while cursor < len(body):
        int64[] header = decode_varint(body, cursor)
        if header[0] != 1:
            print("Malformed entity metadata header")
            return 1
        cursor = header[2]
        if header[1] == pl_metadata_terminator():
            return 0
        int field = (int)(header[1] & 127)
        int serializer = (int)(header[1] >> 7)
        if serializer < 0 or serializer >= pl_metadata_serializer_count():
            print(f"Entity metadata field {field} uses serializer ordinal {serializer} outside the 26.3 registry")
            return 1
        int64 next = pl_meta_payload(body, cursor, table, id, field, serializer)
        if next < 0:
            print(f"Entity metadata field {field} has an unreadable {pl_metadata_serializer_name(serializer)} value")
            return 1
        cursor = next
    print(f"Entity {id} metadata stream has no terminator")
    return 1


public def pl_handle_spawn_entity(body: int64[], offset: int64,
                                  table: VEntities*) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1:
        return 1
    if id[2] + 16 > len(body):
        return 1
    int64[] type_id = decode_varint(body, id[2] + 16)
    if type_id[0] != 1:
        return 1
    # three doubles, then pitch, yaw and head yaw as angle bytes, then motion
    # as three signed shorts, then an optional payload whose shape is bound to
    # the entity type.
    if type_id[2] + 27 > len(body):
        return 1
    double x = decode_be_int64(body, type_id[2])
    double y = decode_be_int64(body, type_id[2] + 8)
    double z = decode_be_int64(body, type_id[2] + 16)
    int pitch = (int)body[type_id[2] + 24]
    int yaw = (int)body[type_id[2] + 25]
    int head_yaw = (int)body[type_id[2] + 26]
    int entity_id = (int)id[1]
    ventities_set_type(table, entity_id, (int)type_id[1])
    ventities_set_position(table, entity_id, x, y, z)
    ventities_set_angle(table, entity_id, 1, pitch)
    ventities_set_angle(table, entity_id, 0, yaw)
    ventities_set_angle(table, entity_id, 2, head_yaw)
    if type_id[2] + 33 > len(body):
        return 0
    double mx = (double)(int)pl_decode_be_int16(body, type_id[2] + 27) / 8000.0
    double my = (double)(int)pl_decode_be_int16(body, type_id[2] + 29) / 8000.0
    double mz = (double)(int)pl_decode_be_int16(body, type_id[2] + 31) / 8000.0
    ventities_set_motion(table, entity_id, mx, my, mz)
    return 0


public def pl_handle_boss_event(body: int64[], offset: int64,
                                bars: VBossBars*) -> int:
    int64[] action = decode_varint(body, offset)
    if action[0] != 1:
        return 1
    int64 cursor = action[2]
    if cursor + vboss_uuid_stride() > len(body):
        return 1
    int uuid_at = (int)cursor
    if action[1] == vboss_action_remove():
        vboss_remove(bars, body, cursor)
        return 0
    if action[1] == vboss_action_add():
        cursor += vboss_uuid_stride()
        int64 after_title = pl_component_end(body, cursor)
        if after_title < 0:
            return 1
        int64[] title = new int64[33]
        int title_length = pl_component_text(body, cursor, title)
        cursor = after_title
        if cursor + 7 > len(body):
            return 1
        double health = decode_be_float(body, cursor)
        int color = (int)body[cursor + 4]
        int style = (int)body[cursor + 5]
        int flags = (int)body[cursor + 6]
        vboss_set_health(bars, body, uuid_at, health)
        vboss_set_appearance(bars, body, uuid_at, color, style)
        vboss_set_flags(bars, body, uuid_at, flags)
        vboss_set_name(bars, body, uuid_at, title, title_length)
        return 0
    if action[1] == vboss_action_update_style():
        cursor += vboss_uuid_stride()
        if cursor + 2 > len(body):
            return 1
        vboss_set_appearance(bars, body, uuid_at, (int)body[cursor],
                              (int)body[cursor + 1])
        return 0
    if action[1] == vboss_action_update_properties():
        cursor += vboss_uuid_stride()
        if cursor + 4 > len(body):
            return 1
        vboss_set_health(bars, body, uuid_at, decode_be_float(body, cursor))
        return 0
    if action[1] == vboss_action_update_options():
        cursor += vboss_uuid_stride()
        if cursor + 1 > len(body):
            return 1
        vboss_set_flags(bars, body, uuid_at, (int)body[cursor])
        return 0
    print(f"Unknown boss event action {action[1]}")
    return 1


public def pl_handle_remove_entities(body: int64[], offset: int64,
                                     table: VEntities*,
                                     effects: VEffects*,
                                     attributes: VAttributes*) -> int:
    int64[] count = decode_varint(body, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > 100000:
        print("Malformed entity-removal count")
        return 1
    int64 cursor = count[2]
    int64 removed = 0
    while removed < count[1]:
        int64[] id = decode_varint(body, cursor)
        if id[0] != 1:
            return 1
        ventities_drop(table, (int)id[1])
        vfx_remove_entity(effects, (int)id[1])
        vat_remove_entity(attributes, (int)id[1])
        cursor = id[2]
        removed = removed + 1
    return 0


public def pl_handle_entity_metadata(body: int64[], offset: int64,
                                     table: VEntities*) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1:
        return 1
    return pl_decode_entity_metadata(table, (int)id[1], body, id[2])


# --- Scoreboard, objectives, scores and teams ---

# Objective, score and team packets all address their entries by identifier
# string, so the handlers hand the store a body slice plus a length instead of
# copying the name first. A component that is nameless NBT flattens to nothing:
# the store keeps the entry, only its display text stays empty.
public def pl_handle_set_objective(body: int64[], offset: int64,
                                   board: VScoreboard*) -> int:
    int64[] name = read_string_field(body, offset, 64)
    if name[0] != 1 or name[1] < 1:
        print("Malformed objective identifier")
        return 1
    int64[] display = new int64[33]
    int64[] shown = pl_component_flat(body, name[2] + name[1], display)
    if shown[0] != 1:
        print("Malformed objective display name")
        return 1
    if vscore_set_objective(board, body, name[2], name[1],
                            vscore_action_change(), display, 0,
                            shown[1]) == 0:
        print("Objective table is full")
        return 1
    return 0


public def pl_handle_reset_score(body: int64[], offset: int64,
                                 board: VScoreboard*) -> int:
    int64[] holder = read_string_field(body, offset, 64)
    if holder[0] != 1 or holder[1] < 1:
        print("Malformed score holder")
        return 1
    int64[] objective = read_string_field(body, holder[2] + holder[1], 64)
    if objective[0] != 1 or objective[1] < 1:
        print("Malformed score objective")
        return 1
    if vscore_reset_score(board, body, holder[2], holder[1], body,
                          objective[2], objective[1]) == 0:
        print("Score table is full")
        return 1
    return 0


public def pl_handle_set_score(body: int64[], offset: int64,
                               board: VScoreboard*) -> int:
    int64[] holder = read_string_field(body, offset, 64)
    if holder[0] != 1 or holder[1] < 1:
        print("Malformed score holder")
        return 1
    int64[] display = new int64[33]
    int64[] shown = pl_component_flat(body, holder[2] + holder[1], display)
    if shown[0] != 1:
        print("Malformed score display name")
        return 1
    int64[] objective = read_string_field(body, shown[2], 64)
    if objective[0] != 1 or objective[1] < 1:
        print("Malformed score objective")
        return 1
    int64[] value = decode_varint(body, objective[2] + objective[1])
    if value[0] != 1:
        print("Malformed score value")
        return 1
    if vscore_set_score(board, body, holder[2], holder[1], body,
                        objective[2], objective[1], (int)value[1]) == 0:
        print("Score table is full")
        return 1
    return 0


public def pl_handle_set_display_objective(body: int64[], offset: int64,
                                           board: VScoreboard*) -> int:
    int64[] slot = decode_varint(body, offset)
    if slot[0] != 1 or slot[1] < 0:
        print("Malformed display objective slot")
        return 1
    int64[] name = read_string_field(body, slot[2], 64)
    if name[0] != 1:
        print("Malformed display objective name")
        return 1
    if vscore_set_display(board, (int)slot[1], body, name[2], name[1]) == 0:
        print("Display objective slot is unknown")
        return 1
    return 0


# id_at/id_len locate the team in the store; count_at is where the member
# varint actually sits, which is not a fixed distance from the id because the
# create mode spells out the whole team settings first.
def pl_team_members(board: VScoreboard*, body: int64[], id_at: int64,
                    id_len: int64, count_at: int64, mode: int) -> int:
    int64[] count = decode_varint(body, count_at)
    if count[0] != 1 or count[1] < 0:
        print("Malformed team member list")
        return 1
    int slot = vscore_team_index(board, body, id_at, id_len)
    if slot < 0:
        if mode == vscore_team_add_members():
            print("Team member list names an unknown team")
            return 1
        return 0
    int64 cursor = count[2]
    int64 walked = 0
    while walked < count[1]:
        int64[] member = read_string_field(body, cursor, 64)
        if member[0] != 1 or member[1] < 1:
            print("Malformed team member name")
            return 1
        int applied = 0
        if mode == vscore_team_remove_members():
            applied = vscore_team_remove_member(board, slot, body, member[2],
                                                member[1])
        else:
            applied = vscore_team_add_member(board, slot, body, member[2],
                                             member[1])
        if applied == 0:
            print("Team member list is full")
            return 1
        cursor = member[2] + member[1]
        walked = walked + 1
    return 0




# The team packet carries a mode byte, so every branch reads a different tail;
# guessing wrong here desynchronises the rest of the session, which is why an
# unknown mode is a hard stop rather than something to skip past.
public def pl_handle_set_player_team(body: int64[], offset: int64,
                                     board: VScoreboard*) -> int:
    int64[] name = read_string_field(body, offset, 64)
    if name[0] != 1 or name[1] < 1:
        print("Malformed team identifier")
        return 1
    int64 mode_at = name[2] + name[1]
    if mode_at >= len(body):
        print("Truncated team packet")
        return 1
    int mode = (int)body[mode_at] & 0xFF
    if mode == vscore_team_remove():
        if vscore_set_team(board, body, name[2], name[1], mode,
                           name, 0, -1, name, 0, -1, name, 0, -1) == 0:
            print("Team table is full")
            return 1
        return 0
    if mode == vscore_team_add_members() or mode == vscore_team_remove_members():
        return pl_team_members(board, body, name[2], name[1], mode_at + 1, mode)
    if mode != vscore_team_create() and mode != vscore_team_update():
        print(f"Unknown team mode {mode}")
        return 1
    int64[] display = new int64[33]
    int64[] shown = pl_component_flat(body, mode_at + 1, display)
    if shown[0] != 1:
        print("Malformed team display name")
        return 1
    if shown[2] + 3 > len(body):
        print("Truncated team options")
        return 1
    int nametag = (int)body[shown[2]] & 0xFF
    int collision = (int)body[shown[2] + 1] & 0xFF
    int color = (int)body[shown[2] + 2] & 0xFF
    int64[] prefix = new int64[33]
    int64[] prefixed = pl_component_flat(body, shown[2] + 3, prefix)
    if prefixed[0] != 1:
        print("Malformed team prefix")
        return 1
    int64[] suffix = new int64[33]
    int64[] suffixed = pl_component_flat(body, prefixed[2], suffix)
    if suffixed[0] != 1:
        print("Malformed team suffix")
        return 1
    if vscore_set_team(board, body, name[2], name[1], mode, display, 0,
                       shown[1], prefix, 0, prefixed[1], suffix, 0,
                       suffixed[1]) == 0:
        print("Team table is full")
        return 1
    if vscore_set_team_options(board, body, name[2], name[1], nametag,
                               collision, color) == 0:
        print("Team vanished while applying its options")
        return 1
    if mode == vscore_team_create():
        return pl_team_members(board, body, name[2], name[1], suffixed[2], mode)
    return 0


public def pl_handle_commands(body: int64[], offset: int64,
                              tree: VCommandTree*) -> int:
    if vcmd_parse(tree, body, offset) != 0:
        print("Malformed command tree")
        return 1
    print(f"Command tree stored: {vcmd_node_total(tree)} nodes, chain limit {vcmd_chain_limit(tree)}")
    return 0


public def pl_handle_update_mob_effect(body: int64[], offset: int64,
                                       table: VEffects*) -> int:
    int64[] entity = decode_varint(body, offset)
    if entity[0] != 1 or entity[1] < 0:
        print("Malformed effect entity id")
        return 1
    int64[] effect = decode_varint(body, entity[2])
    if effect[0] != 1 or effect[1] < 0:
        print("Malformed effect id")
        return 1
    int64[] amplifier = decode_varint(body, effect[2])
    if amplifier[0] != 1 or amplifier[1] < 0:
        print("Malformed effect amplifier")
        return 1
    int64[] duration = decode_varint(body, amplifier[2])
    if duration[0] != 1:
        print("Malformed effect duration")
        return 1
    if duration[2] >= len(body):
        print("Truncated effect packet")
        return 1
    int flags = (int)body[duration[2]] & 0xFF
    int colour_value = 0
    if (flags & vfx_flag_colour()) != 0:
        int64[] colour = decode_varint(body, duration[2] + 1)
        if colour[0] != 1:
            print("Malformed effect colour")
            return 1
        colour_value = (int)colour[1]
    if vfx_set(table, (int)entity[1], (int)effect[1], (int)amplifier[1],
               (int)duration[1], flags, colour_value) == 0:
        print("Effect table is full")
        return 1
    return 0


public def pl_handle_remove_mob_effect(body: int64[], offset: int64,
                                       table: VEffects*) -> int:
    int64[] entity = decode_varint(body, offset)
    if entity[0] != 1 or entity[1] < 0:
        print("Malformed effect entity id")
        return 1
    int64[] effect = decode_varint(body, entity[2])
    if effect[0] != 1 or effect[1] < 0:
        print("Malformed effect id")
        return 1
    if vfx_remove(table, (int)entity[1], (int)effect[1]) == 0:
        print("Effect table is full")
        return 1
    return 0


# --- World events, title timing, server identity and sounds ---

# A component is printed as the bytes it flattens to, capped so a pathological
# server cannot make the trace unbounded.
def pl_dump_text(body: int64[], start: int64, length: int64) -> void:
    int64 shown = length
    if shown > 64:
        shown = 64
    int64 index = 0
    while index < shown:
        mc_write_byte(body[start + index])
        index = index + 1
    if shown < length:
        print("...")


# World Event: Event Int, Location Position, Data Int, Disable Relative Volume
# Boolean. The location is a packed block position, so the coordinates that are
# printed are the ones the effect is drawn at, not the eight wire bytes.
public def pl_handle_level_event(body: int64[], offset: int64) -> int:
    if offset < 0 or offset + 17 > len(body):
        print("Truncated world event packet")
        return 1
    int event_type = (int)decode_be_int32(body, offset)
    int64 packed = decode_be_i64(body, offset + 4)
    int event_data = (int)decode_be_int32(body, offset + 12)
    int absolute = 1 - ((int)body[offset + 16] & 0xFF)
    int* position = vt_calloc_int(3)
    vt_unpack_block_pos(packed, position)
    int x = vt_iget(position, 0)
    int y = vt_iget(position, 1)
    int z = vt_iget(position, 2)
    vt_free((void*)position)
    print(f"World event {event_type} at ({x}, {y}, {z}) data {event_data} volume mode {absolute}")
    return 0


# Set Title Animation Times carries three 4 byte integers, not varints; the
# HUD needs all three because a title with a zero stay time is a flash, not a
# title.
public def pl_handle_titles_animation(body: int64[], offset: int64) -> int:
    if offset < 0 or offset + 12 > len(body):
        print("Truncated title animation packet")
        return 1
    int fade_in = (int)decode_be_int32(body, offset)
    int stay = (int)decode_be_int32(body, offset + 4)
    int fade_out = (int)decode_be_int32(body, offset + 8)
    print(f"Title animation {fade_in} in, {stay} hold, {fade_out} out")
    return 0


# Add Transient Block is the 26.x packet for a block that renders without
# touching the world: a client-side preview or a breaking stage. Nothing is
# stored because the server never re-sends it, so a truncated read here would
# silently drop a visual the client cannot ask for again.
public def pl_handle_add_transient_block(body: int64[], offset: int64) -> int:
    if offset < 0 or offset + 9 > len(body):
        print("Truncated transient block packet")
        return 1
    int64 packed = decode_be_i64(body, offset)
    int64[] state = decode_varint(body, offset + 8)
    if state[0] != 1 or state[1] < 0 or state[1] > 2147483647:
        print("Malformed transient block state")
        return 1
    int* position = vt_calloc_int(3)
    vt_unpack_block_pos(packed, position)
    int x = vt_iget(position, 0)
    int y = vt_iget(position, 1)
    int z = vt_iget(position, 2)
    vt_free((void*)position)
    print(f"Transient block state {state[1]} at ({x}, {y}, {z})")
    return 0


# Server Data: MOTD component, then a prefixed optional icon. The icon is an
# uncompressed PNG the client would upload to the server list; this backend
# only reports its size because there is no image decoder in Cpyte.
public def pl_handle_server_data(body: int64[], offset: int64,
                                 motd: int64[]) -> int:
    int64[] text = pl_component_flat(body, offset, motd)
    if text[0] != 1:
        print("Malformed server MOTD")
        return 1
    print("Server MOTD:")
    pl_dump_text(motd, 0, text[1])
    int64 cursor = text[2]
    if cursor >= len(body):
        print("Truncated server data packet")
        return 1
    int has_icon = (int)body[cursor] & 0xFF
    cursor = cursor + 1
    if has_icon == 0:
        print("Server has no list icon")
        return 0
    int64[] size = decode_varint(body, cursor)
    if size[0] != 1 or size[1] < 0 or size[1] > 8388608:
        print("Malformed server icon size")
        return 1
    cursor = size[2]
    if cursor + size[1] > len(body):
        print("Truncated server icon")
        return 1
    print(f"Server icon {size[1]} bytes")
    return 0


# Disguised Chat Message: the message component, the chat type, the sender name
# component and an optional target name. A chat type of 0 is an inline
# definition rather than a registry id; its body is variable and this client
# does not render the difference, so the packet is accepted with the text it
# carries instead of guessing where the inline definition ends.
public def pl_handle_disguised_chat(body: int64[], offset: int64,
                                    message: int64[], sender: int64[],
                                    target: int64[]) -> int:
    int64[] text = pl_component_flat(body, offset, message)
    if text[0] != 1:
        print("Malformed disguised chat message")
        return 1
    int64[] chat_type = decode_varint(body, text[2])
    if chat_type[0] != 1 or chat_type[1] < 0:
        print("Malformed disguised chat type")
        return 1
    int64[] name = pl_component_flat(body, chat_type[2], sender)
    if name[0] != 1:
        print("Malformed disguised chat sender")
        return 1
    print("Disguised chat:")
    pl_dump_text(sender, 0, name[1])
    pl_dump_text(message, 0, text[1])
    print("")
    if chat_type[1] == 0:
        print("Disguised chat uses an inline chat type")
        return 0
    if name[2] >= len(body):
        return 0
    int has_target = (int)body[name[2]] & 0xFF
    if has_target == 0:
        return 0
    int64[] shown = pl_component_flat(body, name[2] + 1, target)
    if shown[0] != 1:
        print("Malformed disguised chat target")
        return 1
    print("To:")
    pl_dump_text(target, 0, shown[1])
    return 0


# Player Remove carries a prefixed array of uuids; the ids themselves are
# printed because a removal for an unknown player is the one case the tab list
# has to tolerate.
public def pl_handle_player_info_remove(body: int64[], offset: int64,
                                        table: VPlayers*) -> int:
    int64[] count = decode_varint(body, offset)
    if count[0] != 1 or count[1] < 0 or count[1] > 1024:
        print("Malformed player removal count")
        return 1
    int64 cursor = count[2]
    if cursor + count[1] * 16 > len(body):
        print("Truncated player removal list")
        return 1
    int64 index = 0
    int removed = 0
    while index < count[1]:
        int first = (int)body[cursor + index * 16] & 0xFF
        if vplayers_remove(table, body, cursor + index * 16) == 0:
            print(f"Player leave was for someone not in the list, uuid starts {first}")
        else:
            removed = removed + 1
        index = index + 1
    if removed > 0:
        print(f"Removed {removed} players from the list")
    if count[2] + count[1] * 16 != len(body):
        print(f"Player removal has {len(body) - count[2] - count[1] * 16} bytes left over")
    return 0


# Sound Effect carries a fixed-point position, three 4 byte integers in eighths
# of a block; Entity Sound Effect names an entity instead. Both end with
# volume, pitch and a seed that keeps repeating sounds from phasing.
public def pl_read_sound_tail(body: int64[], cursor: int64,
                              needed: int64) -> int64:
    if cursor + needed > len(body):
        return (int64)-1
    return cursor


public def pl_handle_sound(socket_handle: int64, body: int64[],
                            offset: int64, entity_mode: bool) -> int:
    int64[] id = decode_varint(body, offset)
    if id[0] != 1:
        print("Malformed sound event id")
        return 1
    int64[] category = decode_varint(body, id[2])
    if category[0] != 1:
        print("Malformed sound category")
        return 1
    int64 cursor = pl_read_sound_tail(body, category[2], 4)
    if cursor < 0:
        print("Truncated sound packet")
        return 1
    if entity_mode:
        int64[] entity = decode_varint(body, cursor)
        if entity[0] != 1 or entity[1] < 0:
            print("Malformed sound entity id")
            return 1
        cursor = pl_read_sound_tail(body, entity[2], 16)
        if cursor < 0:
            print("Truncated sound entity packet")
            return 1
        double entity_volume = decode_be_float(body, cursor)
        double entity_pitch = decode_be_float(body, cursor + 4)
        int64 entity_seed = decode_be_i64(body, cursor + 8)
        print(f"Sound {id[1]} category {category[1]} on entity {entity[1]} volume {entity_volume} pitch {entity_pitch} seed {entity_seed}")
        return 0
    cursor = pl_read_sound_tail(body, cursor, 28)
    if cursor < 0:
        print("Truncated sound packet")
        return 1
    double x = decode_be_int32(body, cursor) / 8.0
    double y = decode_be_int32(body, cursor + 4) / 8.0
    double z = decode_be_int32(body, cursor + 8) / 8.0
    double volume = decode_be_float(body, cursor + 12)
    double pitch = decode_be_float(body, cursor + 16)
    int64 seed = decode_be_i64(body, cursor + 20)
    print(f"Sound {id[1]} category {category[1]} at ({x}, {y}, {z}) volume {volume} pitch {pitch} seed {seed}")
    return 0


# Block Entity Data: packed position, action, then a network NBT compound - or
# the End tag alone, which is how a server removes a block entity. The payload
# is walked, not decoded: the fields that matter to rendering differ per block
# entity and a wrong guess would desynchronise the rest of the stream.
# Block Entity Data: a packed position, a varint action and an optional
# anonymous NBT compound. The action is the only part this backend keeps — the
# payload's fields differ per block type and nothing renders them yet — but the
# presence of a tile at a position changes how that cell must be drawn, so the
# registry records it and a removal drops the row.
public def pl_handle_block_entity_data(socket_handle: int64, body: int64[],
                                       offset: int64,
                                       table: VBlockEntities*) -> int:
    if offset < 0 or offset + 9 > len(body):
        print("Truncated block entity packet")
        return 1
    int64 packed = decode_be_i64(body, offset)
    int64[] action = decode_varint(body, offset + 8)
    if action[0] != 1 or action[1] < -1 or action[1] > vbes_max_action():
        print("Malformed block entity action")
        return 1
    int* position = vt_calloc_int(3)
    vt_unpack_block_pos(packed, position)
    int x = vt_iget(position, 0)
    int y = vt_iget(position, 1)
    int z = vt_iget(position, 2)
    vt_free((void*)position)
    if action[1] == -1:
        if vbes_remove(table, x, y, z) == 0:
            print(f"Block entity at ({x}, {y}, {z}) removed")
        else:
            print(f"Block entity at ({x}, {y}, {z}) gone")
        return 0
    if action[2] >= len(body):
        print("Truncated block entity payload")
        return 1
    int has_payload = (int)body[action[2]] & 0xFF
    int64 payload_end = action[2] + 1
    if has_payload != 0:
        if (int)body[payload_end] != 10:
            print("Block entity payload is not a compound")
            return 1
        int64[] payload = skip_nbt_payload(body, 10, payload_end + 1, 0)
        if payload[0] != 1 or payload[2] <= payload_end:
            print("Malformed block entity payload")
            return 1
        payload_end = payload[2]
    if payload_end != len(body):
        print(f"Block entity packet has {len(body) - payload_end} bytes left over")
        return 1
    if vbes_set(table, x, y, z, (int)action[1],
                (int)(payload_end - action[2])) == 0:
        print("Block entity table is full")
        return 1
    print(f"Block entity action {action[1]} at ({x}, {y}, {z}) payload {payload_end - action[2]} bytes")
    return 0


public def pl_handle_container_set_slot(body: int64[], offset: int64,
                                        inventory: VInventory*) -> int:
    int64[] window = decode_varint(body, offset)
    if window[0] != 1 or window[1] < 0:
        return 1
    int64[] state_id = decode_varint(body, window[2])
    if state_id[0] != 1:
        return 1
    int64 slot = pl_decode_be_int16(body, state_id[2])
    if slot < 0:
        return 1
    int64[] stack = new int64[3]
    int64 after = sl_read(body, state_id[2] + 2, stack)
    if after < 0 or after != len(body):
        return 1
    int window_id = (int) window[1]
    if vinv_is_open(inventory, window_id) == 0:
        return 0
    vinv_set_state_id(inventory, window_id, (int) state_id[1])
    if vinv_set_slot(inventory, window_id, (int) slot, (int) stack[1],
                     (int) stack[2]) != 0:
        return 1
    if stack[0] == 1:
        print(f"Window {window_id} slot {slot}: item {stack[1]} x{stack[2]}")
    else:
        print(f"Window {window_id} slot {slot} cleared")
    return 0


public def pl_handle_container_set_content(body: int64[], offset: int64,
                                           inventory: VInventory*) -> int:
    int64[] window = decode_varint(body, offset)
    if window[0] != 1 or window[1] < 0:
        return 1
    int64[] state_id = decode_varint(body, window[2])
    if state_id[0] != 1:
        return 1
    int64[] count = decode_varint(body, state_id[2])
    if count[0] != 1 or (count[1] < 0 or count[1] > vinv_slot_max()):
        return 1
    int64[] items = new int64[count[1]]
    int64[] amounts = new int64[count[1]]
    int64 cursor = count[2]
    int64 filled = 0
    int64 slot_index = 0
    while slot_index < count[1]:
        int64[] stack = new int64[3]
        cursor = sl_read(body, cursor, stack)
        if cursor < 0:
            return 1
        items[slot_index] = stack[1]
        amounts[slot_index] = stack[2]
        if stack[0] == 1:
            filled = filled + 1
        slot_index = slot_index + 1
    int64[] carried = new int64[3]
    cursor = sl_read(body, cursor, carried)
    if cursor < 0 or cursor != len(body):
        return 1
    int window_id = (int) window[1]
    if vinv_set_content(inventory, window_id, (int) state_id[1],
                        (int) count[1]) != 0:
        return 1
    slot_index = 0
    while slot_index < count[1]:
        vinv_set_slot(inventory, window_id, (int) slot_index,
                      (int) items[slot_index], (int) amounts[slot_index])
        slot_index = slot_index + 1
    vinv_set_carried(inventory, (int) carried[1], (int) carried[2])
    print(f"Window {window_id} content: {count[1]} slots, {filled} filled")
    return 0


# 26.x sends one slot per packet rather than the whole inventory, and the slot
# id indexes the player's own container: 0 to 8 are the hotbar.
public def pl_handle_set_player_inventory(body: int64[], offset: int64,
                                          inventory: VInventory*) -> int:
    int64[] slot = decode_varint(body, offset)
    if slot[0] != 1 or (slot[1] < 0 or slot[1] >= vinv_player_slots()):
        return 1
    int64[] stack = new int64[3]
    int64 after = sl_read(body, slot[2], stack)
    if after < 0 or after != len(body):
        return 1
    if vinv_set_slot(inventory, vinv_player_window(), (int) slot[1],
                     (int) stack[1], (int) stack[2]) != 0:
        return 1
    if stack[0] == 1:
        print(f"Inventory slot {slot[1]}: item {stack[1]} x{stack[2]}")
    else:
        print(f"Inventory slot {slot[1]} cleared")
    return 0


public def pl_handle_set_cursor_item(body: int64[], offset: int64,
                                     inventory: VInventory*) -> int:
    int64[] stack = new int64[3]
    int64 after = sl_read(body, offset, stack)
    if after < 0 or after != len(body):
        return 1
    if vinv_set_carried(inventory, (int) stack[1], (int) stack[2]) != 0:
        return 1
    if stack[0] == 1:
        print(f"Carried item {stack[1]} x{stack[2]}")
    else:
        print("Carried item cleared")
    return 0


# The equipment array is terminated by the top bit of each slot byte, so the
# count is never sent: bit 7 set means another entry follows this one.
public def pl_handle_set_equipment(body: int64[], offset: int64,
                                   inventory: VInventory*) -> int:
    int64[] entity = decode_varint(body, offset)
    if entity[0] != 1 or entity[1] < 0:
        return 1
    int64 cursor = entity[2]
    int entries = 0
    while true:
        if cursor >= len(body):
            return 1
        int raw = (int) body[cursor]
        cursor = cursor + 1
        int slot = raw & 0x7F
        if slot >= vinv_equip_slots():
            return 1
        int64[] stack = new int64[3]
        cursor = sl_read(body, cursor, stack)
        if cursor < 0:
            return 1
        if vinv_set_equipment(inventory, (int) entity[1], slot,
                              (int) stack[1], (int) stack[2]) != 0:
            return 1
        entries = entries + 1
        if entries > vinv_equip_slots():
            return 1
        if stack[0] == 1:
            print(f"Entity {entity[1]} equipment {slot}: item {stack[1]} x{stack[2]}")
        else:
            print(f"Entity {entity[1]} equipment {slot} cleared")
        if (raw & 0x80) == 0:
            break
    if cursor != len(body):
        return 1
    return 0


public def pl_handle_container_close(body: int64[], offset: int64,
                                     inventory: VInventory*) -> int:
    int64[] window = decode_varint(body, offset)
    if window[0] != 1 or window[1] < 0 or window[2] != len(body):
        return 1
    vinv_close(inventory, (int) window[1])
    print(f"Container {window[1]} closed by the server")
    return 0


public def pl_handle_container_set_data(body: int64[], offset: int64,
                                        inventory: VInventory*) -> int:
    int64[] window = decode_varint(body, offset)
    if window[0] != 1 or window[1] < 0:
        return 1
    int64 property = pl_decode_be_int16(body, window[2])
    if property < 0:
        return 1
    int64 value = pl_decode_be_int16(body, window[2] + 2)
    if value < 0 or window[2] + 4 != len(body):
        return 1
    if vinv_set_property(inventory, (int) window[1], (int) property,
                         (int) value) != 0:
        return 0
    print(f"Window {window[1]} property {property} = {value}")
    return 0


public def pl_handle_open_screen(body: int64[], offset: int64,
                                 inventory: VInventory*) -> int:
    int64[] window = decode_varint(body, offset)
    if window[0] != 1 or window[1] < 0:
        return 1
    int64[] container_type = decode_varint(body, window[2])
    if container_type[0] != 1 or container_type[1] < 0:
        return 1
    int64 after = pl_component_end(body, container_type[2])
    if after < 0 or after != len(body):
        return 1
    int title_tag = (int) body[container_type[2]]
    # The slot count is not on the wire here; container_set_content carries the
    # authoritative one, so the window opens at full capacity and is resized.
    if vinv_open(inventory, (int) window[1], (int) container_type[1],
                 vinv_slot_max()) != 0:
        print("Too many open containers")
        return 1
    print(f"Server opened container type {container_type[1]}")
    print("Title: ")
    print_nbt_text(body, title_tag, container_type[2] + 1)
    print("")
    return 0


# --- Shared field readers for the remaining Play handlers ---
#
# Each returns the offset after the field, or -1 when the packet does not hold
# it. `scratch` carries one scalar back; `span` carries {start, length} so a
# string can be handed to a state table without a second copy.

def pl_vi(body: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64[] field = decode_varint(body, cursor)
    if field[0] != 1:
        return (int64)-1
    scratch[0] = field[1]
    return field[2]


def pl_vl(body: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64[] field = decode_varlong(body, cursor)
    if field[0] != 1:
        return (int64)-1
    scratch[0] = field[1]
    return field[2]


def pl_u8(body: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64 at = pl_take(body, cursor, 1)
    if at < 0:
        return (int64)-1
    scratch[0] = body[cursor] & 0xFF
    return at


def pl_text(body: int64[], cursor: int64, maximum: int64,
            span: int64[]) -> int64:
    int64[] field = read_string_field(body, cursor, maximum)
    if field[0] != 1:
        return (int64)-1
    span[0] = field[2]
    span[1] = field[1]
    return field[2] + field[1]


def pl_name(body: int64[], cursor: int64, span: int64[]) -> int64:
    return pl_text(body, cursor, 32767, span)


# An absent optional varint reads as -1, which no registry id or entity id can
# be, so the caller can tell "not present" from id 0.
def pl_opt_vi(body: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64 at = pl_u8(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    if scratch[0] == (int64)0:
        scratch[0] = (int64)-1
        return at
    return pl_vi(body, at, scratch)


def pl_uuid(body: int64[], cursor: int64, high: int64[],
            low: int64[]) -> int64:
    int64 at = pl_take(body, cursor, 16)
    if at < 0:
        return (int64)-1
    high[0] = decode_be_int32(body, cursor)
    high[1] = decode_be_int32(body, cursor + 4)
    low[0] = decode_be_int32(body, cursor + 8)
    low[1] = decode_be_int32(body, cursor + 12)
    return at


def pl_pos(body: int64[], cursor: int64, xyz: int64[]) -> int64:
    int64 at = pl_take(body, cursor, 8)
    if at < 0:
        return (int64)-1
    int* unpacked = vt_calloc_int(3)
    vt_unpack_block_pos(decode_be_i64(body, cursor), unpacked)
    xyz[0] = (int64)vt_iget(unpacked, 0)
    xyz[1] = (int64)vt_iget(unpacked, 1)
    xyz[2] = (int64)vt_iget(unpacked, 2)
    vt_free((void*)unpacked)
    return at


def pl_vec3(body: int64[], cursor: int64, xyz: int64[]) -> int64:
    int64 at = pl_take(body, cursor, 24)
    if at < 0:
        return (int64)-1
    xyz[0] = vt_double_to_bits(decode_be_int64(body, cursor))
    xyz[1] = vt_double_to_bits(decode_be_int64(body, cursor + 8))
    xyz[2] = vt_double_to_bits(decode_be_int64(body, cursor + 16))
    return at


def pl_opt_vec3(body: int64[], cursor: int64, xyz: int64[]) -> int64:
    int64[] present = new int64[1]
    int64 at = pl_u8(body, cursor, present)
    if at < 0:
        return (int64)-1
    if present[0] == (int64)0:
        return at
    return pl_vec3(body, at, xyz)


# A list count can never exceed the bytes left in the packet, which bounds
# every loop below without a per-packet constant.
def pl_count(body: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64 at = pl_vi(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    if scratch[0] < (int64)0 or scratch[0] > (int64)len(body):
        return (int64)-1
    return at


def pl_opt_name(body: int64[], cursor: int64, span: int64[]) -> int64:
    int64[] present = new int64[1]
    int64 at = pl_u8(body, cursor, present)
    if at < 0:
        return (int64)-1
    span[0] = 0
    span[1] = -1
    if present[0] == (int64)0:
        return at
    return pl_name(body, at, span)


# --- Play handlers: entity and world side effects ---

public def pl_handle_animate(body: int64[], offset: int64,
                             table: VEntities*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int entity_id = (int)scratch[0]
    at = pl_u8(body, at, scratch)
    if at != len(body):
        return 1
    ventities_touch(table, entity_id)
    print(f"Entity {entity_id} animation {scratch[0]}")
    return 0


public def pl_handle_entity_event(body: int64[], offset: int64,
                                  table: VEntities*) -> int:
    int64 at = pl_take(body, offset, 5)
    if at != len(body):
        return 1
    int entity_id = (int)decode_be_int32(body, offset)
    int event = (int)body[offset + 4] & 0xFF
    ventities_touch(table, entity_id)
    if event == 3:
        ventities_drop(table, entity_id)
    print(f"Entity {entity_id} event {event}")
    return 0


public def pl_handle_take_item_entity(body: int64[], offset: int64,
                                      table: VEntities*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0:
        return 1
    int item_id = (int)scratch[0]
    at = pl_vi(body, at, scratch)
    if at < 0:
        return 1
    int collector = (int)scratch[0]
    at = pl_vi(body, at, scratch)
    if at != len(body):
        return 1
    ventities_drop(table, item_id)
    print(f"Entity {collector} picked up {scratch[0]} of item entity {item_id}")
    return 0


public def pl_handle_set_entity_link(body: int64[], offset: int64,
                                     table: VEntities*) -> int:
    int64 at = pl_take(body, offset, 8)
    if at != len(body):
        return 1
    int source = (int)decode_be_int32(body, offset)
    int dest = (int)decode_be_int32(body, offset + 4)
    ventities_touch(table, source)
    # Value slot 0 is the leash/attachment target; -1 detaches.
    int64 target = (int64)dest
    if dest < 0:
        target = (int64)-1
    ventities_set_value(table, source, 0, target)
    print(f"Entity {source} linked to {dest}")
    return 0


public def pl_handle_projectile_power(body: int64[], offset: int64,
                                      table: VEntities*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int entity_id = (int)scratch[0]
    at = pl_take(body, at, 8)
    if at != len(body):
        return 1
    double power = decode_be_int64(body, at - 8)
    ventities_touch(table, entity_id)
    print(f"Entity {entity_id} acceleration power {power}")
    return 0


public def pl_handle_damage_event(body: int64[], offset: int64,
                                  table: VEntities*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int entity_id = (int)scratch[0]
    # DamageType is a holder registry: a plain registry id, not an inline tag.
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int damage_type = (int)scratch[0]
    at = pl_opt_vi(body, at, scratch)
    if at < 0:
        return 1
    int64 cause = scratch[0]
    at = pl_opt_vi(body, at, scratch)
    if at < 0:
        return 1
    int64 direct = scratch[0]
    int64[] xyz = new int64[3]
    at = pl_opt_vec3(body, at, xyz)
    if at != len(body):
        return 1
    ventities_touch(table, entity_id)
    print(f"Entity {entity_id} damaged by type {damage_type} cause {cause} direct {direct}")
    return 0


public def pl_handle_block_destruction(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0:
        return 1
    int64 breaker = scratch[0]
    int64[] xyz = new int64[3]
    at = pl_pos(body, at, xyz)
    if at < 0:
        return 1
    at = pl_u8(body, at, scratch)
    if at != len(body):
        return 1
    print(f"Break progress {scratch[0]} by {breaker} at ({xyz[0]}, {xyz[1]}, {xyz[2]})")
    return 0


public def pl_handle_game_test_highlight_pos(body: int64[],
                                             offset: int64) -> int:
    int64[] absolute = new int64[3]
    int64 at = pl_pos(body, offset, absolute)
    if at < 0:
        return 1
    int64[] relative = new int64[3]
    at = pl_pos(body, at, relative)
    if at != len(body):
        return 1
    print(f"Game test highlight ({absolute[0]}, {absolute[1]}, {absolute[2]}) relative ({relative[0]}, {relative[1]}, {relative[2]})")
    return 0


public def pl_handle_block_changed_ack(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at != len(body):
        return 1
    print(f"Server acknowledged block sequence {scratch[0]}")
    return 0


public def pl_handle_chunks_biomes(body: int64[], offset: int64,
                                   world: VWorld*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    int64 index = 0
    while index < rows:
        at = pl_take(body, at, 8)
        if at < 0:
            return 1
        int64 packed = decode_be_i64(body, at - 8)
        int chunk_x = (int)(packed >> 32)
        int chunk_z = (int)(packed & 0xFFFFFFFF)
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] < (int64)0:
            return 1
        int64 size = scratch[0]
        int64 end = pl_take(body, at, size)
        if end < 0:
            return 1
        VBuf* column = vbuf_new((int)size)
        int64 step = 0
        while step < size:
            vbuf_put_u8(column, (uint64)body[at + step])
            step = step + 1
        column.pos = 0
        int applied = sec_apply_wire_biomes(column, world, chunk_x, chunk_z,
                                            world.section_count,
                                            world.min_section,
                                            world.biome_global_bits)
        vbuf_free(column)
        if applied == 0:
            print(f"Malformed biome update for chunk ({chunk_x}, {chunk_z})")
            return 1
        at = end
        index = index + 1
    if at != len(body):
        return 1
    print(f"Updated biomes in {rows} chunks")
    return 0


public def pl_handle_set_chunk_cache_center(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0:
        return 1
    int64 x = scratch[0]
    at = pl_vi(body, at, scratch)
    if at != len(body):
        return 1
    print(f"Chunk cache centre ({x}, {scratch[0]})")
    return 0


public def pl_handle_set_chunk_cache_radius(body: int64[], offset: int64,
                                            state: VPlayState*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at != len(body) or scratch[0] < (int64)0 or scratch[0] > (int64)64:
        return 1
    state.view_distance = (int)scratch[0]
    print(f"Chunk cache radius {scratch[0]}")
    return 0


public def pl_handle_move_minecart_along_track(body: int64[], offset: int64,
                                               table: VEntities*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int entity_id = (int)scratch[0]
    at = pl_count(body, at, scratch)
    if at < 0:
        return 1
    int64 steps = scratch[0]
    int64 index = 0
    int64[] xyz = new int64[3]
    while index < steps:
        at = pl_vec3(body, at, xyz)
        if at < 0:
            return 1
        double x = vt_bits_to_double(xyz[0])
        double y = vt_bits_to_double(xyz[1])
        double z = vt_bits_to_double(xyz[2])
        at = pl_vec3(body, at, xyz)
        if at < 0:
            return 1
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        int yaw = (int)scratch[0]
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        int pitch = (int)scratch[0]
        at = pl_take(body, at, 4)
        if at < 0:
            return 1
        if index + 1 == steps:
            ventities_set_position(table, entity_id, x, y, z)
            ventities_set_angle(table, entity_id, 0, yaw)
            ventities_set_angle(table, entity_id, 1, pitch)
        index = index + 1
    if at != len(body):
        return 1
    print(f"Minecart {entity_id} moved along {steps} track steps")
    return 0


public def pl_handle_debug_sample(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 samples = scratch[0]
    at = pl_take(body, at, samples * 8)
    if at < 0:
        return 1
    at = pl_vi(body, at, scratch)
    if at != len(body):
        return 1
    print(f"Debug sample kind {scratch[0]} with {samples} longs")
    return 0


public def pl_handle_low_disk_space_warning(body: int64[],
                                            offset: int64) -> int:
    if offset != len(body):
        return 1
    print("Server warned that the client is low on disk space")
    return 0


public def pl_handle_ticking_step(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at != len(body) or scratch[0] < (int64)0:
        return 1
    print(f"Server requested {scratch[0]} tick steps")
    return 0


public def pl_handle_pong_response(body: int64[], offset: int64) -> int:
    int64 at = pl_take(body, offset, 8)
    if at != len(body):
        return 1
    print(f"Pong {decode_be_i64(body, offset)}")
    return 0


public def pl_handle_player_combat_enter(body: int64[], offset: int64) -> int:
    if offset != len(body):
        return 1
    print("Entered combat")
    return 0


public def pl_handle_player_combat_end(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at != len(body):
        return 1
    print(f"Combat ended after {scratch[0]} ticks")
    return 0


public def pl_handle_player_combat_kill(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int64 player = scratch[0]
    at = pl_component_end(body, at)
    if at != len(body):
        return 1
    print(f"Player {player} died")
    return 0


public def pl_handle_player_look_at(body: int64[], offset: int64,
                                    state: VPlayState*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0 or scratch[0] > (int64)1:
        return 1
    int64[] xyz = new int64[3]
    at = pl_vec3(body, at, xyz)
    if at < 0:
        return 1
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    if scratch[0] != (int64)0:
        at = pl_vi(body, at, scratch)
        if at < 0:
            return 1
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] < (int64)0 or scratch[0] > (int64)1:
            return 1
    if at != len(body):
        return 1
    double x = vt_bits_to_double(xyz[0])
    double y = vt_bits_to_double(xyz[1])
    double z = vt_bits_to_double(xyz[2])
    double dx = x - state.x
    double dz = z - state.z
    double flat = mc_sqrt(dx * dx + dz * dz)
    state.yaw = mc_atan2(dz, dx) * 180.0 / 3.141592653589793 - 90.0
    double dy = y - state.y
    state.pitch = 0.0 - mc_atan2(dy, flat) * 180.0 / 3.141592653589793
    return 0


public def pl_handle_player_rotation(body: int64[], offset: int64,
                                     state: VPlayState*) -> int:
    int64 at = pl_take(body, offset, 10)
    if at != len(body):
        return 1
    double yaw = decode_be_float(body, offset)
    double pitch = decode_be_float(body, offset + 5)
    if body[offset + 4] != 0:
        yaw = yaw + state.yaw
    if body[offset + 9] != 0:
        pitch = pitch + state.pitch
    state.yaw = yaw
    state.pitch = pitch
    return 0


public def pl_handle_open_book(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at != len(body) or scratch[0] < (int64)0 or scratch[0] > (int64)1:
        return 1
    print(f"Open book in hand {scratch[0]}")
    return 0


public def pl_handle_open_sign_editor(body: int64[], offset: int64) -> int:
    int64[] xyz = new int64[3]
    int64 at = pl_pos(body, offset, xyz)
    if at < 0:
        return 1
    int64[] scratch = new int64[1]
    at = pl_vi(body, at, scratch)
    if at != len(body) or scratch[0] < (int64)0 or scratch[0] > (int64)1:
        return 1
    print(f"Sign editor at ({xyz[0]}, {xyz[1]}, {xyz[2]}) front {scratch[0]}")
    return 0


public def pl_handle_mount_screen_open(body: int64[], offset: int64,
                                       inventory: VInventory*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int window = (int)scratch[0]
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int columns = (int)scratch[0]
    at = pl_take(body, at, 4)
    if at != len(body):
        return 1
    int entity_id = (int)decode_be_int32(body, at - 4)
    if vinv_open(inventory, window, 0, columns * 15) != 0:
        return 1
    print(f"Mount screen {window} for entity {entity_id} with {columns} columns")
    return 0


public def pl_handle_stop_sound(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_u8(body, offset, scratch)
    if at < 0:
        return 1
    int64 flags = scratch[0]
    if (flags & 1) != 0:
        at = pl_vi(body, at, scratch)
        if at < 0:
            return 1
    if (flags & 2) != 0:
        int64[] span = new int64[2]
        at = pl_name(body, at, span)
        if at < 0:
            return 1
    if at != len(body):
        return 1
    print(f"Stop sound mask {flags}")
    return 0


public def pl_handle_post_effects(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    int64 index = 0
    while index < rows:
        int64[] span = new int64[2]
        at = pl_name(body, at, span)
        if at < 0:
            return 1
        index = index + 1
    if at != len(body):
        return 1
    print(f"Post effects chain replaced with {rows} passes")
    return 0


public def pl_handle_delete_chat(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0:
        return 1
    # The wire carries id + 1; zero means a full 256 byte signature follows.
    if scratch[0] == (int64)0:
        at = pl_take(body, at, 256)
        if at < 0:
            return 1
    if at != len(body):
        return 1
    print("Server deleted a chat message")
    return 0


public def pl_handle_test_instance_block_status(body: int64[],
                                                offset: int64) -> int:
    int64 at = pl_component_end(body, offset)
    if at < 0:
        return 1
    int64[] scratch = new int64[1]
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    if scratch[0] != (int64)0:
        int step = 0
        while step < 3:
            at = pl_vi(body, at, scratch)
            if at < 0:
                return 1
            step = step + 1
    if at != len(body):
        return 1
    print("Game test instance block status updated")
    return 0


# --- Play handlers: server-pushed session metadata ---

public def pl_handle_award_stats(body: int64[], offset: int64,
                                 meta: VServerMeta*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    int64 index = 0
    while index < rows:
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] < (int64)0:
            return 1
        int category = (int)scratch[0]
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] < (int64)0:
            return 1
        int id = (int)scratch[0]
        at = pl_vi(body, at, scratch)
        if at < 0:
            return 1
        if vmeta_set_stat(meta, category, id, (int)scratch[0]) != 0:
            return 1
        index = index + 1
    if at != len(body):
        return 1
    print(f"Awarded {rows} statistics")
    return 0


public def pl_handle_store_cookie(body: int64[], offset: int64,
                                  meta: VServerMeta*) -> int:
    int64[] span = new int64[2]
    int64 at = pl_name(body, offset, span)
    if at < 0:
        return 1
    int64[] scratch = new int64[1]
    int64 payload_at = pl_vi(body, at, scratch)
    if payload_at < 0 or scratch[0] < (int64)0 or scratch[0] > (int64)5120:
        return 1
    int64 end = pl_take(body, payload_at, scratch[0])
    if end != len(body):
        return 1
    if vmeta_set_cookie(meta, body, span[0], span[1], body, payload_at,
                        scratch[0]) != 0:
        return 1
    print(f"Server stored a {scratch[0]} byte cookie")
    return 0


# The client answers with whatever it holds for the key. An unknown key is a
# present byte of zero, which is how the server learns to stop asking.
public def pl_handle_cookie_request(socket_handle: int64, body: int64[],
                                    offset: int64, meta: VServerMeta*) -> int:
    int64[] span = new int64[2]
    int64 at = pl_name(body, offset, span)
    if at != len(body):
        return 1
    int row = vmeta_cookie_find(meta, body, span[0], span[1])
    int64 size = 0
    if row != vmeta_absent():
        size = (int64)vmeta_cookie_length(meta, row)
    int64[] encoded_key = encode_varint(span[1])
    int64[] encoded_size = encode_varint(size)
    int64 present = 0
    if row != vmeta_absent():
        present = 1
    int64[] payload = new int64[len(encoded_key) + span[1] + 1 + len(encoded_size) + (int)size]
    int64 cursor = 0
    int64 index = 0
    while index < len(encoded_key):
        payload[cursor] = encoded_key[index]
        cursor = cursor + 1
        index = index + 1
    index = 0
    while index < span[1]:
        payload[cursor] = body[span[0] + index]
        cursor = cursor + 1
        index = index + 1
    payload[cursor] = present
    cursor = cursor + 1
    index = 0
    while index < len(encoded_size):
        payload[cursor] = encoded_size[index]
        cursor = cursor + 1
        index = index + 1
    index = 0
    while index < size:
        payload[cursor] = (int64)vmeta_cookie_byte(meta, row, (int)index)
        cursor = cursor + 1
        index = index + 1
    int64[] response = encode_packet_frame(pid_pl_s_cookie_response(), payload)
    if send_bytes(socket_handle, response) != 0:
        print("Failed to answer a Play cookie request")
        return 1
    return 0


public def pl_handle_cooldown(body: int64[], offset: int64,
                              meta: VServerMeta*, now: int64) -> int:
    int64[] span = new int64[2]
    int64 at = pl_name(body, offset, span)
    if at < 0:
        return 1
    int64[] scratch = new int64[1]
    at = pl_vi(body, at, scratch)
    if at != len(body) or scratch[0] < (int64)0:
        return 1
    if vmeta_set_cooldown(meta, body, span[0], span[1], (int)scratch[0],
                          now) != 0:
        return 1
    print(f"Cooldown group set for {scratch[0]} ticks")
    return 0


public def pl_handle_game_rule_values(body: int64[], offset: int64,
                                      meta: VServerMeta*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    int64 index = 0
    while index < rows:
        int64[] name = new int64[2]
        at = pl_name(body, at, name)
        if at < 0:
            return 1
        int64[] value = new int64[2]
        at = pl_text(body, at, 32767, value)
        if at < 0:
            return 1
        if vmeta_set_pair(meta, body, name[0], name[1], body, value[0],
                          value[1]) != 0:
            return 1
        index = index + 1
    if at != len(body):
        return 1
    print(f"Server pushed {rows} game rule values")
    return 0


public def pl_handle_custom_report_details(body: int64[], offset: int64,
                                           meta: VServerMeta*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0 or scratch[0] > (int64)32:
        return 1
    int64 rows = scratch[0]
    if vmeta_reset_report(meta) != 0:
        return 1
    int64 index = 0
    while index < rows:
        int64[] name = new int64[2]
        at = pl_text(body, at, 128, name)
        if at < 0:
            return 1
        int64[] value = new int64[2]
        at = pl_text(body, at, 4096, value)
        if at < 0:
            return 1
        if vmeta_set_report_pair(meta, body, name[0], name[1], body, value[0],
                                 value[1]) != 0:
            return 1
        index = index + 1
    if at != len(body):
        return 1
    print(f"Server pushed {rows} custom report details")
    return 0


# Server Links: an either of a known link type id or a trusted component,
# then the URL as a plain string. A known type stores its id; a custom label
# stores the component bytes in the text pool.
public def pl_handle_server_links(body: int64[], offset: int64,
                                  meta: VServerMeta*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    if vmeta_reset_links(meta) != 0:
        return 1
    int64 index = 0
    while index < rows:
        int64 label_start = 0
        int64 label_length = -1
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        int known = -1
        if scratch[0] == (int64)0:
            at = pl_vi(body, at, scratch)
            if at < 0 or scratch[0] < (int64)0:
                return 1
            known = (int)scratch[0]
        else:
            int64 label_at = at
            at = pl_component_end(body, at)
            if at < 0:
                return 1
            label_start = label_at
            label_length = at - label_at
        int64[] url = new int64[2]
        at = pl_text(body, at, 32767, url)
        if at < 0:
            return 1
        if vmeta_add_link(meta, known, body, label_start, label_length,
                          body, url[0], url[1]) != 0:
            return 1
        index = index + 1
    if at != len(body):
        return 1
    print(f"Server pushed {rows} links")
    return 0


# This backend has no resource pack loader, so a pushed pack is declined the
# same way the configuration path declines one. A required pack therefore ends
# the session rather than leaving the client rendering missing textures.
public def pl_handle_resource_pack_push(socket_handle: int64, body: int64[],
                                        offset: int64,
                                        meta: VServerMeta*) -> int:
    int64[] high = new int64[2]
    int64[] low = new int64[2]
    int64 at = pl_uuid(body, offset, high, low)
    if at < 0:
        return 1
    int64[] url = new int64[2]
    at = pl_text(body, at, 32767, url)
    if at < 0:
        return 1
    int64[] hash = new int64[2]
    at = pl_text(body, at, 40, hash)
    if at < 0:
        return 1
    int64[] scratch = new int64[1]
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    bool required = scratch[0] != (int64)0
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    if scratch[0] != (int64)0:
        at = pl_component_end(body, at)
        if at < 0:
            return 1
    if at != len(body):
        return 1
    vmeta_push_pack(meta, high, low, body, url[0], url[1], body, hash[0],
                    hash[1], required)
    int64[] payload = new int64[17]
    int64 index = 0
    while index < 16:
        payload[index] = body[offset + index]
        index = index + 1
    payload[16] = 1
    int64[] response = encode_packet_frame(pid_pl_s_resource_pack(), payload)
    if send_bytes(socket_handle, response) != 0:
        print("Failed to answer a Play resource pack push")
        return 1
    print("Declined a server resource pack: no pack loader in this backend")
    return 0


public def pl_handle_resource_pack_pop(body: int64[], offset: int64,
                                       meta: VServerMeta*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_u8(body, offset, scratch)
    if at < 0:
        return 1
    int64[] high = new int64[2]
    int64[] low = new int64[2]
    bool present = scratch[0] != (int64)0
    if present:
        at = pl_uuid(body, at, high, low)
        if at < 0:
            return 1
    if at != len(body):
        return 1
    if vmeta_pop_pack(meta, high, low, present) != 0:
        return 1
    print("Server popped a resource pack")
    return 0


# Tag Query asks a creative client to echo an entity or block entity back. A
# remote client never answers, so the payload is walked and dropped.
public def pl_handle_tag_query(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0:
        return 1
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    if scratch[0] != (int64)0:
        if (int)body[at] != 10:
            return 1
        int64[] compound = skip_nbt_payload(body, 10, at + 1, 0)
        if compound[0] != 1:
            return 1
        at = compound[2]
    if at != len(body):
        return 1
    return 0


public def pl_handle_custom_chat_completions(body: int64[], offset: int64,
                                             tree: VCommandTree*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0 or scratch[0] > (int64)2:
        return 1
    int64 action = scratch[0]
    at = pl_count(body, at, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    if action == (int64)2:
        vcmd_completions_clear(tree)
    int64 index = 0
    while index < rows:
        int64[] span = new int64[2]
        at = pl_text(body, at, 32767, span)
        if at < 0:
            return 1
        if action == (int64)1:
            vcmd_completions_remove(tree, body, span[0], span[1])
        else:
            vcmd_completions_add(tree, body, span[0], span[1])
        index = index + 1
    if at != len(body):
        return 1
    print(f"Custom chat completions action {action} over {rows} entries")
    return 0


# --- world border ---

public def pl_handle_initialize_border(body: int64[], offset: int64,
                                       border: VBorder*) -> int:
    int64 at = pl_take(body, offset, 32)
    if at < 0:
        return 1
    double x = decode_be_int64(body, offset)
    double z = decode_be_int64(body, offset + 8)
    double old_size = decode_be_int64(body, offset + 16)
    double new_size = decode_be_int64(body, offset + 24)
    int64[] scratch = new int64[1]
    at = pl_vl(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int64 speed = scratch[0]
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int boundary = (int)scratch[0]
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int warning_blocks = (int)scratch[0]
    at = pl_vi(body, at, scratch)
    if at != len(body) or scratch[0] < (int64)0:
        return 1
    if vborder_initialize(border, x, z, old_size, new_size, speed, boundary,
                          warning_blocks, (int)scratch[0]) != 0:
        return 1
    print(f"World border centred at ({x}, {z}) diameter {new_size}")
    return 0


public def pl_handle_set_border_center(body: int64[], offset: int64,
                                       border: VBorder*) -> int:
    int64 at = pl_take(body, offset, 16)
    if at != len(body):
        return 1
    if vborder_set_center(border, decode_be_int64(body, offset),
                          decode_be_int64(body, offset + 8)) != 0:
        return 1
    return 0


public def pl_handle_set_border_size(body: int64[], offset: int64,
                                     border: VBorder*) -> int:
    int64 at = pl_take(body, offset, 8)
    if at != len(body):
        return 1
    if vborder_set_size(border, decode_be_int64(body, offset)) != 0:
        return 1
    return 0


public def pl_handle_set_border_lerp_size(body: int64[], offset: int64,
                                          border: VBorder*) -> int:
    int64 at = pl_take(body, offset, 16)
    if at < 0:
        return 1
    int64[] scratch = new int64[1]
    at = pl_vl(body, at, scratch)
    if at != len(body) or scratch[0] < (int64)0:
        return 1
    if vborder_lerp_size(border, decode_be_int64(body, offset),
                         decode_be_int64(body, offset + 8), scratch[0]) != 0:
        return 1
    return 0


public def pl_handle_set_border_warning_delay(body: int64[], offset: int64,
                                              border: VBorder*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at != len(body) or scratch[0] < (int64)0:
        return 1
    if vborder_set_warning_delay(border, (int)scratch[0]) != 0:
        return 1
    return 0


public def pl_handle_set_border_warning_distance(body: int64[], offset: int64,
                                                 border: VBorder*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at != len(body) or scratch[0] < (int64)0:
        return 1
    if vborder_set_warning_distance(border, (int)scratch[0]) != 0:
        return 1
    return 0


# --- maps ---

public def pl_handle_map_item_data(body: int64[], offset: int64,
                                   meta: VServerMeta*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int map_id = (int)scratch[0]
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    int scale = (int)scratch[0]
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    bool locked = scratch[0] != (int64)0
    int row = vmeta_map_header(meta, map_id, scale, locked)
    if row == vmeta_absent():
        return 1
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    if scratch[0] != (int64)0:
        at = pl_count(body, at, scratch)
        if at < 0:
            return 1
        int64 rows = scratch[0]
        if vmeta_reset_decorations(meta, row) != 0:
            return 1
        int64 index = 0
        while index < rows:
            at = pl_vi(body, at, scratch)
            if at < 0 or scratch[0] < (int64)0:
                return 1
            int kind = (int)scratch[0]
            at = pl_take(body, at, 3)
            if at < 0:
                return 1
            int dx = (int)body[at - 3]
            int dy = (int)body[at - 2]
            int rot = (int)body[at - 1]
            at = pl_u8(body, at, scratch)
            if at < 0:
                return 1
            if scratch[0] != (int64)0:
                at = pl_component_end(body, at)
                if at < 0:
                    return 1
            if vmeta_add_decoration(meta, row, kind, dx, dy, rot) != 0:
                return 1
            index = index + 1
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    int width = (int)scratch[0]
    if width > 0:
        at = pl_take(body, at, 3)
        if at < 0:
            return 1
        int height = (int)body[at - 3]
        int start_x = (int)body[at - 2]
        int start_y = (int)body[at - 1]
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] != (int64)(width * height):
            return 1
        int64 end = pl_take(body, at, scratch[0])
        if end < 0:
            return 1
        if vmeta_map_patch(meta, row, start_x, start_y, width, height,
                           body, at) != 0:
            return 1
        at = end
    if at != len(body):
        return 1
    print(f"Map {map_id} scale {scale} updated")
    return 0


# --- merchant offers ---

# ItemCost is a holder registry id, a count, and an exact component predicate:
# a list of typed components whose payloads are skipped with the Slot reader.
def pl_read_item_cost(body: int64[], cursor: int64, out: int64[]) -> int64:
    out[0] = -1
    out[1] = 0
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, cursor, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return (int64)-1
    out[0] = scratch[0]
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return (int64)-1
    out[1] = scratch[0]
    at = pl_count(body, at, scratch)
    if at < 0:
        return (int64)-1
    int64 rows = scratch[0]
    int64 index = 0
    while index < rows:
        at = pl_vi(body, at, scratch)
        if at < 0:
            return (int64)-1
        int component = (int)scratch[0]
        if sl_component_known(component) == 0:
            return (int64)-1
        at = sl_skip_component(body, at, component)
        if at < 0:
            return (int64)-1
        index = index + 1
    return at


public def pl_handle_merchant_offers(body: int64[], offset: int64,
                                     meta: VServerMeta*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int window = (int)scratch[0]
    at = pl_count(body, at, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    if vmeta_reset_trades(meta, window) != 0:
        return 1
    int64 index = 0
    int64[] cost = new int64[2]
    int64[] stack = new int64[3]
    while index < rows:
        at = pl_read_item_cost(body, at, cost)
        if at < 0:
            return 1
        at = sl_read(body, at, stack)
        if at < 0:
            return 1
        int64[] present = new int64[1]
        at = pl_u8(body, at, present)
        if at < 0:
            return 1
        int cost_b = -1
        int cost_b_count = 0
        if present[0] != (int64)0:
            at = pl_read_item_cost(body, at, cost)
            if at < 0:
                return 1
            cost_b = (int)cost[0]
            cost_b_count = (int)cost[1]
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        bool disabled = scratch[0] != (int64)0
        at = pl_take(body, at, 16)
        if at < 0:
            return 1
        int uses = (int)decode_be_int32(body, at - 16)
        int max_uses = (int)decode_be_int32(body, at - 12)
        # Price multiplier is a float and demand a plain int, not varints.
        at = pl_take(body, at, 8)
        if at < 0:
            return 1
        if vmeta_add_trade(meta, (int)cost[0], (int)cost[1], cost_b,
                           cost_b_count, (int)stack[1], (int)stack[2], uses,
                           max_uses, disabled) != 0:
            return 1
        index = index + 1
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int level = (int)scratch[0]
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int xp = (int)scratch[0]
    at = pl_u8(body, at, scratch)
    if at < 0:
        return 1
    bool progress = scratch[0] != (int64)0
    at = pl_u8(body, at, scratch)
    if at != len(body):
        return 1
    if vmeta_set_merchant(meta, level, xp, progress,
                          scratch[0] != (int64)0) != 0:
        return 1
    print(f"Merchant window {window} offers {rows} trades at level {level}")
    return 0


# --- waypoints ---

# TrackedWaypoint: an either of a UUID or a string id, an icon (a style key
# plus an optional RGB colour), a type enum, then the type's own payload.
def pl_read_waypoint(body: int64[], cursor: int64, high: int64[],
                     low: int64[], out: int64[]) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_u8(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    int64 name_start = 0
    int64 name_length = -1
    if scratch[0] == (int64)0:
        at = pl_uuid(body, at, high, low)
        if at < 0:
            return (int64)-1
    else:
        int64[] span = new int64[2]
        name_start = at
        at = pl_text(body, at, 32767, span)
        if at < 0:
            return (int64)-1
        name_start = span[0]
        name_length = span[1]
        high[0] = 0
        high[1] = 0
        low[0] = 0
        low[1] = 0
    out[4] = name_start
    out[5] = name_length
    int64[] style = new int64[2]
    at = pl_name(body, at, style)
    if at < 0:
        return (int64)-1
    at = pl_u8(body, at, scratch)
    if at < 0:
        return (int64)-1
    int color = -1
    if scratch[0] != (int64)0:
        at = pl_take(body, at, 3)
        if at < 0:
            return (int64)-1
        color = ((int)body[at - 3] << 16) | ((int)body[at - 2] << 8)
        color = color | (int)body[at - 1]
    out[3] = (int64)color
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0 or scratch[0] > (int64)3:
        return (int64)-1
    int64 kind = scratch[0]
    out[0] = kind
    out[1] = 0
    out[2] = 0
    if kind == (int64)1:
        int axis = 0
        while axis < 3:
            at = pl_vi(body, at, scratch)
            if at < 0:
                return (int64)-1
            out[axis + 6] = scratch[0]
            axis = axis + 1
        return at
    if kind == (int64)2:
        at = pl_vi(body, at, scratch)
        if at < 0:
            return (int64)-1
        out[6] = scratch[0]
        at = pl_vi(body, at, scratch)
        if at < 0:
            return (int64)-1
        out[7] = scratch[0]
        return at
    if kind == (int64)3:
        at = pl_take(body, at, 4)
        if at < 0:
            return (int64)-1
        out[6] = (int64)vt_float_to_bits(decode_be_float(body, at - 4))
        return at
    return at


public def pl_handle_waypoint(body: int64[], offset: int64,
                              meta: VServerMeta*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0 or scratch[0] > (int64)2:
        return 1
    int64 operation = scratch[0]
    int64[] high = new int64[2]
    int64[] low = new int64[2]
    int64[] out = new int64[9]
    at = pl_read_waypoint(body, at, high, low, out)
    if at != len(body):
        return 1
    int a = 0
    int b = 0
    int c = 0
    if out[0] == (int64)1:
        a = (int)out[6]
        b = (int)out[7]
        c = (int)out[8]
    if out[0] == (int64)2:
        a = (int)out[6]
        b = (int)out[7]
    if out[0] == (int64)3:
        a = (int)out[6]
    if operation == (int64)1:
        if vmeta_untrack_waypoint(meta, body, out[4], out[5], high, low) != 0:
            return 1
        return 0
    vmeta_track_waypoint(meta, body, out[4], out[5], high, low, (int)out[0],
                         a, b, c, (int)out[3])
    print(f"Waypoint operation {operation} kind {out[0]}")
    return 0


# --- recipes, tags and advancements ---

# Ingredient.CONTENTS_STREAM_CODEC is a holder set: zero introduces a tag name,
# otherwise the count is one more than the number of plain registry ids.
# out[0] receives the id count, or -1 for a tag this client cannot resolve.
def pl_read_ingredient(body: int64[], cursor: int64, items: int64[],
                       out: int64[]) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, cursor, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return (int64)-1
    if scratch[0] == (int64)0:
        int64[] span = new int64[2]
        at = pl_name(body, at, span)
        if at < 0:
            return (int64)-1
        out[0] = (int64)-1
        return at
    int64 count = scratch[0] - 1
    if count > (int64)len(items):
        return (int64)-1
    out[0] = count
    int64 index = 0
    while index < count:
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] < (int64)0:
            return (int64)-1
        items[index] = scratch[0]
        index = index + 1
    return at


public def pl_handle_update_recipes(body: int64[], offset: int64,
                                    book: VRecipes*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 sets = scratch[0]
    if vrecipe_reset_sets(book) != 0:
        return 1
    int64[] items = new int64[vrecipe_entry_max()]
    int64 index = 0
    while index < sets:
        int64[] name = new int64[2]
        at = pl_name(body, at, name)
        if at < 0:
            return 1
        at = pl_count(body, at, scratch)
        if at < 0 or scratch[0] > (int64)vrecipe_entry_max():
            return 1
        int64 count = scratch[0]
        int64 step = 0
        while step < count:
            at = pl_vi(body, at, scratch)
            if at < 0 or scratch[0] < (int64)0:
                return 1
            items[step] = scratch[0]
            step = step + 1
        if vrecipe_add_set(book, body, name[0], name[1], items,
                           (int)count) != 0:
            return 1
        index = index + 1
    at = pl_count(body, at, scratch)
    if at < 0:
        return 1
    int64 stones = scratch[0]
    index = 0
    while index < stones:
        int64[] holders = new int64[1]
        at = pl_read_ingredient(body, at, items, holders)
        if at < 0:
            return 1
        int64[] display = new int64[1]
        at = rd_read(body, at, display)
        if at < 0:
            return 1
        int64 step = 0
        while step < holders[0]:
            if vrecipe_add_stonecutter(book, (int)items[step],
                                       (int)display[0]) != 0:
                return 1
            step = step + 1
        index = index + 1
    if at != len(body):
        return 1
    print(f"Recipe sync: {sets} item sets and {stones} stonecutter entries")
    return 0


public def pl_handle_place_ghost_recipe(body: int64[], offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int64 window = scratch[0]
    int64[] display = new int64[1]
    at = rd_read(body, at, display)
    if at != len(body):
        return 1
    print(f"Ghost recipe type {display[0]} placed in window {window}")
    return 0


# RecipeDisplayEntry: an id, the display tree, an optional group, a recipe book
# category and an optional list of crafting requirements. Only the id, group
# and category are retained; the tree is walked to validate the packet.
# The replace flag trails the list, so entries are buffered and the book is
# cleared only once the whole packet has parsed.
public def pl_handle_recipe_book_add(body: int64[], offset: int64,
                                     book: VRecipes*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    if rows > (int64)vrecipe_entry_max():
        return 1
    int capacity = vrecipe_entry_max()
    int64[] ids = new int64[capacity]
    int64[] categories = new int64[capacity]
    int64[] groups = new int64[capacity]
    int64[] flags = new int64[capacity]
    int64[] items = new int64[vrecipe_entry_max()]
    int64[] holders = new int64[1]
    int64 index = 0
    while index < rows:
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] < (int64)0:
            return 1
        ids[index] = scratch[0]
        int64[] display = new int64[1]
        at = rd_read(body, at, display)
        if at < 0:
            return 1
        at = pl_opt_vi(body, at, scratch)
        if at < 0:
            return 1
        groups[index] = scratch[0]
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] < (int64)0:
            return 1
        categories[index] = scratch[0]
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        if scratch[0] != (int64)0:
            at = pl_count(body, at, scratch)
            if at < 0:
                return 1
            int64 requirements = scratch[0]
            int64 step = 0
            while step < requirements:
                at = pl_read_ingredient(body, at, items, holders)
                if at < 0:
                    return 1
                step = step + 1
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        flags[index] = scratch[0]
        index = index + 1
    at = pl_u8(body, at, scratch)
    if at != len(body):
        return 1
    if scratch[0] != (int64)0:
        vrecipe_book_clear(book)
    index = 0
    while index < rows:
        if vrecipe_book_add(book, (int)ids[index], (int)categories[index],
                            (int)groups[index], (int)flags[index]) != 0:
            return 1
        index = index + 1
    print(f"Recipe book gained {rows} entries")
    return 0


public def pl_handle_recipe_book_remove(body: int64[], offset: int64,
                                        book: VRecipes*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    int64 index = 0
    while index < rows:
        at = pl_vi(body, at, scratch)
        if at < 0 or scratch[0] < (int64)0:
            return 1
        if vrecipe_book_remove(book, (int)scratch[0]) != 0:
            return 1
        index = index + 1
    if at != len(body):
        return 1
    return 0


public def pl_handle_recipe_book_settings(body: int64[], offset: int64,
                                          book: VRecipes*) -> int:
    int64 at = pl_take(body, offset, 8)
    if at != len(body):
        return 1
    int kind = 0
    while kind < vrecipe_book_types():
        if vrecipe_set_settings(book, kind, body[offset + kind * 2] != 0,
                                body[offset + kind * 2 + 1] != 0) != 0:
            return 1
        kind = kind + 1
    return 0


public def pl_handle_update_tags(body: int64[], offset: int64,
                                 table: VTags*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, offset, scratch)
    if at < 0:
        return 1
    int64 registries = scratch[0]
    if vtags_reset(table) != 0:
        return 1
    int64[] ids = new int64[vtags_pool_max()]
    int64 index = 0
    while index < registries:
        int64[] registry = new int64[2]
        at = pl_name(body, at, registry)
        if at < 0:
            return 1
        int row = vtags_registry_row(table, body, registry[0], registry[1])
        if row == vtags_absent():
            return 1
        at = pl_count(body, at, scratch)
        if at < 0:
            return 1
        int64 tags = scratch[0]
        int64 step = 0
        while step < tags:
            int64[] name = new int64[2]
            at = pl_name(body, at, name)
            if at < 0:
                return 1
            at = pl_count(body, at, scratch)
            if at < 0 or scratch[0] > (int64)vtags_pool_max():
                return 1
            int64 count = scratch[0]
            int64 entry = 0
            while entry < count:
                at = pl_vi(body, at, scratch)
                if at < 0 or scratch[0] < (int64)0:
                    return 1
                ids[entry] = scratch[0]
                entry = entry + 1
            if vtags_add(table, row, body, name[0], name[1], ids,
                         (int)count) != 0:
                return 1
            step = step + 1
        index = index + 1
    if at != len(body):
        return 1
    print(f"Tag sync over {registries} registries")
    return 0


# DisplayInfo: two components, an ItemStackTemplate icon, a frame enum, an
# flags int and, when bit 0 is set, the background texture identifier.
def pl_read_display_info(body: int64[], cursor: int64, out: int64[]) -> int64:
    int64 at = pl_component_end(body, cursor)
    if at < 0:
        return (int64)-1
    at = pl_component_end(body, at)
    if at < 0:
        return (int64)-1
    int64[] stack = new int64[3]
    at = sl_read_template(body, at, stack)
    if at < 0:
        return (int64)-1
    out[2] = stack[1]
    int64[] scratch = new int64[1]
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0 or scratch[0] > (int64)2:
        return (int64)-1
    out[0] = scratch[0]
    at = pl_take(body, at, 4)
    if at < 0:
        return (int64)-1
    int64 flags = decode_be_int32(body, at - 4)
    out[1] = flags
    if (flags & 1) != 0:
        int64[] span = new int64[2]
        at = pl_name(body, at, span)
        if at < 0:
            return (int64)-1
    return at


# AdvancementRequirements is a list of lists of criterion names; the client
# only needs the names to match progress against, so the nesting is walked.
def pl_read_requirements(body: int64[], cursor: int64) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    int64 groups = scratch[0]
    int64 index = 0
    while index < groups:
        at = pl_count(body, at, scratch)
        if at < 0:
            return (int64)-1
        int64 names = scratch[0]
        int64 step = 0
        while step < names:
            int64[] span = new int64[2]
            at = pl_text(body, at, 32767, span)
            if at < 0:
                return (int64)-1
            step = step + 1
        index = index + 1
    return at


public def pl_handle_update_advancements(body: int64[], offset: int64,
                                         table: VAdvancements*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_u8(body, offset, scratch)
    if at < 0:
        return 1
    if scratch[0] != (int64)0:
        if vadv_reset(table) != 0:
            return 1
    at = pl_count(body, at, scratch)
    if at < 0:
        return 1
    int64 added = scratch[0]
    int64 index = 0
    while index < added:
        int64[] key = new int64[2]
        at = pl_name(body, at, key)
        if at < 0:
            return 1
        int64[] parent = new int64[2]
        at = pl_opt_name(body, at, parent)
        if at < 0:
            return 1
        int64 frame = 0
        int64 flags = 0
        int64 icon = 0
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        if scratch[0] != (int64)0:
            int64[] display = new int64[3]
            at = pl_read_display_info(body, at, display)
            if at < 0:
                return 1
            frame = display[0]
            flags = display[1]
            icon = display[2]
        at = pl_read_requirements(body, at)
        if at < 0:
            return 1
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        at = pl_take(body, at, 8)
        if at < 0:
            return 1
        double x = decode_be_float(body, at - 8)
        double y = decode_be_float(body, at - 4)
        if vadv_add(table, body, key[0], key[1], body, parent[0], parent[1],
                    (int)frame, (int)flags, (int)icon, x, y) == vadv_absent():
            return 1
        index = index + 1
    at = pl_count(body, at, scratch)
    if at < 0:
        return 1
    int64 removed = scratch[0]
    index = 0
    while index < removed:
        int64[] key = new int64[2]
        at = pl_name(body, at, key)
        if at < 0:
            return 1
        if vadv_remove(table, body, key[0], key[1]) != 0:
            return 1
        index = index + 1
    at = pl_count(body, at, scratch)
    if at < 0:
        return 1
    int64 progress_rows = scratch[0]
    index = 0
    while index < progress_rows:
        int64[] key = new int64[2]
        at = pl_name(body, at, key)
        if at < 0:
            return 1
        int row = vadv_find(table, body, key[0], key[1])
        at = pl_count(body, at, scratch)
        if at < 0:
            return 1
        int64 criteria = scratch[0]
        int64 step = 0
        while step < criteria:
            int64[] name = new int64[2]
            at = pl_text(body, at, 32767, name)
            if at < 0:
                return 1
            at = pl_u8(body, at, scratch)
            if at < 0:
                return 1
            int64 millis = (int64)-1
            if scratch[0] != (int64)0:
                at = pl_take(body, at, 8)
                if at < 0:
                    return 1
                millis = decode_be_i64(body, at - 8)
            if row != vadv_absent():
                if vadv_set_progress(table, row, body, name[0], name[1],
                                     millis) != 0:
                    return 1
            step = step + 1
        index = index + 1
    at = pl_u8(body, at, scratch)
    if at != len(body):
        return 1
    if vadv_set_visible(table, scratch[0] != (int64)0) != 0:
        return 1
    print(f"Advancements: {added} added, {removed} removed, {progress_rows} progressed")
    return 0


public def pl_handle_select_advancements_tab(body: int64[], offset: int64,
                                             table: VAdvancements*) -> int:
    int64[] span = new int64[2]
    int64 at = pl_opt_name(body, offset, span)
    if at != len(body):
        return 1
    if vadv_select_tab(table, body, span[0], span[1]) != 0:
        return 1
    return 0


# --- Play handlers: plugin channels, tab completion and debug subscriptions ---

# A plugin message is an identifier channel followed by the rest of the packet.
# Only minecraft:brand has a vanilla codec; every other channel is opaque, so it
# is size-bounded and reported rather than parsed.
public def pl_handle_custom_payload(body: int64[], offset: int64) -> int:
    int64[] channel = read_string_field(body, offset, 32767)
    if channel[0] != 1:
        return 1
    int64 start = channel[2] + channel[1]
    int64 size = len(body) - start
    if size < 0 or size > 1048576:
        return 1
    if nbt_string_equals(body, channel, "minecraft:brand"):
        int64[] span = new int64[2]
        int64 at = pl_text(body, start, 32767, span)
        if at != len(body):
            return 1
        print("Server brand: ")
        pl_print_bytes(body, span[0], span[1])
        print(f" ({span[1]} bytes)")
        return 0
    print("Plugin message on ")
    pl_print_bytes(body, channel[2], channel[1])
    print(f" ({size} payload bytes)")
    return 0


public def pl_handle_command_suggestions(body: int64[], offset: int64,
                                         tree: VCommandTree*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int id = (int)scratch[0]
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int start = (int)scratch[0]
    at = pl_vi(body, at, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int length = (int)scratch[0]
    at = pl_count(body, at, scratch)
    if at < 0:
        return 1
    int64 rows = scratch[0]
    if vcmd_suggestions_begin(tree, id, start, length) != 0:
        return 1
    int64 index = 0
    while index < rows:
        int64[] span = new int64[2]
        at = pl_text(body, at, 32767, span)
        if at < 0:
            return 1
        if vcmd_suggestions_add(tree, body, span[0], span[1]) == vcmd_absent():
            return 1
        at = pl_u8(body, at, scratch)
        if at < 0:
            return 1
        if scratch[0] != (int64)0:
            at = pl_component_end(body, at)
            if at < 0:
                return 1
        index = index + 1
    if at != len(body):
        return 1
    return 0


# Debug values are projected into an accumulator: scalars in wire order, list
# counts before their elements, strings as byte lengths, floats as raw bits.
# Each reader returns the next offset or -1.

def pl_dbg_vi(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    vdbg_acc_push(acc, scratch[0])
    return at


def pl_dbg_bool(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_u8(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    if scratch[0] == (int64)0:
        vdbg_acc_push(acc, (int64)0)
    else:
        vdbg_acc_push(acc, (int64)1)
    return at


def pl_dbg_i32(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64 at = pl_take(body, cursor, 4)
    if at < 0:
        return (int64)-1
    vdbg_acc_push(acc, decode_be_int32(body, cursor))
    return at


def pl_dbg_f32(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64 at = pl_take(body, cursor, 4)
    if at < 0:
        return (int64)-1
    int64 bits = (int64)vt_float_to_bits(decode_be_float(body, cursor))
    vdbg_acc_push(acc, bits)
    return at


def pl_dbg_text(body: int64[], cursor: int64, acc: VDbgAcc*,
                maximum: int64) -> int64:
    int64[] span = new int64[2]
    int64 at = pl_text(body, cursor, maximum, span)
    if at < 0:
        return (int64)-1
    vdbg_acc_push(acc, span[1])
    return at


def pl_dbg_pos(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] xyz = new int64[3]
    int64 at = pl_pos(body, cursor, xyz)
    if at < 0:
        return (int64)-1
    vdbg_acc_push(acc, xyz[0])
    vdbg_acc_push(acc, xyz[1])
    vdbg_acc_push(acc, xyz[2])
    return at


def pl_dbg_vec3(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] xyz = new int64[3]
    int64 at = pl_vec3(body, cursor, xyz)
    if at < 0:
        return (int64)-1
    vdbg_acc_push(acc, xyz[0])
    vdbg_acc_push(acc, xyz[1])
    vdbg_acc_push(acc, xyz[2])
    return at


# Optionals project as a presence flag followed by the value, so an absent
# optional stays distinguishable from a present zero.
def pl_dbg_opt_pos(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_u8(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    if scratch[0] == (int64)0:
        vdbg_acc_push(acc, (int64)0)
        return at
    vdbg_acc_push(acc, (int64)1)
    return pl_dbg_pos(body, at, acc)


def pl_dbg_opt_vi(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_opt_vi(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    if scratch[0] < (int64)0:
        vdbg_acc_push(acc, (int64)0)
        return at
    vdbg_acc_push(acc, (int64)1)
    vdbg_acc_push(acc, scratch[0])
    return at


def pl_dbg_pos_list(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    int64 rows = scratch[0]
    vdbg_acc_push(acc, rows)
    int64 index = 0
    while index < rows:
        at = pl_dbg_pos(body, at, acc)
        if at < 0:
            return (int64)-1
        index = index + 1
    return at


def pl_dbg_text_list(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    int64 rows = scratch[0]
    vdbg_acc_push(acc, rows)
    int64 index = 0
    while index < rows:
        at = pl_dbg_text(body, at, acc, 32767)
        if at < 0:
            return (int64)-1
        index = index + 1
    return at


# Node and Target share one debug codec; PathType is an idMapper varint.
def pl_dbg_node(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64 at = pl_dbg_i32(body, cursor, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_i32(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_i32(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_f32(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_f32(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_bool(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_vi(body, at, acc)
    if at < 0:
        return (int64)-1
    return pl_dbg_f32(body, at, acc)


def pl_dbg_node_list(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    int64 rows = scratch[0]
    vdbg_acc_push(acc, rows)
    int64 index = 0
    while index < rows:
        at = pl_dbg_node(body, at, acc)
        if at < 0:
            return (int64)-1
        index = index + 1
    return at


def pl_dbg_path(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64 at = pl_dbg_bool(body, cursor, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_i32(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_pos(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_node_list(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_node_list(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_node_list(body, at, acc)
    if at < 0:
        return (int64)-1
    return pl_dbg_node_list(body, at, acc)


def pl_dbg_bbox(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64 at = pl_dbg_pos(body, cursor, acc)
    if at < 0:
        return (int64)-1
    return pl_dbg_pos(body, at, acc)


def pl_dbg_structure(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64 at = pl_dbg_bbox(body, cursor, acc)
    if at < 0:
        return (int64)-1
    int64[] scratch = new int64[1]
    at = pl_count(body, at, scratch)
    if at < 0:
        return (int64)-1
    int64 rows = scratch[0]
    vdbg_acc_push(acc, rows)
    int64 index = 0
    while index < rows:
        at = pl_dbg_bbox(body, at, acc)
        if at < 0:
            return (int64)-1
        at = pl_dbg_bool(body, at, acc)
        if at < 0:
            return (int64)-1
        index = index + 1
    return at


def pl_dbg_structure_list(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    int64 rows = scratch[0]
    vdbg_acc_push(acc, rows)
    int64 index = 0
    while index < rows:
        at = pl_dbg_structure(body, at, acc)
        if at < 0:
            return (int64)-1
        index = index + 1
    return at


def pl_dbg_goals(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_count(body, cursor, scratch)
    if at < 0:
        return (int64)-1
    int64 rows = scratch[0]
    vdbg_acc_push(acc, rows)
    int64 index = 0
    while index < rows:
        at = pl_dbg_vi(body, at, acc)
        if at < 0:
            return (int64)-1
        at = pl_dbg_bool(body, at, acc)
        if at < 0:
            return (int64)-1
        at = pl_dbg_text(body, at, acc, 255)
        if at < 0:
            return (int64)-1
        index = index + 1
    return at


def pl_dbg_brain(body: int64[], cursor: int64, acc: VDbgAcc*) -> int64:
    int64 at = pl_dbg_text(body, cursor, acc, 32767)
    if at < 0:
        return (int64)-1
    at = pl_dbg_text(body, at, acc, 32767)
    if at < 0:
        return (int64)-1
    at = pl_dbg_i32(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_f32(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_f32(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_text(body, at, acc, 32767)
    if at < 0:
        return (int64)-1
    at = pl_dbg_bool(body, at, acc)
    if at < 0:
        return (int64)-1
    at = pl_dbg_i32(body, at, acc)
    if at < 0:
        return (int64)-1
    int group = 0
    while group < 4:
        at = pl_dbg_text_list(body, at, acc)
        if at < 0:
            return (int64)-1
        group = group + 1
    at = pl_dbg_pos_list(body, at, acc)
    if at < 0:
        return (int64)-1
    return pl_dbg_pos_list(body, at, acc)


# The DEBUG_SUBSCRIPTION registry is frozen at bootstrap, so the id selects the
# value codec. Id 0 (dedicated_server_tick_time) has no value codec at all and
# an id outside the vanilla set has an unknown shape; both are rejected rather
# than guessed at.
def pl_dbg_value(body: int64[], cursor: int64, acc: VDbgAcc*,
                 subscription: int) -> int64:
    if subscription == 1:
        int64 at = pl_dbg_opt_pos(body, cursor, acc)
        if at < 0:
            return (int64)-1
        at = pl_dbg_opt_pos(body, at, acc)
        if at < 0:
            return (int64)-1
        at = pl_dbg_vi(body, at, acc)
        if at < 0:
            return (int64)-1
        return pl_dbg_pos_list(body, at, acc)
    if subscription == 2:
        return pl_dbg_brain(body, cursor, acc)
    if subscription == 3:
        int64 at = pl_dbg_opt_vi(body, cursor, acc)
        if at < 0:
            return (int64)-1
        return pl_dbg_opt_pos(body, at, acc)
    if subscription == 4:
        return pl_dbg_goals(body, cursor, acc)
    if subscription == 5:
        int64 at = pl_dbg_path(body, cursor, acc)
        if at < 0:
            return (int64)-1
        return pl_dbg_f32(body, at, acc)
    if subscription == 6:
        return pl_dbg_vi(body, cursor, acc)
    if subscription == 7:
        int64 at = pl_dbg_vi(body, cursor, acc)
        if at < 0:
            return (int64)-1
        at = pl_dbg_vi(body, at, acc)
        if at < 0:
            return (int64)-1
        at = pl_dbg_vi(body, at, acc)
        if at < 0:
            return (int64)-1
        return pl_dbg_bool(body, at, acc)
    if subscription == 8:
        int64 at = pl_dbg_pos(body, cursor, acc)
        if at < 0:
            return (int64)-1
        at = pl_dbg_vi(body, at, acc)
        if at < 0:
            return (int64)-1
        return pl_dbg_vi(body, at, acc)
    if subscription == 9:
        return pl_dbg_vi(body, cursor, acc)
    if subscription == 10:
        return cursor
    if subscription == 11:
        return pl_dbg_pos_list(body, cursor, acc)
    if subscription == 12:
        return pl_dbg_structure_list(body, cursor, acc)
    if subscription == 13:
        return pl_dbg_vi(body, cursor, acc)
    if subscription == 14:
        return pl_dbg_pos(body, cursor, acc)
    if subscription == 15:
        int64 at = pl_dbg_vi(body, cursor, acc)
        if at < 0:
            return (int64)-1
        return pl_dbg_vec3(body, at, acc)
    return (int64)-1


# out carries {subscription, present}. An absent optional still names a valid
# subscription: it clears whatever value the key held.
def pl_dbg_update(body: int64[], cursor: int64, acc: VDbgAcc*,
                  out: int64[]) -> int64:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, cursor, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return (int64)-1
    out[0] = scratch[0]
    at = pl_u8(body, at, scratch)
    if at < 0:
        return (int64)-1
    if scratch[0] == (int64)0:
        out[1] = (int64)0
        return at
    out[1] = (int64)1
    vdbg_acc_reset(acc)
    return pl_dbg_value(body, at, acc, (int)out[0])


public def pl_handle_debug_block_value(body: int64[], offset: int64,
                                       store: VDebug*) -> int:
    int64[] xyz = new int64[3]
    int64 at = pl_pos(body, offset, xyz)
    if at < 0:
        return 1
    VDbgAcc* acc = vdbg_acc_new()
    int64[] head = new int64[2]
    at = pl_dbg_update(body, at, acc, head)
    if at != len(body):
        vdbg_acc_free(acc)
        return 1
    int row = vdebug_set(store, vdebug_kind_block(), (int)head[0],
                         xyz[0], xyz[1], xyz[2], (int)head[1], acc)
    vdbg_acc_free(acc)
    if row == vdebug_absent():
        return 1
    return 0


public def pl_handle_debug_chunk_value(body: int64[], offset: int64,
                                       store: VDebug*) -> int:
    int64 at = pl_take(body, offset, 8)
    if at < 0:
        return 1
    int64 packed = decode_be_i64(body, offset)
    int64 chunk_x = (int64)(int)(packed >> 32)
    int64 chunk_z = (int64)(int)(packed & 0xFFFFFFFF)
    VDbgAcc* acc = vdbg_acc_new()
    int64[] head = new int64[2]
    at = pl_dbg_update(body, at, acc, head)
    if at != len(body):
        vdbg_acc_free(acc)
        return 1
    int row = vdebug_set(store, vdebug_kind_chunk(), (int)head[0],
                         chunk_x, (int64)0, chunk_z, (int)head[1], acc)
    vdbg_acc_free(acc)
    if row == vdebug_absent():
        return 1
    return 0


public def pl_handle_debug_entity_value(body: int64[], offset: int64,
                                        store: VDebug*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int64 entity = scratch[0]
    VDbgAcc* acc = vdbg_acc_new()
    int64[] head = new int64[2]
    at = pl_dbg_update(body, at, acc, head)
    if at != len(body):
        vdbg_acc_free(acc)
        return 1
    int row = vdebug_set(store, vdebug_kind_entity(), (int)head[0],
                         entity, (int64)0, (int64)0, (int)head[1], acc)
    vdbg_acc_free(acc)
    if row == vdebug_absent():
        return 1
    return 0


# An Event has no optional wrapper: the value is always present.
public def pl_handle_debug_event(body: int64[], offset: int64,
                                 store: VDebug*) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0 or scratch[0] < (int64)0:
        return 1
    int subscription = (int)scratch[0]
    VDbgAcc* acc = vdbg_acc_new()
    at = pl_dbg_value(body, at, acc, subscription)
    if at != len(body):
        vdbg_acc_free(acc)
        return 1
    int row = vdebug_push_event(store, subscription, acc)
    vdbg_acc_free(acc)
    if row == vdebug_absent():
        return 1
    return 0


public def pl_handle_player_chat(body: int64[], offset: int64) -> int:
    int64 cursor = offset + 16
    int64[] message_index = decode_varint(body, cursor)
    if message_index[0] != 1:
        return 1
    cursor = message_index[2]
    if cursor >= len(body):
        return 1
    if body[cursor] == 1:
        int64[] signature = read_string_field(body, cursor + 1, 1024)
        if signature[0] != 1:
            return 1
        cursor = signature[2] + signature[1]
    else:
        cursor = cursor + 1
    int64[] message = read_string_field(body, cursor + 8 + 8, 4096)
    if message[0] != 1:
        print("Player chat received")
        return 0
    pl_chat_text("", body, message[2], message[1])
    print("")
    return 0


# --- Terminal-driven Play actions ---
#
# One terminal line becomes one of the serverbound packets produced by the
# encoders above. Parsing works on the raw byte array so the socket poll never
# blocks on input, and an unknown verb falls back to a slash command.

def pl_arg_skip(content: int64[], length: int64, pos: int64) -> int64:
    int64 skip_index = pos
    while skip_index < length:
        int skip_byte = (int)content[skip_index]
        if skip_byte != 32 and skip_byte != 9:
            return skip_index
        skip_index += 1
    return skip_index


def pl_arg_word(content: int64[], length: int64, cursor: int64[]) -> int64[]:
    int64 word_start = pl_arg_skip(content, length, cursor[0])
    int64 word_end = word_start
    while word_end < length:
        int word_byte = (int)content[word_end]
        if word_byte == 32 or word_byte == 9:
            break
        word_end += 1
    cursor[0] = word_end
    int64 word_length = word_end - word_start
    int64[] token = new int64[word_length + 2]
    token[0] = 1
    token[1] = word_length
    int64 word_index = 0
    while word_index < word_length:
        token[word_index + 2] = content[word_start + word_index]
        word_index += 1
    return token


# The remainder of the line as one token, for verbs whose argument is free text
# rather than a single word (a rename, a brand or a partial command).
def pl_arg_rest(content: int64[], length: int64, cursor: int64[]) -> int64[]:
    int64 rest_start = pl_arg_skip(content, length, cursor[0])
    int64 rest_end = length
    while rest_end > rest_start:
        int rest_byte = (int)content[rest_end - 1]
        if rest_byte != 32 and rest_byte != 9:
            break
        rest_end = rest_end - 1
    cursor[0] = length
    int64 rest_length = rest_end - rest_start
    int64[] token = new int64[rest_length + 2]
    token[0] = 1
    token[1] = rest_length
    int64 rest_index = 0
    while rest_index < rest_length:
        token[rest_index + 2] = content[rest_start + rest_index]
        rest_index = rest_index + 1
    return token


def pl_arg_int(content: int64[], length: int64, cursor: int64[]) -> int64[]:
    int64 int_pos = pl_arg_skip(content, length, cursor[0])
    bool int_negative = false
    if int_pos < length and (int)content[int_pos] == 45:
        int_negative = true
        int_pos += 1
    int64 int_value = 0
    int64 int_digits = 0
    while int_pos < length:
        int int_byte = (int)content[int_pos]
        if int_byte < 48 or int_byte > 57:
            break
        int_value = int_value * 10 + (int_byte - 48)
        int_digits += 1
        int_pos += 1
    int64[] int_result = new int64[2]
    if int_digits == 0:
        return int_result
    cursor[0] = int_pos
    int_result[0] = 1
    if int_negative:
        int_result[1] = 0 - int_value
    else:
        int_result[1] = int_value
    return int_result


def pl_arg_double(content: int64[], length: int64, cursor: int64[]) -> double[]:
    double[] real_result = new double[2]
    int64 real_pos = pl_arg_skip(content, length, cursor[0])
    bool real_negative = false
    if real_pos < length and (int)content[real_pos] == 45:
        real_negative = true
        real_pos += 1
    int64 real_whole = 0
    int64 real_digits = 0
    while real_pos < length:
        int real_byte = (int)content[real_pos]
        if real_byte < 48 or real_byte > 57:
            break
        real_whole = real_whole * 10 + (real_byte - 48)
        real_digits += 1
        real_pos += 1
    double real_value = (double) real_whole
    double real_scale = 1.0
    if real_pos < length and (int)content[real_pos] == 46:
        real_pos += 1
        while real_pos < length:
            int frac_byte = (int)content[real_pos]
            if frac_byte < 48 or frac_byte > 57:
                break
            real_scale = real_scale * 10.0
            real_value = real_value + (double) (frac_byte - 48) / real_scale
            real_digits += 1
            real_pos += 1
    if real_digits == 0:
        return real_result
    cursor[0] = real_pos
    real_result[0] = 1
    if real_negative:
        real_result[1] = 0.0 - real_value
    else:
        real_result[1] = real_value
    return real_result


def pl_send_action(socket_handle: int64, packet: int64[], label: str) -> int:
    if send_bytes(socket_handle, packet) != 0:
        print(f"Failed to send {label}")
        return -1
    print(f"{label} sent")
    return 1


# 1 for a verb this function owns, 0 for anything else (the caller then sends
# the line to the server as a slash command), -1 once a send failed.
public def play_terminal_action(socket_handle: int64, state: VPlayState*,
                                content: int64[], length: int64) -> int:
    int64[] action_cursor = new int64[1]
    action_cursor[0] = 1
    int64[] verb = pl_arg_word(content, length, action_cursor)

    if dialog_line_equals(verb, "move"):
        double[] move_x = pl_arg_double(content, length, action_cursor)
        double[] move_y = pl_arg_double(content, length, action_cursor)
        double[] move_z = pl_arg_double(content, length, action_cursor)
        if move_x[0] == 0 or move_y[0] == 0 or move_z[0] == 0:
            print("Usage: /move <x> <y> <z> [rot]")
            return 1
        int64[] move_tail = pl_arg_word(content, length, action_cursor)
        state.x = move_x[1]
        state.y = move_y[1]
        state.z = move_z[1]
        if dialog_line_equals(move_tail, "rot"):
            return pl_send_action(socket_handle,
                encode_move_player_pos_rot(state.x, state.y, state.z,
                                           state.yaw, state.pitch,
                                           state.on_ground, state.vertical,
                                           (int64) state.teleport_id),
                "Position and rotation update")
        return pl_send_action(socket_handle,
            encode_move_player_pos(state.x, state.y, state.z,
                                   state.yaw, state.pitch,
                                   state.on_ground, state.vertical,
                                   (int64) state.teleport_id),
            "Position update")

    if dialog_line_equals(verb, "look"):
        double[] look_yaw = pl_arg_double(content, length, action_cursor)
        double[] look_pitch = pl_arg_double(content, length, action_cursor)
        if look_yaw[0] == 0 or look_pitch[0] == 0:
            print("Usage: /look <yaw> <pitch>")
            return 1
        state.yaw = look_yaw[1]
        state.pitch = look_pitch[1]
        int64[] look_packet = encode_move_player_rot(state.yaw, state.pitch,
                                                     state.on_ground)
        return pl_send_action(socket_handle, look_packet, "Rotation update")

    if dialog_line_equals(verb, "status"):
        int64[] status_tail = pl_arg_word(content, length, action_cursor)
        if dialog_line_equals(status_tail, "air"):
            state.on_ground = false
        elif dialog_line_equals(status_tail, "ground"):
            state.on_ground = true
        int64[] status_packet = encode_move_player_status_only(
            state.on_ground, (int64) state.teleport_id)
        return pl_send_action(socket_handle, status_packet, "Status update")

    if dialog_line_equals(verb, "held"):
        int64[] held_slot = pl_arg_int(content, length, action_cursor)
        if held_slot[0] == 0 or held_slot[1] < 0 or held_slot[1] > 8:
            print("Usage: /held <slot 0-8>")
            return 1
        state.held_slot = (int) held_slot[1]
        int64[] held_packet = encode_set_carried_item(state.held_slot)
        return pl_send_action(socket_handle, held_packet,
                              f"Held slot {state.held_slot}")

    if dialog_line_equals(verb, "use"):
        int64[] use_tail = pl_arg_word(content, length, action_cursor)
        int use_hand = 0
        if dialog_line_equals(use_tail, "off"):
            use_hand = 1
        int64[] use_packet = encode_use_item(use_hand, state.next_chat_seq)
        state.next_chat_seq += 1
        return pl_send_action(socket_handle, use_packet,
                              f"Use item with hand {use_hand}")

    if dialog_line_equals(verb, "attack"):
        int64[] attack_id = pl_arg_int(content, length, action_cursor)
        if attack_id[0] == 0:
            print("Usage: /attack <entity id>")
            return 1
        int64[] attack_packet = encode_attack(attack_id[1])
        return pl_send_action(socket_handle, attack_packet,
                              f"Attack on entity {attack_id[1]}")

    if dialog_line_equals(verb, "interact"):
        int64[] interact_id = pl_arg_int(content, length, action_cursor)
        int64[] interact_kind = pl_arg_word(content, length, action_cursor)
        if interact_id[0] == 0:
            print("Usage: /interact <entity id> [attack|at <x> <y> <z> <face>]")
            return 1
        int interact_action = 0
        if dialog_line_equals(interact_kind, "attack"):
            interact_action = 1
        elif dialog_line_equals(interact_kind, "at"):
            interact_action = 2
        double[] interact_x = pl_arg_double(content, length, action_cursor)
        double[] interact_y = pl_arg_double(content, length, action_cursor)
        double[] interact_z = pl_arg_double(content, length, action_cursor)
        int64[] interact_face = pl_arg_int(content, length, action_cursor)
        double hit_x = 0.0
        double hit_y = 0.0
        double hit_z = 0.0
        int hit_face = 0
        if interact_action == 2:
            if interact_x[0] == 0 or interact_y[0] == 0 or interact_z[0] == 0:
                print("Usage: /interact <id> at <x> <y> <z> <face>")
                return 1
            hit_x = interact_x[1]
            hit_y = interact_y[1]
            hit_z = interact_z[1]
            if interact_face[0] == 1:
                hit_face = (int) interact_face[1]
        int64[] interact_packet = encode_interact(interact_id[1],
                                                  interact_action,
                                                  hit_x, hit_y, hit_z,
                                                  hit_face, false, 0)
        return pl_send_action(socket_handle, interact_packet,
                              f"Interact with entity {interact_id[1]}")

    if dialog_line_equals(verb, "action"):
        int64[] action_kind = pl_arg_word(content, length, action_cursor)
        int64[] action_x = pl_arg_int(content, length, action_cursor)
        int64[] action_y = pl_arg_int(content, length, action_cursor)
        int64[] action_z = pl_arg_int(content, length, action_cursor)
        int64[] action_face = pl_arg_int(content, length, action_cursor)
        int action_status = -1
        if dialog_line_equals(action_kind, "start"):
            action_status = 0
        elif dialog_line_equals(action_kind, "stop"):
            action_status = 1
        elif dialog_line_equals(action_kind, "abort"):
            action_status = 2
        if action_status < 0 or action_x[0] == 0 or action_y[0] == 0 or action_z[0] == 0:
            print("Usage: /action <start|stop|abort> <x> <y> <z> <face>")
            return 1
        int face_value = 0
        if action_face[0] == 1 and action_face[1] >= 0 and action_face[1] <= 5:
            face_value = (int) action_face[1]
        int64 packed = pl_pack_block_pos(action_x[1], action_y[1], action_z[1])
        int64[] action_packet = encode_player_action(action_status, packed,
                                                     face_value,
                                                     state.next_chat_seq)
        state.next_chat_seq += 1
        return pl_send_action(socket_handle, action_packet,
                              f"Block action {action_status}")

    if dialog_line_equals(verb, "command"):
        int64[] command_kind = pl_arg_word(content, length, action_cursor)
        int64[] command_extra = pl_arg_int(content, length, action_cursor)
        int command_action = -1
        if dialog_line_equals(command_kind, "sneak"):
            command_action = 0
        elif dialog_line_equals(command_kind, "unsneak"):
            command_action = 1
        elif dialog_line_equals(command_kind, "land"):
            command_action = 2
        elif dialog_line_equals(command_kind, "sprint"):
            command_action = 3
        elif dialog_line_equals(command_kind, "unsprint"):
            command_action = 4
        elif dialog_line_equals(command_kind, "fly"):
            command_action = 5
        elif dialog_line_equals(command_kind, "jump"):
            command_action = 6
        elif dialog_line_equals(command_kind, "slot"):
            command_action = 7
        if command_action < 0:
            print("Usage: /command <sneak|unsneak|land|sprint|unsprint|fly|jump|slot> [extra]")
            return 1
        int64 extra_value = 0
        if command_extra[0] == 1:
            extra_value = command_extra[1]
        int64[] command_packet = encode_player_command(command_action,
                                                       extra_value)
        return pl_send_action(socket_handle, command_packet,
                              f"Player command {command_action}")

    if dialog_line_equals(verb, "abilities"):
        int64[] ability_kind = pl_arg_word(content, length, action_cursor)
        int64[] ability_state = pl_arg_word(content, length, action_cursor)
        int ability_bit = 0
        if dialog_line_equals(ability_kind, "invulnerable"):
            ability_bit = 1
        elif dialog_line_equals(ability_kind, "flying"):
            ability_bit = 2
        elif dialog_line_equals(ability_kind, "canfly"):
            ability_bit = 4
        elif dialog_line_equals(ability_kind, "creative"):
            ability_bit = 8
        elif dialog_line_equals(ability_kind, "disabledfly"):
            ability_bit = 16
        if ability_bit == 0:
            print("Usage: /abilities <invulnerable|flying|canfly|creative|disabledfly> <on|off> [flying-speed] [fov-modifier]")
            return 1
        if dialog_line_equals(ability_state, "on"):
            state.abilities_flags = state.abilities_flags | ability_bit
        else:
            state.abilities_flags = state.abilities_flags & ~ability_bit
        double[] ability_speed = pl_arg_double(content, length, action_cursor)
        double[] ability_fov = pl_arg_double(content, length, action_cursor)
        if ability_speed[0] == 1:
            state.flying_speed = ability_speed[1]
        if ability_fov[0] == 1:
            state.fov_modifier = ability_fov[1]
        int64[] ability_packet = encode_player_abilities_server(
            state.abilities_flags, state.flying_speed, state.fov_modifier)
        return pl_send_action(socket_handle, ability_packet,
                              f"Abilities {state.abilities_flags}")

    if dialog_line_equals(verb, "settings"):
        int64[] setting_view = pl_arg_int(content, length, action_cursor)
        int64[] setting_chat = pl_arg_int(content, length, action_cursor)
        if setting_view[0] == 0 or setting_view[1] < 1 or setting_view[1] > 32:
            print("Usage: /settings <view distance 1-32> [chat mode 0-2]")
            return 1
        state.view_distance = (int) setting_view[1]
        int chat_mode = 0
        if setting_chat[0] == 1:
            chat_mode = (int) setting_chat[1]
        int64[] setting_packet = encode_client_command_settings(
            state.view_distance, chat_mode)
        return pl_send_action(socket_handle, setting_packet,
                              f"View distance {state.view_distance}")

    if dialog_line_equals(verb, "ack"):
        int64[] ack_count = pl_arg_int(content, length, action_cursor)
        if ack_count[0] == 0:
            print("Usage: /ack <handled message count>")
            return 1
        int64[] ack_packet = encode_chat_ack(state.next_chat_seq, ack_count[1])
        return pl_send_action(socket_handle, ack_packet, "Chat acknowledgement")

    # The screen-driven packets (sign, book, command block, jigsaw, structure,
    # test instance, game rules) and the two chat-signing packets have encoders
    # but no verb here: a headless terminal has no editor to drive them, and a
    # local account has no profile key to sign with.

    if dialog_line_equals(verb, "tick"):
        return pl_send_action(socket_handle, encode_client_tick_end(), "Client tick end")

    if dialog_line_equals(verb, "punch"):
        return pl_send_action(socket_handle, encode_punch(), "Punch")

    if dialog_line_equals(verb, "ping"):
        int64 ping_time = mc_time_millis()
        return pl_send_action(socket_handle, encode_play_ping_request(ping_time), "Play ping request")

    if dialog_line_equals(verb, "input"):
        int64[] input_flags = pl_arg_int(content, length, action_cursor)
        if input_flags[0] == 0 or input_flags[1] < 0 or input_flags[1] > 127:
            print("Usage: /input <flags 0-127> forward 1, backward 2, left 4, right 8, jump 16, shift 32, sprint 64")
            return 1
        return pl_send_action(socket_handle, encode_player_input((int)input_flags[1]), f"Player input {input_flags[1]}")

    if dialog_line_equals(verb, "paddle"):
        int64[] paddle_side = pl_arg_word(content, length, action_cursor)
        bool paddle_left = false
        bool paddle_right = false
        if dialog_line_equals(paddle_side, "left"):
            paddle_left = true
        elif dialog_line_equals(paddle_side, "right"):
            paddle_right = true
        elif dialog_line_equals(paddle_side, "both"):
            paddle_left = true
            paddle_right = true
        elif not dialog_line_equals(paddle_side, "none"):
            print("Usage: /paddle <left|right|both|none>")
            return 1
        return pl_send_action(socket_handle, encode_paddle_boat(paddle_left, paddle_right), "Paddle state")

    if dialog_line_equals(verb, "vehicle"):
        double[] vehicle_x = pl_arg_double(content, length, action_cursor)
        double[] vehicle_y = pl_arg_double(content, length, action_cursor)
        double[] vehicle_z = pl_arg_double(content, length, action_cursor)
        double[] vehicle_yaw = pl_arg_double(content, length, action_cursor)
        double[] vehicle_pitch = pl_arg_double(content, length, action_cursor)
        if vehicle_x[0] == 0 or vehicle_y[0] == 0 or vehicle_z[0] == 0:
            print("Usage: /vehicle <x> <y> <z> [yaw] [pitch]")
            return 1
        double vehicle_yaw_value = state.yaw
        double vehicle_pitch_value = state.pitch
        if vehicle_yaw[0] == 1:
            vehicle_yaw_value = vehicle_yaw[1]
        if vehicle_pitch[0] == 1:
            vehicle_pitch_value = vehicle_pitch[1]
        return pl_send_action(socket_handle, encode_move_vehicle(vehicle_x[1], vehicle_y[1], vehicle_z[1], vehicle_yaw_value, vehicle_pitch_value, state.on_ground), "Vehicle movement")

    if dialog_line_equals(verb, "difficulty"):
        int64[] difficulty_level = pl_arg_int(content, length, action_cursor)
        if difficulty_level[0] == 0 or difficulty_level[1] < 0 or difficulty_level[1] > 3:
            print("Usage: /difficulty <0-3> [lock]")
            return 1
        state.difficulty = (int)difficulty_level[1]
        int64[] difficulty_tail = pl_arg_word(content, length, action_cursor)
        int difficulty_result = pl_send_action(socket_handle, encode_change_difficulty(state.difficulty), f"Difficulty {state.difficulty}")
        if difficulty_result < 0:
            return -1
        if dialog_line_equals(difficulty_tail, "lock"):
            state.difficulty_locked = true
            return pl_send_action(socket_handle, encode_lock_difficulty(true), "Difficulty lock")
        return 1

    if dialog_line_equals(verb, "gamemode"):
        int64[] mode_value = pl_arg_int(content, length, action_cursor)
        if mode_value[0] == 0 or mode_value[1] < 0 or mode_value[1] > 3:
            print("Usage: /gamemode <0-3> survival, creative, adventure, spectator")
            return 1
        return pl_send_action(socket_handle, encode_change_game_mode((int)mode_value[1]), f"Game mode request {mode_value[1]}")

    if dialog_line_equals(verb, "spectate"):
        int64[] spectate_id = pl_arg_int(content, length, action_cursor)
        int64 spectate_target = (int64)-1
        if spectate_id[0] == 1:
            spectate_target = spectate_id[1]
        return pl_send_action(socket_handle, encode_spectator_action(spectate_target), "Spectator action")

    if dialog_line_equals(verb, "pick"):
        int64[] pick_kind = pl_arg_word(content, length, action_cursor)
        if dialog_line_equals(pick_kind, "block"):
            int64[] pick_x = pl_arg_int(content, length, action_cursor)
            int64[] pick_y = pl_arg_int(content, length, action_cursor)
            int64[] pick_z = pl_arg_int(content, length, action_cursor)
            if pick_x[0] == 0 or pick_y[0] == 0 or pick_z[0] == 0:
                print("Usage: /pick block <x> <y> <z> [data]")
                return 1
            int64[] pick_tail = pl_arg_word(content, length, action_cursor)
            return pl_send_action(socket_handle, encode_pick_item_from_block(pick_x[1], pick_y[1], pick_z[1], dialog_line_equals(pick_tail, "data")), "Pick item from block")
        if dialog_line_equals(pick_kind, "entity"):
            int64[] pick_id = pl_arg_int(content, length, action_cursor)
            if pick_id[0] == 0:
                print("Usage: /pick entity <id> [data]")
                return 1
            int64[] pick_tail = pl_arg_word(content, length, action_cursor)
            return pl_send_action(socket_handle, encode_pick_item_from_entity(pick_id[1], dialog_line_equals(pick_tail, "data")), "Pick item from entity")
        print("Usage: /pick <block|entity> ...")
        return 1

    if dialog_line_equals(verb, "useon"):
        int64[] useon_x = pl_arg_int(content, length, action_cursor)
        int64[] useon_y = pl_arg_int(content, length, action_cursor)
        int64[] useon_z = pl_arg_int(content, length, action_cursor)
        int64[] useon_face = pl_arg_int(content, length, action_cursor)
        if useon_x[0] == 0 or useon_y[0] == 0 or useon_z[0] == 0 or useon_face[0] == 0:
            print("Usage: /useon <x> <y> <z> <face 0-5> [hand 0-1] [cx cy cz]")
            return 1
        if useon_face[1] < 0 or useon_face[1] > 5:
            print("Face must be 0-5: down, up, north, south, west, east")
            return 1
        int64[] useon_hand = pl_arg_int(content, length, action_cursor)
        int useon_hand_value = 0
        if useon_hand[0] == 1 and useon_hand[1] == 1:
            useon_hand_value = 1
        double[] useon_cx = pl_arg_double(content, length, action_cursor)
        double[] useon_cy = pl_arg_double(content, length, action_cursor)
        double[] useon_cz = pl_arg_double(content, length, action_cursor)
        double useon_click_x = 0.5
        double useon_click_y = 0.5
        double useon_click_z = 0.5
        if useon_cx[0] == 1:
            useon_click_x = useon_cx[1]
        if useon_cy[0] == 1:
            useon_click_y = useon_cy[1]
        if useon_cz[0] == 1:
            useon_click_z = useon_cz[1]
        int64[] useon_packet = encode_use_item_on(useon_hand_value, useon_x[1], useon_y[1], useon_z[1], (int)useon_face[1], useon_click_x, useon_click_y, useon_click_z, false, false, state.next_chat_seq)
        state.next_chat_seq += 1
        return pl_send_action(socket_handle, useon_packet, "Use item on block")

    if dialog_line_equals(verb, "suggest"):
        int64[] suggest_text = pl_arg_rest(content, length, action_cursor)
        int64[] suggest_packet = encode_command_suggestion(state.next_chat_seq, suggest_text, 2, suggest_text[1])
        state.next_chat_seq += 1
        return pl_send_action(socket_handle, suggest_packet, "Command suggestion request")

    if dialog_line_equals(verb, "query"):
        int64[] query_kind = pl_arg_word(content, length, action_cursor)
        if dialog_line_equals(query_kind, "entity"):
            int64[] query_id = pl_arg_int(content, length, action_cursor)
            if query_id[0] == 0:
                print("Usage: /query entity <id>")
                return 1
            int64[] query_packet = encode_entity_tag_query(state.next_chat_seq, query_id[1])
            state.next_chat_seq += 1
            return pl_send_action(socket_handle, query_packet, "Entity tag query")
        if dialog_line_equals(query_kind, "block"):
            int64[] query_x = pl_arg_int(content, length, action_cursor)
            int64[] query_y = pl_arg_int(content, length, action_cursor)
            int64[] query_z = pl_arg_int(content, length, action_cursor)
            if query_x[0] == 0 or query_y[0] == 0 or query_z[0] == 0:
                print("Usage: /query block <x> <y> <z>")
                return 1
            int64[] query_packet = encode_block_entity_tag_query(state.next_chat_seq, query_x[1], query_y[1], query_z[1])
            state.next_chat_seq += 1
            return pl_send_action(socket_handle, query_packet, "Block entity tag query")
        print("Usage: /query <entity|block> ...")
        return 1

    if dialog_line_equals(verb, "subscribe"):
        int64[] sub_ids = new int64[32]
        int64 sub_count = 0
        while sub_count < 32:
            int64[] sub_id = pl_arg_int(content, length, action_cursor)
            if sub_id[0] == 0:
                break
            if sub_id[1] < 0 or sub_id[1] > 15:
                print("Debug subscription ids run 0-15")
                return 1
            sub_ids[sub_count] = sub_id[1]
            sub_count = sub_count + 1
        if sub_count == 0:
            print("Usage: /subscribe <id 0-15> [more ids]")
            return 1
        return pl_send_action(socket_handle, encode_debug_subscription_request(sub_ids, sub_count), f"Debug subscriptions {sub_count}")

    if dialog_line_equals(verb, "advancements"):
        int64[] adv_action = pl_arg_word(content, length, action_cursor)
        int adv_action_value = 1
        if dialog_line_equals(adv_action, "opened"):
            adv_action_value = 0
        elif not dialog_line_equals(adv_action, "closed"):
            print("Usage: /advancements <opened|closed> [tab id]")
            return 1
        int64[] adv_tab = pl_arg_rest(content, length, action_cursor)
        if adv_action_value == 0 and adv_tab[1] == 0:
            print("Usage: /advancements opened <tab id>")
            return 1
        return pl_send_action(socket_handle, encode_seen_advancements(adv_action_value, adv_tab, 2, adv_tab[1]), "Advancements seen")

    if dialog_line_equals(verb, "rename"):
        int64[] rename_text = pl_arg_rest(content, length, action_cursor)
        return pl_send_action(socket_handle, encode_rename_item(rename_text, 2, rename_text[1]), "Item rename")

    if dialog_line_equals(verb, "brand"):
        int64[] brand_text = pl_arg_rest(content, length, action_cursor)
        return pl_send_action(socket_handle, encode_client_brand(brand_text, 2, brand_text[1]), "Client brand")

    if dialog_line_equals(verb, "info"):
        int64[] info_language = sb_default_language()
        int64[] info_packet = encode_client_information(info_language, 0, 5, state.view_distance, 0, true, 127, 1, false, true, 0)
        return pl_send_action(socket_handle, info_packet, "Client information")

    if dialog_line_equals(verb, "beacon"):
        int64[] beacon_primary = pl_arg_int(content, length, action_cursor)
        int64[] beacon_secondary = pl_arg_int(content, length, action_cursor)
        int64 beacon_primary_value = (int64)-1
        int64 beacon_secondary_value = (int64)-1
        if beacon_primary[0] == 1:
            beacon_primary_value = beacon_primary[1]
        if beacon_secondary[0] == 1:
            beacon_secondary_value = beacon_secondary[1]
        return pl_send_action(socket_handle, encode_set_beacon(beacon_primary_value, beacon_secondary_value), "Beacon effects")

    if dialog_line_equals(verb, "generate"):
        int64[] gen_x = pl_arg_int(content, length, action_cursor)
        int64[] gen_y = pl_arg_int(content, length, action_cursor)
        int64[] gen_z = pl_arg_int(content, length, action_cursor)
        int64[] gen_levels = pl_arg_int(content, length, action_cursor)
        if gen_x[0] == 0 or gen_y[0] == 0 or gen_z[0] == 0:
            print("Usage: /generate <x> <y> <z> [levels] [keep]")
            return 1
        int64 gen_level_value = 7
        if gen_levels[0] == 1:
            gen_level_value = gen_levels[1]
        int64[] gen_tail = pl_arg_word(content, length, action_cursor)
        return pl_send_action(socket_handle, encode_jigsaw_generate(gen_x[1], gen_y[1], gen_z[1], gen_level_value, dialog_line_equals(gen_tail, "keep")), "Jigsaw generation")

    if dialog_line_equals(verb, "state"):
        print(f"Position {state.x}, {state.y}, {state.z} yaw {state.yaw} pitch {state.pitch}")
        print(f"Health {state.health} food {state.food} level {state.xp_level} game mode {state.game_mode}")
        print(f"Abilities {state.abilities_flags} held {state.held_slot} teleport id {state.teleport_id}")
        return 1

    return 0


# The renderer, when one is linked, is driven from here rather than the other
# way round: this publishes the player's view into the engine's mailbox and the
# renderer's pump turns each publish into a frame. The return is the mailbox
# reporting that its window has been closed, which ends the session the way
# /quit does. With no renderer attached the publish is a store and the answer
# is always 0, so a headless run costs nothing and links nothing.
def pl_publish_view(state: VPlayState*) -> int64:
    return vt_publish_view(state.x, state.y, state.z, state.yaw, state.pitch,
                           (double)state.world_time, state.health, state.food,
                           state.saturation, state.xp_progress,
                           (double)state.xp_level, state.held_slot,
                           state.game_mode, state.view_distance)


# Every table the session built is freed on the way out, whether the player
# typed /quit or the renderer's window was closed.
def pl_leave_play(state: VPlayState*) -> void:
    ventities_free(state.entities)
    vboss_free(state.boss_bars)
    vscore_free(state.scoreboard)
    vcmd_free(state.commands)
    vfx_free(state.effects)
    vat_free(state.attributes)
    vplayers_free(state.players)
    vbes_free(state.block_entities)
    vparts_free(state.particles)
    vinv_free(state.inventory)
    vborder_free(state.border)
    vrecipe_free(state.recipes)
    vtags_free(state.tags)
    vadv_free(state.advancements)
    vmeta_free(state.meta)
    vdebug_free(state.debug)


# --- Full Play session loop with all packet dispatch ---

public def play_session_loop(socket_handle: int64, world: VWorld*,
                             registry: VDimensionRegistry*) -> int:
    int64[] tracked_chunks_x = new int64[8192]
    int64[] tracked_chunks_z = new int64[8192]
    int64 tracked_chunk_count = 0
    int64 packet_count = 0
    bool received_play_login = false
    VPlayState* state = new VPlayState
    state.entities = ventities_new()
    state.boss_bars = vboss_new()
    state.scoreboard = vscore_new()
    state.commands = vcmd_new()
    state.effects = vfx_new()
    state.attributes = vat_new()
    state.players = vplayers_new()
    state.block_entities = vbes_new()
    state.particles = vparts_new()
    state.inventory = vinv_new()
    state.border = vborder_new()
    state.recipes = vrecipe_new()
    state.tags = vtags_new()
    state.advancements = vadv_new()
    state.meta = vmeta_new()
    state.debug = vdebug_new()
    state.health = 20.0
    state.food = 20.0
    state.saturation = 5.0
    state.game_mode = 0
    state.view_distance = 8
    state.simulation_distance = 5
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
                pl_leave_play(state)
                return 0
            if line_length > 256:
                print("Chat and command input is limited to 256 UTF-8 bytes")
            elif line_length > 0 and mc_stdin_line_byte(0) == 47:
                if line_length == 1:
                    print("Command cannot be empty")
                else:
                    int64[] command_line = new int64[line_length]
                    int64 cmd_index = 0
                    while cmd_index < line_length:
                        command_line[cmd_index] = mc_stdin_line_byte(cmd_index)
                        cmd_index = cmd_index + 1
                    int action_result = play_terminal_action(
                        socket_handle, state, command_line, line_length)
                    if action_result == -1:
                        mc_stdin_line_done()
                        return 1
                    if action_result == 0:
                        int64[] command_packet = encode_chat_command(command_line, line_length - 1)
                        if send_bytes(socket_handle, command_packet) != 0:
                            print("Failed to send chat command")
                            return 1
                        print("Command sent")
            elif line_length > 0:
                int64[] chat_line = new int64[line_length]
                int64 chat_index = 0
                while chat_index < line_length:
                    chat_line[chat_index] = mc_stdin_line_byte(chat_index)
                    chat_index = chat_index + 1
                int64 timestamp = mc_time_millis()
                if timestamp < 0:
                    print("Could not read system clock for chat message")
                    return 1
                int64[] chat_packet = encode_chat_message(chat_line, line_length, timestamp)
                if send_bytes(socket_handle, chat_packet) != 0:
                    print("Failed to send chat message")
                    return 1
                print("Chat message sent without a secure-chat signature")
                pl_chat_tee("<you>", chat_line, line_length)
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
        int64 pid = packet_id[1]
        int64 off = packet_id[2]
        if pid == pid_pl_c_login():
            int64[] dimension_type = read_play_login_dimension(body, off)
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
            vworld_set_dimension_id(world, (int)dimension_type[1])
            received_play_login = true
            int64[] player_loaded = new int64[0]
            int64[] response = encode_packet_frame(pid_pl_s_player_loaded(), player_loaded)
            if send_bytes(socket_handle, response) != 0:
                print("Failed to acknowledge Play login")
                return 1
            print("Play login accepted; type chat, /command, or /quit")
            if send_bytes(socket_handle,
                          encode_client_command_settings(state.view_distance,
                                                         0)) != 0:
                print("Failed to send the initial client settings")
                return 1
        elif pid == pid_pl_c_keep_alive():
            if len(body) != off + 8:
                print("Malformed Play keep-alive")
                return 1
            int64[] ka_response = encode_keepalive_response(pid_pl_s_keep_alive(), body, off)
            if send_bytes(socket_handle, ka_response) != 0:
                print("Failed to respond to Play keep-alive")
                return 1
        elif pid == pid_pl_c_ping():
            if len(body) != off + 4:
                print("Malformed Play ping")
                return 1
            int64[] pong_payload = new int64[4]
            int64 ping_idx = 0
            while ping_idx < 4:
                pong_payload[ping_idx] = body[off + ping_idx]
                ping_idx = ping_idx + 1
            int64[] pong = encode_packet_frame(pid_pl_s_pong(), pong_payload)
            if send_bytes(socket_handle, pong) != 0:
                print("Failed to answer Play ping")
                return 1
        elif pid == pid_pl_c_player_position():
            int64[] teleport_id = decode_varint(body, off)
            int64 position_start = teleport_id[2]
            if teleport_id[0] != 1 or position_start + 60 != len(body):
                print("Malformed Play player-position update")
                return 1
            state.x = decode_be_int64(body, position_start)
            state.y = decode_be_int64(body, position_start + 8)
            state.z = decode_be_int64(body, position_start + 16)
            state.yaw = decode_be_float(body, position_start + 48)
            state.pitch = decode_be_float(body, position_start + 52)
            state.teleport_id = (int)teleport_id[1]
            int64[] encoded_id = encode_varint(teleport_id[1])
            int64[] payload = new int64[len(encoded_id) + 32]
            int64 tp_idx = 0
            while tp_idx < len(encoded_id):
                payload[tp_idx] = encoded_id[tp_idx]
                tp_idx = tp_idx + 1
            int64 output_index = len(encoded_id)
            tp_idx = 0
            while tp_idx < 8:
                payload[output_index + tp_idx] = mc_double_be_byte(state.x, tp_idx)
                payload[output_index + (8 + tp_idx)] = mc_double_be_byte(state.y, tp_idx)
                payload[output_index + (16 + tp_idx)] = mc_double_be_byte(state.z, tp_idx)
                tp_idx = tp_idx + 1
            tp_idx = 0
            while tp_idx < 4:
                payload[output_index + (24 + tp_idx)] = mc_float_be_byte(state.yaw, tp_idx)
                tp_idx = tp_idx + 1
            tp_idx = 0
            while tp_idx < 4:
                payload[output_index + (28 + tp_idx)] = mc_float_be_byte(state.pitch, tp_idx)
                tp_idx = tp_idx + 1
            int64[] tp_ack = encode_packet_frame(pid_pl_s_accept_teleportation(), payload)
            if send_bytes(socket_handle, tp_ack) != 0:
                print("Failed to acknowledge player teleport")
                return 1
        elif pid == pid_pl_c_level_chunk_with_light():
            if off + 8 > len(body):
                print("Truncated chunk-with-light packet")
                return 1
            int64 chunk_x = decode_be_int32(body, off)
            int64 chunk_z = decode_be_int32(body, off + 4)
            if decode_chunk_sections(world, body, off) != 0:
                print("Could not decode incoming chunk data")
                return 1
            bool found_chunk = false
            int64 chunk_idx = 0
            while chunk_idx < tracked_chunk_count:
                if tracked_chunks_x[chunk_idx] == chunk_x and tracked_chunks_z[chunk_idx] == chunk_z:
                    found_chunk = true
                    break
                chunk_idx = chunk_idx + 1
            if not found_chunk and tracked_chunk_count < 8192:
                tracked_chunks_x[tracked_chunk_count] = chunk_x
                tracked_chunks_z[tracked_chunk_count] = chunk_z
                tracked_chunk_count = tracked_chunk_count + 1
            if not found_chunk:
                print(f"Stored chunk ({chunk_x}, {chunk_z}); loaded chunk count: {tracked_chunk_count}")
            mesh_chunk_native(world, (int)chunk_x, (int)chunk_z)
        elif pid == pid_pl_c_forget_level_chunk():
            if off + 8 > len(body):
                print("Truncated chunk-unload packet")
                return 1
            int64 forget_x = decode_be_int32(body, off)
            int64 forget_z = decode_be_int32(body, off + 4)
            int64 forget_idx = 0
            while forget_idx < tracked_chunk_count:
                if tracked_chunks_x[forget_idx] == forget_x and tracked_chunks_z[forget_idx] == forget_z:
                    int64 source_index = forget_idx + 1
                    while source_index < tracked_chunk_count:
                        tracked_chunks_x[source_index - 1] = tracked_chunks_x[source_index]
                        tracked_chunks_z[source_index - 1] = tracked_chunks_z[source_index]
                        source_index = source_index + 1
                    tracked_chunk_count = tracked_chunk_count - 1
                    break
                forget_idx = forget_idx + 1
            vworld_unload_chunk(world, (int)forget_x, (int)forget_z)
            print(f"Forgot chunk ({forget_x}, {forget_z})")
        elif pid == pid_pl_c_add_entity():
            if pl_handle_spawn_entity(body, off, state.entities) != 0:
                print("Malformed entity spawn packet")
                return 1
        elif pid == pid_pl_c_remove_entities():
            if pl_handle_remove_entities(body, off, state.entities,
                                         state.effects,
                                         state.attributes) != 0:
                print("Malformed entity-removal packet")
                return 1
        elif pid == pid_pl_c_chunk_batch_finished():
            int64[] batch_size = decode_varint(body, off)
            if batch_size[0] != 1 or batch_size[2] != len(body):
                print("Malformed chunk-batch-finished packet")
                return 1
            int64[] batch_payload = new int64[4]
            batch_payload[0] = 66
            batch_payload[1] = 128
            batch_payload[2] = 0
            batch_payload[3] = 0
            int64[] batch_ack = encode_packet_frame(pid_pl_s_chunk_batch_received(), batch_payload)
            if send_bytes(socket_handle, batch_ack) != 0:
                print("Failed to acknowledge chunk batch")
                return 1
            print(f"Chunk batch {batch_size[1]} processed; tracked chunks: {tracked_chunk_count}")
        elif pid == pid_pl_c_chunk_batch_start():
            int64[] batch_size_start = decode_varint(body, off)
            if batch_size_start[0] != 1 or batch_size_start[2] != len(body):
                return 1
        elif pid == pid_pl_c_system_chat():
            if print_system_chat(body, off) != 0:
                return 1
        elif pid == pid_pl_c_player_chat():
            if pl_handle_player_chat(body, off) != 0:
                print("Malformed player chat packet")
                return 1
        elif pid == pid_pl_c_disguised_chat():
            int64[] hidden_message = new int64[64]
            int64[] hidden_sender = new int64[64]
            int64[] hidden_target = new int64[64]
            if pl_handle_disguised_chat(body, off, hidden_message,
                                        hidden_sender, hidden_target) != 0:
                return 1
        elif pid == pid_pl_c_commands():
            if pl_handle_commands(body, off, state.commands) != 0:
                return 1
        elif pid == pid_pl_c_show_dialog():
            if handle_configuration_dialog(socket_handle, body, off, true) != 0:
                print("Could not process the Play dialog")
                return 1
        elif pid == pid_pl_c_clear_dialog():
            print("Server cleared the active Play dialog")
        elif pid == pid_pl_c_disconnect():
            int64[] reason = read_string_field(body, off, 262144)
            if reason[0] == 1:
                print("Server disconnected during Play:")
                int64 r_idx = reason[2]
                while r_idx < reason[2] + reason[1] and r_idx < len(body):
                    mc_write_byte(body[r_idx])
                    r_idx = r_idx + 1
                print("")
            else:
                print("Server disconnected during Play")
            return 0
        elif pid == pid_pl_c_start_configuration():
            print("Server requested a return to Configuration")
            int64[] empty_payload = new int64[0]
            int64[] config_ack = encode_packet_frame(pid_pl_s_configuration_acknowledged(), empty_payload)
            if send_bytes(socket_handle, config_ack) != 0:
                print("Failed to acknowledge the configuration transition")
                return 1
            received_play_login = false
            return 2
        elif pid == pid_pl_c_set_health():
            if pl_handle_set_health(socket_handle, body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_set_experience():
            if pl_handle_set_experience(socket_handle, body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_player_abilities():
            if pl_handle_player_abilities(socket_handle, body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_set_held_slot():
            if pl_handle_set_held_slot(socket_handle, body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_set_time():
            if pl_handle_set_time(socket_handle, body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_respawn():
            if pl_handle_respawn(socket_handle, body, off, state, registry) != 0:
                return 1
        elif pid == pid_pl_c_game_event():
            if pl_handle_game_event(socket_handle, body, off) != 0:
                return 1
        elif pid == pid_pl_c_set_simulation_distance():
            if pl_handle_simulation_distance(socket_handle, body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_player_info_update():
            int64[] listed_display = new int64[64]
            if pl_handle_player_info_update(socket_handle, body, off,
                                            state.players, listed_display) != 0:
                return 1
        elif pid == pid_pl_c_set_default_spawn_position():
            if pl_handle_set_default_spawn(socket_handle, body, off) != 0:
                return 1
        elif pid == pid_pl_c_block_update():
            if handle_block_update(world, body, off) != 0:
                return 1
            remesh_block_position(world, decode_be_i64(body, off))
        elif pid == pid_pl_c_section_blocks_update():
            if handle_section_blocks_update(world, body, off) != 0:
                return 1
            remesh_section_position(world, decode_be_i64(body, off))
        elif pid == pid_pl_c_light_update():
            if handle_light_update(world, body, off) != 0:
                return 1
            int64[] light_cx = decode_varint(body, off)
            int64[] light_cz = decode_varint(body, light_cx[2])
            if light_cx[0] == 1 and light_cz[0] == 1:
                mesh_chunk_native(world, (int)light_cx[1], (int)light_cz[1])
        elif pid == pid_pl_c_move_entity_pos() or pid == pid_pl_c_move_entity_pos_rot():
            int mode = 1
            if pid == pid_pl_c_move_entity_pos_rot():
                mode = 2
            if pl_handle_entity_position(socket_handle, body, off, mode, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_move_vehicle():
            if pl_handle_entity_position(socket_handle, body, off, 0, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_teleport_entity():
            if pl_handle_entity_position(socket_handle, body, off, 3, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_entity_position_sync():
            if pl_handle_entity_position(socket_handle, body, off, 4, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_rotate_head():
            if pl_handle_rotate_head(socket_handle, body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_block_event():
            if pl_handle_block_event(socket_handle, body, off) != 0:
                return 1
        elif pid == pid_pl_c_block_entity_data():
            if pl_handle_block_entity_data(socket_handle, body, off,
                                             state.block_entities) != 0:
                return 1
        elif pid == pid_pl_c_set_entity_motion():
            if pl_handle_set_entity_motion(socket_handle, body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_set_passengers():
            if pl_handle_set_passengers(socket_handle, body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_swing_animation():
            if pl_handle_swing_animation(socket_handle, body, off) != 0:
                return 1
        elif pid == pid_pl_c_sound():
            if pl_handle_sound(socket_handle, body, off, false) != 0:
                return 1
        elif pid == pid_pl_c_sound_entity():
            if pl_handle_sound(socket_handle, body, off, true) != 0:
                return 1
        elif pid == pid_pl_c_level_particles():
            if pl_handle_level_particles(socket_handle, body, off,
                                           state.particles) != 0:
                return 1
        elif pid == pid_pl_c_explode():
            if pl_handle_explode(socket_handle, body, off, world) != 0:
                return 1
        elif pid == pid_pl_c_set_title_text():
            if pl_handle_title(socket_handle, body, off, "Title") != 0:
                return 1
        elif pid == pid_pl_c_set_action_bar_text():
            if pl_handle_title(socket_handle, body, off, "Action bar") != 0:
                return 1
        elif pid == pid_pl_c_set_subtitle_text():
            if pl_handle_title(socket_handle, body, off, "Subtitle") != 0:
                return 1
        elif pid == pid_pl_c_tab_list():
            int64[] tab_header = new int64[64]
            int64[] tab_footer = new int64[64]
            if pl_handle_tab_list(socket_handle, body, off, state.players,
                                     tab_header, tab_footer) != 0:
                return 1
        elif pid == pid_pl_c_update_attributes():
            if pl_handle_update_attributes(socket_handle, body, off,
                                           state.attributes) != 0:
                return 1
        elif pid == pid_pl_c_change_difficulty():
            if pl_handle_change_difficulty(socket_handle, body, off,
                                           state) != 0:
                return 1
        elif pid == pid_pl_c_transfer():
            if pl_handle_transfer(socket_handle, body, off) != 0:
                return 1
        elif pid == pid_pl_c_set_camera():
            if pl_handle_set_camera(socket_handle, body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_ticking_state():
            if pl_handle_set_ticking_state(socket_handle, body, off,
                                          state) != 0:
                return 1
        elif pid == pid_pl_c_server_data():
            int64[] listed_motd = new int64[64]
            if pl_handle_server_data(body, off, listed_motd) != 0:
                return 1
        elif pid == pid_pl_c_boss_event():
            if pl_handle_boss_event(body, off, state.boss_bars) != 0:
                print("Malformed boss event packet")
                return 1
        elif pid == pid_pl_c_bundle_delimiter():
            print("Bundle delimiter")
        elif pid == pid_pl_c_player_info_remove():
            if pl_handle_player_info_remove(body, off, state.players) != 0:
                return 1
        elif pid == pid_pl_c_hurt_animation():
            if pl_handle_set_entity_motion(socket_handle, body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_set_entity_data():
            if pl_handle_entity_metadata(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_set_equipment():
            if pl_handle_set_equipment(body, off, state.inventory) != 0:
                print("Malformed entity equipment packet")
                return 1
        elif pid == pid_pl_c_container_set_slot():
            if pl_handle_container_set_slot(body, off, state.inventory) != 0:
                return 1
        elif pid == pid_pl_c_container_set_content():
            if pl_handle_container_set_content(body, off, state.inventory) != 0:
                return 1
        elif pid == pid_pl_c_set_player_inventory():
            if pl_handle_set_player_inventory(body, off, state.inventory) != 0:
                return 1
        elif pid == pid_pl_c_open_screen():
            if pl_handle_open_screen(body, off, state.inventory) != 0:
                return 1
        elif pid == pid_pl_c_container_close():
            if pl_handle_container_close(body, off, state.inventory) != 0:
                return 1
        elif pid == pid_pl_c_container_set_data():
            if pl_handle_container_set_data(body, off, state.inventory) != 0:
                return 1
        elif pid == pid_pl_c_set_cursor_item():
            if pl_handle_set_cursor_item(body, off, state.inventory) != 0:
                return 1
        elif pid == pid_pl_c_update_mob_effect():
            if pl_handle_update_mob_effect(body, off, state.effects) != 0:
                return 1
        elif pid == pid_pl_c_remove_mob_effect():
            if pl_handle_remove_mob_effect(body, off, state.effects) != 0:
                return 1
        elif pid == pid_pl_c_level_event():
            if pl_handle_level_event(body, off) != 0:
                return 1
        elif pid == pid_pl_c_set_titles_animation():
            if pl_handle_titles_animation(body, off) != 0:
                return 1
        elif pid == pid_pl_c_clear_titles():
            if off >= len(body):
                return 1
            print("Titles cleared")
        elif pid == pid_pl_c_add_transient_block():
            if pl_handle_add_transient_block(body, off) != 0:
                return 1
        elif pid == pid_pl_c_set_objective():
            if pl_handle_set_objective(body, off, state.scoreboard) != 0:
                return 1
        elif pid == pid_pl_c_set_score():
            if pl_handle_set_score(body, off, state.scoreboard) != 0:
                return 1
        elif pid == pid_pl_c_reset_score():
            if pl_handle_reset_score(body, off, state.scoreboard) != 0:
                return 1
        elif pid == pid_pl_c_set_display_objective():
            if pl_handle_set_display_objective(body, off, state.scoreboard) != 0:
                return 1
        elif pid == pid_pl_c_set_player_team():
            if pl_handle_set_player_team(body, off, state.scoreboard) != 0:
                return 1
        elif pid == pid_pl_c_animate():
            if pl_handle_animate(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_award_stats():
            if pl_handle_award_stats(body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_block_changed_ack():
            if pl_handle_block_changed_ack(body, off) != 0:
                return 1
        elif pid == pid_pl_c_block_destruction():
            if pl_handle_block_destruction(body, off) != 0:
                return 1
        elif pid == pid_pl_c_chunks_biomes():
            if pl_handle_chunks_biomes(body, off, world) != 0:
                return 1
        elif pid == pid_pl_c_command_suggestions():
            if pl_handle_command_suggestions(body, off, state.commands) != 0:
                return 1
        elif pid == pid_pl_c_cookie_request():
            if pl_handle_cookie_request(socket_handle, body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_cooldown():
            if pl_handle_cooldown(body, off, state.meta, state.world_time) != 0:
                return 1
        elif pid == pid_pl_c_custom_chat_completions():
            if pl_handle_custom_chat_completions(body, off, state.commands) != 0:
                return 1
        elif pid == pid_pl_c_custom_payload():
            if pl_handle_custom_payload(body, off) != 0:
                return 1
        elif pid == pid_pl_c_damage_event():
            if pl_handle_damage_event(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_debug_block_value():
            if pl_handle_debug_block_value(body, off, state.debug) != 0:
                return 1
        elif pid == pid_pl_c_debug_chunk_value():
            if pl_handle_debug_chunk_value(body, off, state.debug) != 0:
                return 1
        elif pid == pid_pl_c_debug_entity_value():
            if pl_handle_debug_entity_value(body, off, state.debug) != 0:
                return 1
        elif pid == pid_pl_c_debug_event():
            if pl_handle_debug_event(body, off, state.debug) != 0:
                return 1
        elif pid == pid_pl_c_debug_sample():
            if pl_handle_debug_sample(body, off) != 0:
                return 1
        elif pid == pid_pl_c_delete_chat():
            if pl_handle_delete_chat(body, off) != 0:
                return 1
        elif pid == pid_pl_c_entity_event():
            if pl_handle_entity_event(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_game_rule_values():
            if pl_handle_game_rule_values(body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_game_test_highlight_pos():
            if pl_handle_game_test_highlight_pos(body, off) != 0:
                return 1
        elif pid == pid_pl_c_mount_screen_open():
            if pl_handle_mount_screen_open(body, off, state.inventory) != 0:
                return 1
        elif pid == pid_pl_c_initialize_border():
            if pl_handle_initialize_border(body, off, state.border) != 0:
                return 1
        elif pid == pid_pl_c_low_disk_space_warning():
            if pl_handle_low_disk_space_warning(body, off) != 0:
                return 1
        elif pid == pid_pl_c_map_item_data():
            if pl_handle_map_item_data(body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_merchant_offers():
            if pl_handle_merchant_offers(body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_move_minecart_along_track():
            if pl_handle_move_minecart_along_track(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_move_entity_rot():
            if pl_handle_move_entity_rot(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_open_book():
            if pl_handle_open_book(body, off) != 0:
                return 1
        elif pid == pid_pl_c_open_sign_editor():
            if pl_handle_open_sign_editor(body, off) != 0:
                return 1
        elif pid == pid_pl_c_pong_response():
            if pl_handle_pong_response(body, off) != 0:
                return 1
        elif pid == pid_pl_c_place_ghost_recipe():
            if pl_handle_place_ghost_recipe(body, off) != 0:
                return 1
        elif pid == pid_pl_c_player_combat_end():
            if pl_handle_player_combat_end(body, off) != 0:
                return 1
        elif pid == pid_pl_c_player_combat_enter():
            if pl_handle_player_combat_enter(body, off) != 0:
                return 1
        elif pid == pid_pl_c_player_combat_kill():
            if pl_handle_player_combat_kill(body, off) != 0:
                return 1
        elif pid == pid_pl_c_player_look_at():
            if pl_handle_player_look_at(body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_player_rotation():
            if pl_handle_player_rotation(body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_recipe_book_add():
            if pl_handle_recipe_book_add(body, off, state.recipes) != 0:
                return 1
        elif pid == pid_pl_c_recipe_book_remove():
            if pl_handle_recipe_book_remove(body, off, state.recipes) != 0:
                return 1
        elif pid == pid_pl_c_recipe_book_settings():
            if pl_handle_recipe_book_settings(body, off, state.recipes) != 0:
                return 1
        elif pid == pid_pl_c_resource_pack_pop():
            if pl_handle_resource_pack_pop(body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_resource_pack_push():
            if pl_handle_resource_pack_push(socket_handle, body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_post_effects():
            if pl_handle_post_effects(body, off) != 0:
                return 1
        elif pid == pid_pl_c_select_advancements_tab():
            if pl_handle_select_advancements_tab(body, off, state.advancements) != 0:
                return 1
        elif pid == pid_pl_c_set_border_center():
            if pl_handle_set_border_center(body, off, state.border) != 0:
                return 1
        elif pid == pid_pl_c_set_border_lerp_size():
            if pl_handle_set_border_lerp_size(body, off, state.border) != 0:
                return 1
        elif pid == pid_pl_c_set_border_size():
            if pl_handle_set_border_size(body, off, state.border) != 0:
                return 1
        elif pid == pid_pl_c_set_border_warning_delay():
            if pl_handle_set_border_warning_delay(body, off, state.border) != 0:
                return 1
        elif pid == pid_pl_c_set_border_warning_distance():
            if pl_handle_set_border_warning_distance(body, off, state.border) != 0:
                return 1
        elif pid == pid_pl_c_set_chunk_cache_center():
            if pl_handle_set_chunk_cache_center(body, off) != 0:
                return 1
        elif pid == pid_pl_c_set_chunk_cache_radius():
            if pl_handle_set_chunk_cache_radius(body, off, state) != 0:
                return 1
        elif pid == pid_pl_c_set_entity_link():
            if pl_handle_set_entity_link(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_stop_sound():
            if pl_handle_stop_sound(body, off) != 0:
                return 1
        elif pid == pid_pl_c_store_cookie():
            if pl_handle_store_cookie(body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_tag_query():
            if pl_handle_tag_query(body, off) != 0:
                return 1
        elif pid == pid_pl_c_take_item_entity():
            if pl_handle_take_item_entity(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_test_instance_block_status():
            if pl_handle_test_instance_block_status(body, off) != 0:
                return 1
        elif pid == pid_pl_c_ticking_step():
            if pl_handle_ticking_step(body, off) != 0:
                return 1
        elif pid == pid_pl_c_update_advancements():
            if pl_handle_update_advancements(body, off, state.advancements) != 0:
                return 1
        elif pid == pid_pl_c_update_recipes():
            if pl_handle_update_recipes(body, off, state.recipes) != 0:
                return 1
        elif pid == pid_pl_c_update_tags():
            if pl_handle_update_tags(body, off, state.tags) != 0:
                return 1
        elif pid == pid_pl_c_projectile_power():
            if pl_handle_projectile_power(body, off, state.entities) != 0:
                return 1
        elif pid == pid_pl_c_custom_report_details():
            if pl_handle_custom_report_details(body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_server_links():
            if pl_handle_server_links(body, off, state.meta) != 0:
                return 1
        elif pid == pid_pl_c_waypoint():
            if pl_handle_waypoint(body, off, state.meta) != 0:
                return 1
        else:
            str _name = pkt_name(pkt_state_play(), pkt_dir_clientbound(), (int)pid)
            print(f"Play packet {pid} ({_name}) received")
        if received_play_login and pl_publish_view(state) != 0:
            print("Renderer window closed")
            pl_leave_play(state)
            return 0
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
    # The server may send Play login again without ending the connection, so
    # the same world is reused across configuration cycles.
    while result == 2:
        int configured = handle_configuration(socket_handle, registry)
        if configured != 0:
            result = 1
            break
        result = play_session_loop(socket_handle, world, registry)
    # Whatever the server sent is written out as an Anvil world, so a session
    # leaves behind a folder the real game can open. Saving happens once, here,
    # because the loaded columns are only complete once the loop has drained.
    int named = 0
    int numeric = 0
    int unknown = 0
    int saved = anvil_world_save(world, &named, &numeric, &unknown)
    if saved > 0:
        print(f"Saved {saved} chunks to {anvil_save_base()} ({named} registry names)")
        if numeric > 0:
            print(f"  {numeric} palettes written as numeric ids: no registry name table")
        if unknown > 0:
            print(f"  {unknown} saved names were not in the registry name table")
    else:
        if saved < 0:
            print("Anvil save failed; the loaded world is not on disk")
    vworld_free(world)
    return result


public def encode_login_start(username: str, username_length: int64) -> int64[]:
    int64[] body = encode_varint(pid_lg_s_hello())
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

# A login plugin query carries a transaction id, a channel and opaque bytes that
# only the matching channel handler can interpret. The vanilla client answers an
# unknown channel with no payload rather than dropping the connection, so this
# backend echoes the transaction and lets the server decide whether to continue.
def lg_handle_custom_query(socket_handle: int64, body: int64[],
                           offset: int64) -> int:
    int64[] scratch = new int64[1]
    int64 at = pl_vi(body, offset, scratch)
    if at < 0:
        print("Malformed login plugin query transaction id")
        return 1
    int64 transaction = scratch[0]
    int64[] channel = new int64[2]
    at = pl_name(body, at, channel)
    if at < 0:
        print("Malformed login plugin query channel")
        return 1
    int64 size = len(body) - at
    if size > 1048576:
        print("Login plugin query payload exceeds 1048576 bytes")
        return 1
    print("Login plugin query on ")
    pl_print_bytes(body, channel[0], channel[1])
    print(f" ({size} payload bytes); answering with no payload")
    int64[] empty = new int64[0]
    int64[] answer = encode_login_custom_query_answer(transaction, empty, 0, (int64)-1)
    if send_bytes(socket_handle, answer) != 0:
        print("Failed to answer a login plugin query")
        return 1
    return 0


# Login cookie requests arrive before any store_cookie packet can have reached
# this session, so a fresh offline client has nothing to return. Echoing the key
# with an absent payload is the reply the vanilla client gives for a key it does
# not hold, and the server may keep asking or move on.
def lg_handle_cookie_request(socket_handle: int64, body: int64[],
                             offset: int64) -> int:
    int64[] key = new int64[2]
    int64 at = pl_name(body, offset, key)
    if at != len(body):
        print("Malformed login cookie request")
        return 1
    print("Login cookie requested: ")
    pl_print_bytes(body, key[0], key[1])
    print("; answering with no payload")
    int64[] empty = new int64[0]
    int64[] response = encode_cookie_response(pid_lg_s_cookie_response(), body, key[0], key[1], empty, 0, (int64)-1)
    if send_bytes(socket_handle, response) != 0:
        print("Failed to answer a login cookie request")
        return 1
    return 0


# Login success is only accepted when the profile the server assigns matches the
# local account: the offline UUID is derived from the name, so a mismatch means
# the server did not treat this as an offline login.
def lg_handle_login_finished(socket_handle: int64, body: int64[], offset: int64,
                             username: str, username_length: int64) -> int:
    if offset + 16 > len(body):
        print("Truncated login profile UUID")
        return 1
    int64 index = 0
    while index < 16:
        if body[offset + index] != mc_offline_uuid_byte(username, index):
            print("Login profile UUID does not match the offline username")
            return 1
        index = index + 1
    int64[] profile_name = read_string_field(body, offset + 16, 16)
    if profile_name[0] != 1 or profile_name[1] != username_length:
        print("Malformed login profile name")
        return 1
    index = 0
    while index < username_length:
        if body[profile_name[2] + index] != mc_string_byte(username, index):
            print("Login profile name does not match the requested username")
            return 1
        index = index + 1
    int64[] property_count = decode_varint(body, profile_name[2] + profile_name[1])
    if property_count[0] != 1 or (property_count[1] < 0 or property_count[1] > 1024):
        print("Malformed login profile properties")
        return 1
    int64 property_position = property_count[2]
    index = 0
    while index < property_count[1]:
        int64[] property_name = read_string_field(body, property_position, 64)
        if property_name[0] != 1:
            print("Malformed login profile property name")
            return 1
        int64[] property_value = read_string_field(body, property_name[2] + property_name[1], 32767)
        if property_value[0] != 1:
            print("Malformed login profile property value")
            return 1
        property_position = property_value[2] + property_value[1]
        if property_position >= len(body):
            print("Truncated login profile property")
            return 1
        int64 has_signature = body[property_position]
        property_position = property_position + 1
        if has_signature == 1:
            int64[] signature = read_string_field(body, property_position, 1024)
            if signature[0] != 1:
                print("Malformed login profile signature")
                return 1
            property_position = signature[2] + signature[1]
        elif has_signature != 0:
            print("Invalid login profile signature flag")
            return 1
        index = index + 1
    if property_position + 16 != len(body):
        print("Unexpected bytes in login success packet")
        return 1
    int64[] empty = new int64[0]
    int64[] acknowledgement = encode_packet_frame(pid_lg_s_login_acknowledged(), empty)
    if send_bytes(socket_handle, acknowledgement) != 0:
        print("Failed to acknowledge login success")
        return 1
    print(f"Offline login accepted for {username}")
    print("Login acknowledged; entering configuration")
    return 0


# The whole session: handshake, offline login, configuration and Play.
# `preset_socket` is 0 for a network server, or the handle an embedded
# single-player server already attached a transport to, in which case no socket
# is opened and host/port only name the handshake.
public def offline_login(host: str, port: int64, username: str, preset_socket: int64) -> int:
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
    int64 socket_handle = preset_socket
    if socket_handle == 0:
        socket_handle = mc_tcp_connect(host, port)
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
    # A server may ask for cookies and run plugin queries before login success,
    # and enabling compression consumes one round on its own, so the exchange is
    # a bounded loop rather than a single read.
    int64 round = 0
    while round < 64:
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
        if packet_id[1] == pid_lg_c_login_disconnect():
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
        if packet_id[1] == pid_lg_c_hello():
            mc_tcp_close(socket_handle)
            print("Server requires online-mode authentication; this client uses local offline accounts only")
            return 1
        if packet_id[1] == pid_lg_c_custom_query():
            if lg_handle_custom_query(socket_handle, login_body, packet_id[2]) != 0:
                mc_tcp_close(socket_handle)
                return 1
        elif packet_id[1] == pid_lg_c_cookie_request():
            if lg_handle_cookie_request(socket_handle, login_body, packet_id[2]) != 0:
                mc_tcp_close(socket_handle)
                return 1
        elif packet_id[1] == pid_lg_c_login_finished():
            if lg_handle_login_finished(socket_handle, login_body, packet_id[2], username, username_length) != 0:
                mc_tcp_close(socket_handle)
                return 1
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
        else:
            mc_tcp_close(socket_handle)
            print("Unexpected login response packet")
            return 1
        round = round + 1
    mc_tcp_close(socket_handle)
    print("Too many login packets without login success")
    return 1

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
    if packet_id[0] != 1 or packet_id[1] != pid_st_c_status_response():
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
    if pong_id[0] != 1 or (pong_id[1] != pid_st_c_pong_response() or len(pong_body) - pong_id[2] != 8):
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

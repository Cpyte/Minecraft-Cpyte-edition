# Vortex engine - protocol 777 Play wire-format test.
#
# Every assertion is a round trip: outbound packets are built by the encoders in
# src/protocol.cpy, pulled apart by the shared frame/varint decoder, and compared
# against the byte layout the Minecraft 26.3 protocol documents. Inbound packets
# are assembled byte by byte and fed to the handlers, which must either parse
# them or reject them cleanly.
#
# Build with: ./build.sh --run tests/protocol_play.txt

import stdlib


def test_near(label: str, got: double, want: double, fails: int*) -> void:
    double delta = got - want
    if delta < 0.0:
        delta = 0.0 - delta
    if delta < 0.000001:
        print("  ok   " + label)
    else:
        print("  FAIL " + label + ": got " + str((int)got) + " want " + str((int)want))
        *fails = *fails + 1


def test_write(target: int64[], position: int64, source: int64[]) -> int64:
    int64 index = 0
    while index < len(source):
        target[position + index] = source[index]
        index = index + 1
    return position + len(source)


def test_line(text: str) -> int64[]:
    int64 length = mc_string_length(text)
    int64[] bytes = new int64[length]
    int64 index = 0
    while index < length:
        bytes[index] = mc_string_byte(text, index)
        index = index + 1
    return bytes


# Decodes one frame produced by encode_packet_frame and returns the payload
# bytes that follow the packet id varint.
def test_packet(packet: int64[], label: str, expected_id: int64,
                fails: int*) -> int64[]:
    int64[] frame = decode_frame(packet)
    check_int(label + ": frame decodes", (int)frame[0], 1, fails)
    if frame[0] != 1:
        return new int64[0]
    check_int(label + ": frame spans the packet", (int)frame[1],
              (int)len(packet), fails)
    int64[] body = frame_body(frame)
    int64[] id = decode_varint(body, 0)
    check_int(label + ": packet id", (int)id[1], (int)expected_id, fails)
    check_int(label + ": id is one byte", (int)id[2], 1, fails)
    if id[2] != 1:
        return new int64[0]
    int64[] payload = new int64[len(body) - 1]
    int64 index = 0
    while index < len(payload):
        payload[index] = body[index + 1]
        index = index + 1
    return payload


def test_byte(label: str, payload: int64[], offset: int64, want: int64,
              fails: int*) -> void:
    if offset >= len(payload):
        check_int(label + " (past end of payload)", -1, (int)want, fails)
        return
    check_int(label, (int)payload[offset], (int)want, fails)


def test_float(label: str, payload: int64[], offset: int64, want: double,
               fails: int*) -> void:
    if offset + 4 > len(payload):
        check_int(label + " (past end of payload)", -1, 0, fails)
        return
    test_near(label, decode_be_float(payload, offset), want, fails)


def test_double(label: str, payload: int64[], offset: int64, want: double,
                fails: int*) -> void:
    if offset + 8 > len(payload):
        check_int(label + " (past end of payload)", -1, 0, fails)
        return
    test_near(label, mc_double_from_be(payload[offset], payload[offset + 1],
                                       payload[offset + 2], payload[offset + 3],
                                       payload[offset + 4], payload[offset + 5],
                                       payload[offset + 6], payload[offset + 7]),
              want, fails)


def test_float_bytes(target: int64[], position: int64, value: double) -> int64:
    int64 index = 0
    while index < 4:
        target[position + index] = mc_float_be_byte(value, index)
        index = index + 1
    return position + 4


def test_int64_bytes(target: int64[], position: int64, value: int64) -> int64:
    int64 index = 0
    while index < 8:
        target[position + index] = value >> (7 - index) * 8 & 0xFF
        index = index + 1
    return position + 8


def test_state() -> VPlayState*:
    VPlayState* state = new VPlayState
    state.x = 0.0
    state.y = 0.0
    state.z = 0.0
    state.yaw = 0.0
    state.pitch = 0.0
    state.health = -1.0
    state.food = -1.0
    state.saturation = -1.0
    state.xp_progress = -1.0
    state.xp_level = -1
    state.xp_total = -1
    state.game_mode = -1
    state.held_slot = -1
    state.abilities_flags = -1
    state.flying_speed = -1.0
    state.fov_modifier = -1.0
    state.teleport_id = -1
    state.on_ground = false
    state.vertical = false
    state.world_time = (int64)-1
    state.dimension = -1
    state.view_distance = -1
    state.simulation_distance = -1
    state.next_chat_seq = (int64)0
    state.inventory = vinv_new()
    return state


def test_pos_roundtrip(label: str, x: int64, y: int64, z: int64,
                       fails: int*) -> int64:
    int64 packed = pl_pack_block_pos(x, y, z)
    int* position = vt_calloc_int(3)
    vt_unpack_block_pos(packed, position)
    check_int(label + " x", vt_iget(position, 0), (int)x, fails)
    check_int(label + " y", vt_iget(position, 1), (int)y, fails)
    check_int(label + " z", vt_iget(position, 2), (int)z, fails)
    vt_free((void*)position)
    return packed


def test_varints(fails: int*) -> void:
    check_int("zero encodes to one byte", (int)len(encode_varint(0)), 1, fails)
    check_int("127 stays one byte", (int)len(encode_varint(127)), 1, fails)
    check_int("128 spills to two bytes", (int)len(encode_varint(128)), 2, fails)
    int64[] wide = encode_varint(300)
    check_int("300 low continuation byte", (int)wide[0], 172, fails)
    check_int("300 high byte", (int)wide[1], 2, fails)
    int64[] back = decode_varint(wide, 0)
    check_int("300 round trips", (int)back[1], 300, fails)
    check_int("300 consumes two bytes", (int)back[2], 2, fails)
    int64[] five = new int64[5]
    int64 index = 0
    while index < 4:
        five[index] = 255
        index = index + 1
    five[4] = 16
    check_int("five byte overflow is rejected", (int)decode_varint(five, 0)[0],
              -2, fails)
    int64[] six = new int64[6]
    index = 0
    while index < 5:
        six[index] = 255
        index = index + 1
    six[5] = 1
    check_int("six byte continuation is rejected", (int)decode_varint(six, 0)[0],
              -2, fails)
    int64[] short_body = new int64[1]
    short_body[0] = 129
    check_int("truncated varint is rejected", (int)decode_varint(short_body, 0)[0],
              -1, fails)


def test_framing(fails: int*) -> void:
    int64[] empty = new int64[0]
    int64[] frame = encode_packet_frame(5, empty)
    check_int("headerless id plus empty payload", (int)len(frame), 2, fails)
    int64[] decoded = decode_frame(frame)
    check_int("empty payload frame decodes", (int)decoded[0], 1, fails)
    check_int("empty payload body length", (int)decoded[2], 1, fails)
    int64[] id = decode_varint(frame_body(decoded), 0)
    check_int("empty payload frame id", (int)id[1], 5, fails)
    int64[] truncated = new int64[2]
    truncated[0] = 9
    check_int("short frame asks for more bytes", (int)decode_frame(truncated)[0],
              -1, fails)
    int64[] zero_length = new int64[1]
    check_int("zero length frame is rejected", (int)decode_frame_header(zero_length)[0],
              -2, fails)


def test_move_encoders(fails: int*) -> void:
    int64[] pos_body = test_packet(encode_move_player_pos(1.5, -2.25, 3.0, 90.0,
                                                          12.5, true, false, 7),
                                   "move pos", pid_pl_s_move_player_pos(), fails)
    check_int("move pos payload length", (int)len(pos_body), 42, fails)
    test_double("move pos x", pos_body, 0, 1.5, fails)
    test_double("move pos y", pos_body, 8, -2.25, fails)
    test_double("move pos z", pos_body, 16, 3.0, fails)
    test_float("move pos yaw", pos_body, 24, 90.0, fails)
    test_float("move pos pitch", pos_body, 28, 12.5, fails)
    test_byte("move pos flags", pos_body, 32, 9, fails)
    test_byte("move pos teleport id", pos_body, 33, 7, fails)
    test_byte("move pos delta x", pos_body, 34, 0, fails)
    test_byte("move pos trailing byte", pos_body, 41, 0, fails)

    int64[] rot_body = test_packet(encode_move_player_pos_rot(0.0, 64.0, 0.0, 0.0,
                                                              0.0, false, true, 300),
                                   "move pos rot", pid_pl_s_move_player_pos_rot(),
                                   fails)
    check_int("move pos rot payload length", (int)len(rot_body), 43, fails)
    test_double("move pos rot y", rot_body, 8, 64.0, fails)
    test_byte("move pos rot flags", rot_body, 32, 14, fails)
    test_byte("move pos rot teleport low", rot_body, 33, 172, fails)
    test_byte("move pos rot teleport high", rot_body, 34, 2, fails)
    test_byte("move pos rot delta x", rot_body, 35, 0, fails)

    int64[] look_body = test_packet(encode_move_player_rot(45.0, -5.0, false),
                                    "move rot", pid_pl_s_move_player_rot(), fails)
    check_int("move rot payload length", (int)len(look_body), 10, fails)
    test_float("move rot yaw", look_body, 0, 45.0, fails)
    test_float("move rot pitch", look_body, 4, -5.0, fails)
    test_byte("move rot flags", look_body, 8, 0, fails)
    test_byte("move rot teleport absent", look_body, 9, 0, fails)

    int64[] flags_body = test_packet(encode_move_player_status_only(true, 3),
                                     "move status", pid_pl_s_move_player_status_only(),
                                     fails)
    check_int("move status payload length", (int)len(flags_body), 10, fails)
    test_byte("move status flags", flags_body, 0, 9, fails)
    test_byte("move status teleport id", flags_body, 1, 3, fails)

    int64[] far_body = test_packet(encode_move_player_status_only(false, 200),
                                   "move status wide", pid_pl_s_move_player_status_only(),
                                   fails)
    check_int("move status wide payload length", (int)len(far_body), 11, fails)
    test_byte("move status wide flags", far_body, 0, 8, fails)
    test_byte("move status wide teleport low", far_body, 1, 200, fails)
    test_byte("move status wide teleport high", far_body, 2, 1, fails)


def test_action_encoders(fails: int*) -> void:
    int64[] use_body = test_packet(encode_use_item(1, 5), "use item",
                                   pid_pl_s_use_item(), fails)
    check_int("use item payload length", (int)len(use_body), 2, fails)
    test_byte("use item hand", use_body, 0, 1, fails)
    test_byte("use item sequence", use_body, 1, 5, fails)

    int64[] held_body = test_packet(encode_set_carried_item(4), "carried item",
                                    pid_pl_s_set_carried_item(), fails)
    check_int("carried item payload length", (int)len(held_body), 2, fails)
    test_byte("carried item slot high", held_body, 0, 0, fails)
    test_byte("carried item slot low", held_body, 1, 4, fails)

    int64[] command_body = test_packet(encode_player_command(3, -1),
                                       "player command", pid_pl_s_player_command(),
                                       fails)
    check_int("player command payload length", (int)len(command_body), 8, fails)
    test_byte("player command action low", command_body, 3, 3, fails)
    test_byte("player command extra high", command_body, 4, 255, fails)
    test_byte("player command extra low", command_body, 7, 255, fails)
    int64[] header = encode_player_command_header()
    check_int("player command header is the id varint", (int)header[0],
              (int64)pid_pl_s_player_command(), fails)

    int64[] touch_body = test_packet(encode_interact(9, 2, 0.5, 0.25, 0.0, 1,
                                                     true, 0),
                                     "interact at", pid_pl_s_interact(), fails)
    check_int("interact at payload length", (int)len(touch_body), 17, fails)
    test_byte("interact at entity", touch_body, 0, 9, fails)
    test_byte("interact at action", touch_body, 1, 2, fails)
    test_float("interact at x", touch_body, 2, 0.5, fails)
    test_float("interact at y", touch_body, 6, 0.25, fails)
    test_float("interact at z", touch_body, 10, 0.0, fails)
    test_byte("interact at face", touch_body, 14, 1, fails)
    test_byte("interact at inside room", touch_body, 15, 1, fails)
    test_byte("interact at hand", touch_body, 16, 0, fails)

    int64[] attack_body = test_packet(encode_interact(9, 1, 0.0, 0.0, 0.0, 0,
                                                      false, 0),
                                      "interact attack", pid_pl_s_interact(), fails)
    check_int("interact attack payload length", (int)len(attack_body), 2, fails)
    test_byte("interact attack action", attack_body, 1, 1, fails)

    int64[] hit_body = test_packet(encode_attack(300), "attack", pid_pl_s_attack(),
                                   fails)
    check_int("attack payload length", (int)len(hit_body), 2, fails)
    test_byte("attack target low", hit_body, 0, 172, fails)
    test_byte("attack target high", hit_body, 1, 2, fails)

    int64[] ack_body = test_packet(encode_chat_ack(0, 5), "chat ack",
                                   pid_pl_s_chat_ack(), fails)
    check_int("chat ack payload length", (int)len(ack_body), 2, fails)
    test_byte("chat ack offset", ack_body, 0, 0, fails)
    test_byte("chat ack count", ack_body, 1, 5, fails)

    int64 mined = test_pos_roundtrip("block position", 1000000, 64, 2000000, fails)
    test_pos_roundtrip("negative block position", -1000000, -64, -2000000, fails)
    test_pos_roundtrip("origin block position", 0, 0, 0, fails)

    int64[] dig_body = test_packet(encode_player_action(0, mined, 2, 1),
                                   "player action", pid_pl_s_player_action(), fails)
    check_int("player action payload length", (int)len(dig_body), 11, fails)
    test_byte("player action status", dig_body, 0, 0, fails)
    check_int("player action position", (int)decode_be_i64(dig_body, 1),
              (int)mined, fails)
    test_byte("player action face", dig_body, 9, 2, fails)
    test_byte("player action sequence", dig_body, 10, 1, fails)

    int64[] ability_body = test_packet(encode_player_abilities_server(3, 0.1, 0.0),
                                       "abilities", pid_pl_s_player_abilities(), fails)
    check_int("abilities payload length", (int)len(ability_body), 9, fails)
    test_byte("abilities flags", ability_body, 0, 3, fails)
    test_float("abilities flying speed", ability_body, 1, 0.1, fails)
    test_float("abilities fov", ability_body, 5, 0.0, fails)

    int64[] settings_body = test_packet(encode_client_command_settings(8, 0),
                                        "settings", pid_pl_s_client_command(), fails)
    check_int("settings payload length", (int)len(settings_body), 9, fails)
    test_byte("settings view distance", settings_body, 0, 8, fails)
    test_byte("settings chat enabled", settings_body, 1, 1, fails)
    test_byte("settings chat mode", settings_body, 2, 0, fails)
    test_byte("settings skin parts", settings_body, 4, 255, fails)
    test_byte("settings last byte", settings_body, 8, 0, fails)


def test_arg_parsers(fails: int*) -> void:
    int64[] content = test_line("/move -1.25 2 300")
    int64 length = len(content)
    int64[] cursor = new int64[1]
    cursor[0] = 1
    int64[] verb = pl_arg_word(content, length, cursor)
    check("verb word is readable", verb[0] == 1, fails)
    check("verb is move", dialog_line_equals(verb, "move"), fails)
    double[] move_x = pl_arg_double(content, length, cursor)
    check("negative decimal parses", move_x[0] == 1.0, fails)
    test_near("parsed x", move_x[1], -1.25, fails)
    double[] move_y = pl_arg_double(content, length, cursor)
    test_near("parsed y", move_y[1], 2.0, fails)
    int64[] move_z = pl_arg_int(content, length, cursor)
    check_int("parsed z", (int)move_z[1], 300, fails)
    int64[] tail = pl_arg_word(content, length, cursor)
    check_int("no trailing word", (int)tail[1], 0, fails)

    int64[] blank = new int64[1]
    int64[] blank_cursor = new int64[1]
    blank[0] = 32
    int64[] missing = pl_arg_int(blank, 1, blank_cursor)
    check_int("non numeric int is refused", (int)missing[0], 0, fails)
    double[] missing_real = pl_arg_double(blank, 1, blank_cursor)
    check("non numeric double is refused", missing_real[0] == 0.0, fails)


def test_item_stacks(fails: int*) -> void:
    int64[] empty_body = new int64[1]
    int64[] empty_out = new int64[3]
    check_int("empty stack advances one byte",
              (int)pl_read_item_stack(empty_body, 0, empty_out), 1, fails)
    check_int("empty stack presence", (int)empty_out[0], 0, fails)

    int64[] plain = new int64[5]
    int64[] plain_out = new int64[3]
    plain[0] = 3
    int64 cursor = test_write(plain, 1, encode_varint(1457))
    plain[cursor] = 0
    cursor = test_write(plain, cursor + 1, encode_varint(0))
    check_int("plain stack fills the buffer", (int)cursor, 5, fails)
    check_int("plain stack parses", (int)pl_read_item_stack(plain, 0, plain_out),
              5, fails)
    check_int("plain stack is present", (int)plain_out[0], 1, fails)
    check_int("plain stack item id", (int)plain_out[1], 1457, fails)
    check_int("plain stack count", (int)plain_out[2], 3, fails)

    # count, item, one added component (repair_cost, id 3), no removals.
    int64[] tagged = new int64[7]
    int64[] tagged_out = new int64[3]
    tagged[0] = 1
    cursor = test_write(tagged, 1, encode_varint(1457))
    cursor = test_write(tagged, cursor, encode_varint(1))
    cursor = test_write(tagged, cursor, encode_varint(0))
    cursor = test_write(tagged, cursor, encode_varint(3))
    tagged[cursor] = 5
    check_int("tagged stack fills the buffer", (int)cursor + 1, 7, fails)
    check_int("tagged stack parses", (int)pl_read_item_stack(tagged, 0, tagged_out),
              7, fails)
    check_int("tagged stack item id", (int)tagged_out[1], 1457, fails)

    # Two components: custom_name (an unnamed NBT compound) then item_model
    # (a resource location).
    int64[] compound = new int64[16]
    int64[] compound_out = new int64[3]
    compound[0] = 1
    cursor = test_write(compound, 1, encode_varint(7))
    cursor = test_write(compound, cursor, encode_varint(2))
    cursor = test_write(compound, cursor, encode_varint(0))
    cursor = test_write(compound, cursor, encode_varint(6))
    # the compound: one byte entry named x, then the end tag
    compound[cursor] = 10
    compound[cursor + 1] = 1
    compound[cursor + 2] = 0
    compound[cursor + 3] = 1
    compound[cursor + 4] = 120
    compound[cursor + 5] = 7
    compound[cursor + 6] = 0
    cursor = test_write(compound, cursor + 7, encode_varint(10))
    cursor = test_write(compound, cursor, encode_varint(2))
    compound[cursor] = 104
    compound[cursor + 1] = 105
    check_int("two component stack fills the buffer", (int)cursor + 2, 16, fails)
    check_int("compound and string components parse",
              (int)pl_read_item_stack(compound, 0, compound_out), 16, fails)
    check_int("compound stack count", (int)compound_out[2], 1, fails)

    int64[] broken = new int64[2]
    int64[] broken_out = new int64[3]
    broken[0] = 1
    broken[1] = 177
    check_int("truncated stack item id is refused",
              (int)pl_read_item_stack(broken, 0, broken_out), -1, fails)
    int64[] absent = new int64[0]
    check_int("empty buffer is refused", (int)pl_read_item_stack(absent, 0, absent),
              -1, fails)


def test_state_handlers(fails: int*) -> void:
    VPlayState* state = test_state()

    int64[] health_body = new int64[12]
    test_float_bytes(health_body, 0, 20.0)
    test_float_bytes(health_body, 4, 12.0)
    test_float_bytes(health_body, 8, 3.5)
    check_int("set health parses", (int)pl_handle_set_health(0, health_body, 0, state),
              0, fails)
    test_near("health applied", state.health, 20.0, fails)
    test_near("food applied", state.food, 12.0, fails)
    test_near("saturation applied", state.saturation, 3.5, fails)
    check_int("short health packet is refused",
              (int)pl_handle_set_health(0, health_body, 1, state), 1, fails)

    int64[] xp_body = new int64[7]
    int64 cursor = test_float_bytes(xp_body, 0, 0.25)
    cursor = test_write(xp_body, cursor, encode_varint(7))
    cursor = test_write(xp_body, cursor, encode_varint(300))
    check_int("experience packet fills the buffer", (int)cursor, 7, fails)
    check_int("set experience parses", (int)pl_handle_set_experience(0, xp_body, 0, state),
              0, fails)
    test_near("experience progress applied", state.xp_progress, 0.25, fails)
    check_int("experience level applied", state.xp_level, 7, fails)
    check_int("experience total applied", state.xp_total, 300, fails)

    int64[] ability_body = new int64[9]
    ability_body[0] = 5
    test_float_bytes(ability_body, 1, 0.1)
    test_float_bytes(ability_body, 5, -0.5)
    check_int("player abilities parse", (int)pl_handle_player_abilities(0, ability_body,
                                                                       0, state),
              0, fails)
    check_int("ability flags applied", state.abilities_flags, 5, fails)
    test_near("flying speed applied", state.flying_speed, 0.1, fails)
    test_near("fov modifier applied", state.fov_modifier, -0.5, fails)
    check_int("short ability packet is refused",
              (int)pl_handle_player_abilities(0, ability_body, 1, state), 1, fails)

    int64[] slot_body = new int64[1]
    slot_body[0] = 4
    check_int("held slot parses", (int)pl_handle_set_held_slot(0, slot_body, 0, state),
              0, fails)
    check_int("held slot applied", state.held_slot, 4, fails)
    int64[] no_slot = new int64[0]
    check_int("empty held slot packet is refused",
              (int)pl_handle_set_held_slot(0, no_slot, 0, state), 1, fails)

    int64[] time_body = new int64[8]
    test_int64_bytes(time_body, 0, 1000)
    check_int("world time parses", (int)pl_handle_set_time(0, time_body, 0, state),
              0, fails)
    check_int("world time applied", (int)state.world_time, 1000, fails)

    int64[] distance_body = new int64[2]
    distance_body[0] = 8
    distance_body[1] = 5
    check_int("simulation distance parses",
              (int)pl_handle_simulation_distance(0, distance_body, 0, state), 0, fails)
    check_int("view distance applied", state.view_distance, 8, fails)
    check_int("simulation distance applied", state.simulation_distance, 5, fails)
    check_int("half a distance packet is refused",
              (int)pl_handle_simulation_distance(0, distance_body, 1, state), 1, fails)

    int64[] respawn_body = new int64[13]
    cursor = test_write(respawn_body, 0, encode_varint(0))
    cursor = test_write(respawn_body, cursor, encode_varint(1))
    cursor = test_write(respawn_body, cursor, encode_varint(0))
    cursor = test_int64_bytes(respawn_body, cursor, 0)
    cursor = test_write(respawn_body, cursor, encode_varint(0))
    cursor = test_write(respawn_body, cursor, encode_varint(0))
    check_int("respawn packet fills the buffer", (int)cursor, 13, fails)
    check_int("respawn parses",
              (int)pl_handle_respawn(0, respawn_body, 0, state, (VDimensionRegistry*)0),
              0, fails)
    check_int("game mode applied", state.game_mode, 1, fails)
    check_int("empty respawn is refused",
              (int)pl_handle_respawn(0, no_slot, 0, state, (VDimensionRegistry*)0),
              1, fails)
    check_int("respawn missing its distances is refused",
              (int)pl_handle_respawn(0, respawn_body, 12, state,
                                     (VDimensionRegistry*)0),
              1, fails)

    int64[] event_body = new int64[5]
    event_body[0] = 3
    test_float_bytes(event_body, 1, 0.5)
    check_int("game event parses", (int)pl_handle_game_event(0, event_body, 0),
              0, fails)
    check_int("game event missing its value is refused",
              (int)pl_handle_game_event(0, event_body, 1), 1, fails)
    check_int("empty game event is refused", (int)pl_handle_game_event(0, no_slot, 0),
              1, fails)

    int64[] truncated_block_event = new int64[10]
    truncated_block_event[5] = 128
    truncated_block_event[6] = 128
    truncated_block_event[7] = 128
    truncated_block_event[8] = 128
    truncated_block_event[9] = 128
    check_int("truncated block event position is refused",
              (int)pl_handle_block_event(0, truncated_block_event, 0), 1, fails)
    VBlockEntities* brief_tiles = vbes_new()
    int64[] truncated_block_entity = new int64[9]
    truncated_block_entity[1] = 128
    truncated_block_entity[2] = 128
    truncated_block_entity[3] = 128
    truncated_block_entity[4] = 128
    truncated_block_entity[5] = 128
    check_int("truncated block entity action is refused",
              (int)pl_handle_block_entity_data(0, truncated_block_entity, 0,
                                            brief_tiles), 1, fails)

    vbes_free(brief_tiles)

    VPlayers* brief_list = vplayers_new()
    int64[] brief_text = new int64[64]
    int64[] info_body = new int64[1]
    info_body[0] = 3
    check_int("a player info update without an entry count is refused",
              (int)pl_handle_player_info_update(0, info_body, 0, brief_list,
                                                brief_text), 1, fails)
    int64[] huge_info = new int64[8]
    huge_info[0] = 1
    test_write(huge_info, 1, encode_varint(2000))
    check_int("oversized player info is refused",
              (int)pl_handle_player_info_update(0, huge_info, 0, brief_list,
                                                brief_text), 1, fails)
    int64[] empty_mask = new int64[2]
    empty_mask[0] = 0
    empty_mask[1] = 0
    check_int("a player info update with no actions is refused",
              (int)pl_handle_player_info_update(0, empty_mask, 0, brief_list,
                                                brief_text), 1, fails)
    vplayers_free(brief_list)

    int64[] spawn_body = new int64[5]
    spawn_body[0] = 0
    spawn_body[1] = 3
    spawn_body[2] = 65
    spawn_body[3] = 66
    spawn_body[4] = 67
    check_int("default spawn parses", (int)pl_handle_set_default_spawn(0, spawn_body, 0),
              0, fails)
    check_int("truncated default spawn is refused",
              (int)pl_handle_set_default_spawn(0, spawn_body, 2), 1, fails)


def test_container_handlers(fails: int*) -> void:
    VInventory* slots = vinv_new()
    int64[] cleared = new int64[5]
    cleared[0] = 0
    cleared[1] = 0
    cleared[2] = 0
    cleared[3] = 2
    cleared[4] = 0
    check_int("cleared slot packet size", (int)len(cleared), 5, fails)
    check_int("cleared slot parses", (int)pl_handle_container_set_slot(cleared, 0, slots),
              0, fails)

    # The 26.3 stack envelope: count, item id, added count, removed count.
    int64[] filled = new int64[9]
    filled[0] = 0
    filled[1] = 0
    filled[2] = 0
    filled[3] = 2
    filled[4] = 1
    int64 cursor = test_write(filled, 5, encode_varint(1457))
    cursor = test_write(filled, cursor, encode_varint(0))
    cursor = test_write(filled, cursor, encode_varint(0))
    check_int("filled slot packet size", (int)cursor, 9, fails)
    check_int("filled slot parses", (int)pl_handle_container_set_slot(filled, 0, slots),
              0, fails)
    check_int("filled slot item continuation byte", (int)filled[5], 177, fails)

    int64[] stub = new int64[4]
    stub[0] = 0
    stub[1] = 0
    stub[2] = 0
    stub[3] = 2
    check_int("stub slot packet size", (int)len(stub), 4, fails)
    int64[] stub_out = new int64[3]
    check_int("stub stack read", (int)pl_read_item_stack(stub, 4, stub_out), -1, fails)
    check_int("slot without a stack is refused",
              (int)pl_handle_container_set_slot(stub, 0, slots), 1, fails)

    int64[] content_body = new int64[10]
    content_body[0] = 0
    content_body[1] = 0
    content_body[2] = 2
    content_body[3] = 1
    cursor = test_write(content_body, 4, encode_varint(1457))
    content_body[cursor] = 0
    cursor = cursor + 1
    content_body[cursor] = 0
    cursor = cursor + 1
    content_body[cursor] = 0
    cursor = cursor + 1
    content_body[cursor] = 0
    cursor = cursor + 1
    check_int("content packet size", (int)cursor, 10, fails)
    check_int("container content parses", (int)pl_handle_container_set_content(content_body, 0, slots),
              0, fails)

    int64[] inventory = new int64[6]
    inventory[0] = 1
    inventory[1] = 1
    cursor = test_write(inventory, 2, encode_varint(1457))
    cursor = test_write(inventory, cursor, encode_varint(0))
    cursor = test_write(inventory, cursor, encode_varint(0))
    check_int("inventory packet size", (int)cursor, 6, fails)
    check_int("player inventory parses", (int)pl_handle_set_player_inventory(inventory, 0, slots),
              0, fails)

    int64[] wide_inventory = new int64[3]
    wide_inventory[0] = 0
    wide_inventory[1] = 7
    wide_inventory[2] = 208
    check_int("oversized inventory is refused",
              (int)pl_handle_set_player_inventory(wide_inventory, 0, slots), 1, fails)
    vinv_free(slots)


def test_text_handlers(fails: int*) -> void:
    VInventory* slots = vinv_new()
    int64[] screen_body = new int64[7]
    screen_body[0] = 0
    screen_body[1] = 5
    screen_body[2] = 8
    screen_body[3] = 0
    screen_body[4] = 2
    screen_body[5] = 104
    screen_body[6] = 105
    check_int("open screen parses", (int)pl_handle_open_screen(screen_body, 0, slots),
              0, fails)
    int64[] clipped_screen = new int64[3]
    clipped_screen[0] = 0
    clipped_screen[1] = 200
    clipped_screen[2] = 65
    check_int("screen with a clipped title is refused",
              (int)pl_handle_open_screen(clipped_screen, 0, slots), 1, fails)
    vinv_free(slots)

    int64[] chat_body = new int64[37]
    int64 cursor = test_write(chat_body, 16, encode_varint(0))
    check_int("chat message index offset", (int)cursor, 17, fails)
    chat_body[cursor] = 0
    cursor = test_write(chat_body, cursor + 17, encode_varint(2))
    chat_body[cursor] = 104
    chat_body[cursor + 1] = 105
    check_int("chat packet size", (int)cursor + 2, 37, fails)
    check_int("player chat parses", (int)pl_handle_player_chat(chat_body, 0), 0, fails)

    int64[] signed_body = new int64[41]
    cursor = test_write(signed_body, 16, encode_varint(0))
    signed_body[cursor] = 1
    cursor = test_write(signed_body, cursor + 1, encode_varint(3))
    signed_body[cursor] = 1
    signed_body[cursor + 1] = 2
    signed_body[cursor + 2] = 3
    cursor = test_write(signed_body, cursor + 3 + 16, encode_varint(2))
    signed_body[cursor] = 104
    signed_body[cursor + 1] = 105
    check_int("signed chat packet size", (int)cursor + 2, 41, fails)
    check_int("signed chat parses", (int)pl_handle_player_chat(signed_body, 0),
              0, fails)

    int64[] short_chat = new int64[16]
    check_int("chat without an index is refused",
              (int)pl_handle_player_chat(short_chat, 0), 1, fails)


def test_terminal_routing(fails: int*) -> void:
    VPlayState* state = test_state()
    int64[] status_line = test_line("/state")
    check_int("state verb is owned",
              (int)play_terminal_action(0, state, status_line, len(status_line)),
              1, fails)
    int64[] unknown_line = test_line("/frobnicate 1")
    check_int("unknown verb falls through to chat",
              (int)play_terminal_action(0, state, unknown_line, len(unknown_line)),
              0, fails)
    int64[] bad_move = test_line("/move here")
    check_int("malformed move args are rejected",
              (int)play_terminal_action(0, state, bad_move, len(bad_move)), 1, fails)
    test_near("move failure leaves position alone", state.x, 0.0, fails)


# Builds a metadata entry header the way 1.20.2+ packs it: the field id in the
# low seven bits and the serializer ordinal above them.
# Handlers that require the body to end with their last field are fed a packet
# trimmed to exactly the bytes written.
def test_trim(source: int64[], length: int64) -> int64[]:
    int64[] trimmed = new int64[length]
    int64 index = 0
    while index < length:
        trimmed[index] = source[index]
        index = index + 1
    return trimmed


# Writes one update-mob-effect body: the four varints, the flags byte and, when
# the colour bit is set, the colour varint that follows it.
def test_effect_packet(entity: int, effect: int, amplifier: int,
                       duration: int, flags: int) -> int64[]:
    int64[] body = new int64[32]
    int64 at = test_write(body, 0, encode_varint(entity))
    at = test_write(body, at, encode_varint(effect))
    at = test_write(body, at, encode_varint(amplifier))
    at = test_write(body, at, encode_varint(duration))
    body[at] = flags
    at = at + 1
    if (flags & vfx_flag_colour()) != 0:
        at = test_write(body, at, encode_varint(0xFF55AA))
    return test_trim(body, at)


def test_mob_effects(fails: int*) -> void:
    print("protocol play: mob effects")
    VEffects* table = vfx_new()

    check("effect without colour parses",
          pl_handle_update_mob_effect(test_effect_packet(11, 9, 2, 200, 0), 0,
                                      table) == 0, fails)
    check_int("amplifier stored", vfx_amplitude(table, 11, 9), 2, fails)
    check_int("duration stored", vfx_duration(table, 11, 9), 200, fails)
    check_int("no colour stored", vfx_colour(table, 11, 9), 0, fails)
    check_int("particles off", vfx_flag(table, 11, 9, vfx_flag_particles()), 0,
              fails)

    check("effect with colour parses",
          pl_handle_update_mob_effect(test_effect_packet(11, 26, 0, -1, 15), 0,
                                      table) == 0, fails)
    check_int("countless duration stored", vfx_duration(table, 11, 26), -1, fails)
    check_int("colour stored", vfx_colour(table, 11, 26), 0xFF55AA, fails)
    check_int("ambient flag set", vfx_flag(table, 11, 26, vfx_flag_ambient()), 1,
              fails)
    check_int("icon flag set", vfx_flag(table, 11, 26, vfx_flag_icon()), 1, fails)
    check_int("two effects on one entity", vfx_active_count(table), 2, fails)

    check("repeated update replaces fields",
          pl_handle_update_mob_effect(test_effect_packet(11, 9, 4, 60, 0), 0,
                                      table) == 0, fails)
    check_int("amplifier replaced", vfx_amplitude(table, 11, 9), 4, fails)
    check_int("duration replaced", vfx_duration(table, 11, 9), 60, fails)
    check_int("colour replaced", vfx_colour(table, 11, 9), 0, fails)
    check_int("still two effects", vfx_active_count(table), 2, fails)

    int64[] remove = new int64[8]
    int64 at = test_write(remove, 0, encode_varint(11))
    at = test_write(remove, at, encode_varint(26))
    check("removal parses",
          pl_handle_remove_mob_effect(test_trim(remove, at), 0, table) == 0, fails)
    check_int("other effect survives", vfx_has(table, 11, 9), 1, fails)
    check_int("listed effect is gone", vfx_has(table, 11, 26), 0, fails)
    check_int("one effect remains", vfx_active_count(table), 1, fails)

    check("unknown entity has no effect", vfx_has(table, 909, 9) == 0, fails)
    check_int("missing amplifier reads as absent",
              vfx_amplitude(table, 909, 9), vfx_absent(), fails)
    check_int("missing duration reads as absent",
              vfx_duration(table, 909, 9), vfx_absent(), fails)
    check_int("missing colour reads as absent",
              vfx_colour(table, 909, 9), vfx_absent(), fails)

    int64[] bad = new int64[16]
    bad[0] = 0x80
    check("truncated effect id is refused",
          pl_handle_update_mob_effect(test_trim(bad, 1), 0, table) != 0, fails)
    int64[] no_flags = new int64[16]
    int64 s = test_write(no_flags, 0, encode_varint(4))
    s = test_write(no_flags, s, encode_varint(5))
    s = test_write(no_flags, s, encode_varint(1))
    s = test_write(no_flags, s, encode_varint(2))
    check("truncated flags byte is refused",
          pl_handle_update_mob_effect(test_trim(no_flags, s), 0, table) != 0,
          fails)
    int64[] no_colour = test_effect_packet(4, 5, 1, 2, 8)
    check("missing colour varint is refused",
          pl_handle_update_mob_effect(test_trim(no_colour, len(no_colour) - 1),
                                      0, table) != 0, fails)
    check("negative effect id is refused",
          pl_handle_update_mob_effect(test_effect_packet(4, -5, 1, 2, 0), 0,
                                      table) != 0, fails)
    check_int("refusals left the table alone", vfx_active_count(table), 1, fails)

    vfx_free(table)


# Builds a varint-prefixed string exactly as the scoreboard packets send one.
def test_write_str(target: int64[], position: int64, text: str) -> int64:
    int64 length = mc_string_length(text)
    int64 next = test_write(target, position, encode_varint(length))
    int64 index = 0
    while index < length:
        target[next + index] = mc_string_byte(text, index)
        index = index + 1
    return next + length


# A 26.3 component is an unnamed network NBT tag; a plain string is a String
# tag with its 16-bit big-endian length.
def test_write_component(target: int64[], position: int64, text: str) -> int64:
    target[position] = 8
    int64 length = mc_string_length(text)
    target[position + 1] = length >> 8 & 255
    target[position + 2] = length & 255
    int64 index = 0
    while index < length:
        target[position + 3 + index] = mc_string_byte(text, index)
        index = index + 1
    return position + 3 + length


def test_tab_list(fails: int*) -> void:
    print("protocol play: tab list")
    VPlayers* list = vplayers_new()
    int64[] flat = new int64[64]

    # A full add: every action bit is set, so every field is present exactly in
    # declaration order.
    int64[] full = new int64[192]
    int64 at = 1
    full[0] = 255
    at = test_write(full, at, encode_varint(1))
    int64 uuid_at = at
    int64 seed = 0
    while seed < 16:
        full[at + seed] = 10 + seed
        seed = seed + 1
    at = at + 16
    at = test_write_str(full, at, "Alex")
    at = test_write(full, at, encode_varint(0))
    full[at] = 0
    at = at + 1
    at = test_write(full, at, encode_varint(3))
    at = test_write(full, at, encode_varint(1))
    at = test_write(full, at, encode_varint(70))
    full[at] = 1
    at = at + 1
    at = test_write_component(full, at, "Best Alex")
    at = test_write(full, at, encode_varint(4))
    full[at] = 1
    at = at + 1
    check("a full add parses",
          pl_handle_player_info_update(0, test_trim(full, at), 0, list,
                                       flat) == 0, fails)
    check_int("one row", vplayers_active_count(list), 1, fails)
    check_int("row uuid first byte", vplayers_row_uuid(list, 0), 10, fails)
    check_int("row name length", vplayers_row_length(list, 0), 4, fails)
    check_int("row name first byte", vplayers_row_name_byte(list, 0, 0), 65,
              fails)
    check_int("game mode stored",
              vplayers_game_mode(list, full, uuid_at), 3, fails)
    check_int("listed stored", vplayers_is_listed(list, full, uuid_at), 1, fails)
    check_int("latency stored", vplayers_latency(list, full, uuid_at), 70, fails)
    check_int("priority stored", vplayers_priority(list, full, uuid_at), 4,
              fails)
    check_int("hat stored", vplayers_hat(list, full, uuid_at), 1, fails)
    check_int("chat session absent", vplayers_has_chat(list, full, uuid_at), 0,
              fails)
    check_int("display name length", vplayers_row_display_length(list, 0), 9,
              fails)
    check_int("display name first byte", vplayers_row_display_byte(list, 0, 0),
              66, fails)

    # An update for somebody the client has never met is walked and dropped:
    # latency alone must not invent a tab entry.
    int64[] stranger = new int64[32]
    at = test_write(stranger, 0, encode_varint(16))
    at = test_write(stranger, at, encode_varint(1))
    int64 stranger_uuid = at
    seed = 0
    while seed < 16:
        stranger[at + seed] = 200 + seed
        seed = seed + 1
    at = at + 16
    at = test_write(stranger, at, encode_varint(15))
    check("an update for a stranger parses",
          pl_handle_player_info_update(0, test_trim(stranger, at), 0, list,
                                       flat) == 0, fails)
    check_int("a stranger was not added", vplayers_active_count(list), 1, fails)

    # A chat session carries the expiry, the key and the signature buffers.
    int64[] session = new int64[96]
    at = test_write(session, 0, encode_varint(2))
    at = test_write(session, at, encode_varint(1))
    seed = 0
    while seed < 16:
        session[at + seed] = 10 + seed
        seed = seed + 1
    at = at + 16
    int64 session_uuid = at - 16
    session[at] = 1
    at = at + 1
    seed = 0
    while seed < 24:
        session[at + seed] = 7
        seed = seed + 1
    at = at + 24
    at = test_write(session, at, encode_varint(4))
    seed = 0
    while seed < 4:
        session[at + seed] = 1
        seed = seed + 1
    at = at + 4
    at = test_write(session, at, encode_varint(2))
    session[at] = 2
    session[at + 1] = 3
    at = at + 2
    check("a chat session parses",
          pl_handle_player_info_update(0, test_trim(session, at), 0, list,
                                       flat) == 0, fails)
    check_int("the session was recorded",
              vplayers_has_chat(list, session, session_uuid), 1, fails)
    check_int("the update kept the row count", vplayers_active_count(list), 1,
              fails)

    # A body with bytes past the last field is a desynchronisation, so it is
    # refused rather than half-applied.
    int64[] ragged = new int64[32]
    at = test_write(ragged, 0, encode_varint(16))
    at = test_write(ragged, at, encode_varint(1))
    seed = 0
    while seed < 16:
        ragged[at + seed] = 10 + seed
        seed = seed + 1
    at = at + 16
    at = test_write(ragged, at, encode_varint(9))
    ragged[at] = 5
    at = at + 1
    check("leftover bytes after a player update are refused",
          pl_handle_player_info_update(0, test_trim(ragged, at), 0, list,
                                       flat) != 0, fails)

    int64[] short = new int64[8]
    at = test_write(short, 0, encode_varint(1))
    at = test_write(short, at, encode_varint(1))
    short[at] = 1
    at = at + 1
    check("a truncated player update is refused",
          pl_handle_player_info_update(0, test_trim(short, at), 0, list,
                                       flat) != 0, fails)

    check("by-name lookup finds the row",
          vplayers_slot_by_name(list, "Alex") == 0, fails)
    check_int("by-name lookup misses", vplayers_slot_by_name(list, "Nobody"),
              vplayers_absent(), fails)
    check_int("a row past the list has no uuid",
              vplayers_row_uuid(list, vplayers_capacity()), vplayers_absent(),
              fails)
    vplayers_free(list)


def test_attributes(fails: int*) -> void:
    print("protocol play: attributes")
    VAttributes* table = vat_new()

    check_int("max health has a numeric key", vat_key_max_health(), 19, fails)
    check_int("movement speed has a numeric key", vat_key_movement_speed(), 22,
              fails)
    check_int("a bare name resolves", vat_key_by_name("generic.max_health"), 19,
              fails)
    check_int("an unknown name has no key",
              vat_key_by_name("generic.not_an_attribute"), vat_absent(), fails)

    check("max health stored",
          vat_set(table, 3, vat_key_max_health(), 20.0, 0) == 1, fails)
    test_near("max health read back",
              vat_lookup(table, 3, "minecraft:generic.max_health"), 20.0, fails)
    check_int("no modifiers",
              vat_lookup_modifier_count(table, 3, "minecraft:generic.max_health"),
              0, fails)
    check_int("one row", vat_active_count(table), 1, fails)

    check("move speed stored",
          vat_set(table, 3, vat_key_movement_speed(), 0.2, 2) == 1, fails)
    check_int("two rows", vat_active_count(table), 2, fails)
    check_int("entity row total", vat_entity_rows(table, 3), 2, fails)
    test_near("move speed read back", vat_value(table, 3, vat_key_movement_speed()),
              0.2, fails)
    check_int("modifiers counted",
              vat_modifier_count(table, 3, vat_key_movement_speed()), 2, fails)

    check("an update replaces the value",
          vat_set(table, 3, vat_key_max_health(), 12.0, 1) == 1, fails)
    test_near("replaced value",
              vat_lookup(table, 3, "minecraft:generic.max_health"), 12.0, fails)
    check_int("replacement added no row", vat_active_count(table), 2, fails)

    check("another entity has its own row",
          vat_set(table, 9, vat_key_max_health(), 10.0, 0) == 1, fails)
    test_near("second entity value",
              vat_lookup(table, 9, "minecraft:generic.max_health"), 10.0, fails)
    test_near("first entity value untouched",
              vat_lookup(table, 3, "minecraft:generic.max_health"), 12.0, fails)

    test_near("an attribute the entity lacks is missing",
              vat_value(table, 3, vat_key_flying_speed()), -1.0, fails)
    check_int("an attribute the entity lacks has no modifier count",
              vat_modifier_count(table, 3, vat_key_flying_speed()),
              vat_absent(), fails)
    test_near("an unknown entity is missing",
              vat_value(table, 404, vat_key_max_health()), -1.0, fails)
    check("a key past the registry is refused",
          vat_set(table, 3, vat_key_count(), 1.0, 0) == 0, fails)
    check_int("the refusal added no row", vat_active_count(table), 3, fails)

    check("the default health is the vanilla one",
          vat_max_health(table, 404) == 20.0, fails)
    test_near("a published health wins", vat_max_health(table, 9), 10.0, fails)

    vat_remove(table, 3, vat_key_movement_speed())
    check_int("a single row can be dropped", vat_entity_rows(table, 3), 1, fails)

    vat_remove_entity(table, 3)
    check_int("the despawned entity has no rows", vat_entity_rows(table, 3), 0,
              fails)
    check_int("the other entity survives", vat_entity_rows(table, 9), 1, fails)
    check_int("the total dropped", vat_active_count(table), 1, fails)
    test_near("a dropped value is missing",
              vat_lookup(table, 3, "minecraft:generic.max_health"), -1.0, fails)

    int live = vat_capacity()
    int scan = 0
    while scan < vat_capacity():
        if vat_row_entity(table, scan) >= 0:
            live = scan
            scan = vat_capacity()
        scan = scan + 1
    check("a live row was found", live < vat_capacity(), fails)
    check_int("live row entity", vat_row_entity(table, live), 9, fails)
    check_int("live row key", vat_row_key(table, live), vat_key_max_health(),
              fails)
    check_int("live row modifier count", vat_row_modifier_count(table, live), 0,
              fails)
    test_near("live row value", vat_row_value(table, live), 10.0, fails)

    check_int("an index past the table has no entity",
              vat_row_entity(table, vat_capacity()), vat_absent(), fails)
    check_int("a dropped row has no key", vat_row_key(table, 0),
              vat_absent(), fails)
    test_near("a dropped row has no value", vat_row_value(table, 0), -1.0, fails)
    vat_free(table)


def test_meta_header(field: int, serializer: int) -> int64[]:
    return encode_varint(field | (serializer << 7))


def test_entity_state(fails: int*) -> void:
    print("protocol play: entity state")
    VEntities* table = ventities_new()

    int64[] spawn = new int64[80]
    int64 at = test_write(spawn, 0, encode_varint(7))
    int64 filler = 0
    while filler < 16:
        spawn[at] = filler
        at = at + 1
        filler = filler + 1
    at = test_write(spawn, at, encode_varint(61))
    at = test_int64_bytes(spawn, at, (int64)vt_double_to_bits(1.5))
    at = test_int64_bytes(spawn, at, (int64)vt_double_to_bits(-2.25))
    at = test_int64_bytes(spawn, at, (int64)vt_double_to_bits(3.0))
    spawn[at] = 64
    spawn[at + 1] = 128
    spawn[at + 2] = 10
    at = at + 3
    spawn[at] = 1
    spawn[at + 1] = 144
    spawn[at + 2] = 224
    spawn[at + 3] = 192
    spawn[at + 4] = 0
    spawn[at + 5] = 0
    check("spawn packet parses", pl_handle_spawn_entity(spawn, 0, table) == 0, fails)
    check_int("spawn recorded the type", ventities_type(table, 7), 61, fails)
    test_near("spawn recorded x", ventities_position(table, 7, 0), 1.5, fails)
    test_near("spawn recorded y", ventities_position(table, 7, 1), -2.25, fails)
    test_near("spawn recorded z", ventities_position(table, 7, 2), 3.0, fails)
    test_near("spawn recorded yaw", ventities_angle(table, 7, 0), 180.0, fails)
    test_near("spawn recorded pitch", ventities_angle(table, 7, 1), 90.0, fails)
    test_near("spawn recorded head yaw", ventities_angle(table, 7, 2), 14.0625, fails)
    test_near("spawn recorded x motion", ventities_motion(table, 7, 0), 0.05, fails)
    test_near("spawn recorded y motion", ventities_motion(table, 7, 1), -1.0, fails)
    check_int("spawned entity is live", ventities_flag(table, 7, vent_flag_live()), 1, fails)
    int64[] short_spawn = new int64[at]
    int64 copy = 0
    while copy < at - 6:
        short_spawn[copy] = spawn[copy]
        copy = copy + 1
    check("spawn without motion still parses",
          pl_handle_spawn_entity(short_spawn, 0, table) == 0, fails)
    int64[] clipped = new int64[6]
    copy = 0
    while copy < 6:
        clipped[copy] = spawn[copy]
        copy = copy + 1
    check("spawn without a type is refused",
          pl_handle_spawn_entity(clipped, 0, table) != 0, fails)

    int64[] meta = new int64[96]
    int64 m = test_write(meta, 0, encode_varint(7))
    meta[m] = 0
    m = m + 1
    meta[m] = 3
    m = m + 1
    m = test_write(meta, m, test_meta_header(1, 1))
    m = test_write(meta, m, encode_varint(300))
    m = test_write(meta, m, test_meta_header(5, 3))
    m = test_float_bytes(meta, m, 1.5)
    m = test_write(meta, m, test_meta_header(2, 6))
    meta[m] = 1
    m = m + 1
    # The 26.3 component is an unnamed NBT tag: a String tag with its
    # 16-bit length, not a length prefixed JSON document.
    meta[m] = 8
    m = m + 1
    meta[m] = 0
    meta[m + 1] = 7
    m = m + 2
    m = test_write(meta, m, test_line("Creeper"))
    m = test_write(meta, m, test_meta_header(20, 7))
    meta[m] = 0
    m = m + 1
    # The 26.3 registry sends an entity reference as an optional UUID: the
    # ordinal is 13, not the 8 that older lists give to "optional uuid".
    m = test_write(meta, m, test_meta_header(9, 13))
    meta[m] = 1
    m = m + 1
    int64 uuid_byte = 0
    while uuid_byte < 16:
        meta[m] = uuid_byte
        m = m + 1
        uuid_byte = uuid_byte + 1
    m = test_write(meta, m, test_meta_header(3, 2))
    m = test_write(meta, m, encode_varint(123456789))
    # The terminator is a varint, so 255 is two bytes on the wire.
    m = test_write(meta, m, encode_varint(255))
    check("metadata stream parses", pl_handle_entity_metadata(meta, 0, table) == 0, fails)
    check_int("flag byte landed in field 0",
              (int)ventities_value(table, 7, 0), 3, fails)
    check_int("on fire flag", ventities_flag(table, 7, vent_flag_on_fire()), 1, fails)
    check_int("sneaking flag", ventities_flag(table, 7, vent_flag_sneaking()), 1, fails)
    check("glowing flag stays clear", ventities_flag(table, 7, vent_flag_glowing()) == 0, fails)
    check_int("varint field landed in field 1",
              (int)ventities_value(table, 7, 1), 300, fails)
    check_int("float field scaled to micro-units",
              (int)ventities_value(table, 7, 5), 1500000, fails)
    check_int("component became the name", ventities_name_length(table, 7), 7, fails)
    check_int("first name byte", ventities_name_byte(table, 7, 0), 67, fails)
    check_int("varlong field landed in field 3",
              (int)ventities_value(table, 7, 3), 123456789, fails)

    int64[] signed = new int64[8]
    int64 sg = test_write(signed, 0, encode_varint(7))
    sg = test_write(signed, sg, test_meta_header(6, 0))
    signed[sg] = 200
    sg = sg + 1
    sg = test_write(signed, sg, encode_varint(255))
    check("signed byte metadata parses",
          pl_handle_entity_metadata(signed, 0, table) == 0, fails)
    check_int("metadata byte is signed", (int)ventities_value(table, 7, 6), -56, fails)

    int64[] riders = new int64[8]
    int64 r = test_write(riders, 0, encode_varint(7))
    r = test_write(riders, r, encode_varint(2))
    r = test_write(riders, r, encode_varint(8))
    r = test_write(riders, r, encode_varint(9))
    check("passenger list parses", pl_handle_set_passengers(0, riders, 0, table) == 0, fails)
    check("passengers are known", ventities_find(table, 9) >= 0, fails)
    int64[] broken_riders = new int64[3]
    broken_riders[0] = 7
    broken_riders[1] = 3
    broken_riders[2] = 8
    check("short passenger list is refused",
          pl_handle_set_passengers(0, broken_riders, 0, table) != 0, fails)

    int64[] unsupported = new int64[8]
    int64 u = test_write(unsupported, 0, encode_varint(7))
    u = test_write(unsupported, u, test_meta_header(0, 14))
    check("unknown serializer is refused",
          pl_handle_entity_metadata(unsupported, 0, table) != 0, fails)

    int64[] unterminated = new int64[3]
    unterminated[0] = 7
    unterminated[1] = 0
    unterminated[2] = 3
    check("metadata without a terminator is refused",
          pl_handle_entity_metadata(unterminated, 0, table) != 0, fails)

    int64[] delta = new int64[8]
    int64 d = test_write(delta, 0, encode_varint(7))
    # The 26.3 record packs one varint before the coordinates: bit 0 is
    # on-ground and the remaining bits count the stepped deltas that follow.
    d = test_write(delta, d, encode_varint(1))
    delta[d] = 16
    delta[d + 1] = 0
    delta[d + 2] = 224
    delta[d + 3] = 0
    delta[d + 4] = 16
    delta[d + 5] = 0
    d = d + 6
    check("delta move parses",
          pl_handle_entity_position(0, delta, 0, 1, table) == 0, fails)
    test_near("delta moved x", ventities_position(table, 7, 0), 2.5, fails)
    test_near("delta moved y", ventities_position(table, 7, 1), -4.25, fails)
    test_near("delta moved z", ventities_position(table, 7, 2), 4.0, fails)
    check_int("delta set on ground",
              ventities_flag(table, 7, vent_flag_on_ground()), 1, fails)

    int64[] truncated_teleport = new int64[28]
    truncated_teleport[0] = 7
    check("truncated teleport angle/ground fields are refused",
          pl_handle_entity_position(0, truncated_teleport, 0, 3, table) != 0,
          fails)

    int64[] teleport = new int64[64]
    int64 t = test_write(teleport, 0, encode_varint(7))
    t = test_int64_bytes(teleport, t, (int64)vt_double_to_bits(10.0))
    t = test_int64_bytes(teleport, t, (int64)vt_double_to_bits(20.0))
    t = test_int64_bytes(teleport, t, (int64)vt_double_to_bits(30.0))
    teleport[t] = 0
    teleport[t + 1] = 0
    teleport[t + 2] = 0
    teleport[t + 3] = 0
    teleport[t + 4] = 0
    check("teleport parses",
          pl_handle_entity_position(0, teleport, 0, 3, table) == 0, fails)
    test_near("teleport replaced x", ventities_position(table, 7, 0), 10.0, fails)
    test_near("teleport replaced y", ventities_position(table, 7, 1), 20.0, fails)
    check("on ground cleared by teleport",
          ventities_flag(table, 7, vent_flag_on_ground()) == 0, fails)

    int64[] head = new int64[4]
    int64 h = test_write(head, 0, encode_varint(7))
    head[h] = 64
    check("head rotation parses", pl_handle_rotate_head(0, head, 0, table) == 0, fails)
    test_near("head rotation applied", ventities_angle(table, 7, 2), 90.0, fails)

    int64[] cut = new int64[4]
    int64 c = test_write(cut, 0, encode_varint(1))
    c = test_write(cut, c, encode_varint(7))
    VEffects* removed_carrier = vfx_new()
    check("effect attached before removal",
          pl_handle_update_mob_effect(test_effect_packet(7, 9, 1, 200, 0), 0,
                                      removed_carrier) == 0, fails)
    check("removal parses",
          pl_handle_remove_entities(cut, 0, table, removed_carrier,
                                    (VAttributes*)0) == 0, fails)
    check("removed entity is gone", ventities_find(table, 7) < 0, fails)
    check("removal cleared the entity effects",
          vfx_has(removed_carrier, 7, 9) == 0, fails)
    ventities_free(table)
    vfx_free(removed_carrier)


def test_boss_bars(fails: int*) -> void:
    print("protocol play: boss bars")
    VBossBars* bars = vboss_new()
    int64[] body = new int64[80]
    int64 at = test_write(body, 0, encode_varint(vboss_action_add()))
    int64 uuid_at = at
    int64 byte = 0
    while byte < 16:
        body[at] = byte + 1
        at = at + 1
        byte = byte + 1
    body[at] = 8
    body[at + 1] = 0
    body[at + 2] = 12
    at = at + 3
    at = test_write(body, at, test_line("Ender Dragon"))
    at = test_float_bytes(body, at, 0.75)
    body[at] = 5
    body[at + 1] = 6
    body[at + 2] = 7
    at = at + 3
    check("boss add parses", pl_handle_boss_event(body, 0, bars) == 0, fails)
    check_int("one bar is shown", bars.count, 1, fails)
    test_near("boss health", vboss_health(bars, body, uuid_at), 0.75, fails)
    check_int("boss color", vboss_color(bars, body, uuid_at), 5, fails)
    check_int("boss style", vboss_style(bars, body, uuid_at), 6, fails)
    check_int("boss flags", vboss_flags(bars, body, uuid_at), 7, fails)
    check_int("boss name length", vboss_name_length(bars, body, uuid_at), 12, fails)
    check_int("first boss name byte", vboss_name_byte(bars, body, uuid_at, 0), 69, fails)

    int64[] other = new int64[20]
    byte = 0
    while byte < 16:
        other[byte] = byte
        byte = byte + 1
    check("an unknown bar is absent", vboss_find(bars, other, 0) < 0, fails)
    test_near("missing bar health reads as -1", vboss_health(bars, other, 0), -1.0, fails)

    int64[] properties = new int64[80]
    at = test_write(properties, 0, encode_varint(vboss_action_update_properties()))
    byte = 0
    while byte < 16:
        properties[at] = byte + 1
        at = at + 1
        byte = byte + 1
    at = test_float_bytes(properties, at, 0.5)
    check("health update parses", pl_handle_boss_event(properties, 0, bars) == 0, fails)
    test_near("health update applied", vboss_health(bars, body, uuid_at), 0.5, fails)
    check_int("style survives a health update", vboss_style(bars, body, uuid_at), 6, fails)

    int64[] style = new int64[80]
    at = test_write(style, 0, encode_varint(vboss_action_update_style()))
    byte = 0
    while byte < 16:
        style[at] = byte + 1
        at = at + 1
        byte = byte + 1
    style[at] = 2
    style[at + 1] = 4
    check("style update parses", pl_handle_boss_event(style, 0, bars) == 0, fails)
    check_int("color update applied", vboss_color(bars, body, uuid_at), 2, fails)
    check_int("style update applied", vboss_style(bars, body, uuid_at), 4, fails)

    int64[] options = new int64[80]
    at = test_write(options, 0, encode_varint(vboss_action_update_options()))
    byte = 0
    while byte < 16:
        options[at] = byte + 1
        at = at + 1
        byte = byte + 1
    options[at] = 1
    check("options update parses", pl_handle_boss_event(options, 0, bars) == 0, fails)
    check_int("options update applied", vboss_flags(bars, body, uuid_at), 1, fails)

    int64[] remove = new int64[80]
    at = test_write(remove, 0, encode_varint(vboss_action_remove()))
    byte = 0
    while byte < 16:
        remove[at] = byte + 1
        at = at + 1
        byte = byte + 1
    check("removal parses", pl_handle_boss_event(remove, 0, bars) == 0, fails)
    check_int("bar was removed", bars.count, 0, fails)

    int64[] clipped = new int64[4]
    clipped[0] = 0
    check("a header without a uuid is refused",
          pl_handle_boss_event(clipped, 0, bars) != 0, fails)
    vboss_free(bars)


# Update Attributes begins with the entity and how many properties follow.
def test_attr_head(target: int64[], entity: int64, count: int64) -> int64:
    int64 next = test_write(target, 0, encode_varint(entity))
    return test_write(target, next, encode_varint(count))


# One property without modifiers: registry id, post-modifier total, zero count.
def test_attr_property(target: int64[], position: int64, key: int64,
                       value: double) -> int64:
    int64 next = test_write(target, position, encode_varint(key))
    next = test_int64_bytes(target, next, (int64)vt_double_to_bits(value))
    return test_write(target, next, encode_varint(0))


# One modifier, with the uuid either prefixed (the generated schema) or raw
# (what the vanilla server has put on the wire).
def test_attr_modifier(target: int64[], position: int64, prefixed_uuid: bool,
                       amount: double, operation: int64) -> int64:
    int64 next = position
    if prefixed_uuid:
        next = test_write(target, next, encode_varint(16))
    int64 index = 0
    while index < 16:
        target[next + index] = index
        index = index + 1
    next = next + 16
    next = test_int64_bytes(target, next, (int64)vt_double_to_bits(amount))
    target[next] = operation
    return next + 1


def test_score_str(board: VScoreboard*, text: str) -> int:
    int64[] needle = test_line(text)
    return vscore_team_index(board, needle, 0, (int64)len(needle))


# Membership is a separate lookup: the same name can be a team id and a player.
def test_team_of(board: VScoreboard*, text: str) -> int:
    int64[] needle = test_line(text)
    return vscore_find_team_of(board, needle, 0, (int64)len(needle))


# A 4 byte big-endian Int, the width the wire uses for titles, sound
# coordinates and world events.
def test_int_field(target: int64[], position: int64, value: int64) -> int64:
    int64 index = 0
    while index < 4:
        target[position + index] = value >> (3 - index) * 8 & 0xFF
        index = index + 1
    return position + 4


def test_position(target: int64[], position: int64, x: int64, y: int64,
                  z: int64) -> int64:
    return test_int64_bytes(target, position, pl_pack_block_pos(x, y, z))


def test_real_bytes(target: int64[], position: int64, value: double) -> int64:
    int64 index = 0
    while index < 8:
        target[position + index] = mc_double_be_byte(value, index)
        index = index + 1
    return position + 8


# The fixed emitter description in front of every particle: the two flags, a
# double position, three float spreads, a float velocity and an integer count.
def test_particle_head(target: int64[], long_distance: int64,
                       always_show: int64, amount: int64) -> void:
    target[0] = long_distance
    target[1] = always_show
    int64 index = 0
    while index < 8:
        target[2 + index] = mc_double_be_byte(12.5, index)
        target[10 + index] = mc_double_be_byte(-34.5, index)
        target[18 + index] = mc_double_be_byte(56.5, index)
        index = index + 1
    test_float_bytes(target, 26, 0.5)
    test_float_bytes(target, 30, 0.25)
    test_float_bytes(target, 34, 0.125)
    test_float_bytes(target, 38, 0.0625)
    index = 0
    while index < 4:
        target[42 + index] = amount >> (3 - index) * 8 & 0xFF
        index = index + 1


def test_particles(fails: int*) -> void:
    print("protocol play: particles")
    VParticles* queue = vparts_new()
    check_int("the queue starts empty", vparts_count(queue), 0, fails)

    int64 at = 0
    int64[] plain = new int64[48]
    test_particle_head(plain, 0, 0, 4)
    plain[46] = vparts_kind_block()
    plain[47] = 0
    check("a block emitter parses",
          pl_handle_level_particles(0, plain, 0, queue) == 0, fails)
    check_int("one record", vparts_count(queue), 1, fails)
    check_int("the kind was kept", vparts_row_kind(queue, 0),
              vparts_kind_block(), fails)
    check_int("the count was kept", vparts_row_amount(queue, 0), 4, fails)
    check_int("no flags", vparts_row_flags(queue, 0), 0, fails)
    test_near("the emitter position", vparts_row_x(queue, 0), 12.5, fails)
    test_near("the emitter height", vparts_row_y(queue, 0), -34.5, fails)
    test_near("the emitter depth", vparts_row_z(queue, 0), 56.5, fails)
    check_int("the spread was quantised", vparts_row_offset_x(queue, 0), 500,
              fails)
    check_int("the velocity was quantised", vparts_row_velocity(queue, 0), 62,
              fails)
    check_int("the blockstate was stored",
              (int)vparts_row_payload(queue, 0, 0), 0, fails)
    check_int("one payload word", vparts_row_payload_length(queue, 0), 1, fails)
    check_int("a word past the record is absent",
              (int)vparts_row_payload(queue, 0, 1), vparts_no_data(), fails)

    int64[] both = new int64[48]
    test_particle_head(both, 1, 1, 1)
    both[46] = vparts_kind_block()
    both[47] = 77
    check("the flags parse",
          pl_handle_level_particles(0, both, 0, queue) == 0, fails)
    check_int("both flags were kept", vparts_row_flags(queue, 1),
              vparts_flag_long_distance() | vparts_flag_always_show(), fails)
    check_int("the blockstate payload",
              (int)vparts_row_payload(queue, 1, 0), 77, fails)

    vparts_clear(queue)
    check_int("the queue cleared", vparts_count(queue), 0, fails)

    # dust: a colour and a scale.
    int64[] dust = new int64[55]
    test_particle_head(dust, 0, 0, 1)
    dust[46] = vparts_kind_dust()
    dust[47] = 0x11
    dust[48] = 0x22
    dust[49] = 0x33
    dust[50] = 0x44
    test_float_bytes(dust, 51, 2.5)
    check("dust parses", pl_handle_level_particles(0, dust, 0, queue) == 0,
          fails)
    check_int("dust has two words", vparts_row_payload_length(queue, 0), 2,
              fails)
    check_int("dust colour", (int)vparts_row_payload(queue, 0, 0), 0x11223344,
              fails)
    test_near("dust scale", vparts_row_payload_double(queue, 0, 1), 2.5, fails)

    # dust_color_transition: two colours and a scale.
    int64[] fade = new int64[59]
    test_particle_head(fade, 0, 0, 1)
    fade[46] = vparts_kind_dust_color_transition()
    fade[47] = 0
    fade[48] = 0
    fade[49] = 0
    fade[50] = 1
    fade[51] = 0
    fade[52] = 0
    fade[53] = 0
    fade[54] = 2
    test_float_bytes(fade, 55, 1.0)
    check("a colour transition parses",
          pl_handle_level_particles(0, fade, 0, queue) == 0, fails)
    check_int("transition words", vparts_row_payload_length(queue, 1), 3, fails)
    check_int("the first colour", (int)vparts_row_payload(queue, 1, 0), 1, fails)
    check_int("the second colour", (int)vparts_row_payload(queue, 1, 1), 2, fails)

    # effect: a colour and a power.
    int64[] effect = new int64[55]
    test_particle_head(effect, 0, 0, 1)
    effect[46] = vparts_kind_effect()
    effect[47] = 0
    effect[48] = 0
    effect[49] = 0
    effect[50] = 9
    test_float_bytes(effect, 51, 0.5)
    check("an effect particle parses",
          pl_handle_level_particles(0, effect, 0, queue) == 0, fails)
    check_int("effect colour", (int)vparts_row_payload(queue, 2, 0), 9, fails)

    # sculk_charge: a single float.
    int64[] charge = new int64[51]
    test_particle_head(charge, 0, 0, 1)
    charge[46] = vparts_kind_sculk_charge()
    test_float_bytes(charge, 47, 3.25)
    check("a sculk charge parses",
          pl_handle_level_particles(0, charge, 0, queue) == 0, fails)
    test_near("the charge phase", vparts_row_payload_double(queue, 3, 0), 3.25,
              fails)

    # item: a whole stack, components and all.
    int64[] carried = new int64[52]
    test_particle_head(carried, 0, 0, 1)
    carried[46] = vparts_kind_item()
    carried[47] = 3
    at = test_write(carried, 48, encode_varint(1457))
    at = test_write(carried, at, encode_varint(0))
    at = test_write(carried, at, encode_varint(0))
    check("an item particle parses",
          pl_handle_level_particles(0, test_trim(carried, at), 0, queue) == 0,
          fails)
    check_int("the item id", (int)vparts_row_payload(queue, 4, 0), 1457, fails)
    check_int("the item count", (int)vparts_row_payload(queue, 4, 1), 3, fails)

    # shriek: one varint.
    int64[] shriek = new int64[48]
    test_particle_head(shriek, 0, 0, 1)
    shriek[46] = vparts_kind_shriek()
    shriek[47] = 20
    check("a shriek parses", pl_handle_level_particles(0, shriek, 0, queue) == 0,
          fails)
    check_int("the shriek delay", (int)vparts_row_payload(queue, 5, 0), 20, fails)

    # vibration against a block position.
    int64[] shake = new int64[57]
    test_particle_head(shake, 0, 0, 1)
    shake[46] = vparts_kind_vibration()
    shake[47] = vparts_vibration_position()
    at = test_position(shake, 48, 1, 2, 3)
    shake[at] = 5
    check("a position vibration parses",
          pl_handle_level_particles(0, test_trim(shake, at + 1), 0, queue) == 0,
          fails)
    check_int("vibration selector", (int)vparts_row_payload(queue, 6, 0),
              vparts_vibration_position(), fails)
    check_int("vibration target", (int)vparts_row_payload(queue, 6, 1),
              (int)pl_pack_block_pos(1, 2, 3), fails)
    check_int("vibration delay", (int)vparts_row_payload(queue, 6, 2), 5, fails)

    # vibration against an entity.
    int64[] follow = new int64[54]
    test_particle_head(follow, 0, 0, 1)
    follow[46] = vparts_kind_vibration()
    follow[47] = vparts_vibration_entity()
    follow[48] = 9
    test_float_bytes(follow, 49, 1.62)
    follow[53] = 7
    check("an entity vibration parses",
          pl_handle_level_particles(0, follow, 0, queue) == 0, fails)
    check_int("the tracked entity", (int)vparts_row_payload(queue, 7, 1), 9, fails)
    check_int("four words", vparts_row_payload_length(queue, 7), 4, fails)

    # trail: a double target, a colour and a duration.
    int64[] comet = new int64[76]
    test_particle_head(comet, 0, 0, 1)
    comet[46] = vparts_kind_trail()
    test_real_bytes(comet, 47, 1.5)
    test_real_bytes(comet, 55, 2.5)
    test_real_bytes(comet, 63, 3.5)
    test_int_field(comet, 71, 8)
    comet[75] = 40
    check("a trail parses", pl_handle_level_particles(0, comet, 0, queue) == 0,
          fails)
    check_int("trail words", vparts_row_payload_length(queue, 8), 5, fails)
    test_near("the trail target", vparts_row_payload_double(queue, 8, 2), 3.5,
              fails)
    check_int("the trail colour", (int)vparts_row_payload(queue, 8, 3), 8, fails)
    check_int("the trail duration", (int)vparts_row_payload(queue, 8, 4), 40,
              fails)

    # flash: a duration integer.
    int64[] lit = new int64[51]
    test_particle_head(lit, 0, 0, 1)
    lit[46] = vparts_kind_flash()
    test_int_field(lit, 47, 2000)
    check("a flash parses", pl_handle_level_particles(0, lit, 0, queue) == 0,
          fails)
    check_int("the flash duration", (int)vparts_row_payload(queue, 9, 0), 2000,
              fails)

    # Refusals.
    check("a truncated emitter is refused",
          pl_handle_level_particles(0, test_trim(comet, 40), 0, queue) != 0,
          fails)
    int64[] negative = new int64[48]
    test_particle_head(negative, 0, 0, -1)
    negative[46] = vparts_kind_block()
    negative[47] = 1
    check("a negative amount is refused",
          pl_handle_level_particles(0, negative, 0, queue) != 0, fails)
    int64[] unknown = new int64[48]
    test_particle_head(unknown, 0, 0, 1)
    unknown[46] = vparts_kind_max() + 1
    unknown[47] = 1
    check("a particle id past the registry is refused",
          pl_handle_level_particles(0, unknown, 0, queue) != 0, fails)
    int64[] ragged = new int64[56]
    test_particle_head(ragged, 0, 0, 1)
    ragged[46] = vparts_kind_dust()
    ragged[47] = 0
    ragged[48] = 0
    ragged[49] = 0
    ragged[50] = 1
    test_float_bytes(ragged, 51, 1.0)
    ragged[55] = 9
    check("a particle packet with leftovers is refused",
          pl_handle_level_particles(0, ragged, 0, queue) != 0, fails)
    int64[] short_payload = new int64[51]
    test_particle_head(short_payload, 0, 0, 1)
    short_payload[46] = vparts_kind_dust()
    short_payload[47] = 0
    short_payload[48] = 0
    check("a truncated particle payload is refused",
          pl_handle_level_particles(0, short_payload, 0, queue) != 0, fails)

    # The ring overwrites the oldest record once it is full. Feeding it
    # directly keeps the packet decoder out of a thousand-line loop.
    vparts_clear(queue)
    int64[] filler = new int64[1]
    int refusals = 0
    int round = 0
    while round < vparts_capacity() + 5:
        filler[0] = round % 250 + 1
        if vparts_push(queue, vparts_kind_block(), 0.0, 0.0, 0.0, 0, 0, 0, 0,
                       1, 0, filler, 1) < 0:
            refusals = refusals + 1
        round = round + 1
    check_int("every record was accepted", refusals, 0, fails)
    check_int("the queue stays at capacity", vparts_count(queue),
              vparts_capacity(), fails)
    check_int("the oldest record was replaced",
              (int)vparts_row_payload(queue, 0, 0), 6, fails)
    check_int("the newest record is last",
              (int)vparts_row_payload(queue, vparts_capacity() - 1, 0), 29, fails)
    check_int("a row past the queue is absent", vparts_row_kind(queue,
              vparts_capacity()), vparts_absent(), fails)
    vparts_free(queue)


def test_difficulty_and_camera(fails: int*) -> void:
    print("protocol play: difficulty, camera and ticking")
    VPlayState* state = test_state()

    int64[] hard = new int64[2]
    hard[0] = 3
    hard[1] = 1
    check("difficulty parses",
          pl_handle_change_difficulty(0, hard, 0, state) == 0, fails)
    check_int("the level was kept", state.difficulty, 3, fails)
    check("the lock was kept", state.difficulty_locked, fails)

    int64[] unlocked = new int64[2]
    unlocked[0] = 1
    check("an unlocked difficulty parses",
          pl_handle_change_difficulty(0, unlocked, 0, state) == 0, fails)
    check_int("the level changed", state.difficulty, 1, fails)
    check("the lock cleared", state.difficulty_locked == false, fails)

    int64[] impossible = new int64[2]
    impossible[0] = 7
    impossible[1] = 0
    check("a difficulty outside the enum is refused",
          pl_handle_change_difficulty(0, impossible, 0, state) != 0, fails)
    int64[] no_lock = new int64[1]
    no_lock[0] = 2
    check("a difficulty without its lock is refused",
          pl_handle_change_difficulty(0, no_lock, 0, state) != 0, fails)
    int64[] long_lock = new int64[3]
    long_lock[0] = 2
    long_lock[2] = 4
    check("a difficulty with leftovers is refused",
          pl_handle_change_difficulty(0, long_lock, 0, state) != 0, fails)

    int64[] camera = new int64[1]
    camera[0] = 2
    check("a camera id parses",
          pl_handle_set_camera(0, camera, 0, state) == 0, fails)
    check_int("the camera was kept", state.camera_id, 2, fails)
    int64[] two_byte_camera = new int64[2]
    two_byte_camera[0] = 0x80
    two_byte_camera[1] = 0x01
    check("a wide camera id parses",
          pl_handle_set_camera(0, two_byte_camera, 0, state) == 0, fails)
    check_int("the wide camera was kept", state.camera_id, 128, fails)
    int64[] extra = new int64[2]
    extra[1] = 9
    check("a camera packet with leftovers is refused",
          pl_handle_set_camera(0, extra, 0, state) != 0, fails)

    int64[] ticking = new int64[5]
    test_float_bytes(ticking, 0, 2.5)
    ticking[4] = 1
    check("ticking state parses",
          pl_handle_set_ticking_state(0, ticking, 0, state) == 0, fails)
    test_near("the tick rate was kept", state.tick_rate, 2.5, fails)
    check("the freeze was kept", state.tick_frozen == true, fails)
    check("a short ticking packet is refused",
          pl_handle_set_ticking_state(0, test_trim(ticking, 4), 0,
                                      state) != 0, fails)
    int64[] long_ticking = new int64[6]
    test_float_bytes(long_ticking, 0, 1.0)
    check("a ticking packet with leftovers is refused",
          pl_handle_set_ticking_state(0, long_ticking, 0, state) != 0, fails)


def test_server_packets(fails: int*) -> void:
    print("protocol play: world events, sounds and server identity")

    int64[] event = new int64[24]
    int64 at = test_int_field(event, 0, 2001)
    at = test_position(event, at, 10, 64, -20)
    at = test_int_field(event, at, 42)
    event[at] = 0
    at = at + 1
    int64[] event_body = test_trim(event, at)
    check("world event parses", pl_handle_level_event(event_body, 0) == 0, fails)
    check("world event missing its flag is refused",
          pl_handle_level_event(test_trim(event, at - 1), 0) != 0, fails)

    int64[] timing = new int64[12]
    at = test_int_field(timing, 0, 5)
    at = test_int_field(timing, at, 40)
    at = test_int_field(timing, at, 10)
    check("title animation parses", pl_handle_titles_animation(timing, 0) == 0,
          fails)
    check("title animation missing a field is refused",
          pl_handle_titles_animation(timing, 4) != 0, fails)

    int64[] preview = new int64[16]
    at = test_position(preview, 0, 3, -10, 7)
    at = test_write(preview, at, encode_varint(1500))
    check("transient block parses",
          pl_handle_add_transient_block(test_trim(preview, at), 0) == 0, fails)
    check("transient block without a state is refused",
          pl_handle_add_transient_block(test_trim(preview, 8), 0) != 0, fails)
    preview[8] = 0x80
    check("transient block with a broken state is refused",
          pl_handle_add_transient_block(test_trim(preview, 9), 0) != 0, fails)

    int64[] motd = new int64[64]
    int64[] listed = new int64[96]
    at = test_write_component(listed, 0, "A test server")
    listed[at] = 1
    at = at + 1
    at = test_write(listed, at, encode_varint(6))
    int64 filler = 0
    while filler < 6:
        listed[at + filler] = 70
        filler = filler + 1
    at = at + 6
    check("server data parses",
          pl_handle_server_data(test_trim(listed, at), 0, motd) == 0, fails)
    check_int("MOTD bytes kept", (int)len("A test server"), 13, fails)
    check_int("MOTD first byte", motd[0], 65, fails)
    check("server data without an icon body is refused",
          pl_handle_server_data(test_trim(listed, at - 3), 0, motd) != 0, fails)
    at = test_write_component(listed, 0, "Plain")
    check("server data without the icon flag is refused",
          pl_handle_server_data(test_trim(listed, at), 0, motd) != 0, fails)

    int64[] hidden = new int64[96]
    int64[] hidden_message = new int64[64]
    int64[] hidden_sender = new int64[64]
    int64[] hidden_target = new int64[64]
    at = test_write_component(hidden, 0, "nobody says")
    at = test_write(hidden, at, encode_varint(3))
    at = test_write_component(hidden, at, "Steve")
    check("disguised chat parses",
          pl_handle_disguised_chat(test_trim(hidden, at), 0, hidden_message,
                                   hidden_sender, hidden_target) == 0, fails)
    check_int("disguised sender kept", hidden_sender[0], 83, fails)
    check_int("disguised message kept", hidden_message[0], 110, fails)
    hidden[at] = 1
    at = at + 1
    at = test_write_component(hidden, at, "Alex")
    check("disguised chat with a target parses",
          pl_handle_disguised_chat(test_trim(hidden, at), 0, hidden_message,
                                   hidden_sender, hidden_target) == 0, fails)
    check_int("disguised target kept", hidden_target[0], 65, fails)
    at = test_write_component(hidden, 0, "ghost")
    hidden[at] = 0x80
    check("disguised chat with a broken type is refused",
          pl_handle_disguised_chat(test_trim(hidden, at + 1), 0, hidden_message,
                                   hidden_sender, hidden_target) != 0, fails)

    VPlayers* leaving = vplayers_new()
    int64[] leave_text = new int64[64]
    int64[] left = new int64[48]
    at = test_write(left, 0, encode_varint(2))
    int64 uuid_byte = 0
    while uuid_byte < 32:
        left[at + uuid_byte] = uuid_byte
        uuid_byte = uuid_byte + 1
    at = at + 32
    int64[] add_body = new int64[64]
    int64 added_at = test_write(add_body, 0, encode_varint(25))
    added_at = test_write(add_body, added_at, encode_varint(1))
    uuid_byte = 0
    while uuid_byte < 16:
        add_body[added_at + uuid_byte] = 200 + uuid_byte
        uuid_byte = uuid_byte + 1
    added_at = added_at + 16
    added_at = test_write_str(add_body, added_at, "Steve")
    added_at = test_write(add_body, added_at, encode_varint(0))
    added_at = test_write(add_body, added_at, encode_varint(1))
    added_at = test_write(add_body, added_at, encode_varint(55))
    int64[] one_more_body = test_trim(add_body, added_at)

    int64[] remove_body = test_trim(left, at)
    check("player removal parses",
          pl_handle_player_info_remove(remove_body, 0, leaving) == 0, fails)
    check_int("removing strangers leaves the list empty",
              vplayers_active_count(leaving), 0, fails)
    check("the update with an added player parses",
          pl_handle_player_info_update(0, one_more_body, 0, leaving,
                                       leave_text) == 0, fails)
    check_int("the added player is listed", vplayers_active_count(leaving), 1,
              fails)
    check_int("the added player has a name",
              vplayers_row_length(leaving, 0), 5, fails)
    check_int("the name first byte", vplayers_row_name_byte(leaving, 0, 0), 83,
              fails)
    check_int("the added player has a ping",
              vplayers_latency(leaving, one_more_body, 2), 55, fails)
    check_int("the added player is shown",
              vplayers_is_listed(leaving, one_more_body, 2), 1, fails)
    int64[] drop_body = new int64[20]
    int64 drop_at = test_write(drop_body, 0, encode_varint(1))
    int64 copy_index = 0
    while copy_index < 16:
        drop_body[drop_at + copy_index] = add_body[2 + copy_index]
        copy_index = copy_index + 1
    drop_at = drop_at + 16
    check("removal now drops the row",
          pl_handle_player_info_remove(test_trim(drop_body, drop_at), 0,
                                       leaving) == 0, fails)
    check_int("the list is empty again", vplayers_active_count(leaving), 0,
              fails)
    check("player removal past the body is refused",
          pl_handle_player_info_remove(test_trim(left, at - 8), 0,
                                       leaving) != 0, fails)
    left[0] = 0x80
    check("player removal with a broken count is refused",
          pl_handle_player_info_remove(test_trim(left, 1), 0, leaving) != 0,
          fails)
    vplayers_free(leaving)

    int64[] noise = new int64[48]
    at = test_write(noise, 0, encode_varint(9))
    at = test_write(noise, at, encode_varint(2))
    at = test_int_field(noise, at, 80)
    at = test_int_field(noise, at, 8)
    at = test_int_field(noise, at, -40)
    at = test_float_bytes(noise, at, 0.5)
    at = test_float_bytes(noise, at, 1.25)
    at = test_int64_bytes(noise, at, 1234)
    check("sound effect parses",
          pl_handle_sound(0, test_trim(noise, at), 0, false) == 0, fails)
    check("sound without a seed is refused",
          pl_handle_sound(0, test_trim(noise, at - 4), 0, false) != 0, fails)
    int64[] carried = new int64[48]
    at = test_write(carried, 0, encode_varint(9))
    at = test_write(carried, at, encode_varint(2))
    at = test_write(carried, at, encode_varint(7))
    at = test_float_bytes(carried, at, 1.0)
    at = test_float_bytes(carried, at, 0.75)
    at = test_int64_bytes(carried, at, 7)
    check("entity sound parses",
          pl_handle_sound(0, test_trim(carried, at), 0, true) == 0, fails)
    check("entity sound without a seed is refused",
          pl_handle_sound(0, test_trim(carried, at - 4), 0, true) != 0, fails)

    # Block Entity Data carries an anonymous optional NBT compound, so the
    # presence byte is part of the packet and a tile can legitimately arrive
    # with no payload at all.
    VBlockEntities* tiles = vbes_new()
    int64[] chest = new int64[40]
    at = test_position(chest, 0, 1, 2, 3)
    at = test_write(chest, at, encode_varint(0))
    check("a block entity without a payload flag is refused",
          pl_handle_block_entity_data(0, test_trim(chest, at), 0, tiles) != 0,
          fails)

    chest[at] = 0
    at = at + 1
    check("a block entity with no payload parses",
          pl_handle_block_entity_data(0, test_trim(chest, at), 0, tiles) == 0,
          fails)
    check_int("the tile is recorded", vbes_count(tiles), 1, fails)
    check_int("the tile has only its flag", vbes_payload(tiles, 1, 2, 3), 1,
              fails)
    check_int("the tile position row", vbes_row_x(tiles, 0), 1, fails)

    at = test_position(chest, 0, 1, 2, 3)
    at = test_write(chest, at, encode_varint(0))
    chest[at] = 1
    at = at + 1
    chest[at] = 10
    at = at + 1
    chest[at] = 0
    at = at + 1
    check("a block entity compound payload walks",
          pl_handle_block_entity_data(0, test_trim(chest, at), 0, tiles) == 0,
          fails)
    check_int("the payload size was stored", vbes_payload(tiles, 1, 2, 3), 3,
              fails)
    check_int("the update did not add a row", vbes_count(tiles), 1, fails)

    chest[at] = 7
    check("leftover bytes after a block entity are refused",
          pl_handle_block_entity_data(0, test_trim(chest, at + 1), 0,
                                      tiles) != 0, fails)

    at = test_position(chest, 0, 4, 5, 6)
    at = test_write(chest, at, encode_varint(0))
    chest[at] = 1
    at = at + 1
    chest[at] = 11
    at = at + 1
    check("a block entity payload that is not a compound is refused",
          pl_handle_block_entity_data(0, test_trim(chest, at), 0, tiles) != 0,
          fails)

    at = test_position(chest, 0, 4, 5, 6)
    at = test_write(chest, at, encode_varint(4))
    chest[at] = 0
    at = at + 1
    check("an unknown block entity action is refused",
          pl_handle_block_entity_data(0, test_trim(chest, at), 0, tiles) != 0,
          fails)

    at = test_position(chest, 0, 1, 2, 3)
    at = test_write(chest, at, encode_varint(-1))
    check("a block entity removal parses",
          pl_handle_block_entity_data(0, test_trim(chest, at), 0, tiles) == 0,
          fails)
    check_int("removal dropped the row", vbes_count(tiles), 0, fails)
    check_int("a position nobody mentioned is absent",
              vbes_has(tiles, 9, 9, 9), 0, fails)
    check_int("a row past the table has no action",
              vbes_row_action(tiles, vbes_capacity()), vbes_absent(), fails)
    check_int("removing it again changes nothing",
              vbes_remove(tiles, 1, 2, 3), 0, fails)
    vbes_free(tiles)

    VAttributes* incoming = vat_new()
    int64[] simple = new int64[96]
    at = test_attr_head(simple, 3, 1)
    at = test_attr_property(simple, at, (int64)vat_key_max_health(), 15.0)
    check("attribute packet parses",
          pl_handle_update_attributes(0, test_trim(simple, at), 0,
                                      incoming) == 0, fails)
    test_near("attribute value stored",
              vat_value(incoming, 3, vat_key_max_health()), 15.0, fails)
    check_int("attribute packet has one row", vat_active_count(incoming), 1,
              fails)

    int64[] buffed = new int64[96]
    at = test_attr_head(buffed, 3, 1)
    at = test_write(buffed, at, encode_varint((int64)vat_key_max_health()))
    at = test_int64_bytes(buffed, at, (int64)vt_double_to_bits(30.0))
    at = test_write(buffed, at, encode_varint(1))
    at = test_attr_modifier(buffed, at, true, 4.0, 0)
    check("a prefixed modifier uuid parses",
          pl_handle_update_attributes(0, test_trim(buffed, at), 0,
                                      incoming) == 0, fails)
    test_near("modifier total replaced the base",
              vat_lookup(incoming, 3, "minecraft:generic.max_health"), 30.0,
              fails)
    check_int("modifiers counted",
              vat_lookup_modifier_count(incoming, 3,
                                        "minecraft:generic.max_health"),
              1, fails)

    int64[] raw_uuid = new int64[96]
    at = test_attr_head(raw_uuid, 4, 1)
    at = test_write(raw_uuid, at, encode_varint((int64)vat_key_max_health()))
    at = test_int64_bytes(raw_uuid, at, (int64)vt_double_to_bits(6.0))
    at = test_write(raw_uuid, at, encode_varint(1))
    at = test_attr_modifier(raw_uuid, at, false, 1.0, 1)
    check("a raw modifier uuid parses",
          pl_handle_update_attributes(0, test_trim(raw_uuid, at), 0,
                                      incoming) == 0, fails)
    check_int("raw uuid row stored", vat_entity_rows(incoming, 4), 1, fails)
    check_int("raw uuid modifier counted",
              vat_modifier_count(incoming, 4, vat_key_max_health()), 1, fails)

    int64[] two = new int64[96]
    at = test_attr_head(two, 5, 2)
    at = test_attr_property(two, at, (int64)vat_key_movement_speed(), 0.1)
    at = test_attr_property(two, at, (int64)vat_key_armor(), 8.0)
    check("two attributes parse",
          pl_handle_update_attributes(0, test_trim(two, at), 0, incoming) == 0,
          fails)
    check_int("both rows stored", vat_entity_rows(incoming, 5), 2, fails)
    test_near("second property reads back",
              vat_value(incoming, 5, vat_key_armor()), 8.0, fails)

    int64[] outside = new int64[96]
    at = test_attr_head(outside, 6, 1)
    at = test_attr_property(outside, at, (int64)vat_key_count(), 1.0)
    check("an id past the registry still consumes the packet",
          pl_handle_update_attributes(0, test_trim(outside, at), 0,
                                      incoming) == 0, fails)
    check_int("an id past the registry is not stored",
              vat_entity_rows(incoming, 6), 0, fails)

    int64[] extra = new int64[96]
    at = test_attr_head(extra, 8, 1)
    at = test_attr_property(extra, at, (int64)vat_key_follow_range(), 1.0)
    extra[at] = 7
    at = at + 1
    check("trailing bytes after attributes are refused",
          pl_handle_update_attributes(0, test_trim(extra, at), 0,
                                      incoming) != 0, fails)
    check_int("the property before the refusal is kept",
              vat_entity_rows(incoming, 8), 1, fails)
    test_near("the kept property reads back",
              vat_value(incoming, 8, vat_key_follow_range()), 1.0, fails)

    int64[] cut = new int64[96]
    at = test_attr_head(cut, 9, 1)
    at = test_write(cut, at, encode_varint((int64)vat_key_max_health()))
    cut[at] = 0
    cut[at + 1] = 0
    at = at + 2
    check("a truncated attribute value is refused",
          pl_handle_update_attributes(0, test_trim(cut, at), 0,
                                      incoming) != 0, fails)
    check_int("a truncated value is not stored", vat_entity_rows(incoming, 9),
              0, fails)

    int64[] too_many = new int64[96]
    at = test_write(too_many, 0, encode_varint(10))
    at = test_write(too_many, at, encode_varint(65))
    check("a property list past the limit is refused",
          pl_handle_update_attributes(0, test_trim(too_many, at), 0,
                                      incoming) != 0, fails)

    int64[] carrier = new int64[96]
    at = test_attr_head(carrier, 7, 1)
    at = test_attr_property(carrier, at, (int64)vat_key_armor(), 3.0)
    VEntities* carriers = ventities_new()
    VEffects* carrier_effects = vfx_new()
    check("carrier attributes parse",
          pl_handle_update_attributes(0, test_trim(carrier, at), 0,
                                      incoming) == 0, fails)
    check_int("carrier has a row", vat_entity_rows(incoming, 7), 1, fails)
    check("effect attached before removal",
          pl_handle_update_mob_effect(test_effect_packet(7, 9, 1, 200, 0), 0,
                                      carrier_effects) == 0, fails)
    int64[] despawn = new int64[4]
    int64 despawn_at = test_write(despawn, 0, encode_varint(1))
    despawn_at = test_write(despawn, despawn_at, encode_varint(7))
    check("removal parses",
          pl_handle_remove_entities(despawn, 0, carriers, carrier_effects,
                                    incoming) == 0, fails)
    check("removed entity is gone", ventities_find(carriers, 7) < 0, fails)
    check("removal cleared the entity effects",
          vfx_has(carrier_effects, 7, 9) == 0, fails)
    check_int("removal cleared the entity attributes",
              vat_entity_rows(incoming, 7), 0, fails)
    ventities_free(carriers)
    vfx_free(carrier_effects)
    vat_free(incoming)


def test_scoreboard(fails: int*) -> void:
    print("protocol play: scoreboard")
    VScoreboard* board = vscore_new()
    int64[] deaths = test_line("deaths")
    int64[] steve = test_line("Steve")
    int64[] red = test_line("red")

    int64[] objective = new int64[64]
    int64 at = test_write_str(objective, 0, "deaths")
    at = test_write_component(objective, at, "Deaths")
    check_int("objective packet parses", pl_handle_set_objective(objective, 0, board),
              0, fails)
    check("objective is registered",
          vscore_objective_exists(board, deaths, 0, (int64)len(deaths)) == 1, fails)
    check_int("objective name first byte",
              vscore_objective_name_byte(board, 0, 0), 100, fails)
    check_int("objective display first byte",
              vscore_objective_display_byte(board, 0, 0), 68, fails)
    check_int("objective display length",
              vscore_objective_display_length(board, 0), 6, fails)

    int64[] score = new int64[96]
    at = test_write_str(score, 0, "Steve")
    at = test_write_component(score, at, "Steve")
    at = test_write_str(score, at, "deaths")
    at = test_write(score, at, encode_varint(7))
    check_int("score packet parses", pl_handle_set_score(score, 0, board), 0, fails)
    check_int("score reads back",
              vscore_get_score(board, steve, 0, (int64)len(steve), deaths, 0,
                               (int64)len(deaths)), 7, fails)
    at = test_write_str(score, 0, "Alex")
    at = test_write_component(score, at, "Alex")
    at = test_write_str(score, at, "deaths")
    at = test_write(score, at, encode_varint(3))
    check_int("second score packet parses", pl_handle_set_score(score, 0, board),
              0, fails)
    check_int("second holder counted separately", board.score_count, 2, fails)

    at = test_write(score, 0, encode_varint(11))
    at = test_write_str(score, at, "deaths")
    check_int("display objective packet parses",
              pl_handle_set_display_objective(score, 0, board), 0, fails)
    check_int("display slot points at the objective",
              vscore_display_objective(board, 11), 0, fails)
    at = test_write(score, 0, encode_varint(11))
    at = test_write_str(score, at, "")
    check_int("clearing a display slot parses",
              pl_handle_set_display_objective(score, 0, board), 0, fails)
    check_int("cleared slot is empty", vscore_display_objective(board, 11), -1, fails)
    at = test_write(score, 0, encode_varint(99))
    at = test_write_str(score, at, "deaths")
    check("an unknown display slot is refused",
          pl_handle_set_display_objective(score, 0, board) != 0, fails)

    at = test_write_str(score, 0, "Steve")
    at = test_write_str(score, at, "deaths")
    check_int("reset score packet parses", pl_handle_reset_score(score, 0, board),
              0, fails)
    check_int("reset score is gone",
              vscore_get_score(board, steve, 0, (int64)len(steve), deaths, 0,
                               (int64)len(deaths)), vscore_score_absent(), fails)

    int64[] team = new int64[160]
    at = test_write_str(team, 0, "red")
    team[at] = 0
    at = at + 1
    at = test_write_component(team, at, "Red Team")
    team[at] = 0
    team[at + 1] = 0
    team[at + 2] = 1
    at = at + 3
    at = test_write_component(team, at, "R-")
    at = test_write_component(team, at, "")
    at = test_write(team, at, encode_varint(2))
    at = test_write_str(team, at, "Steve")
    at = test_write_str(team, at, "Alex")
    check_int("team create packet parses", pl_handle_set_player_team(team, 0, board),
              0, fails)
    check_int("team is registered",
              vscore_team_exists(board, red, 0, (int64)len(red)), 1, fails)
    check_int("team name first byte",
              vscore_team_name_byte(board, red, 0, (int64)len(red), 0), 114, fails)
    check_int("team prefix first byte",
              vscore_team_prefix_byte(board, red, 0, (int64)len(red), 0), 82, fails)
    check_int("team keeps both members",
              vscore_team_member_count(board, red, 0, (int64)len(red)), 2, fails)
    check_int("Steve is on the team", test_team_of(board, "Steve"), 0, fails)
    check_int("chat mode was stored",
              vscore_team_chat(board, red, 0, (int64)len(red)), 1, fails)

    at = test_write_str(team, 0, "red")
    team[at] = 4
    at = at + 1
    at = test_write(team, at, encode_varint(1))
    at = test_write_str(team, at, "Steve")
    check_int("team remove-player packet parses",
              pl_handle_set_player_team(team, 0, board), 0, fails)
    check_int("member count dropped",
              vscore_team_member_count(board, red, 0, (int64)len(red)), 1, fails)
    check_int("removed member is gone", test_team_of(board, "Steve"), -1, fails)
    check_int("remaining member stays", test_team_of(board, "Alex"), 0, fails)

    at = test_write_str(team, 0, "red")
    team[at] = 1
    check_int("team remove packet parses", pl_handle_set_player_team(team, 0, board),
              0, fails)
    check_int("team is gone", test_score_str(board, "red"), -1, fails)

    at = test_write_str(team, 0, "blue")
    team[at] = 3
    at = at + 1
    at = test_write(team, at, encode_varint(1))
    at = test_write_str(team, at, "Steve")
    check("adding to an unknown team is refused",
          pl_handle_set_player_team(team, 0, board) != 0, fails)

    at = test_write_str(team, 0, "red")
    team[at] = 9
    check("an unknown team mode is refused",
          pl_handle_set_player_team(team, 0, board) != 0, fails)

    # A reconnect re-sends the same member list; counting it twice would make
    # the tab list show the same player several times.
    at = test_write_str(team, 0, "red")
    team[at] = 0
    at = at + 1
    at = test_write_component(team, at, "")
    team[at] = 0
    team[at + 1] = 0
    team[at + 2] = 0
    at = at + 3
    at = test_write_component(team, at, "")
    at = test_write_component(team, at, "")
    at = test_write(team, at, encode_varint(2))
    at = test_write_str(team, at, "Steve")
    at = test_write_str(team, at, "Steve")
    check_int("team re-create parses", pl_handle_set_player_team(team, 0, board),
              0, fails)
    check_int("a repeated member is stored once",
              vscore_team_member_count(board, red, 0, (int64)len(red)), 1, fails)

    at = test_write_str(team, 0, "red")
    team[at] = 3
    at = at + 1
    at = test_write(team, at, encode_varint(1))
    at = test_write_str(team, at, "Alex")
    check_int("adding a member parses", pl_handle_set_player_team(team, 0, board),
              0, fails)
    check_int("both members are listed",
              vscore_team_member_count(board, red, 0, (int64)len(red)), 2, fails)

    # A body that ends with the identifier has no mode byte to branch on.
    int64[] stub = new int64[4]
    int64 stub_at = test_write_str(stub, 0, "red")
    check_int("an identifier-only packet is refused",
              pl_handle_set_player_team(stub, 0, board), 1, fails)
    check_int("the identifier fills the stub body", (int)stub_at, 4, fails)
    check("the objective outlives its teams",
          vscore_objective_exists(board, deaths, 0, (int64)len(deaths)) == 1, fails)

    vscore_free(board)


def test_commands(fails: int*) -> void:
    print("protocol play: command tree")
    VCommandTree* tree = vcmd_new()
    int64[] raw = new int64[256]

    int64 at = test_write(raw, 0, encode_varint(4))
    raw[at] = 0
    at = at + 1
    at = test_write(raw, at, encode_varint(2))
    at = test_write(raw, at, encode_varint(1))
    at = test_write(raw, at, encode_varint(2))
    raw[at] = 5
    at = at + 1
    at = test_write(raw, at, encode_varint(1))
    at = test_write(raw, at, encode_varint(3))
    at = test_write_str(raw, at, "say")
    raw[at] = 5
    at = at + 1
    at = test_write(raw, at, encode_varint(0))
    at = test_write_str(raw, at, "me")
    raw[at] = 2
    at = at + 1
    at = test_write(raw, at, encode_varint(0))
    at = test_write_str(raw, at, "message")
    at = test_write_str(raw, at, "brigadier:string")
    raw[at] = 2
    at = at + 1
    raw[at] = 1
    at = at + 1
    int64[] packet = test_trim(raw, at)
    int64[] probe = vcmd_take_varint(packet, 0)
    check_int("the tree varint reader ends after one byte", (int)probe[0], 1, fails)
    check_int("the tree varint reader decodes the node count", (int)probe[1], 4, fails)
    int64[] probe_text = vcmd_take_string(packet, 8)
    check_int("a tree string starts after its length", (int)probe_text[1], 9, fails)
    check_int("a tree string keeps its length", (int)probe_text[2], 3, fails)
    check_int("a tree string ends at the next field", (int)probe_text[0], 12, fails)
    check_int("command tree parses", vcmd_parse(tree, packet, 0), 0, fails)
    check_int("every node was stored", vcmd_node_total(tree), 4, fails)
    check_int("node 0 is the root", vcmd_node_type(tree, 0), vcmd_type_root(), fails)
    check_int("node 1 is a literal", vcmd_node_type(tree, 1), vcmd_type_literal(),
              fails)
    check_int("node 3 is an argument", vcmd_node_type(tree, 3), vcmd_type_argument(),
              fails)
    check_int("a node beyond the tree is absent", vcmd_node_type(tree, 9),
              vcmd_absent(), fails)
    check_int("say is executable", vcmd_is_executable(tree, 1), 1, fails)
    check_int("an argument is not executable", vcmd_is_executable(tree, 3), 0, fails)
    check_int("the root lists two commands", vcmd_child_count(tree, 0), 2, fails)
    check_int("the second root child", vcmd_child(tree, 0, 1), 2, fails)
    check_int("an absent child index", vcmd_child(tree, 0, 2), vcmd_absent(), fails)
    check_int("say kept its literal", vcmd_name_length(tree, 1), 3, fails)
    check_int("the literal first byte", vcmd_name_byte(tree, 1, 0), 115, fails)
    check_int("me kept its literal", vcmd_name_byte(tree, 2, 0), 109, fails)
    check_int("the root carries no name", vcmd_name_length(tree, 0), 0, fails)
    check_int("the parser was recorded", vcmd_parser_length(tree, 3), 16, fails)
    check_int("the parser first byte", vcmd_parser_name_byte(tree, 3, 0), 98, fails)
    check_int("a node without a redirect", vcmd_redirect(tree, 1), vcmd_absent(),
              fails)
    check_int("the chain limit was stored", vcmd_chain_limit(tree), 1, fails)
    check_int("completion offers say for s",
              vcmd_match_children(tree, 0, "s"), 1, fails)
    check_int("completion offers me for m",
              vcmd_match_children(tree, 0, "m"), 1, fails)
    check_int("completion narrows to one for me",
              vcmd_match_children(tree, 0, "me"), 1, fails)
    check_int("completion rejects an unknown prefix",
              vcmd_match_children(tree, 0, "q"), 0, fails)
    check_int("an empty prefix offers everything",
              vcmd_match_children(tree, 0, ""), 2, fails)

    at = test_write(raw, 0, encode_varint(2))
    raw[at] = 0
    at = at + 1
    at = test_write(raw, at, encode_varint(1))
    at = test_write(raw, at, encode_varint(1))
    raw[at] = 26
    at = at + 1
    at = test_write(raw, at, encode_varint(0))
    at = test_write_str(raw, at, "target")
    at = test_write_str(raw, at, "minecraft:entity")
    raw[at] = 3
    at = at + 1
    at = test_write(raw, at, encode_varint(0))
    at = test_write_str(raw, at, "minecraft:all_players")
    raw[at] = 1
    at = at + 1
    int64[] redirected = test_trim(raw, at)
    check_int("a redirected tree parses", vcmd_parse(tree, redirected, 0), 0, fails)
    check_int("the redirect was stored", vcmd_redirect(tree, 1), 0, fails)
    check_int("a re-parse replaces the tree", vcmd_node_total(tree), 2, fails)
    check_int("the suggestion provider was skipped",
              vcmd_name_length(tree, 1), 6, fails)

    at = test_write(raw, 0, encode_varint(1))
    raw[at] = 2
    at = at + 1
    at = test_write(raw, at, encode_varint(0))
    at = test_write_str(raw, at, "x")
    at = test_write_str(raw, at, "weird:parser")
    raw[at] = 0
    at = at + 1
    raw[at] = 1
    at = at + 1
    check("a tree with an unknown parser is refused",
          vcmd_parse(tree, test_trim(raw, at), 0) != 0, fails)

    at = test_write(raw, 0, encode_varint(1))
    raw[at] = 0
    at = at + 1
    at = test_write(raw, at, encode_varint(1))
    at = test_write(raw, at, encode_varint(7))
    int64[] dangling = test_trim(raw, at)
    check("a child index past the tree is refused",
          vcmd_parse(tree, dangling, 0) != 0, fails)

    at = test_write(raw, 0, encode_varint(1))
    raw[at] = 0
    at = at + 1
    at = test_write(raw, at, encode_varint(0))
    raw[at] = 1
    at = at + 1
    check("a tree without a chain limit is refused",
          vcmd_parse(tree, test_trim(raw, at - 1), 0) != 0, fails)
    check("trailing bytes after a tree are refused",
          vcmd_parse(tree, raw, 0) != 0, fails)

    vcmd_free(tree)


def main() -> int:
    int fails = 0
    mc_set_compression_threshold(-1)
    print("protocol play: varints and framing")
    test_varints(&fails)
    test_framing(&fails)
    print("protocol play: serverbound movement")
    test_move_encoders(&fails)
    print("protocol play: serverbound actions")
    test_action_encoders(&fails)
    print("protocol play: terminal argument parsing")
    test_arg_parsers(&fails)
    print("protocol play: item stacks")
    test_item_stacks(&fails)
    print("protocol play: clientbound state")
    test_state_handlers(&fails)
    print("protocol play: clientbound containers")
    test_container_handlers(&fails)
    print("protocol play: clientbound text")
    test_text_handlers(&fails)
    print("protocol play: terminal routing")
    test_terminal_routing(&fails)
    test_entity_state(&fails)
    test_boss_bars(&fails)
    test_mob_effects(&fails)
    test_attributes(&fails)
    test_tab_list(&fails)
    test_particles(&fails)
    test_difficulty_and_camera(&fails)
    test_server_packets(&fails)
    test_scoreboard(&fails)
    test_commands(&fails)
    return report("protocol_play", fails)

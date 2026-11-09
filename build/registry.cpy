# Vortex engine - generated bundle. Do not edit: this file is assembled from
# the modules listed below by tools/bundle.py.
#
#   native.cpy, core.cpy, strings.cpy, wire_read.cpy, protocol_ids.cpy, vbuf.cpy, nbt.cpy, slot.cpy, display.cpy, palette.cpy, section.cpy, heightmap.cpy, world.cpy, entities.cpy, bossbars.cpy, scoreboard.cpy, commands.cpy, effects.cpy, attributes.cpy, players.cpy, blockentities.cpy, particles.cpy, inventory.cpy, border.cpy, recipes.cpy, tags.cpy, advancements.cpy, debug.cpy, serverdata.cpy, protocol_chunk.cpy, blockdb.cpy, anvil.cpy, mesher.cpy, mesher_native.cpy, shape.cpy, wire.cpy, protocol.cpy, harness.cpy, test_registry.cpy

import stdlib
import "../src/engine/blockdb.c"
import "../src/engine/blockdb_setup.c"
import "../src/engine/mesher.c"
import "../src/engine/native.c"
import "../src/io/region_io.c"
import "../src/network.c"


# ===== native.cpy =====
# Vortex engine - native primitive declarations.
#
# The implementation lives in native.c so Cpyte never parses C syntax.



# ===== core.cpy =====
# Vortex engine - shared scalar constants.
#
# Cpyte only resolves a module-level `int NAME = value` inside `main()`: any
# other function that reads one aborts codegen with "Undefined variable", even
# within a single flat translation unit. Engine-wide values are therefore plain
# accessor functions.
#
# Delimiters have to be integers as well: a Cpyte character literal compiles to
# a string pointer, so `code_at(text, i) == '|'` is never true.


# ---- character codes used by the text formats --------------------------------

public def code_nul() -> int:
    return 0


public def code_tab() -> int:
    return 9


public def code_newline() -> int:
    return 10


public def code_cr() -> int:
    return 13


public def code_space() -> int:
    return 32


public def code_hash() -> int:
    return 35


public def code_plus() -> int:
    return 43


public def code_comma() -> int:
    return 44


public def code_minus() -> int:
    return 45


public def code_dot() -> int:
    return 46


public def code_zero() -> int:
    return 48


public def code_nine() -> int:
    return 57


public def code_colon() -> int:
    return 58


public def code_semicolon() -> int:
    return 59


public def code_equals() -> int:
    return 61


public def code_underscore() -> int:
    return 95


public def code_pipe() -> int:
    return 124


# ---- the usual limits --------------------------------------------------------

public def i8_min() -> int:
    return -128


public def i8_max() -> int:
    return 127


public def i16_min() -> int:
    return -32768


public def i16_max() -> int:
    return 32767


public def i32_min() -> int:
    return -2147483648


public def i32_max() -> int:
    return 2147483647


# A negative literal written straight into the `return` of a `-> int64` def is
# folded into the unsigned constant 4294967295, so the caller sees a huge
# positive number and every `result < 0` test silently misses. Building the same
# value in a local keeps the sign, which is what the byte walkers need.
public def i64_failed() -> int64:
    int64 failure = 0
    failure = failure - 1
    return failure


# ===== strings.cpy =====
# Vortex engine - text and numeric helpers.
#
# Every operation here delegates to the C layer in src/engine/native.cpy:
# Cpyte's own support stops at `+` on two strings and `len()`, a character
# literal is a string pointer rather than a byte, and text cannot be built by
# appending characters.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.


public def text_len(text: str) -> int:
    return vt_strlen(text)


# Characters [begin, end) of `text`, clamped to the string bounds.
public def str_slice(text: str, begin: int, end: int) -> str:
    int length = vt_strlen(text)
    if begin < 0:
        begin = 0
    if end > length:
        end = length
    if begin >= end:
        return ""
    return vt_slice(text, begin, end)


public def str_trim(text: str) -> str:
    return vt_trim(text)


public def str_equals(a: str, b: str) -> bool:
    return vt_eq(a, b) == 1


# Ordering (-1, 0, 1) for the registry's sorted name index.
public def str_compare(a: str, b: str) -> int:
    return vt_cmp(a, b)


public def str_starts(text: str, prefix: str) -> bool:
    return vt_starts(text, prefix) == 1


# Index of the first occurrence of `needle`, or -1.
public def str_find(text: str, needle: str) -> int:
    return vt_find_str(text, needle)


# Index of the first character with code `sep` at or after `from`, or -1.
public def str_find_code(text: str, from: int, sep: int) -> int:
    return vt_find_code(text, from, sep)


# `index`th field of `line` split on `sep`. Fields are kept verbatim and
# untrimmed, so "a,,b" still reads as three fields - the registry file format
# depends on that.
public def str_field(line: str, sep: int, index: int) -> str:
    return vt_field(line, sep, index)


# Number of fields a `str_field` walk would see.
public def str_field_count(line: str, sep: int) -> int:
    return vt_count(line, sep) + 1


# Byte at `index` as an unsigned code, for comparison against the code_xxx()
# accessors in src/engine/core.cpy.
public def code_at(text: str, index: int) -> int:
    return vt_at(text, index)


# Parses a decimal integer. `ok` receives 1 on success, 0 on failure, in which
# case `fallback` is returned. (`default` is a reserved word in Cpyte, so the
# fallback value carries a different name.)
public def parse_int_or(text: str, fallback: int, ok: int*) -> int:
    int strict = 0
    int64 wide = vt_parse_int(text, &strict)
    if strict == 0:
        *ok = 0
        return fallback
    *ok = 1
    return (int)wide


public def parse_int(text: str) -> int:
    int ok = 0
    return parse_int_or(text, 0, &ok)


public def parse_float(text: str) -> float:
    int strict = 0
    return (float)vt_parse_double(text, &strict)


public def parse_bool(text: str) -> bool:
    str body = vt_trim(text)
    if vt_eq(body, "1") == 1:
        return true
    if vt_eq(body, "true") == 1:
        return true
    if vt_eq(body, "yes") == 1:
        return true
    return false


# FNV-1a over the ASCII bytes; used by the registry's name index.
public def str_hash(text: str) -> uint64:
    return (uint64)vt_fnv1a(text)


# ---- growable text -----------------------------------------------------------

# A character sink. Cpyte cannot append a character to a string, so readers
# that assemble names byte by byte build them through this instead.
struct VStr:
    char* data
    int len
    int cap


public def vstr_new(cap: int) -> VStr*:
    VStr* s = new VStr
    if cap < 16:
        cap = 16
    s.data = vt_calloc_char(cap)
    s.len = 0
    s.cap = cap
    return s


public def vstr_put(s: VStr*, code: int) -> void:
    if s.len + 1 >= s.cap:
        int cap = s.cap * 2
        char* next = vt_calloc_char(cap)
        vt_copy_bytes(next, 0, s.data, 0, s.len)
        vt_free((void*)s.data)
        s.data = next
        s.cap = cap
    vt_put(s.data, s.len, code)
    s.len += 1
    vt_put(s.data, s.len, code_nul())


public def vstr_text(s: VStr*) -> str:
    return vt_dup(s.data)


public def vstr_put_text(s: VStr*, text: str) -> void:
    int n = vt_strlen(text)
    int i = 0
    while i < n:
        vstr_put(s, vt_at(text, i))
        i += 1


# Characters [from, to) of `text`, appended without producing a slice of their
# own. Table building and lookup run over tens of thousands of short ranges,
# and a `str_slice` per range is a per-row allocation that nothing can free
# until the whole registry is dropped.
public def vstr_put_slice(s: VStr*, text: str, from: int, to: int) -> void:
    int n = vt_strlen(text)
    if from < 0:
        from = 0
    if to > n:
        to = n
    int i = from
    while i < to:
        vstr_put(s, vt_at(text, i))
        i = i + 1


public def vstr_clear(s: VStr*) -> void:
    s.len = 0
    vt_put(s.data, 0, code_nul())


def text_is_blank(code: int) -> int:
    if code == 32 or code == 9 or code == 13 or code == 10:
        return 1
    return 0


# Characters [from, to) of `text`, with the blanks around them dropped. A table
# row has to lose its trailing carriage return before it can be parsed, and
# doing that with a trim over a slice allocates twice for every row.
public def vstr_put_trimmed_slice(s: VStr*, text: str, from: int, to: int) -> void:
    int n = vt_strlen(text)
    if from < 0:
        from = 0
    if to > n:
        to = n
    int begin = from
    int end = to
    while begin < end and text_is_blank(vt_at(text, begin)) == 1:
        begin = begin + 1
    while end > begin and text_is_blank(vt_at(text, end - 1)) == 1:
        end = end - 1
    int i = begin
    while i < end:
        vstr_put(s, vt_at(text, i))
        i = i + 1


public def vstr_hash(s: VStr*) -> uint64:
    return (uint64)vt_fnv1a(s.data)


public def vstr_free(s: VStr*) -> void:
    if s == null:
        return
    if s.data != null:
        vt_free((void*)s.data)
        s.data = null
    s.len = 0
    s.cap = 0
    del s


# ===== wire_read.cpy =====
# Vortex engine - the shared big-endian readers every protocol walker uses.
#
# These live ahead of the world and protocol modules so both the item stack
# reader and the Play handlers can call one implementation. Each returns either
# a plain value or a {status, value, next} triple, where status 1 means the
# field was read, and `next` is the offset the caller continues from.


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

# ===== protocol_ids.cpy =====
# Vortex engine - protocol 777 packet ids (Minecraft 26.3).
#
# GENERATED by tools/gen_protocol_ids.py from the vanilla data generator's
# reports/packets.json; do not edit by hand. The report itself is not part of
# this repository (see docs/PARITY_BOUNDARY.md); these tables are transport
# metadata, not game data.
#
# States: handshake=0 status=1 login=2 configuration=3 play=4.
# Directions: clientbound=0 serverbound=1. Packet names are stored without the
# "minecraft:" namespace.


public def pkt_state_handshake() -> int:
    return 0

public def pkt_state_status() -> int:
    return 1

public def pkt_state_login() -> int:
    return 2

public def pkt_state_configuration() -> int:
    return 3

public def pkt_state_play() -> int:
    return 4

public def pkt_dir_clientbound() -> int:
    return 0

public def pkt_dir_serverbound() -> int:
    return 1

public def pkt_empty_names() -> str[]:
    str[] names = new str[0]
    return names

public def pkt_empty_ids() -> int64[]:
    int64[] ids = new int64[0]
    return ids

def pkt_names_0_0() -> str[]:
    str[] names = pkt_empty_names()
    return names

def pkt_ids_0_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    return ids

def pkt_names_0_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "intention")
    return names

def pkt_ids_0_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    return ids

def pkt_names_1_0() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "status_response")
    append(names, "pong_response")
    return names

def pkt_ids_1_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    return ids

def pkt_names_1_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "status_request")
    append(names, "ping_request")
    return names

def pkt_ids_1_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    return ids

def pkt_names_2_0() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "login_disconnect")
    append(names, "hello")
    append(names, "login_finished")
    append(names, "login_compression")
    append(names, "custom_query")
    append(names, "cookie_request")
    return names

def pkt_ids_2_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    return ids

def pkt_names_2_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "hello")
    append(names, "key")
    append(names, "custom_query_answer")
    append(names, "login_acknowledged")
    append(names, "cookie_response")
    return names

def pkt_ids_2_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    return ids

def pkt_names_3_0() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "cookie_request")
    append(names, "custom_payload")
    append(names, "disconnect")
    append(names, "finish_configuration")
    append(names, "keep_alive")
    append(names, "ping")
    append(names, "reset_chat")
    append(names, "registry_data")
    append(names, "resource_pack_pop")
    append(names, "resource_pack_push")
    append(names, "post_effects")
    append(names, "store_cookie")
    append(names, "transfer")
    append(names, "update_enabled_features")
    append(names, "update_tags")
    append(names, "select_known_packs")
    append(names, "custom_report_details")
    append(names, "server_links")
    append(names, "clear_dialog")
    append(names, "show_dialog")
    append(names, "code_of_conduct")
    return names

def pkt_ids_3_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    append(ids, 6)
    append(ids, 7)
    append(ids, 8)
    append(ids, 9)
    append(ids, 10)
    append(ids, 11)
    append(ids, 12)
    append(ids, 13)
    append(ids, 14)
    append(ids, 15)
    append(ids, 16)
    append(ids, 17)
    append(ids, 18)
    append(ids, 19)
    append(ids, 20)
    return ids

def pkt_names_3_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "client_information")
    append(names, "cookie_response")
    append(names, "custom_payload")
    append(names, "finish_configuration")
    append(names, "keep_alive")
    append(names, "pong")
    append(names, "resource_pack")
    append(names, "select_known_packs")
    append(names, "custom_click_action")
    append(names, "accept_code_of_conduct")
    return names

def pkt_ids_3_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    append(ids, 6)
    append(ids, 7)
    append(ids, 8)
    append(ids, 9)
    return ids

def pkt_names_4_0() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "bundle_delimiter")
    append(names, "add_entity")
    append(names, "animate")
    append(names, "award_stats")
    append(names, "block_changed_ack")
    append(names, "block_destruction")
    append(names, "block_entity_data")
    append(names, "block_event")
    append(names, "block_update")
    append(names, "boss_event")
    append(names, "change_difficulty")
    append(names, "chunk_batch_finished")
    append(names, "chunk_batch_start")
    append(names, "chunks_biomes")
    append(names, "clear_titles")
    append(names, "command_suggestions")
    append(names, "commands")
    append(names, "container_close")
    append(names, "container_set_content")
    append(names, "container_set_data")
    append(names, "container_set_slot")
    append(names, "cookie_request")
    append(names, "cooldown")
    append(names, "custom_chat_completions")
    append(names, "custom_payload")
    append(names, "damage_event")
    append(names, "debug/block_value")
    append(names, "debug/chunk_value")
    append(names, "debug/entity_value")
    append(names, "debug/event")
    append(names, "debug_sample")
    append(names, "delete_chat")
    append(names, "disconnect")
    append(names, "disguised_chat")
    append(names, "entity_event")
    append(names, "entity_position_sync")
    append(names, "explode")
    append(names, "add_transient_block")
    append(names, "forget_level_chunk")
    append(names, "game_event")
    append(names, "game_rule_values")
    append(names, "game_test_highlight_pos")
    append(names, "mount_screen_open")
    append(names, "hurt_animation")
    append(names, "initialize_border")
    append(names, "keep_alive")
    append(names, "level_chunk_with_light")
    append(names, "level_event")
    append(names, "level_particles")
    append(names, "light_update")
    append(names, "login")
    append(names, "low_disk_space_warning")
    append(names, "map_item_data")
    append(names, "merchant_offers")
    append(names, "move_entity_pos")
    append(names, "move_entity_pos_rot")
    append(names, "move_minecart_along_track")
    append(names, "move_entity_rot")
    append(names, "move_vehicle")
    append(names, "open_book")
    append(names, "open_screen")
    append(names, "open_sign_editor")
    append(names, "ping")
    append(names, "pong_response")
    append(names, "place_ghost_recipe")
    append(names, "player_abilities")
    append(names, "player_chat")
    append(names, "player_combat_end")
    append(names, "player_combat_enter")
    append(names, "player_combat_kill")
    append(names, "player_info_remove")
    append(names, "player_info_update")
    append(names, "player_look_at")
    append(names, "player_position")
    append(names, "player_rotation")
    append(names, "recipe_book_add")
    append(names, "recipe_book_remove")
    append(names, "recipe_book_settings")
    append(names, "remove_entities")
    append(names, "remove_mob_effect")
    append(names, "reset_score")
    append(names, "resource_pack_pop")
    append(names, "resource_pack_push")
    append(names, "post_effects")
    append(names, "respawn")
    append(names, "rotate_head")
    append(names, "section_blocks_update")
    append(names, "select_advancements_tab")
    append(names, "server_data")
    append(names, "set_action_bar_text")
    append(names, "set_border_center")
    append(names, "set_border_lerp_size")
    append(names, "set_border_size")
    append(names, "set_border_warning_delay")
    append(names, "set_border_warning_distance")
    append(names, "set_camera")
    append(names, "set_chunk_cache_center")
    append(names, "set_chunk_cache_radius")
    append(names, "set_cursor_item")
    append(names, "set_default_spawn_position")
    append(names, "set_display_objective")
    append(names, "set_entity_data")
    append(names, "set_entity_link")
    append(names, "set_entity_motion")
    append(names, "set_equipment")
    append(names, "set_experience")
    append(names, "set_health")
    append(names, "set_held_slot")
    append(names, "set_objective")
    append(names, "set_passengers")
    append(names, "set_player_inventory")
    append(names, "set_player_team")
    append(names, "set_score")
    append(names, "set_simulation_distance")
    append(names, "set_subtitle_text")
    append(names, "set_time")
    append(names, "set_title_text")
    append(names, "set_titles_animation")
    append(names, "sound_entity")
    append(names, "sound")
    append(names, "start_configuration")
    append(names, "stop_sound")
    append(names, "store_cookie")
    append(names, "swing_animation")
    append(names, "system_chat")
    append(names, "tab_list")
    append(names, "tag_query")
    append(names, "take_item_entity")
    append(names, "teleport_entity")
    append(names, "test_instance_block_status")
    append(names, "ticking_state")
    append(names, "ticking_step")
    append(names, "transfer")
    append(names, "update_advancements")
    append(names, "update_attributes")
    append(names, "update_mob_effect")
    append(names, "update_recipes")
    append(names, "update_tags")
    append(names, "projectile_power")
    append(names, "custom_report_details")
    append(names, "server_links")
    append(names, "waypoint")
    append(names, "clear_dialog")
    append(names, "show_dialog")
    return names

def pkt_ids_4_0() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    append(ids, 6)
    append(ids, 7)
    append(ids, 8)
    append(ids, 9)
    append(ids, 10)
    append(ids, 11)
    append(ids, 12)
    append(ids, 13)
    append(ids, 14)
    append(ids, 15)
    append(ids, 16)
    append(ids, 17)
    append(ids, 18)
    append(ids, 19)
    append(ids, 20)
    append(ids, 21)
    append(ids, 22)
    append(ids, 23)
    append(ids, 24)
    append(ids, 25)
    append(ids, 26)
    append(ids, 27)
    append(ids, 28)
    append(ids, 29)
    append(ids, 30)
    append(ids, 31)
    append(ids, 32)
    append(ids, 33)
    append(ids, 34)
    append(ids, 35)
    append(ids, 36)
    append(ids, 37)
    append(ids, 38)
    append(ids, 39)
    append(ids, 40)
    append(ids, 41)
    append(ids, 42)
    append(ids, 43)
    append(ids, 44)
    append(ids, 45)
    append(ids, 46)
    append(ids, 47)
    append(ids, 48)
    append(ids, 49)
    append(ids, 50)
    append(ids, 51)
    append(ids, 52)
    append(ids, 53)
    append(ids, 54)
    append(ids, 55)
    append(ids, 56)
    append(ids, 57)
    append(ids, 58)
    append(ids, 59)
    append(ids, 60)
    append(ids, 61)
    append(ids, 62)
    append(ids, 63)
    append(ids, 64)
    append(ids, 65)
    append(ids, 66)
    append(ids, 67)
    append(ids, 68)
    append(ids, 69)
    append(ids, 70)
    append(ids, 71)
    append(ids, 72)
    append(ids, 73)
    append(ids, 74)
    append(ids, 75)
    append(ids, 76)
    append(ids, 77)
    append(ids, 78)
    append(ids, 79)
    append(ids, 80)
    append(ids, 81)
    append(ids, 82)
    append(ids, 83)
    append(ids, 84)
    append(ids, 85)
    append(ids, 86)
    append(ids, 87)
    append(ids, 88)
    append(ids, 89)
    append(ids, 90)
    append(ids, 91)
    append(ids, 92)
    append(ids, 93)
    append(ids, 94)
    append(ids, 95)
    append(ids, 96)
    append(ids, 97)
    append(ids, 98)
    append(ids, 99)
    append(ids, 100)
    append(ids, 101)
    append(ids, 102)
    append(ids, 103)
    append(ids, 104)
    append(ids, 105)
    append(ids, 106)
    append(ids, 107)
    append(ids, 108)
    append(ids, 109)
    append(ids, 110)
    append(ids, 111)
    append(ids, 112)
    append(ids, 113)
    append(ids, 114)
    append(ids, 115)
    append(ids, 116)
    append(ids, 117)
    append(ids, 118)
    append(ids, 119)
    append(ids, 120)
    append(ids, 121)
    append(ids, 122)
    append(ids, 123)
    append(ids, 124)
    append(ids, 125)
    append(ids, 126)
    append(ids, 127)
    append(ids, 128)
    append(ids, 129)
    append(ids, 130)
    append(ids, 131)
    append(ids, 132)
    append(ids, 133)
    append(ids, 134)
    append(ids, 135)
    append(ids, 136)
    append(ids, 137)
    append(ids, 138)
    append(ids, 139)
    append(ids, 140)
    append(ids, 141)
    append(ids, 142)
    append(ids, 143)
    return ids

def pkt_names_4_1() -> str[]:
    str[] names = pkt_empty_names()
    append(names, "accept_teleportation")
    append(names, "attack")
    append(names, "block_entity_tag_query")
    append(names, "bundle_item_selected")
    append(names, "change_difficulty")
    append(names, "change_game_mode")
    append(names, "chat_ack")
    append(names, "chat_command")
    append(names, "chat_command_signed")
    append(names, "chat")
    append(names, "chat_session_update")
    append(names, "chunk_batch_received")
    append(names, "client_command")
    append(names, "client_tick_end")
    append(names, "client_information")
    append(names, "command_suggestion")
    append(names, "configuration_acknowledged")
    append(names, "container_button_click")
    append(names, "container_click")
    append(names, "container_close")
    append(names, "container_slot_state_changed")
    append(names, "cookie_response")
    append(names, "custom_payload")
    append(names, "debug_subscription_request")
    append(names, "edit_book")
    append(names, "entity_tag_query")
    append(names, "interact")
    append(names, "jigsaw_generate")
    append(names, "keep_alive")
    append(names, "lock_difficulty")
    append(names, "move_player_pos")
    append(names, "move_player_pos_rot")
    append(names, "move_player_rot")
    append(names, "move_player_status_only")
    append(names, "move_vehicle")
    append(names, "paddle_boat")
    append(names, "pick_item_from_block")
    append(names, "pick_item_from_entity")
    append(names, "ping_request")
    append(names, "place_recipe")
    append(names, "player_abilities")
    append(names, "player_action")
    append(names, "player_command")
    append(names, "player_input")
    append(names, "player_loaded")
    append(names, "pong")
    append(names, "punch")
    append(names, "recipe_book_change_settings")
    append(names, "recipe_book_seen_recipe")
    append(names, "rename_item")
    append(names, "resource_pack")
    append(names, "seen_advancements")
    append(names, "select_trade")
    append(names, "set_beacon")
    append(names, "set_carried_item")
    append(names, "set_command_block")
    append(names, "set_command_minecart")
    append(names, "set_creative_mode_slot")
    append(names, "set_game_rule")
    append(names, "set_jigsaw_block")
    append(names, "set_structure_block")
    append(names, "set_test_block")
    append(names, "sign_update")
    append(names, "spectator_action")
    append(names, "teleport_to_entity")
    append(names, "test_instance_block_action")
    append(names, "use_item_on")
    append(names, "use_item")
    append(names, "custom_click_action")
    return names

def pkt_ids_4_1() -> int64[]:
    int64[] ids = pkt_empty_ids()
    append(ids, 0)
    append(ids, 1)
    append(ids, 2)
    append(ids, 3)
    append(ids, 4)
    append(ids, 5)
    append(ids, 6)
    append(ids, 7)
    append(ids, 8)
    append(ids, 9)
    append(ids, 10)
    append(ids, 11)
    append(ids, 12)
    append(ids, 13)
    append(ids, 14)
    append(ids, 15)
    append(ids, 16)
    append(ids, 17)
    append(ids, 18)
    append(ids, 19)
    append(ids, 20)
    append(ids, 21)
    append(ids, 22)
    append(ids, 23)
    append(ids, 24)
    append(ids, 25)
    append(ids, 26)
    append(ids, 27)
    append(ids, 28)
    append(ids, 29)
    append(ids, 30)
    append(ids, 31)
    append(ids, 32)
    append(ids, 33)
    append(ids, 34)
    append(ids, 35)
    append(ids, 36)
    append(ids, 37)
    append(ids, 38)
    append(ids, 39)
    append(ids, 40)
    append(ids, 41)
    append(ids, 42)
    append(ids, 43)
    append(ids, 44)
    append(ids, 45)
    append(ids, 46)
    append(ids, 47)
    append(ids, 48)
    append(ids, 49)
    append(ids, 50)
    append(ids, 51)
    append(ids, 52)
    append(ids, 53)
    append(ids, 54)
    append(ids, 55)
    append(ids, 56)
    append(ids, 57)
    append(ids, 58)
    append(ids, 59)
    append(ids, 60)
    append(ids, 61)
    append(ids, 62)
    append(ids, 63)
    append(ids, 64)
    append(ids, 65)
    append(ids, 66)
    append(ids, 67)
    append(ids, 68)
    return ids

# Names indexed by packet id for one state/direction; empty for an
# unknown state or direction.
public def pkt_names(state: int, direction: int) -> str[]:
    if state == pkt_state_handshake() and direction == pkt_dir_clientbound():
        return pkt_names_0_0()
    if state == pkt_state_handshake() and direction == pkt_dir_serverbound():
        return pkt_names_0_1()
    if state == pkt_state_status() and direction == pkt_dir_clientbound():
        return pkt_names_1_0()
    if state == pkt_state_status() and direction == pkt_dir_serverbound():
        return pkt_names_1_1()
    if state == pkt_state_login() and direction == pkt_dir_clientbound():
        return pkt_names_2_0()
    if state == pkt_state_login() and direction == pkt_dir_serverbound():
        return pkt_names_2_1()
    if state == pkt_state_configuration() and direction == pkt_dir_clientbound():
        return pkt_names_3_0()
    if state == pkt_state_configuration() and direction == pkt_dir_serverbound():
        return pkt_names_3_1()
    if state == pkt_state_play() and direction == pkt_dir_clientbound():
        return pkt_names_4_0()
    if state == pkt_state_play() and direction == pkt_dir_serverbound():
        return pkt_names_4_1()
    return pkt_empty_names()

public def pkt_table_ids(state: int, direction: int) -> int64[]:
    if state == pkt_state_handshake() and direction == pkt_dir_clientbound():
        return pkt_ids_0_0()
    if state == pkt_state_handshake() and direction == pkt_dir_serverbound():
        return pkt_ids_0_1()
    if state == pkt_state_status() and direction == pkt_dir_clientbound():
        return pkt_ids_1_0()
    if state == pkt_state_status() and direction == pkt_dir_serverbound():
        return pkt_ids_1_1()
    if state == pkt_state_login() and direction == pkt_dir_clientbound():
        return pkt_ids_2_0()
    if state == pkt_state_login() and direction == pkt_dir_serverbound():
        return pkt_ids_2_1()
    if state == pkt_state_configuration() and direction == pkt_dir_clientbound():
        return pkt_ids_3_0()
    if state == pkt_state_configuration() and direction == pkt_dir_serverbound():
        return pkt_ids_3_1()
    if state == pkt_state_play() and direction == pkt_dir_clientbound():
        return pkt_ids_4_0()
    if state == pkt_state_play() and direction == pkt_dir_serverbound():
        return pkt_ids_4_1()
    return pkt_empty_ids()

public def pkt_count(state: int, direction: int) -> int:
    return (int)len(pkt_names(state, direction))

# Numeric id of `name` in one table, or -1. `name` may be bare or
# namespace qualified.
public def pkt_id(state: int, direction: int, name: str) -> int:
    str bare = name
    if str_starts(bare, "minecraft:"):
        bare = str_slice(bare, 10, text_len(bare))
    str[] names = pkt_names(state, direction)
    int i = 0
    while i < (int)len(names):
        if str_equals(names[i], bare):
            return i
        i += 1
    return -1

# Namespace-qualified name of packet `packet_id`, or "" when absent.
public def pkt_name(state: int, direction: int, packet_id: int) -> str:
    str[] names = pkt_names(state, direction)
    if packet_id < 0 or packet_id >= (int)len(names):
        return ""
    return "minecraft:" + names[packet_id]

public def pkt_known(state: int, direction: int, packet_id: int) -> bool:
    if packet_id < 0:
        return false
    return packet_id < pkt_count(state, direction)

# FNV-1a over "name=id\n" for every entry, masked to 31 bits, so a
# test can pin the whole table without duplicating it.
public def pkt_table_digest(state: int, direction: int) -> uint64:
    VStr* sink = vstr_new(4096)
    str[] names = pkt_names(state, direction)
    int i = 0
    while i < (int)len(names):
        vstr_put_text(sink, names[i])
        vstr_put(sink, code_equals())
        vstr_put_text(sink, str(i))
        vstr_put(sink, code_newline())
        i += 1
    uint64 hash = vstr_hash(sink)
    vstr_free(sink)
    return hash

public def pid_hs_s_intention() -> int:
    return 0

public def pid_st_c_status_response() -> int:
    return 0

public def pid_st_c_pong_response() -> int:
    return 1

public def pid_st_s_status_request() -> int:
    return 0

public def pid_st_s_ping_request() -> int:
    return 1

public def pid_lg_c_login_disconnect() -> int:
    return 0

public def pid_lg_c_hello() -> int:
    return 1

public def pid_lg_c_login_finished() -> int:
    return 2

public def pid_lg_c_login_compression() -> int:
    return 3

public def pid_lg_c_custom_query() -> int:
    return 4

public def pid_lg_c_cookie_request() -> int:
    return 5

public def pid_lg_s_hello() -> int:
    return 0

public def pid_lg_s_key() -> int:
    return 1

public def pid_lg_s_custom_query_answer() -> int:
    return 2

public def pid_lg_s_login_acknowledged() -> int:
    return 3

public def pid_lg_s_cookie_response() -> int:
    return 4

public def pid_cfg_c_cookie_request() -> int:
    return 0

public def pid_cfg_c_custom_payload() -> int:
    return 1

public def pid_cfg_c_disconnect() -> int:
    return 2

public def pid_cfg_c_finish_configuration() -> int:
    return 3

public def pid_cfg_c_keep_alive() -> int:
    return 4

public def pid_cfg_c_ping() -> int:
    return 5

public def pid_cfg_c_reset_chat() -> int:
    return 6

public def pid_cfg_c_registry_data() -> int:
    return 7

public def pid_cfg_c_resource_pack_pop() -> int:
    return 8

public def pid_cfg_c_resource_pack_push() -> int:
    return 9

public def pid_cfg_c_post_effects() -> int:
    return 10

public def pid_cfg_c_store_cookie() -> int:
    return 11

public def pid_cfg_c_transfer() -> int:
    return 12

public def pid_cfg_c_update_enabled_features() -> int:
    return 13

public def pid_cfg_c_update_tags() -> int:
    return 14

public def pid_cfg_c_select_known_packs() -> int:
    return 15

public def pid_cfg_c_custom_report_details() -> int:
    return 16

public def pid_cfg_c_server_links() -> int:
    return 17

public def pid_cfg_c_clear_dialog() -> int:
    return 18

public def pid_cfg_c_show_dialog() -> int:
    return 19

public def pid_cfg_c_code_of_conduct() -> int:
    return 20

public def pid_cfg_s_client_information() -> int:
    return 0

public def pid_cfg_s_cookie_response() -> int:
    return 1

public def pid_cfg_s_custom_payload() -> int:
    return 2

public def pid_cfg_s_finish_configuration() -> int:
    return 3

public def pid_cfg_s_keep_alive() -> int:
    return 4

public def pid_cfg_s_pong() -> int:
    return 5

public def pid_cfg_s_resource_pack() -> int:
    return 6

public def pid_cfg_s_select_known_packs() -> int:
    return 7

public def pid_cfg_s_custom_click_action() -> int:
    return 8

public def pid_cfg_s_accept_code_of_conduct() -> int:
    return 9

public def pid_pl_c_bundle_delimiter() -> int:
    return 0

public def pid_pl_c_add_entity() -> int:
    return 1

public def pid_pl_c_animate() -> int:
    return 2

public def pid_pl_c_award_stats() -> int:
    return 3

public def pid_pl_c_block_changed_ack() -> int:
    return 4

public def pid_pl_c_block_destruction() -> int:
    return 5

public def pid_pl_c_block_entity_data() -> int:
    return 6

public def pid_pl_c_block_event() -> int:
    return 7

public def pid_pl_c_block_update() -> int:
    return 8

public def pid_pl_c_boss_event() -> int:
    return 9

public def pid_pl_c_change_difficulty() -> int:
    return 10

public def pid_pl_c_chunk_batch_finished() -> int:
    return 11

public def pid_pl_c_chunk_batch_start() -> int:
    return 12

public def pid_pl_c_chunks_biomes() -> int:
    return 13

public def pid_pl_c_clear_titles() -> int:
    return 14

public def pid_pl_c_command_suggestions() -> int:
    return 15

public def pid_pl_c_commands() -> int:
    return 16

public def pid_pl_c_container_close() -> int:
    return 17

public def pid_pl_c_container_set_content() -> int:
    return 18

public def pid_pl_c_container_set_data() -> int:
    return 19

public def pid_pl_c_container_set_slot() -> int:
    return 20

public def pid_pl_c_cookie_request() -> int:
    return 21

public def pid_pl_c_cooldown() -> int:
    return 22

public def pid_pl_c_custom_chat_completions() -> int:
    return 23

public def pid_pl_c_custom_payload() -> int:
    return 24

public def pid_pl_c_damage_event() -> int:
    return 25

public def pid_pl_c_debug_block_value() -> int:
    return 26

public def pid_pl_c_debug_chunk_value() -> int:
    return 27

public def pid_pl_c_debug_entity_value() -> int:
    return 28

public def pid_pl_c_debug_event() -> int:
    return 29

public def pid_pl_c_debug_sample() -> int:
    return 30

public def pid_pl_c_delete_chat() -> int:
    return 31

public def pid_pl_c_disconnect() -> int:
    return 32

public def pid_pl_c_disguised_chat() -> int:
    return 33

public def pid_pl_c_entity_event() -> int:
    return 34

public def pid_pl_c_entity_position_sync() -> int:
    return 35

public def pid_pl_c_explode() -> int:
    return 36

public def pid_pl_c_add_transient_block() -> int:
    return 37

public def pid_pl_c_forget_level_chunk() -> int:
    return 38

public def pid_pl_c_game_event() -> int:
    return 39

public def pid_pl_c_game_rule_values() -> int:
    return 40

public def pid_pl_c_game_test_highlight_pos() -> int:
    return 41

public def pid_pl_c_mount_screen_open() -> int:
    return 42

public def pid_pl_c_hurt_animation() -> int:
    return 43

public def pid_pl_c_initialize_border() -> int:
    return 44

public def pid_pl_c_keep_alive() -> int:
    return 45

public def pid_pl_c_level_chunk_with_light() -> int:
    return 46

public def pid_pl_c_level_event() -> int:
    return 47

public def pid_pl_c_level_particles() -> int:
    return 48

public def pid_pl_c_light_update() -> int:
    return 49

public def pid_pl_c_login() -> int:
    return 50

public def pid_pl_c_low_disk_space_warning() -> int:
    return 51

public def pid_pl_c_map_item_data() -> int:
    return 52

public def pid_pl_c_merchant_offers() -> int:
    return 53

public def pid_pl_c_move_entity_pos() -> int:
    return 54

public def pid_pl_c_move_entity_pos_rot() -> int:
    return 55

public def pid_pl_c_move_minecart_along_track() -> int:
    return 56

public def pid_pl_c_move_entity_rot() -> int:
    return 57

public def pid_pl_c_move_vehicle() -> int:
    return 58

public def pid_pl_c_open_book() -> int:
    return 59

public def pid_pl_c_open_screen() -> int:
    return 60

public def pid_pl_c_open_sign_editor() -> int:
    return 61

public def pid_pl_c_ping() -> int:
    return 62

public def pid_pl_c_pong_response() -> int:
    return 63

public def pid_pl_c_place_ghost_recipe() -> int:
    return 64

public def pid_pl_c_player_abilities() -> int:
    return 65

public def pid_pl_c_player_chat() -> int:
    return 66

public def pid_pl_c_player_combat_end() -> int:
    return 67

public def pid_pl_c_player_combat_enter() -> int:
    return 68

public def pid_pl_c_player_combat_kill() -> int:
    return 69

public def pid_pl_c_player_info_remove() -> int:
    return 70

public def pid_pl_c_player_info_update() -> int:
    return 71

public def pid_pl_c_player_look_at() -> int:
    return 72

public def pid_pl_c_player_position() -> int:
    return 73

public def pid_pl_c_player_rotation() -> int:
    return 74

public def pid_pl_c_recipe_book_add() -> int:
    return 75

public def pid_pl_c_recipe_book_remove() -> int:
    return 76

public def pid_pl_c_recipe_book_settings() -> int:
    return 77

public def pid_pl_c_remove_entities() -> int:
    return 78

public def pid_pl_c_remove_mob_effect() -> int:
    return 79

public def pid_pl_c_reset_score() -> int:
    return 80

public def pid_pl_c_resource_pack_pop() -> int:
    return 81

public def pid_pl_c_resource_pack_push() -> int:
    return 82

public def pid_pl_c_post_effects() -> int:
    return 83

public def pid_pl_c_respawn() -> int:
    return 84

public def pid_pl_c_rotate_head() -> int:
    return 85

public def pid_pl_c_section_blocks_update() -> int:
    return 86

public def pid_pl_c_select_advancements_tab() -> int:
    return 87

public def pid_pl_c_server_data() -> int:
    return 88

public def pid_pl_c_set_action_bar_text() -> int:
    return 89

public def pid_pl_c_set_border_center() -> int:
    return 90

public def pid_pl_c_set_border_lerp_size() -> int:
    return 91

public def pid_pl_c_set_border_size() -> int:
    return 92

public def pid_pl_c_set_border_warning_delay() -> int:
    return 93

public def pid_pl_c_set_border_warning_distance() -> int:
    return 94

public def pid_pl_c_set_camera() -> int:
    return 95

public def pid_pl_c_set_chunk_cache_center() -> int:
    return 96

public def pid_pl_c_set_chunk_cache_radius() -> int:
    return 97

public def pid_pl_c_set_cursor_item() -> int:
    return 98

public def pid_pl_c_set_default_spawn_position() -> int:
    return 99

public def pid_pl_c_set_display_objective() -> int:
    return 100

public def pid_pl_c_set_entity_data() -> int:
    return 101

public def pid_pl_c_set_entity_link() -> int:
    return 102

public def pid_pl_c_set_entity_motion() -> int:
    return 103

public def pid_pl_c_set_equipment() -> int:
    return 104

public def pid_pl_c_set_experience() -> int:
    return 105

public def pid_pl_c_set_health() -> int:
    return 106

public def pid_pl_c_set_held_slot() -> int:
    return 107

public def pid_pl_c_set_objective() -> int:
    return 108

public def pid_pl_c_set_passengers() -> int:
    return 109

public def pid_pl_c_set_player_inventory() -> int:
    return 110

public def pid_pl_c_set_player_team() -> int:
    return 111

public def pid_pl_c_set_score() -> int:
    return 112

public def pid_pl_c_set_simulation_distance() -> int:
    return 113

public def pid_pl_c_set_subtitle_text() -> int:
    return 114

public def pid_pl_c_set_time() -> int:
    return 115

public def pid_pl_c_set_title_text() -> int:
    return 116

public def pid_pl_c_set_titles_animation() -> int:
    return 117

public def pid_pl_c_sound_entity() -> int:
    return 118

public def pid_pl_c_sound() -> int:
    return 119

public def pid_pl_c_start_configuration() -> int:
    return 120

public def pid_pl_c_stop_sound() -> int:
    return 121

public def pid_pl_c_store_cookie() -> int:
    return 122

public def pid_pl_c_swing_animation() -> int:
    return 123

public def pid_pl_c_system_chat() -> int:
    return 124

public def pid_pl_c_tab_list() -> int:
    return 125

public def pid_pl_c_tag_query() -> int:
    return 126

public def pid_pl_c_take_item_entity() -> int:
    return 127

public def pid_pl_c_teleport_entity() -> int:
    return 128

public def pid_pl_c_test_instance_block_status() -> int:
    return 129

public def pid_pl_c_ticking_state() -> int:
    return 130

public def pid_pl_c_ticking_step() -> int:
    return 131

public def pid_pl_c_transfer() -> int:
    return 132

public def pid_pl_c_update_advancements() -> int:
    return 133

public def pid_pl_c_update_attributes() -> int:
    return 134

public def pid_pl_c_update_mob_effect() -> int:
    return 135

public def pid_pl_c_update_recipes() -> int:
    return 136

public def pid_pl_c_update_tags() -> int:
    return 137

public def pid_pl_c_projectile_power() -> int:
    return 138

public def pid_pl_c_custom_report_details() -> int:
    return 139

public def pid_pl_c_server_links() -> int:
    return 140

public def pid_pl_c_waypoint() -> int:
    return 141

public def pid_pl_c_clear_dialog() -> int:
    return 142

public def pid_pl_c_show_dialog() -> int:
    return 143

public def pid_pl_s_accept_teleportation() -> int:
    return 0

public def pid_pl_s_attack() -> int:
    return 1

public def pid_pl_s_block_entity_tag_query() -> int:
    return 2

public def pid_pl_s_bundle_item_selected() -> int:
    return 3

public def pid_pl_s_change_difficulty() -> int:
    return 4

public def pid_pl_s_change_game_mode() -> int:
    return 5

public def pid_pl_s_chat_ack() -> int:
    return 6

public def pid_pl_s_chat_command() -> int:
    return 7

public def pid_pl_s_chat_command_signed() -> int:
    return 8

public def pid_pl_s_chat() -> int:
    return 9

public def pid_pl_s_chat_session_update() -> int:
    return 10

public def pid_pl_s_chunk_batch_received() -> int:
    return 11

public def pid_pl_s_client_command() -> int:
    return 12

public def pid_pl_s_client_tick_end() -> int:
    return 13

public def pid_pl_s_client_information() -> int:
    return 14

public def pid_pl_s_command_suggestion() -> int:
    return 15

public def pid_pl_s_configuration_acknowledged() -> int:
    return 16

public def pid_pl_s_container_button_click() -> int:
    return 17

public def pid_pl_s_container_click() -> int:
    return 18

public def pid_pl_s_container_close() -> int:
    return 19

public def pid_pl_s_container_slot_state_changed() -> int:
    return 20

public def pid_pl_s_cookie_response() -> int:
    return 21

public def pid_pl_s_custom_payload() -> int:
    return 22

public def pid_pl_s_debug_subscription_request() -> int:
    return 23

public def pid_pl_s_edit_book() -> int:
    return 24

public def pid_pl_s_entity_tag_query() -> int:
    return 25

public def pid_pl_s_interact() -> int:
    return 26

public def pid_pl_s_jigsaw_generate() -> int:
    return 27

public def pid_pl_s_keep_alive() -> int:
    return 28

public def pid_pl_s_lock_difficulty() -> int:
    return 29

public def pid_pl_s_move_player_pos() -> int:
    return 30

public def pid_pl_s_move_player_pos_rot() -> int:
    return 31

public def pid_pl_s_move_player_rot() -> int:
    return 32

public def pid_pl_s_move_player_status_only() -> int:
    return 33

public def pid_pl_s_move_vehicle() -> int:
    return 34

public def pid_pl_s_paddle_boat() -> int:
    return 35

public def pid_pl_s_pick_item_from_block() -> int:
    return 36

public def pid_pl_s_pick_item_from_entity() -> int:
    return 37

public def pid_pl_s_ping_request() -> int:
    return 38

public def pid_pl_s_place_recipe() -> int:
    return 39

public def pid_pl_s_player_abilities() -> int:
    return 40

public def pid_pl_s_player_action() -> int:
    return 41

public def pid_pl_s_player_command() -> int:
    return 42

public def pid_pl_s_player_input() -> int:
    return 43

public def pid_pl_s_player_loaded() -> int:
    return 44

public def pid_pl_s_pong() -> int:
    return 45

public def pid_pl_s_punch() -> int:
    return 46

public def pid_pl_s_recipe_book_change_settings() -> int:
    return 47

public def pid_pl_s_recipe_book_seen_recipe() -> int:
    return 48

public def pid_pl_s_rename_item() -> int:
    return 49

public def pid_pl_s_resource_pack() -> int:
    return 50

public def pid_pl_s_seen_advancements() -> int:
    return 51

public def pid_pl_s_select_trade() -> int:
    return 52

public def pid_pl_s_set_beacon() -> int:
    return 53

public def pid_pl_s_set_carried_item() -> int:
    return 54

public def pid_pl_s_set_command_block() -> int:
    return 55

public def pid_pl_s_set_command_minecart() -> int:
    return 56

public def pid_pl_s_set_creative_mode_slot() -> int:
    return 57

public def pid_pl_s_set_game_rule() -> int:
    return 58

public def pid_pl_s_set_jigsaw_block() -> int:
    return 59

public def pid_pl_s_set_structure_block() -> int:
    return 60

public def pid_pl_s_set_test_block() -> int:
    return 61

public def pid_pl_s_sign_update() -> int:
    return 62

public def pid_pl_s_spectator_action() -> int:
    return 63

public def pid_pl_s_teleport_to_entity() -> int:
    return 64

public def pid_pl_s_test_instance_block_action() -> int:
    return 65

public def pid_pl_s_use_item_on() -> int:
    return 66

public def pid_pl_s_use_item() -> int:
    return 67

public def pid_pl_s_custom_click_action() -> int:
    return 68



# ===== vbuf.cpy =====
# Vortex engine - growable byte buffer and the variable length integer
# encodings used by world data (chunk palettes, region files).
#
# The varint / varlong rules are the ones published by the community protocol
# references; no Mojang byte code or decompiled source was consulted.
# See docs/PARITY_BOUNDARY.md.
#
# Byte access goes through vt_at / vt_put rather than `b.data[i]`: the C layer
# is the only place the engine is known to index raw memory reliably.


struct VBuf:
    char* data       # owned, zero initialised, grows by doubling
    int len          # bytes written
    int cap          # bytes allocated
    int pos          # read cursor for the take_* helpers


public def vbuf_min_cap() -> int:
    return 512


public def vbuf_new(cap: int) -> VBuf*:
    VBuf* b = new VBuf
    if cap < vbuf_min_cap():
        cap = vbuf_min_cap()
    b.data = vt_calloc_char(cap)
    b.len = 0
    b.cap = cap
    b.pos = 0
    return b


public def vbuf_free(b: VBuf*) -> void:
    if b == null:
        return
    if b.data != null:
        vt_free((void*)b.data)
        b.data = null
    b.len = 0
    b.cap = 0
    b.pos = 0
    del b


public def vbuf_reset(b: VBuf*) -> void:
    b.len = 0
    b.pos = 0


public def vbuf_ensure(b: VBuf*, need: int) -> void:
    if need <= b.cap:
        return
    int cap = b.cap
    while cap < need:
        cap = cap * 2
    char* next = vt_calloc_char(cap)
    vt_copy_bytes(next, 0, b.data, 0, b.len)
    if b.data != null:
        vt_free((void*)b.data)
    b.data = next
    b.cap = cap


# Byte value as an unsigned 0..255 integer.
public def vbuf_at(b: VBuf*, index: int) -> uint64:
    if index < 0 or index >= b.len:
        return (uint64)0
    return (uint64)vt_at(b.data, index)


# ---- little endian -----------------------------------------------------------

public def vbuf_put_u8(b: VBuf*, v: uint64) -> void:
    vbuf_ensure(b, b.len + 1)
    vt_put(b.data, b.len, (int)(v & (uint64)255))
    b.len += 1


public def vbuf_put_u16_le(b: VBuf*, v: uint64) -> void:
    vbuf_put_u8(b, v & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)8) & (uint64)255)


public def vbuf_put_u32_le(b: VBuf*, v: uint64) -> void:
    vbuf_put_u8(b, v & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)8) & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)16) & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)24) & (uint64)255)


public def vbuf_put_u64_le(b: VBuf*, v: uint64) -> void:
    int i = 0
    while i < 8:
        vbuf_put_u8(b, (v >> ((uint64)i * (uint64)8)) & (uint64)255)
        i += 1


# ---- big endian --------------------------------------------------------------

public def vbuf_put_u16_be(b: VBuf*, v: uint64) -> void:
    vbuf_put_u8(b, (v >> (uint64)8) & (uint64)255)
    vbuf_put_u8(b, v & (uint64)255)


public def vbuf_put_u32_be(b: VBuf*, v: uint64) -> void:
    vbuf_put_u8(b, (v >> (uint64)24) & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)16) & (uint64)255)
    vbuf_put_u8(b, (v >> (uint64)8) & (uint64)255)
    vbuf_put_u8(b, v & (uint64)255)


public def vbuf_put_u64_be(b: VBuf*, v: uint64) -> void:
    vbuf_put_u32_be(b, (v >> (uint64)32) & (uint64)4294967295)
    vbuf_put_u32_be(b, v & (uint64)4294967295)


public def vbuf_put_i64_be(b: VBuf*, v: int64) -> void:
    vbuf_put_u64_be(b, (uint64)v)


public def vbuf_put_i8(b: VBuf*, v: int) -> void:
    vbuf_put_u8(b, (uint64)(v & 255))


public def vbuf_put_i16_be(b: VBuf*, v: int) -> void:
    vbuf_put_u16_be(b, (uint64)(v & 65535))


public def vbuf_put_i32_be(b: VBuf*, v: int) -> void:
    vbuf_put_u32_be(b, (uint64)v & (uint64)4294967295)


public def vbuf_put_f32_be(b: VBuf*, v: float) -> void:
    vbuf_put_u32_be(b, (uint64)vt_float_to_bits(v))


public def vbuf_put_f64_be(b: VBuf*, v: double) -> void:
    vbuf_put_u64_be(b, vt_double_to_bits(v))


# ---- varint / varlong --------------------------------------------------------

# A VarInt is the low 32 bits of the value in 7-bit little-endian groups, so a
# negative int runs to the full five groups. The group loop lives in C: Cpyte
# compares uint64 relationally as a signed value, which makes the "more groups
# follow?" test come out wrong for every negative number.
public def vbuf_put_varint(b: VBuf*, value: int) -> void:
    vbuf_ensure(b, b.len + 5)
    int n = vt_write_varint_at(b.data, b.len, value)
    b.len += n


# VarLong keeps the full 64 bit two's complement form, so a negative value
# always runs to ten groups.
public def vbuf_put_varlong(b: VBuf*, value: int64) -> void:
    vbuf_ensure(b, b.len + 10)
    int n = vt_write_varlong_at(b.data, b.len, (int64)value)
    b.len += n


# ---- reading -----------------------------------------------------------------

public def vbuf_avail(b: VBuf*) -> int:
    return b.len - b.pos


# Cpyte cannot read through two levels of struct field in one expression, so
# callers that only hold a VWire use these instead of `w.b.pos`.
public def vbuf_pos(b: VBuf*) -> int:
    return b.pos


public def vbuf_len(b: VBuf*) -> int:
    return b.len


# Keeps the low 32 bits of `raw` and sign extends them into a Cpyte int.
public def vsign_extend_32(raw: uint64) -> int:
    return vt_sign_extend_32((uint64)raw)


public def vbuf_take_u8(b: VBuf*) -> uint64:
    if b.pos >= b.len:
        return (uint64)0
    uint64 v = (uint64)vt_at(b.data, b.pos)
    b.pos += 1
    return v


public def vbuf_take_u16_le(b: VBuf*) -> uint64:
    uint64 a = vbuf_take_u8(b)
    uint64 c = vbuf_take_u8(b)
    return a | (c << (uint64)8)


public def vbuf_take_u32_le(b: VBuf*) -> uint64:
    uint64 a = vbuf_take_u8(b)
    uint64 c = vbuf_take_u8(b)
    uint64 e = vbuf_take_u8(b)
    uint64 f = vbuf_take_u8(b)
    return a | (c << (uint64)8) | (e << (uint64)16) | (f << (uint64)24)


public def vbuf_take_u64_le(b: VBuf*) -> uint64:
    uint64 low = vbuf_take_u32_le(b)
    uint64 high = vbuf_take_u32_le(b)
    return low | (high << (uint64)32)


public def vbuf_take_u16_be(b: VBuf*) -> uint64:
    uint64 a = vbuf_take_u8(b)
    uint64 c = vbuf_take_u8(b)
    return (a << (uint64)8) | c


public def vbuf_take_u32_be(b: VBuf*) -> uint64:
    uint64 a = vbuf_take_u8(b)
    uint64 c = vbuf_take_u8(b)
    uint64 e = vbuf_take_u8(b)
    uint64 f = vbuf_take_u8(b)
    return (a << (uint64)24) | (c << (uint64)16) | (e << (uint64)8) | f


public def vbuf_take_i32_be(b: VBuf*) -> int:
    return vsign_extend_32(vbuf_take_u32_be(b))


public def vbuf_take_u64_be(b: VBuf*) -> uint64:
    uint64 high = vbuf_take_u32_be(b)
    uint64 low = vbuf_take_u32_be(b)
    return (high << (uint64)32) | low


public def vbuf_take_i64_be(b: VBuf*) -> int64:
    return (int64)vbuf_take_u64_be(b)


# Signed fixed-width reads. The wrap-around is done on Cpyte `int` values,
# where relational operators are trustworthy.
public def vbuf_take_i8(b: VBuf*) -> int:
    int raw = (int)vbuf_take_u8(b)
    if raw >= 128:
        raw -= 256
    return raw


public def vbuf_take_i16_be(b: VBuf*) -> int:
    int raw = (int)vbuf_take_u16_be(b)
    if raw >= 32768:
        raw -= 65536
    return raw


public def vbuf_take_f32_be(b: VBuf*) -> float:
    return vt_bits_to_float((int)vbuf_take_u32_be(b))


public def vbuf_take_f64_be(b: VBuf*) -> double:
    return vt_bits_to_double(vbuf_take_u64_be(b))


# Decodes a VarLong. `ok` receives 0 when the buffer runs out or more than ten
# groups are consumed; the cursor only advances on success.
public def vbuf_take_varlong(b: VBuf*, ok: int*) -> int64:
    int64 value = (int64)0
    int next = vt_read_varint(b.data, b.pos, b.len, &value, 1)
    if next < 0:
        *ok = 0
        return (int64)0
    b.pos = next
    *ok = 1
    return value


# Decodes a VarInt: five groups at most, sign extended from 32 bits.
public def vbuf_take_varint(b: VBuf*, ok: int*) -> int:
    int64 value = (int64)0
    int next = vt_read_varint(b.data, b.pos, b.len, &value, 0)
    *ok = 0
    if next < 0:
        return 0
    b.pos = next
    *ok = 1
    return (int)value


public def vbuf_take_varlong_unchecked(b: VBuf*) -> int64:
    int ok = 0
    return vbuf_take_varlong(b, &ok)


public def vbuf_take_varint_unchecked(b: VBuf*) -> int:
    int ok = 0
    return vbuf_take_varint(b, &ok)


# ---- bulk --------------------------------------------------------------------

public def vbuf_put_bytes(b: VBuf*, src: char*, count: int) -> void:
    if count <= 0:
        return
    vbuf_ensure(b, b.len + count)
    vt_copy_bytes(b.data, b.len, src, 0, count)
    b.len += count


public def vbuf_take_bytes(b: VBuf*, dst: char*, count: int) -> void:
    int i = 0
    while i < count:
        if b.pos < b.len:
            vt_put(dst, i, vt_at(b.data, b.pos))
            b.pos += 1
        else:
            vt_put(dst, i, code_nul())
        i += 1


public def vbuf_skip(b: VBuf*, count: int) -> void:
    b.pos += count
    if b.pos > b.len:
        b.pos = b.len


# The NBT string payload: a big endian u16 byte count followed by the bytes.
public def vbuf_put_str_u16_be(b: VBuf*, text: str) -> void:
    int n = vt_strlen(text)
    vbuf_put_u16_be(b, (uint64)n)
    int i = 0
    while i < n:
        vbuf_put_u8(b, (uint64)vt_at(text, i))
        i += 1


# Reads a u16 big endian length followed by that many bytes. `ok` receives 0
# when the buffer cannot supply the whole payload: a length that outruns the
# data must not read back as silent NUL padding.
public def vbuf_take_str_u16_be(b: VBuf*, ok: int*) -> str:
    int n = (int)vbuf_take_u16_be(b)
    *ok = 0
    if n < 0 or vbuf_avail(b) < n:
        return ""
    VStr* sink = vstr_new(n + 2)
    int i = 0
    while i < n:
        vstr_put(sink, (int)vbuf_take_u8(b))
        i += 1
    str result = vstr_text(sink)
    vstr_free(sink)
    *ok = 1
    return result


# ===== nbt.cpy =====
# Vortex engine - NBT tag tree, reader and writer.
#
# NBT is the community-documented tree format used by region files, structure
# files and (through the user's protocol layer) network chunk data: big endian
# fixed width payloads, TAG_End terminated compounds, one element type per
# list. Tag numbering and payload sizes are the published interchange rules,
# not a reimplementation of any decompiled source. See docs/PARITY_BOUNDARY.md.
#
# A tag is a flat union: exactly one payload group is live for a given kind.
# Keeping it flat avoids virtual dispatch per node, which matters because a
# chunk section's palette is a compound of a list of compounds.


# ---- tag kinds ---------------------------------------------------------------

public def nbt_end() -> int:
    return 0


public def nbt_byte() -> int:
    return 1


public def nbt_short() -> int:
    return 2


public def nbt_int() -> int:
    return 3


public def nbt_long() -> int:
    return 4


public def nbt_float() -> int:
    return 5


public def nbt_double() -> int:
    return 6


public def nbt_byte_array() -> int:
    return 7


public def nbt_string() -> int:
    return 8


public def nbt_list() -> int:
    return 9


public def nbt_compound() -> int:
    return 10


public def nbt_int_array() -> int:
    return 11


public def nbt_long_array() -> int:
    return 12


# Depth a reader will accept before calling the input hostile; region files
# nest at most four or five levels.
public def nbt_max_depth() -> int:
    return 64


# ---- the node ----------------------------------------------------------------

struct VNbt:
    int kind
    str name                   # key inside its parent compound, "" in a list
    int val_int                # byte / short / int payload
    int64 val_long
    float val_float
    double val_double
    str val_str                # string payload, only for kind == nbt_string
    char* bytes                # byte array
    int bytes_len
    int* ints                  # int array
    int ints_len
    uint64* longs              # long array
    int longs_len
    char* items                # child pointers, one slot per entry
    int items_len
    int items_cap


# String ownership: `name` always, and `val_str` for a string node, are heap
# copies the node frees itself. A caller may hand over a literal, a slice or a
# buffer it releases immediately, and the tree keeps its own copy - which is
# what lets a decoded registry packet give its bytes back as soon as it is
# done with them.
public def nbt_new(kind: int, name: str) -> VNbt*:
    VNbt* t = new VNbt
    t.kind = kind
    t.name = vt_dup(name)
    t.val_int = 0
    t.val_long = (int64)0
    t.val_float = (float)0
    t.val_double = (double)0
    t.val_str = ""
    t.bytes = null
    t.bytes_len = 0
    t.ints = null
    t.ints_len = 0
    t.longs = null
    t.longs_len = 0
    t.items = null
    t.items_len = 0
    t.items_cap = 0
    return t


# Renames a node, taking a copy of `name` and releasing the one it held.
public def nbt_set_name(t: VNbt*, name: str) -> void:
    if t == null:
        return
    str copy = vt_dup(name)
    vt_free((void*)t.name)
    t.name = copy


public def nbt_free(t: VNbt*) -> void:
    if t == null:
        return
    int i = 0
    while i < t.items_len:
        nbt_free((VNbt*)vt_ptr_get(t.items, i))
        i += 1
    if t.kind == nbt_string():
        vt_free((void*)t.val_str)
    vt_free((void*)t.bytes)
    vt_free((void*)t.ints)
    vt_free((void*)t.longs)
    vt_free((void*)t.items)
    vt_free((void*)t.name)
    del t


public def nbt_child_count(t: VNbt*) -> int:
    if t == null:
        return 0
    return t.items_len


public def nbt_child_at(t: VNbt*, index: int) -> VNbt*:
    if t == null:
        return null
    if index < 0 or index >= t.items_len:
        return null
    return (VNbt*)vt_ptr_get(t.items, index)


# Appends `child` to `t`, adopting it. Grows the slot array by doubling.
public def nbt_append(t: VNbt*, child: VNbt*) -> void:
    if child == null:
        return
    if t.items_len >= t.items_cap:
        int cap = t.items_cap * 2
        if cap < 4:
            cap = 4
        char* next = vt_calloc_ptrs(cap)
        vt_copy_bytes(next, 0, t.items, 0, t.items_len * vt_ptr_size())
        if t.items != null:
            vt_free((void*)t.items)
        t.items = next
        t.items_cap = cap
    vt_ptr_set(t.items, t.items_len, (void*)child)
    t.items_len += 1


# The child of compound `t` stored under `name`, or null.
public def nbt_find(t: VNbt*, name: str) -> VNbt*:
    if t == null:
        return null
    int i = 0
    while i < t.items_len:
        VNbt* child = (VNbt*)vt_ptr_get(t.items, i)
        if child != null and vt_eq(child.name, name) == 1:
            return child
        i += 1
    return null


public def nbt_has(t: VNbt*, name: str) -> bool:
    return nbt_find(t, name) != null


# ---- typed constructors ------------------------------------------------------

public def nbt_int_of(name: str, value: int) -> VNbt*:
    VNbt* t = nbt_new(nbt_int(), name)
    t.val_int = value
    return t


public def nbt_byte_of(name: str, value: int) -> VNbt*:
    VNbt* t = nbt_new(nbt_byte(), name)
    t.val_int = value
    return t


public def nbt_short_of(name: str, value: int) -> VNbt*:
    VNbt* t = nbt_new(nbt_short(), name)
    t.val_int = value
    return t


public def nbt_long_of(name: str, value: int64) -> VNbt*:
    VNbt* t = nbt_new(nbt_long(), name)
    t.val_long = value
    return t


public def nbt_float_of(name: str, value: float) -> VNbt*:
    VNbt* t = nbt_new(nbt_float(), name)
    t.val_float = value
    return t


public def nbt_double_of(name: str, value: double) -> VNbt*:
    VNbt* t = nbt_new(nbt_double(), name)
    t.val_double = value
    return t


public def nbt_string_of(name: str, value: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_string(), name)
    # The node owns the payload copy, so `value` may be a literal or a buffer
    # the caller frees as soon as this returns.
    t.val_str = vt_dup(value)
    return t


public def nbt_compound_of(name: str) -> VNbt*:
    return nbt_new(nbt_compound(), name)


public def nbt_list_of(name: str, kind: int) -> VNbt*:
    # The list's element type is a property of the tag, not of each entry.
    VNbt* t = nbt_new(nbt_list(), name)
    t.val_int = kind
    return t


# val_int of a list node records the element type, so list constructors use
# val_long for their own scalar payloads - hence these take the element kind.
public def nbt_list_element_kind(t: VNbt*) -> int:
    return t.val_int


# ---- value accessors with fallbacks ------------------------------------------

public def nbt_int_value(t: VNbt*, fallback: int) -> int:
    if t == null:
        return fallback
    if t.kind == nbt_byte() or t.kind == nbt_short() or t.kind == nbt_int():
        return t.val_int
    if t.kind == nbt_long():
        return (int)t.val_long
    return fallback


public def nbt_long_value(t: VNbt*, fallback: int64) -> int64:
    if t == null:
        return fallback
    if t.kind == nbt_long():
        return t.val_long
    return nbt_int_value(t, (int)fallback)


public def nbt_str_value(t: VNbt*, fallback: str) -> str:
    if t == null:
        return fallback
    if t.kind == nbt_string():
        return t.val_str
    return fallback


public def nbt_get_int(t: VNbt*, name: str, fallback: int) -> int:
    return nbt_int_value(nbt_find(t, name), fallback)


public def nbt_get_str(t: VNbt*, name: str, fallback: str) -> str:
    return nbt_str_value(nbt_find(t, name), fallback)


public def nbt_byte_at(t: VNbt*, index: int) -> int:
    if t == null or index < 0 or index >= t.bytes_len:
        return 0
    return vt_at(t.bytes, index)


public def nbt_int_at(t: VNbt*, index: int) -> int:
    if t == null or index < 0 or index >= t.ints_len:
        return 0
    return vt_iget(t.ints, index)


public def nbt_long_at(t: VNbt*, index: int) -> int64:
    if t == null or index < 0 or index >= t.longs_len:
        return (int64)0
    return (int64)vt_uget(t.longs, index)


# Array lengths: nbt_child_count counts list and compound children, and an
# array holds none of those.
public def nbt_byte_len(t: VNbt*) -> int:
    if t == null:
        return 0
    return t.bytes_len


public def nbt_int_len(t: VNbt*) -> int:
    if t == null:
        return 0
    return t.ints_len


public def nbt_long_len(t: VNbt*) -> int:
    if t == null:
        return 0
    return t.longs_len


# ---- writing -----------------------------------------------------------------

public def nbt_set_bytes(t: VNbt*, src: char*, count: int) -> void:
    if t.bytes != null:
        vt_free((void*)t.bytes)
    t.bytes = vt_calloc_char(count)
    vt_copy_bytes(t.bytes, 0, src, 0, count)
    t.bytes_len = count


public def nbt_set_ints(t: VNbt*, count: int) -> void:
    if t.ints != null:
        vt_free((void*)t.ints)
    t.ints = vt_calloc_int(count)
    t.ints_len = count


public def nbt_set_longs(t: VNbt*, count: int) -> void:
    if t.longs != null:
        vt_free((void*)t.longs)
    t.longs = vt_calloc_u64(count)
    t.longs_len = count


public def nbt_set_int_at(t: VNbt*, index: int, value: int) -> void:
    vt_iset(t.ints, index, value)


public def nbt_set_long_at(t: VNbt*, index: int, value: int64) -> void:
    vt_uset(t.longs, index, (uint64)value)


# mode 0 writes a complete named tag - kind byte, name, payload. mode 1 writes
# a payload alone, which is how list elements are stored (the element type is
# recorded once in the list header). One function keeps the recursion inside a
# single scope: Cpyte resolves a call to a function that is defined later.
def nbt_write_tag(b: VBuf*, t: VNbt*, mode: int) -> void:
    if mode == 0:
        vbuf_put_u8(b, (uint64)t.kind)
        if t.kind == nbt_end():
            return
        vbuf_put_str_u16_be(b, t.name)
    if t.kind == nbt_byte():
        vbuf_put_i8(b, t.val_int)
        return
    if t.kind == nbt_short():
        vbuf_put_i16_be(b, t.val_int)
        return
    if t.kind == nbt_int():
        vbuf_put_i32_be(b, t.val_int)
        return
    if t.kind == nbt_long():
        vbuf_put_i64_be(b, t.val_long)
        return
    if t.kind == nbt_float():
        vbuf_put_f32_be(b, t.val_float)
        return
    if t.kind == nbt_double():
        vbuf_put_f64_be(b, t.val_double)
        return
    if t.kind == nbt_string():
        vbuf_put_str_u16_be(b, t.val_str)
        return
    if t.kind == nbt_byte_array():
        vbuf_put_i32_be(b, t.bytes_len)
        vbuf_put_bytes(b, t.bytes, t.bytes_len)
        return
    if t.kind == nbt_int_array():
        vbuf_put_i32_be(b, t.ints_len)
        int i = 0
        while i < t.ints_len:
            vbuf_put_i32_be(b, vt_iget(t.ints, i))
            i += 1
        return
    if t.kind == nbt_long_array():
        vbuf_put_i32_be(b, t.longs_len)
        int j = 0
        while j < t.longs_len:
            vbuf_put_i64_be(b, (int64)vt_uget(t.longs, j))
            j += 1
        return
    if t.kind == nbt_list():
        # An empty list still writes its element type, so a reader can tell an
        # empty compound list from an empty int list.
        int elem = t.val_int
        if elem == nbt_end() and t.items_len > 0:
            VNbt* first = (VNbt*)vt_ptr_get(t.items, 0)
            elem = first.kind
        vbuf_put_u8(b, (uint64)elem)
        vbuf_put_i32_be(b, t.items_len)
        int k = 0
        while k < t.items_len:
            nbt_write_tag(b, (VNbt*)vt_ptr_get(t.items, k), 1)
            k += 1
        return
    if t.kind == nbt_compound():
        int m = 0
        while m < t.items_len:
            nbt_write_tag(b, (VNbt*)vt_ptr_get(t.items, m), 0)
            m += 1
        vbuf_put_u8(b, (uint64)nbt_end())


# Writes kind byte, name and payload - a complete named tag.
public def nbt_write(b: VBuf*, t: VNbt*) -> void:
    nbt_write_tag(b, t, 0)


# ---- reading -----------------------------------------------------------------

# True when `b` still holds at least `count` bytes at the cursor.
def nbt_need(b: VBuf*, count: int) -> bool:
    return vbuf_avail(b) >= count


# Reads a payload only (no kind byte, no name) - the list element form. Names
# are absent inside a list, so `name` is "" there. A truncated buffer fails the
# `nbt_need` guards and yields null rather than a partly built tag.
def nbt_read_payload(kind: int, name: str, b: VBuf*, depth: int) -> VNbt*:
    if depth > nbt_max_depth() or kind == nbt_end():
        return null
    if kind == nbt_byte():
        if not nbt_need(b, 1):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_int = vbuf_take_i8(b)
        return t
    if kind == nbt_short():
        if not nbt_need(b, 2):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_int = vbuf_take_i16_be(b)
        return t
    if kind == nbt_int():
        if not nbt_need(b, 4):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_int = vbuf_take_i32_be(b)
        return t
    if kind == nbt_long():
        if not nbt_need(b, 8):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_long = vbuf_take_i64_be(b)
        return t
    if kind == nbt_float():
        if not nbt_need(b, 4):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_float = vbuf_take_f32_be(b)
        return t
    if kind == nbt_double():
        if not nbt_need(b, 8):
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_double = vbuf_take_f64_be(b)
        return t
    if kind == nbt_string():
        if not nbt_need(b, 2):
            return null
        int ok = 0
        str text = vbuf_take_str_u16_be(b, &ok)
        if ok == 0:
            return null
        VNbt* t = nbt_new(kind, name)
        t.val_str = text
        return t
    if kind == nbt_byte_array():
        if not nbt_need(b, 4):
            return null
        int n = vbuf_take_i32_be(b)
        if n < 0 or not nbt_need(b, n):
            return null
        VNbt* t = nbt_new(kind, name)
        t.bytes = vt_calloc_char(n)
        vbuf_take_bytes(b, t.bytes, n)
        t.bytes_len = n
        return t
    if kind == nbt_int_array():
        if not nbt_need(b, 4):
            return null
        int n = vbuf_take_i32_be(b)
        if n < 0 or not nbt_need(b, n * 4):
            return null
        VNbt* t = nbt_new(kind, name)
        t.ints = vt_calloc_int(n)
        t.ints_len = n
        int i = 0
        while i < n:
            vt_iset(t.ints, i, vbuf_take_i32_be(b))
            i += 1
        return t
    if kind == nbt_long_array():
        if not nbt_need(b, 4):
            return null
        int n = vbuf_take_i32_be(b)
        if n < 0 or not nbt_need(b, n * 8):
            return null
        VNbt* t = nbt_new(kind, name)
        t.longs = vt_calloc_u64(n)
        t.longs_len = n
        int j = 0
        while j < n:
            vt_uset(t.longs, j, (uint64)vbuf_take_i64_be(b))
            j += 1
        return t
    if kind == nbt_list():
        if not nbt_need(b, 5):
            return null
        int elem = (int)vbuf_take_u8(b)
        int n = vbuf_take_i32_be(b)
        if n < 0:
            return null
        VNbt* t = nbt_new(kind, name)
        # The element type is a property of the list node itself.
        t.val_int = elem
        int k = 0
        while k < n:
            VNbt* child = nbt_read_payload(elem, "", b, depth + 1)
            if child == null:
                return null
            nbt_append(t, child)
            k += 1
        return t
    if kind == nbt_compound():
        VNbt* t = nbt_new(kind, name)
        while true:
            if not nbt_need(b, 1):
                return null
            int next = (int)vbuf_take_u8(b)
            if next == nbt_end():
                return t
            if not nbt_need(b, 2):
                return null
            int ok_name = 0
            str child_name = vbuf_take_str_u16_be(b, &ok_name)
            if ok_name == 0:
                return null
            VNbt* child = nbt_read_payload(next, child_name, b, depth + 1)
            vt_free((void*)child_name)
            if child == null:
                return null
            nbt_append(t, child)
    return null


# Reads a complete named tag: kind byte, name, payload.
public def nbt_read(b: VBuf*) -> VNbt*:
    if not nbt_need(b, 3):
        return null
    int kind = (int)vbuf_take_u8(b)
    if kind == nbt_end():
        return null
    int ok_name = 0
    str name = vbuf_take_str_u16_be(b, &ok_name)
    if ok_name == 0:
        return null
    VNbt* t = nbt_read_payload(kind, name, b, 0)
    # nbt_new takes its own copy, so this one is no longer needed by anyone.
    vt_free((void*)name)
    return t



# ===== slot.cpy =====
# Vortex engine - the 26.3 item stack and its data components.
#
# Wire layout (protocol 777, verified against the published 26.x interchange
# description):
#
#   Slot             itemCount VarInt          0 means the slot is empty
#                    itemId VarInt             only when itemCount != 0
#                    addedComponentCount VarInt
#                    removedComponentCount VarInt
#                    components              addedComponentCount entries of
#                                            { type VarInt, payload }
#                    removeComponents        removedComponentCount VarInts
#
#   ItemStackTemplate is the same envelope with an explicit itemCount, used by
#   bundles, charged projectiles and the use-remainder component.
#
# A component's payload length depends on its type, so the reader has to know
# every one of the 122 types to find the end of a stack. Everything here is a
# structural walk: it validates the bytes and reports where the stack ends,
# without building a tree, because the renderer only needs the id and count
# until the item atlas lands.
#
# Registry holders follow the interchange rule for a holder: a VarInt of 0 is
# followed by the inline value, anything else is a registry id minus one and
# carries no payload. A holder set is a VarInt of 0 followed by a tag name, or
# a count plus one followed by that many registry ids.
#
# One self-recursive dispatcher walks the whole tree. Cpyte needs a definition
# before its use, so mutually recursive readers are not expressible; a single
# node number space keeps the cycle inside one function instead.


public def sl_component_count() -> int:
    return 122


public def sl_depth_max() -> int:
    return 12


public def sl_array_max() -> int:
    return 4096


public def sl_stack_max() -> int:
    return 1024


public def sl_text_max() -> int:
    return 32767


public def sl_item_max() -> int:
    return 1000000


def sl_fail_named(name: str) -> int64:
    if len(name) > 0:
        print("Slot: rejected component {name}")
    return (int64)-1


def sl_fail() -> int64:
    return sl_fail_named("")


# A varint into scratch[0]; the return value is the next cursor.
def sl_value(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64[] read = decode_varint(data, cursor)
    if read[0] != 1:
        return sl_fail()
    scratch[0] = read[1]
    return read[2]


def sl_byte(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    if cursor < 0 or cursor >= len(data):
        return sl_fail()
    scratch[0] = data[cursor]
    return cursor + 1


def sl_text(data: int64[], cursor: int64) -> int64:
    int64[] read = read_string_field(data, cursor, sl_text_max())
    if read[0] != 1:
        return sl_fail()
    return read[2] + read[1]


# One unnamed network NBT tag: a type byte, then that type's payload.
def sl_tag(data: int64[], cursor: int64) -> int64:
    if cursor < 0 or cursor >= len(data):
        return sl_fail()
    int64[] after = skip_nbt_payload(data, data[cursor], cursor + 1, 0)
    if after[0] != 1 or after[2] <= cursor:
        return sl_fail()
    return after[2]


def sl_count(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64 at = sl_value(data, cursor, scratch)
    if at < 0:
        return sl_fail()
    if scratch[0] < (int64)0 or scratch[0] > (int64)sl_array_max():
        return sl_fail()
    return at


# A holder set: zero introduces a tag name, otherwise the value is one more
# than the number of registry ids that follow.
def sl_holder_set(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64 at = sl_value(data, cursor, scratch)
    if at < 0:
        return sl_fail()
    int64 size = scratch[0]
    if size < (int64)0 or size > (int64)sl_array_max():
        return sl_fail()
    if size == (int64)0:
        return sl_text(data, at)
    int64 left = size - 1
    while left > (int64)0:
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        left = left - 1
    return at


# The 26.3 component names, in registry id order. Only used for diagnostics:
# a payload that cannot be walked is refused with its name printed.
def sl_component_name(component: int) -> str:
    if component == 0:
        return "custom_data"
    if component == 1:
        return "max_stack_size"
    if component == 2:
        return "max_damage"
    if component == 3:
        return "damage"
    if component == 4:
        return "unbreakable"
    if component == 5:
        return "use_effects"
    if component == 6:
        return "custom_name"
    if component == 7:
        return "minimum_attack_charge"
    if component == 8:
        return "damage_type"
    if component == 9:
        return "item_name"
    if component == 10:
        return "item_model"
    if component == 11:
        return "lore"
    if component == 12:
        return "rarity"
    if component == 13:
        return "enchantments"
    if component == 14:
        return "can_place_on"
    if component == 15:
        return "can_break"
    if component == 16:
        return "attribute_modifiers"
    if component == 17:
        return "custom_model_data"
    if component == 18:
        return "tooltip_display"
    if component == 19:
        return "repair_cost"
    if component == 20:
        return "creative_slot_lock"
    if component == 21:
        return "enchantment_glint_override"
    if component == 22:
        return "intangible_projectile"
    if component == 23:
        return "food"
    if component == 24:
        return "consumable"
    if component == 25:
        return "use_remainder"
    if component == 26:
        return "use_cooldown"
    if component == 27:
        return "damage_resistant"
    if component == 28:
        return "tool"
    if component == 29:
        return "weapon"
    if component == 30:
        return "attack_range"
    if component == 31:
        return "enchantable"
    if component == 32:
        return "equippable"
    if component == 33:
        return "repairable"
    if component == 34:
        return "glider"
    if component == 35:
        return "tooltip_style"
    if component == 36:
        return "death_protection"
    if component == 37:
        return "blocks_attacks"
    if component == 38:
        return "piercing_weapon"
    if component == 39:
        return "kinetic_weapon"
    if component == 40:
        return "attack_animation"
    if component == 41:
        return "interact_animation"
    if component == 42:
        return "additional_trade_cost"
    if component == 43:
        return "block_transformer"
    if component == 44:
        return "villager_food"
    if component == 45:
        return "stored_enchantments"
    if component == 46:
        return "dye"
    if component == 47:
        return "dyed_color"
    if component == 48:
        return "map_id"
    if component == 49:
        return "map_decorations"
    if component == 50:
        return "map_post_processing"
    if component == 51:
        return "charged_projectiles"
    if component == 52:
        return "bundle_contents"
    if component == 53:
        return "potion_contents"
    if component == 54:
        return "potion_duration_scale"
    if component == 55:
        return "suspicious_stew_effects"
    if component == 56:
        return "writable_book_content"
    if component == 57:
        return "written_book_content"
    if component == 58:
        return "trim"
    if component == 59:
        return "debug_stick_state"
    if component == 60:
        return "entity_data"
    if component == 61:
        return "bucket_entity_data"
    if component == 62:
        return "block_entity_data"
    if component == 63:
        return "instrument"
    if component == 64:
        return "provides_trim_material"
    if component == 65:
        return "ominous_bottle_amplifier"
    if component == 66:
        return "jukebox_playable"
    if component == 67:
        return "provides_banner_patterns"
    if component == 68:
        return "recipes"
    if component == 69:
        return "lodestone_tracker"
    if component == 70:
        return "firework_explosion"
    if component == 71:
        return "fireworks"
    if component == 72:
        return "profile"
    if component == 73:
        return "note_block_sound"
    if component == 74:
        return "banner_patterns"
    if component == 75:
        return "base_color"
    if component == 76:
        return "pot_decorations"
    if component == 77:
        return "container"
    if component == 78:
        return "block_state"
    if component == 79:
        return "bees"
    if component == 80:
        return "sulfur_cube_content"
    if component == 81:
        return "lock"
    if component == 82:
        return "container_loot"
    if component == 83:
        return "break_sound"
    if component == 84:
        return "compostable"
    if component == 85:
        return "cooking_fuel"
    if component == 86:
        return "brewing_fuel"
    if component == 87:
        return "mob_visibility"
    if component == 88:
        return "villager/variant"
    if component == 89:
        return "wolf/variant"
    if component == 90:
        return "wolf/sound_variant"
    if component == 91:
        return "wolf/collar"
    if component == 92:
        return "fox/variant"
    if component == 93:
        return "salmon/size"
    if component == 94:
        return "parrot/variant"
    if component == 95:
        return "tropical_fish/pattern"
    if component == 96:
        return "tropical_fish/base_color"
    if component == 97:
        return "tropical_fish/pattern_color"
    if component == 98:
        return "mooshroom/variant"
    if component == 99:
        return "rabbit/variant"
    if component == 100:
        return "pig/variant"
    if component == 101:
        return "pig/sound_variant"
    if component == 102:
        return "cow/variant"
    if component == 103:
        return "cow/sound_variant"
    if component == 104:
        return "chicken/variant"
    if component == 105:
        return "chicken/sound_variant"
    if component == 106:
        return "zombie_nautilus/variant"
    if component == 107:
        return "frog/variant"
    if component == 108:
        return "horse/variant"
    if component == 109:
        return "painting/variant"
    if component == 110:
        return "llama/variant"
    if component == 111:
        return "axolotl/variant"
    if component == 112:
        return "cat/variant"
    if component == 113:
        return "cat/sound_variant"
    if component == 114:
        return "cat/collar"
    if component == 115:
        return "sheep/color"
    if component == 116:
        return "shulker/color"
    if component == 117:
        return "provides_pottery_pattern"
    if component == 118:
        return "sign_text_front"
    if component == 119:
        return "sign_text_back"
    if component == 120:
        return "waxed"
    if component == 121:
        return "cushion/color"
    return "?"


# Components whose whole payload is one VarInt: the scalars, the id mappers
# and every registry holder with no inline form.
def sl_shape_varint(component: int) -> int:
    if component == 1 or (component == 2 or component == 3):
        return 1
    if component == 8 or (component == 12 or component == 19):
        return 1
    if component == 31 or (component == 42 or component == 43):
        return 1
    if component == 44 or (component == 46 or component == 48):
        return 1
    if component == 50 or (component == 60 or component == 65):
        return 1
    if component == 75:
        return 1
    if component >= 88 and component <= 108:
        return 1
    if component >= 110 and component <= 117:
        return 1
    return 0


# One unnamed network NBT tag: the JSON only components and the chat
# components that are streamed as NBT.
def sl_shape_nbt(component: int) -> int:
    if component == 6 or (component == 9 or component == 61):
        return 1
    return 0


# One resource location.
def sl_shape_text(component: int) -> int:
    if component == 10 or (component == 35 or component == 73):
        return 1
    return 0


# The first node of a payload, or -1 when it carries no bytes and -2 when its
# shape is not known here.
def sl_component_first(component: int) -> int:
    if component == 4 or (component == 20 or component == 34):
        return -1
    if component == 120:
        return -1
    # These have no networkSynchronized codec, so a server never puts them in a
    # stack. Landing here means the bytes are not what they claim to be.
    if component == 0 or (component == 22 or component == 49):
        return -2
    if component == 59 or (component == 68 or component == 81):
        return -2
    if component == 82:
        return -2
    if sl_shape_varint(component):
        return 250
    if sl_shape_nbt(component):
        return 255
    if sl_shape_text(component):
        return 254
    if component == 7 or component == 54:
        return 252
    if component == 47:
        return 251
    if component == 21:
        return 253
    if component == 11:
        return 1255
    if component == 13 or (component == 45 or component == 55):
        return 1240
    if component == 14 or component == 15:
        return 1215
    if component == 16:
        return 1233
    if component == 27 or (component == 33 or component == 67):
        return 211
    if component == 36:
        return 1214
    if component == 51 or component == 52:
        return 1202
    if component == 25 or component == 80:
        return 202
    if component == 56:
        return 1238
    if component == 70:
        return 218
    if component == 72:
        return 219
    if component == 74:
        return 1243
    if component == 79:
        return 1237
    if component == 63:
        return 627
    if component == 64:
        return 625
    if component == 66:
        return 628
    if component == 83:
        return 644
    if component == 109:
        return 629
    if component == 77:
        return 300
    if component == 78:
        return 303
    if component == 84:
        return 304
    if component == 118 or component == 119:
        return 320
    # Multi field payloads, of which these are the first step.
    if component == 5:
        return 253
    if component == 18:
        return 253
    if component == 23:
        return 250
    if component == 24:
        return 252
    if component == 26:
        return 252
    if component == 17:
        return 1252
    if component == 28:
        return 1234
    if component == 29:
        return 250
    if component == 30:
        return 252
    if component == 32:
        return 250
    if component == 37:
        return 252
    if component == 38:
        return 253
    if component == 39:
        return 250
    if component == 40 or component == 41:
        return 250
    if component == 53:
        return 258
    if component == 57:
        return 238
    if component == 58:
        return 625
    if component == 62:
        return 250
    if component == 69:
        return 2231
    if component == 71:
        return 250
    if component == 76:
        return 2202
    if component == 85 or component == 86:
        return 304
    if component == 87:
        return 211
    return -2


# The step at index, for the payloads with more than one field. -1 ends the
# payload, and any component not listed here is a single step payload.
def sl_component_next(component: int, index: int) -> int:
    if component == 5:
        if index == 1:
            return 253
        if index == 2:
            return 252
        return -1
    if component == 17:
        if index == 1:
            return 1253
        if index == 2:
            return 1254
        if index == 3:
            return 1251
        return -1
    if component == 18:
        if index == 1:
            return 1250
        return -1
    if component == 23:
        if index == 1:
            return 252
        if index == 2:
            return 253
        return -1
    if component == 24:
        if index == 1:
            return 250
        if index == 2:
            return 644
        if index == 3:
            return 253
        if index == 4:
            return 1214
        return -1
    if component == 26:
        if index == 1:
            return 256
        return -1
    if component == 28:
        if index == 1:
            return 252
        if index == 2:
            return 250
        if index == 3:
            return 253
        return -1
    if component == 29:
        if index == 1:
            return 252
        return -1
    if component == 30:
        if index < 6:
            return 252
        return -1
    if component == 32:
        if index == 1:
            return 644
        if index == 2:
            return 256
        if index == 3:
            return 256
        if index == 4:
            return 2211
        if index < 10:
            return 253
        if index == 10:
            return 644
        return -1
    if component == 37:
        if index == 1:
            return 252
        if index == 2:
            return 1235
        if index == 3:
            return 236
        if index == 4:
            return 2211
        if index == 5:
            return 2210
        if index == 6:
            return 2210
        return -1
    if component == 38:
        if index == 1:
            return 253
        if index == 2:
            return 2210
        if index == 3:
            return 2210
        return -1
    if component == 39:
        if index == 1:
            return 250
        if index < 5:
            return 2232
        if index < 7:
            return 252
        if index == 7:
            return 2210
        if index == 8:
            return 2210
        return -1
    if component == 40 or component == 41:
        if index == 1:
            return 250
        return -1
    if component == 53:
        if index == 1:
            return 259
        if index == 2:
            return 1213
        if index == 3:
            return 256
        return -1
    if component == 57:
        if index == 1:
            return 254
        if index == 2:
            return 250
        if index == 3:
            return 1239
        if index == 4:
            return 253
        return -1
    if component == 58:
        if index == 1:
            return 626
        return -1
    if component == 62:
        if index == 1:
            return 255
        return -1
    if component == 69:
        if index == 1:
            return 253
        return -1
    if component == 71:
        if index == 1:
            return 1218
        return -1
    if component == 76:
        if index < 4:
            return 2202
        return -1
    if component == 85 or component == 86:
        if index == 1:
            return 305
        return -1
    if component == 87:
        if index == 1:
            return 252
        return -1
    return -1


def sl_component_step(component: int, index: int) -> int:
    if index == 0:
        return sl_component_first(component)
    return sl_component_next(component, index)


# Node numbers. Components are their own type id, 0 to 121. Above that:
#
#   200 the component lists that close a stack envelope
#   201 a Slot              202 an ItemStackTemplate
#   210 sound holder        211 holder set        212 effect detail
#   213 potion effect       214 consume effect    215 block predicate
#   216 block property      217 component matchers
#   218 firework explosion  219 resolvable profile 220 skin patch
#   221 game profile        222 partial profile   223 profile property
#   225 trim material       226 trim pattern
#   227 instrument data     228 jukebox song      229 painting variant
#   230 banner pattern      231 global position   232 kinetic condition
#   233 attribute modifier  234 tool rule         235 damage reduction
#   236 item damage         237 hive occupant     238 filtered string
#   239 filtered component  240 varint pair       243 banner layer
#   244 sound event
#   250 varint  251 i32  252 f32  253 bool  254 string  255 nbt
#   256 optional string   257 optional nbt      258 optional varint
#   259 optional i32      260 optional f32      261 optional bool
#   262 uuid  263 optional uuid     264 f64  265 block position
#   300 list of optional stacks     301 typed component value
#   303 string keyed string map     304 resolvable int
#   305 resolvable float            306 component matcher entry
#   307 attribute modifier value    320 sign text
#   400 + n  a registry holder whose inline value is node n
#   1000 + n a VarInt counted array of node n
#   2000 + n a boolean prefixed optional node n
def sl_node(data: int64[], cursor: int64, node: int, depth: int,
            scratch: int64[]) -> int64:
    if depth > sl_depth_max():
        return sl_fail()
    if cursor < 0 or cursor > len(data):
        return sl_fail()
    int down = depth + 1
    if node >= 2000:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] == (int64)0:
            return at
        if scratch[0] != (int64)1:
            return sl_fail()
        return sl_node(data, at, node - 2000, down, scratch)
    if node >= 1000:
        int64 at = sl_count(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 left = scratch[0]
        int element = node - 1000
        while left > (int64)0:
            at = sl_node(data, at, element, down, scratch)
            if at < 0:
                return sl_fail()
            left = left - 1
        return at
    if node >= 400:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 holder = scratch[0]
        if holder < (int64)0:
            return sl_fail()
        if holder == (int64)0:
            return sl_node(data, at, node - 400, down, scratch)
        return at
    if node == 200:
        int64 at = sl_count(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 added = scratch[0]
        at = sl_count(data, at, scratch)
        if at < 0:
            return sl_fail()
        int64 removed = scratch[0]
        if added + removed > (int64)sl_array_max():
            return sl_fail()
        while added > (int64)0:
            at = sl_value(data, at, scratch)
            if at < 0:
                return sl_fail()
            int64 kind = scratch[0]
            if kind < (int64)0 or kind >= (int64)sl_component_count():
                return sl_fail()
            at = sl_node(data, at, (int)kind, down, scratch)
            if at < 0:
                return sl_fail_named(sl_component_name((int)kind))
            added = added - 1
        while removed > (int64)0:
            at = sl_value(data, at, scratch)
            if at < 0:
                return sl_fail()
            if scratch[0] < (int64)0 or scratch[0] >= (int64)sl_component_count():
                return sl_fail()
            removed = removed - 1
        return at
    if node == 201:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 count = scratch[0]
        if count < (int64)0 or count > (int64)sl_stack_max():
            return sl_fail()
        if count == (int64)0:
            return at
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] < (int64)0 or scratch[0] > (int64)sl_item_max():
            return sl_fail()
        return sl_node(data, at, 200, down, scratch)
    if node == 202:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] < (int64)0 or scratch[0] > (int64)sl_item_max():
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] < (int64)0 or scratch[0] > (int64)sl_stack_max():
            return sl_fail()
        return sl_node(data, at, 200, down, scratch)
    if node == 210:
        return sl_node(data, cursor, 644, down, scratch)
    if node == 211:
        return sl_holder_set(data, cursor, scratch)
    if node == 212:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 253, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 253, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 253, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 2212, down, scratch)
    if node == 213:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 212, down, scratch)
    if node == 214:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 kind = scratch[0]
        if kind == (int64)0:
            at = sl_node(data, at, 1213, down, scratch)
            if at < 0:
                return sl_fail()
            return sl_node(data, at, 252, down, scratch)
        if kind == (int64)1:
            return sl_node(data, at, 211, down, scratch)
        if kind == (int64)2:
            return at
        if kind == (int64)3:
            at = sl_node(data, at, 252, down, scratch)
            if at < 0:
                return sl_fail()
            return sl_node(data, at, 253, down, scratch)
        if kind == (int64)4:
            return sl_node(data, at, 210, down, scratch)
        return sl_fail()
    if node == 215:
        int64 at = sl_node(data, cursor, 2211, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 3216, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 257, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 217, down, scratch)
    if node == 216:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        at = sl_byte(data, at, scratch)
        if at < 0:
            return sl_fail()
        int64 exact = scratch[0]
        if exact == (int64)0:
            return sl_text(data, at)
        if exact != (int64)1:
            return sl_fail()
        at = sl_node(data, at, 256, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 256, down, scratch)
    if node == 217:
        int64 at = sl_node(data, cursor, 1301, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 1306, down, scratch)
    if node == 218:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 1251, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 1251, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 253, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 253, down, scratch)
    if node == 219:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 kind = scratch[0]
        if kind == (int64)0:
            at = sl_node(data, at, 221, down, scratch)
        elif kind == (int64)1:
            at = sl_node(data, at, 222, down, scratch)
        else:
            return sl_fail()
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 220, down, scratch)
    if node == 220:
        int64 at = sl_node(data, cursor, 256, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 256, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 256, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 261, down, scratch)
    if node == 221:
        int64 at = pl_take(data, cursor, 16)
        if at < 0:
            return sl_fail()
        at = sl_text(data, at)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 1223, down, scratch)
    if node == 222:
        int64 at = sl_node(data, cursor, 256, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 263, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 1223, down, scratch)
    if node == 223:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        at = sl_text(data, at)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 256, down, scratch)
    if node == 225:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 255, down, scratch)
    if node == 226:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 253, down, scratch)
    if node == 227:
        int64 at = sl_node(data, cursor, 210, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 255, down, scratch)
    if node == 228:
        int64 at = sl_node(data, cursor, 210, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 229:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        at = sl_text(data, at)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 257, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 257, down, scratch)
    if node == 230:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return sl_text(data, at)
    if node == 231:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return pl_take(data, at, 8)
    if node == 232:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 252, down, scratch)
    if node == 233:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 307, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        int64 display = scratch[0]
        if display == (int64)2:
            return sl_node(data, at, 255, down, scratch)
        if display < (int64)0 or display > (int64)2:
            return sl_fail()
        return at
    if node == 234:
        int64 at = sl_node(data, cursor, 211, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 260, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 261, down, scratch)
    if node == 235:
        int64 at = sl_node(data, cursor, 252, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 2211, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 252, down, scratch)
    if node == 236:
        return pl_take(data, cursor, 12)
    if node == 237:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 238:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 256, down, scratch)
    if node == 239:
        int64 at = sl_node(data, cursor, 255, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 257, down, scratch)
    if node == 240:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 243:
        int64 at = sl_node(data, cursor, 630, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 244:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 260, down, scratch)
    if node == 250:
        return sl_value(data, cursor, scratch)
    if node == 251 or node == 252:
        return pl_take(data, cursor, 4)
    if node == 253:
        return sl_byte(data, cursor, scratch)
    if node == 254:
        return sl_text(data, cursor)
    if node == 255:
        return sl_tag(data, cursor)
    if node == 262:
        return pl_take(data, cursor, 16)
    if node == 264 or node == 265:
        return pl_take(data, cursor, 8)
    if node >= 256 and node <= 263:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] == (int64)0:
            return at
        if scratch[0] != (int64)1:
            return sl_fail()
        int inner = 254
        if node == 257:
            inner = 255
        elif node == 258:
            inner = 250
        elif node == 259:
            inner = 251
        elif node == 260:
            inner = 252
        elif node == 261:
            inner = 253
        elif node == 263:
            inner = 262
        return sl_node(data, at, inner, down, scratch)
    if node == 300:
        int64 at = sl_count(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 left = scratch[0]
        while left > (int64)0:
            at = sl_node(data, at, 2202, down, scratch)
            if at < 0:
                return sl_fail()
            left = left - 1
        return at
    if node == 301:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 kind = scratch[0]
        if kind < (int64)0 or kind >= (int64)sl_component_count():
            return sl_fail()
        return sl_node(data, at, (int)kind, down, scratch)
    if node == 303:
        int64 at = sl_count(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 left = scratch[0]
        while left > (int64)0:
            at = sl_text(data, at)
            if at < 0:
                return sl_fail()
            at = sl_text(data, at)
            if at < 0:
                return sl_fail()
            left = left - 1
        return at
    if node == 304:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] == (int64)0:
            return pl_take(data, at, 4)
        if scratch[0] != (int64)1:
            return sl_fail()
        return sl_text(data, at)
    if node == 305:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] == (int64)0:
            return pl_take(data, at, 4)
        if scratch[0] != (int64)1:
            return sl_fail()
        return sl_text(data, at)
    if node == 306:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] > (int64)1:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 255, down, scratch)
    if node == 307:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        at = pl_take(data, at, 8)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 320:
        int64 at = sl_node(data, cursor, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_byte(data, at, scratch)
        if at < 0:
            return sl_fail()
        int64 filtered = scratch[0]
        if filtered == (int64)1:
            at = sl_node(data, at, 255, down, scratch)
            if at < 0:
                return sl_fail()
            at = sl_node(data, at, 255, down, scratch)
            if at < 0:
                return sl_fail()
            at = sl_node(data, at, 255, down, scratch)
            if at < 0:
                return sl_fail()
            at = sl_node(data, at, 255, down, scratch)
            if at < 0:
                return sl_fail()
        elif filtered != (int64)0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        return sl_byte(data, at, scratch)

    # Everything below is one component payload: walk its step list.
    int component = node
    if component < 0 or component >= sl_component_count():
        return sl_fail()
    int64 here = cursor
    int index = 0
    int step = sl_component_step(component, 0)
    while step >= 0:
        here = sl_node(data, here, step, down, scratch)
        if here < 0:
            return sl_fail_named(sl_component_name(component))
        index = index + 1
        step = sl_component_step(component, index)
    if step == -2:
        return sl_fail_named(sl_component_name(component))
    return here


public def sl_component_known(component: int) -> int:
    if component < 0 or component >= sl_component_count():
        return 0
    return 1


# Skip one component payload, for a caller that already read the type varint.
public def sl_skip_component(data: int64[], cursor: int64, component: int) -> int64:
    int64[] scratch = new int64[1]
    return sl_node(data, cursor, component, 0, scratch)


# Read one Slot. out receives {present, item id, count}; the return value is
# the offset after the stack, or -1 when the bytes are not a valid stack.
public def sl_read(data: int64[], cursor: int64, out: int64[]) -> int64:
    out[0] = 0
    out[1] = 0
    out[2] = 0
    int64[] scratch = new int64[1]
    int64 at = sl_value(data, cursor, scratch)
    if at < 0:
        return sl_fail()
    int64 count = scratch[0]
    if count < (int64)0 or count > (int64)sl_stack_max():
        return sl_fail()
    if count == (int64)0:
        return at
    at = sl_value(data, at, scratch)
    if at < 0:
        return sl_fail()
    int64 item = scratch[0]
    if item < (int64)0 or item > (int64)sl_item_max():
        return sl_fail()
    at = sl_node(data, at, 200, 0, scratch)
    if at < 0:
        return sl_fail()
    out[0] = 1
    out[1] = item
    out[2] = count
    return at


# Read one ItemStackTemplate: the same envelope with an explicit item count.
public def sl_read_template(data: int64[], cursor: int64,
                            out: int64[]) -> int64:
    out[0] = 0
    out[1] = 0
    out[2] = 0
    int64[] scratch = new int64[1]
    int64 at = sl_value(data, cursor, scratch)
    if at < 0:
        return sl_fail()
    int64 item = scratch[0]
    if item < (int64)0 or item > (int64)sl_item_max():
        return sl_fail()
    at = sl_value(data, at, scratch)
    if at < 0:
        return sl_fail()
    int64 count = scratch[0]
    if count < (int64)0 or count > (int64)sl_stack_max():
        return sl_fail()
    at = sl_node(data, at, 200, 0, scratch)
    if at < 0:
        return sl_fail()
    out[0] = 1
    out[1] = item
    out[2] = count
    return at

# Public entry points for the registry-holder forms, so the recipe and display
# readers can reuse the same length rules as the component payloads.
public def sl_read_node(data: int64[], cursor: int64, node: int) -> int64:
    int64[] scratch = new int64[1]
    return sl_node(data, cursor, node, 0, scratch)


public def sl_read_holder(data: int64[], cursor: int64, node: int) -> int64:
    return sl_read_node(data, cursor, 400 + node)


public def sl_read_holder_set(data: int64[], cursor: int64) -> int64:
    int64[] scratch = new int64[1]
    return sl_holder_set(data, cursor, scratch)


# ===== display.cpy =====
# Vortex engine - SlotDisplay and RecipeDisplay readers (protocol 777).
#
# Both are registry-dispatched: a varint registry id selects the payload. The
# ids below are the bootstrap registration order in SlotDisplays / RecipeDisplays,
# which is what the wire carries. SlotDisplay nests, so sd_read is the single
# recursive function; RecipeDisplay only ever calls into it.


public def sd_type_count() -> int:
    return 11


public def rd_type_count() -> int:
    return 5


public def sd_depth_max() -> int:
    return 16


public def sd_list_max() -> int64:
    return 4096


def sd_fail() -> int64:
    return (int64)-1


def sd_varint(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64[] field = decode_varint(data, cursor)
    if field[0] != 1:
        return sd_fail()
    scratch[0] = field[1]
    return field[2]


# One SlotDisplay. Returns the offset after it, or -1 when the bytes do not
# describe a display this client knows.
def sd_read(data: int64[], cursor: int64, depth: int, scratch: int64[]) -> int64:
    if depth > sd_depth_max():
        return sd_fail()
    int64 at = sd_varint(data, cursor, scratch)
    if at < 0:
        return sd_fail()
    int64 kind = scratch[0]
    if kind == (int64)0 or kind == (int64)1:
        return at
    if kind == (int64)2:
        return sd_read(data, at, depth + 1, scratch)
    if kind == (int64)3:
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        # DataComponentType travels as a plain registry id.
        return sd_varint(data, at, scratch)
    if kind == (int64)4:
        return sd_varint(data, at, scratch)
    if kind == (int64)5:
        int64[] stack = new int64[3]
        return sl_read_template(data, at, stack)
    if kind == (int64)6:
        return sl_read_holder_set(data, at)
    if kind == (int64)7 or kind == (int64)9:
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        return sd_read(data, at, depth + 1, scratch)
    if kind == (int64)8:
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        return sl_read_holder(data, at, 226)
    if kind == (int64)10:
        at = sd_varint(data, at, scratch)
        if at < 0:
            return sd_fail()
        int64 count = scratch[0]
        if count < (int64)0 or count > sd_list_max():
            return sd_fail()
        int64 index = 0
        while index < count:
            at = sd_read(data, at, depth + 1, scratch)
            if at < 0:
                return sd_fail()
            index = index + 1
        return at
    return sd_fail()


public def sd_skip(data: int64[], cursor: int64) -> int64:
    int64[] scratch = new int64[1]
    return sd_read(data, cursor, 0, scratch)


def sd_list(data: int64[], cursor: int64, depth: int,
            scratch: int64[]) -> int64:
    int64 at = sd_varint(data, cursor, scratch)
    if at < 0:
        return sd_fail()
    int64 count = scratch[0]
    if count < (int64)0 or count > sd_list_max():
        return sd_fail()
    int64 index = 0
    while index < count:
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        index = index + 1
    return at


# One RecipeDisplay. `out` receives {type id, result item hint} where the hint
# is only filled for the item-stack result form; callers that need the real
# result re-read the recorded span.
public def rd_read(data: int64[], cursor: int64, out: int64[]) -> int64:
    out[0] = -1
    int64[] scratch = new int64[1]
    int64 at = sd_varint(data, cursor, scratch)
    if at < 0:
        return sd_fail()
    int64 kind = scratch[0]
    if kind < (int64)0 or kind >= (int64)rd_type_count():
        return sd_fail()
    out[0] = kind
    if kind == (int64)0:
        at = sd_list(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        at = sd_read(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        return sd_read(data, at, 0, scratch)
    if kind == (int64)1:
        at = sd_varint(data, at, scratch)
        if at < 0:
            return sd_fail()
        int64 width = scratch[0]
        at = sd_varint(data, at, scratch)
        if at < 0:
            return sd_fail()
        int64 height = scratch[0]
        if width < (int64)1 or (width > (int64)3 or height < (int64)1):
            return sd_fail()
        if height > (int64)3:
            return sd_fail()
        at = sd_list(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        at = sd_read(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        return sd_read(data, at, 0, scratch)
    if kind == (int64)2:
        int step = 0
        while step < 4:
            at = sd_read(data, at, 0, scratch)
            if at < 0:
                return sd_fail()
            step = step + 1
        at = sd_varint(data, at, scratch)
        if at < 0:
            return sd_fail()
        return pl_take(data, at, 4)
    if kind == (int64)3:
        int step = 0
        while step < 3:
            at = sd_read(data, at, 0, scratch)
            if at < 0:
                return sd_fail()
            step = step + 1
        return at
    int step = 0
    while step < 5:
        at = sd_read(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        step = step + 1
    return at

# ===== palette.cpy =====
# Vortex engine - paletted container.
#
# A chunk section's 4096 block states and a biome section's 64 biomes are both
# stored the same way, so one container serves both and only the entry count,
# the width bounds and the value meanings differ.
#
# Three storage modes, following the community "paletted container" rules:
#   uniform   - every entry holds the same value; no palette, no data words;
#   indirect  - a palette of values plus packed palette indices;
#   direct    - the values themselves, packed at the full width, no palette.
#
# The packed words use padded packing (an entry never straddles two 64 bit
# words); the arithmetic lives in src/engine/native.cpy because Cpyte compares
# unsigned values as signed.
#
# Reading a section is a one way trip: vcont_reset, vcont_palette_add for each
# palette entry, vcont_alloc_words, then vcont_set_word for each stored word.
# The palette may be added before or after the words because only vcont_at
# reads them.
#
# The compiler resolves a call against what it has already read, so this module
# is ordered bottom up: every helper is defined before its callers.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.


public def vcont_uniform_mode() -> int:
    return 0


public def vcont_indirect_mode() -> int:
    return 1


public def vcont_direct_mode() -> int:
    return 2


struct VContainer:
    int count             # entries held: 4096 blocks, 64 biomes
    int min_bits          # narrowest indirect encoding
    int max_bits          # widest indirect encoding
    int direct_bits       # width once the palette is dropped
    int mode
    int bits              # current encoding width; 0 while uniform
    int uniform_value
    int* palette          # palette slot -> stored value
    int palette_len
    int palette_cap
    int palette_limit     # most palette slots the encoding may use
    uint64* words         # packed indices (indirect) or values (direct)
    int words_len


# ---- arithmetic helpers ------------------------------------------------------

# 2**bits as an int, computed by doubling so no widening shift is involved.
def vcont_pow2(bits: int) -> int:
    int v = 1
    int i = 0
    while i < bits:
        v = v * 2
        i += 1
    return v


def vcont_capacity_bits(max_bits: int) -> int:
    if max_bits < 1:
        return 2
    if max_bits > 30:
        return vcont_pow2(30)
    return vcont_pow2(max_bits)


# Smallest width whose range covers `needed` values, never below `min_bits`.
public def vcont_bits_for(needed: int, min_bits: int) -> int:
    int bits = min_bits
    int cap = vcont_pow2(bits)
    while cap < needed and bits < 30:
        bits += 1
        cap = cap * 2
    return bits


# ---- slots and words ---------------------------------------------------------

# Ensures the slot array can hold one more entry within palette_limit.
def vcont_grow_palette(c: VContainer*) -> void:
    if c.palette_len < c.palette_cap:
        return
    int cap = c.palette_cap * 2
    if cap < 8:
        cap = 8
    if cap > c.palette_limit:
        cap = c.palette_limit
    int* next = vt_calloc_int(cap)
    int keep = c.palette_len
    if keep > cap:
        keep = cap
    int i = 0
    while i < keep:
        vt_iset(next, i, vt_iget(c.palette, i))
        i += 1
    if c.palette != null:
        vt_free((void*)c.palette)
    c.palette = next
    c.palette_cap = cap


def vcont_palette_push(c: VContainer*, value: int) -> int:
    vcont_grow_palette(c)
    int index = c.palette_len
    vt_iset(c.palette, index, value)
    c.palette_len += 1
    return index


def vcont_palette_index_of(c: VContainer*, value: int) -> int:
    int i = 0
    while i < c.palette_len:
        if vt_iget(c.palette, i) == value:
            return i
        i += 1
    return -1


def vcont_palette_get(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.palette_len:
        return 0
    return vt_iget(c.palette, index)


# Allocates words for `bits`, discarding whatever was stored before.
def vcont_alloc_words(c: VContainer*, bits: int) -> void:
    int need = vt_packed_words(c.count, bits)
    if c.words != null:
        vt_free((void*)c.words)
    if need < 1:
        need = 1
    c.words = vt_calloc_u64(need)
    c.words_len = need
    c.bits = bits


# The value at `index`, whatever the current mode. An indirect container stores
# palette slots, so the slot has to be resolved before returning.
def vcont_at(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.count:
        return 0
    if c.mode == vcont_uniform_mode():
        return c.uniform_value
    if c.mode == vcont_direct_mode():
        return (int)vt_packed_get(c.words, index, c.direct_bits)
    int slot = (int)vt_packed_get(c.words, index, c.bits)
    return vcont_palette_get(c, slot)


# ---- mode transitions --------------------------------------------------------

# Back to uniform storage holding `value`. The palette and word arrays stay
# allocated for the next encoding to reuse.
public def vcont_reset(c: VContainer*, value: int) -> void:
    c.mode = vcont_uniform_mode()
    c.bits = 0
    c.uniform_value = value
    c.palette_len = 0
    c.words_len = 0
    c.palette_limit = vcont_capacity_bits(c.max_bits)


# Re-encodes every entry at `new_bits`, keeping the palette unchanged.
def vcont_repack(c: VContainer*, new_bits: int) -> void:
    uint64* old = c.words
    int old_bits = c.bits
    c.words = null
    c.words_len = 0
    vcont_alloc_words(c, new_bits)
    if old == null:
        return
    int i = 0
    while i < c.count:
        uint64 slot = vt_packed_get(old, i, old_bits)
        vt_packed_set(c.words, i, new_bits, slot)
        i += 1
    vt_free((void*)old)


# Leaves uniform storage: the old value and the new one enter the palette,
# every entry is re-encoded as the old value's index, and `index` takes the new
# one.
def vcont_leave_uniform(c: VContainer*, index: int, value: int) -> void:
    int old_value = c.uniform_value
    int bits = c.min_bits
    vcont_alloc_words(c, bits)
    int first = vcont_palette_push(c, old_value)
    int second = vcont_palette_push(c, value)
    c.mode = vcont_indirect_mode()
    int i = 0
    while i < c.count:
        vt_packed_set(c.words, i, bits, (uint64)first)
        i += 1
    vt_packed_set(c.words, index, bits, (uint64)second)


# Drops the palette and stores values at the full direct width. Every entry
# keeps the value its palette slot pointed at.
def vcont_promote(c: VContainer*) -> void:
    uint64* old = c.words
    int* slots = c.palette
    int old_bits = c.bits
    int entries = c.palette_len
    c.words = null
    c.words_len = 0
    vcont_alloc_words(c, c.direct_bits)
    if old != null:
        int i = 0
        while i < c.count:
            int slot = (int)vt_packed_get(old, i, old_bits)
            uint64 value = (uint64)0
            if slot >= 0 and slot < entries:
                value = (uint64)vt_iget(slots, slot)
            vt_packed_set(c.words, i, c.direct_bits, value)
            i += 1
        vt_free((void*)old)
    c.palette_len = 0
    c.mode = vcont_direct_mode()


# ---- rebuild from values -----------------------------------------------------

# Reads every entry into `values` as the value it denotes; `values` needs
# `count` slots.
def vcont_collect(c: VContainer*, values: int*) -> void:
    int i = 0
    while i < c.count:
        vt_iset(values, i, vcont_at(c, i))
        i += 1


# Counts distinct values in linear expected time; section compaction calls this
# on all 4096 block entries, so a pairwise scan is prohibitively slow.
def vcont_count_distinct(values: int*, count: int) -> int:
    if count <= 0:
        return 0
    int capacity = 1
    while capacity < count * 2:
        capacity *= 2
    int* slots = vt_calloc_int(capacity)
    char* occupied = vt_calloc_char(capacity)
    int distinct = 0
    int probe = 0
    while probe < count:
        int candidate = vt_iget(values, probe)
        uint64 key = (uint64)candidate
        key = key ^ (key >> (uint64)16)
        key = key * (uint64)2654435761
        key = key ^ (key >> (uint64)13)
        int slot = (int)(key & (uint64)(capacity - 1))
        while vt_at(occupied, slot) != 0 and vt_iget(slots, slot) != candidate:
            slot = (slot + 1) & (capacity - 1)
        if vt_at(occupied, slot) == 0:
            vt_put(occupied, slot, 1)
            vt_iset(slots, slot, candidate)
            distinct += 1
        probe += 1
    vt_free((void*)slots)
    vt_free((void*)occupied)
    return distinct


# Number of distinct values held, which a save needs to size its palette.
public def vcont_distinct_count(c: VContainer*) -> int:
    if c.mode == vcont_uniform_mode():
        return 1
    if c.mode == vcont_indirect_mode():
        return c.palette_len
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
    vt_free((void*)values)
    return distinct


def vcont_rebuild_indirect(c: VContainer*, values: int*, bits: int) -> void:
    vcont_reset(c, vt_iget(values, 0))
    int width_limit = vcont_capacity_bits(bits)
    if width_limit > c.palette_limit:
        c.palette_limit = width_limit
    vcont_alloc_words(c, bits)
    c.mode = vcont_indirect_mode()
    int i = 0
    while i < c.count:
        int value = vt_iget(values, i)
        int slot = vcont_palette_index_of(c, value)
        if slot < 0:
            slot = vcont_palette_push(c, value)
        vt_packed_set(c.words, i, bits, (uint64)slot)
        i += 1


def vcont_rebuild_direct(c: VContainer*, values: int*) -> void:
    vcont_reset(c, vt_iget(values, 0))
    vcont_alloc_words(c, c.direct_bits)
    c.mode = vcont_direct_mode()
    int i = 0
    while i < c.count:
        vt_packed_set(c.words, i, c.direct_bits, (uint64)vt_iget(values, i))
        i += 1


# ---- writing -----------------------------------------------------------------

# Width and word count the section records for this container.
def vcont_save_bits(c: VContainer*) -> int:
    int distinct = vcont_distinct_count(c)
    if distinct <= 1:
        return 0
    int bits = vcont_bits_for(distinct, c.min_bits)
    if bits > c.max_bits:
        return c.direct_bits
    return bits


def vcont_save_word_count(c: VContainer*, bits: int) -> int:
    if bits <= 0:
        return 0
    return vt_packed_words(c.count, bits)


# Collapses the encoding to its narrowest form: uniform for one distinct
# value, otherwise the smallest width that indexes the palette.
public def vcont_compact(c: VContainer*) -> void:
    if c.mode == vcont_uniform_mode():
        return
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
    if distinct <= 1:
        vcont_reset(c, vt_iget(values, 0))
        vt_free((void*)values)
        return
    int bits = vcont_bits_for(distinct, c.min_bits)
    if bits > c.max_bits:
        vcont_rebuild_direct(c, values)
        vt_free((void*)values)
        return
    vcont_rebuild_indirect(c, values, bits)
    vt_free((void*)values)


# ---- palette view ------------------------------------------------------------

public def vcont_palette_len(c: VContainer*) -> int:
    return c.palette_len


# 1 when `index` is a palette slot, so vcont_palette_at returns its value.
public def vcont_has_palette(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.palette_len:
        return 0
    return 1


public def vcont_palette_at(c: VContainer*, index: int) -> int:
    return vcont_palette_get(c, index)


# ---- word view ---------------------------------------------------------------

# 1 when the container is uniform, which is when a save writes no words at all.
public def vcont_is_uniform(c: VContainer*) -> int:
    if c.mode == vcont_uniform_mode():
        return 1
    int first = vcont_at(c, 0)
    int i = 1
    while i < c.count:
        if vcont_at(c, i) != first:
            return 0
        i += 1
    return 1


public def vcont_uniform_value(c: VContainer*) -> int:
    return vcont_at(c, 0)


# Collapses a container that has gone back to a single value. 1 when it did.
public def vcont_try_uniform(c: VContainer*) -> int:
    if vcont_is_uniform(c) == 0:
        return 0
    vcont_reset(c, vcont_at(c, 0))
    return 1


public def vcont_save_bits_for(c: VContainer*) -> int:
    return vcont_save_bits(c)


public def vcont_save_words_for(c: VContainer*, bits: int) -> int:
    return vcont_save_word_count(c, bits)


# 1 when `index` is a stored word; the caller reads it with vcont_save_word.
public def vcont_has_save_word(c: VContainer*, index: int) -> int:
    if c.words == null or c.bits <= 0 or index < 0:
        return 0
    if index >= vcont_save_word_count(c, c.bits):
        return 0
    return 1


public def vcont_save_word(c: VContainer*, index: int) -> uint64:
    if c.words == null or index < 0 or index >= c.words_len:
        return (uint64)0
    return (uint64)vt_uget(c.words, index)


# ---- accessors ---------------------------------------------------------------

public def vcont_new(count: int, min_bits: int, max_bits: int, direct_bits: int) -> VContainer*:
    VContainer* c = new VContainer
    c.count = count
    c.min_bits = min_bits
    c.max_bits = max_bits
    c.direct_bits = direct_bits
    c.mode = vcont_uniform_mode()
    c.bits = 0
    c.uniform_value = 0
    c.palette = null
    c.palette_len = 0
    c.palette_cap = 0
    c.palette_limit = vcont_capacity_bits(max_bits)
    c.words = null
    c.words_len = 0
    return c


public def vcont_free(c: VContainer*) -> void:
    if c == null:
        return
    if c.palette != null:
        vt_free((void*)c.palette)
    if c.words != null:
        vt_free((void*)c.words)
    del c


public def vcont_bits(c: VContainer*) -> int:
    return c.bits


public def vcont_mode(c: VContainer*) -> int:
    return c.mode


public def vcont_count(c: VContainer*) -> int:
    return c.count


# A uniform container stores no words, which is what the saved form records.
public def vcont_word_count(c: VContainer*) -> int:
    return vcont_save_word_count(c, c.bits)


# Appends a value read from the saved palette; the words can be filled before
# or after, only vcont_at reads them.
public def vcont_palette_add(c: VContainer*, value: int) -> void:
    if c.palette_len >= c.palette_limit:
        return
    vcont_palette_push(c, value)


# Allocates and clears the data words for `bits`; pairs with vcont_set_word and
# vcont_palette_add.
public def vcont_alloc(c: VContainer*, bits: int) -> void:
    vcont_alloc_words(c, bits)
    c.mode = vcont_indirect_mode()


public def vcont_alloc_direct(c: VContainer*, bits: int) -> void:
    vcont_alloc_words(c, bits)
    c.mode = vcont_direct_mode()


public def vcont_set_word(c: VContainer*, index: int, value: uint64) -> void:
    if c.words == null or index < 0 or index >= c.words_len:
        return
    vt_uset(c.words, index, (uint64)value)


public def vcont_set(c: VContainer*, index: int, value: int) -> void:
    if index < 0 or index >= c.count:
        return
    if c.mode == vcont_uniform_mode():
        if value == c.uniform_value:
            return
        vcont_leave_uniform(c, index, value)
        return
    if c.mode == vcont_direct_mode():
        vt_packed_set(c.words, index, c.direct_bits, (uint64)value)
        return
    int slot = vcont_palette_index_of(c, value)
    if slot >= 0:
        vt_packed_set(c.words, index, c.bits, (uint64)slot)
        return
    if c.palette_len >= c.palette_limit:
        vcont_promote(c)
        vt_packed_set(c.words, index, c.direct_bits, (uint64)value)
        return
    int new_bits = vcont_bits_for(c.palette_len + 1, c.bits)
    if new_bits > c.bits:
        vcont_repack(c, new_bits)
    int added = vcont_palette_push(c, value)
    vt_packed_set(c.words, index, c.bits, (uint64)added)


# A direct container carries no palette, but a saved section always has one,
# so the values are re-collected at `save_bits` before writing. Returns 0 when
# the distinct values do not fit that width, leaving the container untouched.
public def vcont_save_prepare(c: VContainer*, save_bits: int) -> int:
    if c.mode != vcont_direct_mode():
        return 1
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
    int needed = vcont_bits_for(distinct, 1)
    if needed > save_bits:
        vt_free((void*)values)
        return 0
    vcont_rebuild_indirect(c, values, save_bits)
    vt_free((void*)values)
    return 1


# ===== section.cpy =====
# Vortex engine - chunk section.
#
# One 16x16x16 slice of the world: 4096 block states plus, following Horizon's
# split of the biome container, 64 biomes at 4x4x4 resolution, and the two
# four bit light masks.
#
# Entries are addressed the way the game lays a section out in memory:
#   block (x, y, z) -> x + z * 16 + y * 256
#   biome (x, y, z) -> x + z *  4 + y *  16
#
# Block states and biomes are held as ids chosen by the caller's registry; the
# engine never numbers them itself, so the NBT mapping here records the palette
# as ids. The io layer that owns a registry turns those ids into the
# Name/Properties compounds the game writes, and can read them back, through
# vcont_palette_at and sec_load_palette - the seams this module leaves open.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.


public def sec_size() -> int:
    return 16


public def sec_block_count() -> int:
    return 4096


public def sec_biome_count() -> int:
    return 64


# Two 4 bit light levels per byte.
public def sec_light_bytes() -> int:
    return 2048


def sec_block_index(x: int, y: int, z: int) -> int:
    return x + z * 16 + y * 256


def sec_biome_index(x: int, y: int, z: int) -> int:
    return x + z * 4 + y * 16


# The block and biome containers differ only in entry count and width bounds.
def sec_blocks_min_bits() -> int:
    return 4


def sec_blocks_max_bits() -> int:
    return 8


def sec_blocks_direct_bits() -> int:
    return 16


def sec_biomes_min_bits() -> int:
    return 1


def sec_biomes_max_bits() -> int:
    return 3


def sec_biomes_direct_bits() -> int:
    return 7


struct VSection:
    int y                 # section index in the column, not a block coordinate
    int non_empty         # non-air block count from a network section, if known
    VContainer* blocks
    VContainer* biomes
    char* block_light     # 2048 bytes, two 4 bit levels per byte
    char* sky_light


# ---- light -------------------------------------------------------------------

def sec_light_at(light: char*, index: int) -> int:
    if light == null or index < 0 or index >= 4096:
        return 0
    int byte = (int)vt_at(light, index / 2)
    if index % 2 == 0:
        return byte & 15
    return (byte >> 4) & 15


def sec_light_set(light: char*, index: int, level: int) -> void:
    if light == null or index < 0 or index >= 4096:
        return
    int at = index / 2
    int other = 0
    if index % 2 == 0:
        other = sec_light_at(light, index + 1) << 4
        vt_put(light, at, other | (level & 15))
    else:
        other = sec_light_at(light, index - 1)
        vt_put(light, at, other | ((level & 15) << 4))


# 256 longs, each holding eight bytes little endian.
def sec_light_words() -> int:
    return 256


def sec_light_to_tag(light: char*, name: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_long_array(), name)
    nbt_set_longs(t, sec_light_words())
    int w = 0
    while w < sec_light_words():
        int64 value = (int64)0
        int b = 0
        while b < 8:
            int byte = (int)vt_at(light, w * 8 + b) & 255
            value = value | ((int64)byte << ((int64)b * (int64)8))
            b += 1
        nbt_set_long_at(t, w, value)
        w += 1
    return t


def sec_light_from_tag(t: VNbt*, light: char*) -> void:
    if t == null or light == null:
        return
    int count = nbt_long_len(t)
    if count > sec_light_words():
        count = sec_light_words()
    int w = 0
    while w < count:
        int64 value = nbt_long_at(t, w)
        int b = 0
        while b < 8:
            int byte = (int)((value >> ((int64)b * (int64)8)) & (int64)255)
            vt_put(light, w * 8 + b, byte)
            b += 1
        w += 1
    while w < sec_light_words():
        int b = 0
        while b < 8:
            vt_put(light, w * 8 + b, 0)
            b += 1
        w += 1
    return


# ---- container to and from NBT -----------------------------------------------

# Palette entry count, whether the tag is a list of ints or an int array. A
# list of Name/Properties compounds is the registry layer's to read, so it is
# reported as no palette here rather than silently decoding to zeros.
def sec_palette_slots(t: VNbt*) -> int:
    VNbt* palette = nbt_find(t, "palette")
    if palette == null:
        return 0
    if palette.kind == nbt_list():
        int elem = nbt_list_element_kind(palette)
        if elem != nbt_int() and elem != nbt_byte() and elem != nbt_short():
            return 0
        return nbt_child_count(palette)
    if palette.kind == nbt_int_array():
        return nbt_int_len(palette)
    return 0


# Appends each palette entry to `c`, in tag order.
def sec_load_palette(palette: VNbt*, c: VContainer*) -> void:
    if palette == null:
        return
    int count = nbt_child_count(palette)
    if palette.kind == nbt_int_array():
        count = nbt_int_len(palette)
    int i = 0
    while i < count:
        if palette.kind == nbt_int_array():
            vcont_palette_add(c, nbt_int_at(palette, i))
        else:
            vcont_palette_add(c, nbt_int_value(nbt_child_at(palette, i), 0))
        i += 1
    return


# The palette the saved form records: one entry while the container is uniform,
# otherwise its own. An io layer translating ids to Name compounds walks these,
# so it sees exactly what the tag will hold.
public def sec_palette_size(c: VContainer*) -> int:
    if vcont_mode(c) == vcont_uniform_mode():
        return 1
    return vcont_palette_len(c)


public def sec_palette_entry(c: VContainer*, index: int) -> int:
    if vcont_mode(c) == vcont_uniform_mode():
        return vcont_uniform_value(c)
    return vcont_palette_at(c, index)


# TAG_Compound `{palette: [...], data: [long...]}` for one container. A uniform
# container writes the single palette entry and no data array, which is exactly
# what the game does.
def sec_container_to_nbt(c: VContainer*, name: str) -> VNbt*:
    VContainer* encoded = c
    VContainer* temporary = c
    if vcont_mode(c) == vcont_direct_mode():
        temporary = vcont_new(vcont_count(c), c.min_bits, 30, c.direct_bits)
        int at = 0
        while at < vcont_count(c):
            vcont_set(temporary, at, vcont_at(c, at))
            at += 1
        vcont_compact(temporary)
        encoded = temporary

    VNbt* root = nbt_compound_of(name)
    VNbt* palette = nbt_list_of("palette", nbt_int())
    int slots = sec_palette_size(encoded)
    int i = 0
    while i < slots:
        nbt_append(palette, nbt_int_of("", sec_palette_entry(encoded, i)))
        i += 1
    nbt_append(root, palette)

    int bits = vcont_save_bits_for(encoded)
    if bits <= 0:
        if temporary != c:
            vcont_free(temporary)
        return root
    VNbt* data = nbt_new(nbt_long_array(), "data")
    int words = vcont_save_words_for(encoded, bits)
    nbt_set_longs(data, words)
    int w = 0
    while w < words:
        nbt_set_long_at(data, w, (int64)vcont_save_word(encoded, w))
        w += 1
    nbt_append(root, data)
    if temporary != c:
        vcont_free(temporary)
    return root


# Fills `c` from a `{palette, data}` compound. Returns 0 when the tag is not a
# compound or carries no palette.
def sec_container_from_nbt(t: VNbt*, c: VContainer*, min_bits: int) -> int:
    if t == null:
        return 0
    if t.kind != nbt_compound():
        return 0
    int slots = sec_palette_slots(t)
    if slots <= 0:
        return 0
    int bits = vcont_bits_for(slots, min_bits)
    vcont_reset(c, 0)
    VNbt* palette = nbt_find(t, "palette")
    VNbt* data = nbt_find(t, "data")
    if data == null:
        sec_load_palette(palette, c)
        if vcont_palette_len(c) <= 0:
            return 0
        # A single valued palette needs no data array: the whole section holds
        # the one entry.
        if vcont_palette_len(c) == 1:
            vcont_reset(c, vcont_palette_at(c, 0))
            return 1
        return 0
    if data.kind != nbt_long_array():
        return 0
    VContainer* decoded = c
    VContainer* temporary = c
    if bits > c.max_bits:
        temporary = vcont_new(vcont_count(c), min_bits, 30, c.direct_bits)
        decoded = temporary
    sec_load_palette(palette, decoded)

    vcont_alloc(decoded, bits)
    int words = nbt_long_len(data)
    int want = vcont_save_words_for(decoded, bits)
    if words > want:
        words = want
    int w = 0
    while w < words:
        vcont_set_word(decoded, w, (uint64)nbt_long_at(data, w))
        w += 1

    if temporary != c:
        int at = 0
        while at < vcont_count(c):
            vcont_set(c, at, vcont_at(decoded, at))
            at += 1
        vcont_free(temporary)
    return 1


# ---- the section itself ------------------------------------------------------

public def sec_new_for_wire(y: int, block_global_bits: int, biome_global_bits: int) -> VSection*:
    VSection* s = new VSection
    s.y = y
    s.non_empty = 0
    s.blocks = vcont_new(sec_block_count(), sec_blocks_min_bits(),
                         sec_blocks_max_bits(), block_global_bits)
    s.biomes = vcont_new(sec_biome_count(), sec_biomes_min_bits(),
                         sec_biomes_max_bits(), biome_global_bits)
    s.block_light = vt_calloc_char(sec_light_bytes())
    s.sky_light = vt_calloc_char(sec_light_bytes())
    return s


public def sec_new(y: int) -> VSection*:
    return sec_new_for_wire(y, sec_blocks_direct_bits(), sec_biomes_direct_bits())


public def sec_free(s: VSection*) -> void:
    if s == null:
        return
    vcont_free(s.blocks)
    vcont_free(s.biomes)
    if s.block_light != null:
        vt_free((void*)s.block_light)
    if s.sky_light != null:
        vt_free((void*)s.sky_light)
    del s


public def sec_index_ok(x: int, y: int, z: int, stride: int) -> int:
    if x < 0 or x >= stride:
        return 0
    if y < 0 or y >= stride:
        return 0
    if z < 0 or z >= stride:
        return 0
    return 1


public def sec_block_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return vcont_at(s.blocks, sec_block_index(x, y, z))


public def sec_block_set(s: VSection*, x: int, y: int, z: int, state: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    vcont_set(s.blocks, sec_block_index(x, y, z), state)


public def sec_biome_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 4) == 0:
        return 0
    return vcont_at(s.biomes, sec_biome_index(x, y, z))


public def sec_biome_set(s: VSection*, x: int, y: int, z: int, biome: int) -> void:
    if sec_index_ok(x, y, z, 4) == 0:
        return
    vcont_set(s.biomes, sec_biome_index(x, y, z), biome)


public def sec_block_light_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return sec_light_at(s.block_light, sec_block_index(x, y, z))


public def sec_block_light_set(s: VSection*, x: int, y: int, z: int, level: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    sec_light_set(s.block_light, sec_block_index(x, y, z), level)


public def sec_sky_light_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return sec_light_at(s.sky_light, sec_block_index(x, y, z))


public def sec_sky_light_set(s: VSection*, x: int, y: int, z: int, level: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    sec_light_set(s.sky_light, sec_block_index(x, y, z), level)


# Flat-index accessors for the native parallel mesher (engine/mesher.c). Its
# worker threads read decoded sections through these C-callable symbols instead
# of the paletted-container path, so the inner face loop never touches the GC.
# The index is the section's own layout: x + z * 16 + y * 256.
public def sec_block_at_index(s: VSection*, index: int) -> int:
    if s == null or index < 0 or index >= sec_block_count():
        return 0
    return vcont_at(s.blocks, index)


# Flat biome accessor for the native mesher: index is x + z * 4 + y * 16 over
# the section's 4x4x4 biome grid.
public def sec_biome_at_index(s: VSection*, index: int) -> int:
    if s == null or index < 0 or index >= sec_biome_count():
        return 0
    return vcont_at(s.biomes, index)


# Packed sky/block light, sky * 16 + block, matching vworld_light_at. An absent
# section reads as full sky so a partially loaded world stays visible.
public def sec_light_packed_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 15 * 16
    int index = sec_block_index(x, y, z)
    return sec_light_at(s.sky_light, index) * 16 + sec_light_at(s.block_light, index)


public def sec_light_packed_index(s: VSection*, index: int) -> int:
    if s == null or index < 0 or index >= sec_block_count():
        return 15 * 16
    return sec_light_at(s.sky_light, index) * 16 + sec_light_at(s.block_light, index)


# Shrinks both containers before a save so the palette and data width are the
# narrowest the contents allow.
public def sec_compact(s: VSection*) -> void:
    vcont_compact(s.blocks)
    vcont_compact(s.biomes)
    return


# The whole section compound: `block_states`, `biomes`, the Y index and the
# light masks. `AltValues` is the block light array and `SkyLight` the sky one.
public def sec_to_nbt(s: VSection*, name: str) -> VNbt*:
    sec_compact(s)
    VNbt* root = nbt_compound_of(name)
    nbt_append(root, sec_container_to_nbt(s.blocks, "block_states"))
    nbt_append(root, sec_container_to_nbt(s.biomes, "biomes"))
    nbt_append(root, nbt_byte_of("Y", s.y))
    nbt_append(root, sec_light_to_tag(s.block_light, "AltValues"))
    nbt_append(root, sec_light_to_tag(s.sky_light, "SkyLight"))
    return root


# Accepts either tag spelling for the light arrays, which differ between
# versions of the format.
public def sec_from_nbt(t: VNbt*, y: int) -> VSection*:
    VSection* s = sec_new(y)
    VNbt* blocks = nbt_find(t, "block_states")
    if sec_container_from_nbt(blocks, s.blocks, sec_blocks_min_bits()) == 0:
        sec_free(s)
        return null
    VNbt* biomes = nbt_find(t, "biomes")
    if sec_container_from_nbt(biomes, s.biomes, sec_biomes_min_bits()) == 0:
        sec_free(s)
        return null
    s.y = nbt_get_int(t, "Y", y)
    VNbt* light = nbt_find(t, "AltValues")
    if light == null:
        light = nbt_find(t, "BlockLight")
    sec_light_from_tag(light, s.block_light)
    sec_light_from_tag(nbt_find(t, "SkyLight"), s.sky_light)
    return s


# ===== heightmap.cpy =====
# Vortex engine - chunk column heightmaps.
#
# A server sends one height value per block column, packed 9 bits at a time
# least significant bit first across a big endian long array, so 256 values
# occupy 36 longs. The values are absolute world Y, which is why a dimension
# that starts below y = 0 still reports heights above its minimum: the packing
# carries no offset. Cpyte shifts and masks `int64` correctly but compares an
# unsigned value as signed, so the unpack loops stay in `int64` and only ever
# test the low nine bits after the mask.


public def hm_cells() -> int:
    return 256


public def hm_kind_count() -> int:
    return 2


# The kinds this engine stores. The wire names each one with its own id, so
# these numbers only index the stored column.
public def hm_motion_blocking() -> int:
    return 0


public def hm_world_surface() -> int:
    return 1


# `Heightmap.Type` ids as they appear in a chunk packet. The other types the
# server may send - world surface and ocean floor before world generation -
# are walked but not stored.
public def hm_wire_world_surface() -> int64:
    return (int64)1


public def hm_wire_motion_blocking() -> int64:
    return (int64)4


public def hm_wire_kind_count() -> int64:
    return (int64)6


public def hm_bits() -> int:
    return 9


public def hm_value_mask() -> int64:
    return (int64)511


public def hm_long_count() -> int:
    return (hm_cells() * hm_bits() + 63) / 64


public def hm_values() -> int:
    return hm_cells() * hm_kind_count()


public def hm_kind_offset(kind: int) -> int:
    if kind < 0 or kind >= hm_kind_count():
        return -1
    return kind * hm_cells()


public def hm_new() -> int*:
    return vt_calloc_int(hm_values())


public def hm_free(values: int*) -> void:
    if values != null:
        vt_free((void*)values)


public def hm_index(kind: int, x: int, z: int) -> int:
    if x < 0 or x >= 16 or z < 0 or z >= 16:
        return -1
    int base = hm_kind_offset(kind)
    if base < 0:
        return -1
    return base + z * 16 + x


public def hm_set(values: int*, kind: int, x: int, z: int, height: int) -> int:
    int slot = hm_index(kind, x, z)
    if values == null or slot < 0:
        return 0
    vt_iset(values, slot, height)
    return 1


public def hm_get(values: int*, kind: int, x: int, z: int) -> int:
    int slot = hm_index(kind, x, z)
    if values == null or slot < 0:
        return -1
    return vt_iget(values, slot)


# Unpacks one kind's 36 longs into `cells` heights at `kind * 256`.
public def hm_unpack(longs: int64[], kind: int, values: int*) -> int:
    int base = hm_kind_offset(kind)
    if values == null or base < 0:
        return 0
    int i = 0
    while i < hm_cells():
        int bit = i * hm_bits()
        int word = bit / 64
        int shift = bit % 64
        int64 raw = longs[word] >> shift
        if shift > 64 - hm_bits():
            # The field continues in the next long. `>>` sign extends, so the
            # part held by this word has to be masked before the rest is
            # OR-ed in, or the extension overwrites the high field bits.
            int keep = 64 - shift
            raw = (raw & (((int64)1 << keep) - (int64)1)) | (longs[word + 1] << keep)
        vt_iset(values, base + i, (int)(raw & hm_value_mask()))
        i += 1
    return 1


# Packs one kind's heights back into longs; the inverse, used by the tests and
# by any future serverbound heightmap.
public def hm_pack(values: int*, kind: int, longs: int64[]) -> int:
    int base = hm_kind_offset(kind)
    if values == null or base < 0:
        return 0
    int i = 0
    while i < hm_long_count():
        longs[i] = (int64)0
        i += 1
    i = 0
    while i < hm_cells():
        int bit = i * hm_bits()
        int word = bit / 64
        int shift = bit % 64
        int64 value = (int64)vt_iget(values, base + i) & hm_value_mask()
        longs[word] = longs[word] | (value << shift)
        if shift > 64 - hm_bits():
            longs[word + 1] = longs[word + 1] | (value >> (64 - shift))
        i += 1
    return 1


# ===== world.cpy =====
# Vortex engine - bounded loaded-chunk store.


struct VWorld:
    int capacity
    int count
    int min_section
    int section_count
    int block_global_bits
    int biome_global_bits
    int dimension_id
    int* chunk_x
    int* chunk_z
    char* columns
    char* heightmaps


struct VDimensionRegistry:
    int capacity
    int dimension_count
    int dimension_registry_seen
    int biome_registry_seen
    int block_global_bits
    int biome_global_bits
    int* min_sections
    int* section_counts


public def vdimension_registry_new() -> VDimensionRegistry*:
    VDimensionRegistry* registry = new VDimensionRegistry
    registry.capacity = 256
    registry.dimension_count = 0
    registry.dimension_registry_seen = 0
    registry.biome_registry_seen = 0
    registry.block_global_bits = 15
    registry.biome_global_bits = 6
    registry.min_sections = vt_calloc_int(registry.capacity)
    registry.section_counts = vt_calloc_int(registry.capacity)
    return registry


public def vdimension_registry_free(registry: VDimensionRegistry*) -> void:
    if registry == null:
        return
    vt_free((void*)registry.min_sections)
    vt_free((void*)registry.section_counts)
    del registry


public def vdimension_registry_add_dimension(registry: VDimensionRegistry*,
                                             index: int, min_y: int,
                                             height: int) -> int:
    if registry == null or index < 0 or index >= registry.capacity:
        return 0
    if height < 16 or height > 4096 or height % 16 != 0 or min_y % 16 != 0:
        return 0
    vt_iset(registry.min_sections, index, min_y / 16)
    vt_iset(registry.section_counts, index, height / 16)
    if registry.dimension_count <= index:
        registry.dimension_count = index + 1
    return 1


public def vdimension_registry_finish_dimensions(registry: VDimensionRegistry*,
                                                  count: int) -> int:
    if registry == null or count < 0 or count > registry.capacity:
        return 0
    registry.dimension_count = count
    registry.dimension_registry_seen = 1
    return 1


public def vdimension_registry_dimension(registry: VDimensionRegistry*,
                                         index: int) -> int64[]:
    int64[] result = new int64[3]
    if registry == null or index < 0 or index >= registry.dimension_count:
        return result
    result[0] = vt_iget(registry.section_counts, index) > 0
    result[1] = vt_iget(registry.min_sections, index)
    result[2] = vt_iget(registry.section_counts, index)
    return result


public def vdimension_registry_set_biome_count(registry: VDimensionRegistry*,
                                                count: int) -> int:
    if registry == null or count < 1 or count > 1048576:
        return 0
    int bits = 0
    int capacity = 1
    while capacity < count:
        bits += 1
        capacity *= 2
    if bits < 1:
        bits = 1
    if bits > 32:
        return 0
    registry.biome_global_bits = bits
    registry.biome_registry_seen = 1
    return 1


def vworld_find(world: VWorld*, x: int, z: int) -> int:
    int i = 0
    while i < world.count:
        if vt_iget(world.chunk_x, i) == x and vt_iget(world.chunk_z, i) == z:
            return i
        i += 1
    return -1


def vworld_free_column(sections: char*, count: int) -> void:
    if sections == null:
        return
    int i = 0
    while i < count:
        sec_free((VSection*)vt_ptr_get(sections, i))
        i += 1
    vt_free((void*)sections)


public def vworld_new(capacity: int, min_section: int, section_count: int,
                      block_global_bits: int, biome_global_bits: int) -> VWorld*:
    if capacity < 1:
        capacity = 1
    if section_count < 1:
        section_count = 1
    VWorld* world = new VWorld
    world.capacity = capacity
    world.count = 0
    world.min_section = min_section
    world.section_count = section_count
    world.block_global_bits = block_global_bits
    world.biome_global_bits = biome_global_bits
    world.dimension_id = 0
    world.chunk_x = vt_calloc_int(capacity)
    world.chunk_z = vt_calloc_int(capacity)
    world.columns = vt_calloc_ptrs(capacity)
    world.heightmaps = vt_calloc_ptrs(capacity)
    return world


public def vworld_free(world: VWorld*) -> void:
    if world == null:
        return
    int i = 0
    while i < world.count:
        vworld_free_column((char*)vt_ptr_get(world.columns, i), world.section_count)
        hm_free((int*)vt_ptr_get(world.heightmaps, i))
        i += 1
    vt_free((void*)world.chunk_x)
    vt_free((void*)world.chunk_z)
    vt_free((void*)world.columns)
    vt_free((void*)world.heightmaps)
    del world


public def vworld_chunk_count(world: VWorld*) -> int:
    return world.count


# The dimension id the server named in Play login. Saving keeps one world
# folder per dimension, so chunks from two dimensions never share a region.
public def vworld_set_dimension_id(world: VWorld*, dimension_id: int) -> void:
    if world != null:
        world.dimension_id = dimension_id


public def vworld_dimension_id(world: VWorld*) -> int:
    if world == null:
        return 0
    return world.dimension_id


public def vworld_set_dimension(world: VWorld*, min_section: int,
                                section_count: int,
                                block_global_bits: int,
                                biome_global_bits: int) -> int:
    if world == null or world.count != 0 or section_count < 1 or section_count > 256:
        return 0
    if block_global_bits < 1 or block_global_bits > 32 or biome_global_bits < 1 or biome_global_bits > 32:
        return 0
    world.min_section = min_section
    world.section_count = section_count
    world.block_global_bits = block_global_bits
    world.biome_global_bits = biome_global_bits
    return 1


# The column slot for (x, z), inserting an empty one when the chunk is new and
# returning -1 once the store is full. A fresh slot has neither sections nor
# heightmaps, so either half of the chunk packet may arrive first.
def vworld_slot(world: VWorld*, x: int, z: int) -> int:
    int index = vworld_find(world, x, z)
    if index >= 0:
        return index
    if world.count >= world.capacity:
        return -1
    index = world.count
    world.count += 1
    vt_iset(world.chunk_x, index, x)
    vt_iset(world.chunk_z, index, z)
    return index


public def vworld_replace_sections(world: VWorld*, x: int, z: int,
                                   sections: char*) -> int:
    if world == null or sections == null:
        return 0
    int index = vworld_slot(world, x, z)
    if index < 0:
        return 0
    vworld_free_column((char*)vt_ptr_get(world.columns, index), world.section_count)
    vt_ptr_set(world.columns, index, (void*)sections)
    return 1


# Takes ownership of `values`, one packed heightmap column of `hm_values()`
# entries, and frees whatever the chunk held before.
public def vworld_set_heightmaps(world: VWorld*, x: int, z: int,
                                 values: int*) -> int:
    if world == null or values == null:
        return 0
    int index = vworld_slot(world, x, z)
    if index < 0:
        return 0
    hm_free((int*)vt_ptr_get(world.heightmaps, index))
    vt_ptr_set(world.heightmaps, index, (void*)values)
    return 1


public def vworld_unload_chunk(world: VWorld*, x: int, z: int) -> int:
    if world == null:
        return 0
    int index = vworld_find(world, x, z)
    if index < 0:
        return 0
    vworld_free_column((char*)vt_ptr_get(world.columns, index), world.section_count)
    hm_free((int*)vt_ptr_get(world.heightmaps, index))
    int i = index + 1
    while i < world.count:
        vt_iset(world.chunk_x, i - 1, vt_iget(world.chunk_x, i))
        vt_iset(world.chunk_z, i - 1, vt_iget(world.chunk_z, i))
        vt_ptr_set(world.columns, i - 1, vt_ptr_get(world.columns, i))
        vt_ptr_set(world.heightmaps, i - 1, vt_ptr_get(world.heightmaps, i))
        i += 1
    world.count -= 1
    vt_ptr_set(world.columns, world.count, null)
    vt_ptr_set(world.heightmaps, world.count, null)
    return 1


public def vworld_section(world: VWorld*, chunk_x: int, chunk_z: int,
                          section_y: int) -> VSection*:
    if world == null:
        return null
    int column_index = vworld_find(world, chunk_x, chunk_z)
    int section_index = section_y - world.min_section
    if column_index < 0 or section_index < 0 or section_index >= world.section_count:
        return null
    char* sections = (char*)vt_ptr_get(world.columns, column_index)
    if sections == null:
        return null
    return (VSection*)vt_ptr_get(sections, section_index)


public def vworld_block_at(world: VWorld*, x: int, y: int, z: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 0
    return sec_block_at(section, local_x, local_y, local_z)


public def vworld_biome_at(world: VWorld*, x: int, y: int, z: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 0
    return sec_biome_at(section, local_x / 4, local_y / 4, local_z / 4)


# The stored height for one world block column, or -1 while the chunk is not
# loaded or the server sent no heightmap of that kind. Heights are absolute
# world Y as packed on the wire, so a negative minimum build height does not
# shift them.
public def vworld_height_at(world: VWorld*, kind: int, x: int, z: int) -> int:
    if world == null:
        return -1
    int local_x = x % 16
    int chunk_x = x / 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int local_z = z % 16
    int chunk_z = z / 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int column_index = vworld_find(world, chunk_x, chunk_z)
    if column_index < 0:
        return -1
    int* values = (int*)vt_ptr_get(world.heightmaps, column_index)
    if values == null:
        return -1
    return hm_get(values, kind, local_x, local_z)


# Packed sky/block light: sky * 16 + block. An unloaded section reads as full
# sky, which keeps the mesh of a partially loaded world visible.
public def vworld_light_at(world: VWorld*, x: int, y: int, z: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 15 * 16
    return sec_sky_light_at(section, local_x, local_y, local_z) * 16 + sec_block_light_at(section, local_x, local_y, local_z)


# Writes one block. Returns 0 when the chunk or section is not loaded, so a
# block update for an unloaded chunk is a no-op rather than an error.
public def vworld_set_block_at(world: VWorld*, x: int, y: int, z: int,
                               state: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 0
    sec_block_set(section, local_x, local_y, local_z, state)
    return 1


# ===== entities.cpy =====
# Vortex engine - client-side entity registry.
#
# The Play stream refers to entities by id long before it describes them: a
# move packet can arrive for an entity the server never spawned in a way this
# client understands, and metadata updates only carry the fields that changed.
# This module is the accumulated answer to "what does the client currently
# believe about entity N", so handlers can merge partial packets instead of
# throwing them away.


struct VEntities:
    int capacity
    int mask
    int count
    int tombs
    int* ids
    int* type_ids
    int* flags
    int* angles
    uint64* positions
    uint64* motions
    uint64* values
    char* names


def ventity_angle_stride() -> int:
    return 3


def ventity_value_stride() -> int:
    return 16


def ventity_name_stride() -> int:
    return 64


# Flag bits shared with the handlers; a slot is live once the server has
# mentioned it at all, and on_ground is carried by most movement packets.
public def vent_flag_live() -> int:
    return 1


public def vent_flag_on_ground() -> int:
    return 2


public def vent_flag_removed() -> int:
    return 4


public def vent_flag_on_fire() -> int:
    return 8


public def vent_flag_sneaking() -> int:
    return 16


public def vent_flag_glowing() -> int:
    return 32


public def vent_flag_invisible() -> int:
    return 64


def ventities_empty_marker() -> int:
    return -1


def ventities_tomb_marker() -> int:
    return -2


def ventities_slot_in(ids: int*, mask: int, id: int) -> int:
    int slot = (int)(id * 2654435761) & mask
    while vt_iget(ids, slot) >= 0 and vt_iget(ids, slot) != id:
        slot = (slot + 1) & mask
    return slot


def ventities_free_arrays(table: VEntities*) -> void:
    vt_free((void*)table.ids)
    vt_free((void*)table.type_ids)
    vt_free((void*)table.flags)
    vt_free((void*)table.angles)
    vt_free((void*)table.positions)
    vt_free((void*)table.motions)
    vt_free((void*)table.values)
    vt_free((void*)table.names)


def ventities_blank(capacity: int) -> VEntities*:
    VEntities* fresh = new VEntities
    fresh.capacity = capacity
    fresh.mask = capacity - 1
    fresh.count = 0
    fresh.tombs = 0
    fresh.ids = vt_calloc_int(capacity)
    fresh.type_ids = vt_calloc_int(capacity)
    fresh.flags = vt_calloc_int(capacity)
    fresh.angles = vt_calloc_int(capacity * ventity_angle_stride())
    fresh.positions = vt_calloc_u64(capacity * 3)
    fresh.motions = vt_calloc_u64(capacity * 3)
    fresh.values = vt_calloc_u64(capacity * ventity_value_stride())
    fresh.names = vt_calloc_char(capacity * ventity_name_stride())
    int index = 0
    while index < capacity:
        vt_iset(fresh.ids, index, -1)
        index = index + 1
    return fresh


# Rebuild the table at `capacity`, dropping tombstones; only live ids move.
def ventities_rehome(table: VEntities*, capacity: int) -> void:
    VEntities* fresh = ventities_blank(capacity)
    int index = 0
    while index < table.capacity:
        int id = vt_iget(table.ids, index)
        if id >= 0:
            int target = ventities_slot_in(fresh.ids, fresh.mask, id)
            vt_iset(fresh.ids, target, id)
            vt_iset(fresh.type_ids, target, vt_iget(table.type_ids, index))
            vt_iset(fresh.flags, target, vt_iget(table.flags, index))
            int field = 0
            while field < ventity_angle_stride():
                vt_iset(fresh.angles, target * ventity_angle_stride() + field,
                        vt_iget(table.angles, index * ventity_angle_stride() + field))
                field = field + 1
            field = 0
            while field < 3:
                vt_uset(fresh.positions, target * 3 + field, vt_uget(table.positions, index * 3 + field))
                vt_uset(fresh.motions, target * 3 + field, vt_uget(table.motions, index * 3 + field))
                field = field + 1
            field = 0
            while field < ventity_value_stride():
                vt_uset(fresh.values, target * ventity_value_stride() + field,
                        vt_uget(table.values, index * ventity_value_stride() + field))
                field = field + 1
            field = 0
            while field < ventity_name_stride():
                vt_put(fresh.names, target * ventity_name_stride() + field,
                       vt_at(table.names, index * ventity_name_stride() + field))
                field = field + 1
            fresh.count = fresh.count + 1
        index = index + 1
    if table.capacity > 0:
        ventities_free_arrays(table)
    table.capacity = fresh.capacity
    table.mask = fresh.mask
    table.count = fresh.count
    table.tombs = 0
    table.ids = fresh.ids
    table.type_ids = fresh.type_ids
    table.flags = fresh.flags
    table.angles = fresh.angles
    table.positions = fresh.positions
    table.motions = fresh.motions
    table.values = fresh.values
    table.names = fresh.names
    del fresh


public def ventities_reserve(table: VEntities*, capacity: int) -> int:
    if table == null or capacity < 16 or capacity > 65536:
        return 0
    int wanted = 16
    while wanted < capacity:
        wanted = wanted * 2
    if table.capacity >= wanted:
        return 1
    ventities_rehome(table, wanted)
    return 1


public def ventities_new() -> VEntities*:
    VEntities* table = new VEntities
    table.capacity = 0
    table.mask = 0
    table.count = 0
    ventities_reserve(table, 1024)
    return table


public def ventities_free(table: VEntities*) -> void:
    if table == null:
        return
    ventities_free_arrays(table)
    table.capacity = 0
    table.mask = 0
    table.count = 0
    del table


public def ventities_find(table: VEntities*, id: int) -> int:
    if table == null or id < 0 or table.capacity == 0:
        return -1
    int slot = (int)(id * 2654435761) & table.mask
    int guard = 0
    while guard <= table.mask:
        int current = vt_iget(table.ids, slot)
        if current == id:
            return slot
        if current == ventities_empty_marker():
            return -1
        slot = (slot + 1) & table.mask
        guard = guard + 1
    return -1


# An absent id lands on the first free cell, or on the first tombstone seen so
# that removals do not turn inserts into permanent table growth.
def ventities_insert_slot(table: VEntities*, id: int) -> int:
    int slot = (int)(id * 2654435761) & table.mask
    int tomb = -1
    int guard = 0
    while guard <= table.mask:
        int current = vt_iget(table.ids, slot)
        if current == id:
            return slot
        if current == ventities_empty_marker():
            if tomb >= 0:
                return tomb
            return slot
        if current == ventities_tomb_marker() and tomb < 0:
            tomb = slot
        slot = (slot + 1) & table.mask
        guard = guard + 1
    return slot


def ventities_clear_slot(table: VEntities*, slot: int) -> void:
    vt_iset(table.type_ids, slot, -1)
    vt_iset(table.flags, slot, 0)
    int base = slot * ventity_angle_stride()
    int field = 0
    while field < ventity_angle_stride():
        vt_iset(table.angles, base + field, 0)
        field = field + 1
    base = slot * 3
    field = 0
    while field < 3:
        vt_uset(table.positions, base + field, 0)
        vt_uset(table.motions, base + field, 0)
        field = field + 1
    base = slot * ventity_value_stride()
    field = 0
    while field < ventity_value_stride():
        vt_uset(table.values, base + field, 0)
        field = field + 1
    base = slot * ventity_name_stride()
    field = 0
    while field < ventity_name_stride():
        vt_put(table.names, base + field, 0)
        field = field + 1


public def ventities_touch(table: VEntities*, id: int) -> int:
    if table == null or id < 0:
        return -1
    if table.count * 4 >= table.capacity * 3:
        if table.capacity >= 65536:
            return -1
        ventities_rehome(table, table.capacity * 2)
    elif table.tombs * 4 >= table.capacity * 3:
        ventities_rehome(table, table.capacity)
    int slot = ventities_insert_slot(table, id)
    int current = vt_iget(table.ids, slot)
    if current >= 0:
        return slot
    if current == ventities_tomb_marker():
        table.tombs = table.tombs - 1
    table.count = table.count + 1
    ventities_clear_slot(table, slot)
    vt_iset(table.flags, slot, vent_flag_live())
    vt_iset(table.ids, slot, id)
    return slot


# Removal leaves a tombstone: shifting the run behind the hole would have to
# move the whole payload alongside the id, and entities carry six arrays of it.
public def ventities_drop(table: VEntities*, id: int) -> int:
    int slot = ventities_find(table, id)
    if slot < 0:
        return 0
    vt_iset(table.ids, slot, ventities_tomb_marker())
    ventities_clear_slot(table, slot)
    table.count = table.count - 1
    table.tombs = table.tombs + 1
    return 1


public def ventities_type(table: VEntities*, id: int) -> int:
    int slot = ventities_find(table, id)
    if slot < 0:
        return -1
    return vt_iget(table.type_ids, slot)


public def ventities_set_type(table: VEntities*, id: int, type_id: int) -> int:
    if type_id < 0:
        return 0
    int slot = ventities_touch(table, id)
    if slot < 0:
        return 0
    vt_iset(table.type_ids, slot, type_id)
    return 1


public def ventities_flag(table: VEntities*, id: int, bit: int) -> int:
    int slot = ventities_find(table, id)
    if slot < 0:
        return 0
    if (vt_iget(table.flags, slot) & bit) == 0:
        return 0
    return 1


public def ventities_set_flag(table: VEntities*, id: int, bit: int, on: bool) -> int:
    int slot = ventities_find(table, id)
    if slot < 0:
        return 0
    int flags = vt_iget(table.flags, slot)
    if on:
        flags = flags | bit
    else:
        flags = flags & ~bit
    vt_iset(table.flags, slot, flags)
    return 1


public def ventities_set_position(table: VEntities*, id: int, x: double,
                                   y: double, z: double) -> int:
    int slot = ventities_touch(table, id)
    if slot < 0:
        return 0
    vt_uset(table.positions, slot * 3, vt_double_to_bits(x))
    vt_uset(table.positions, slot * 3 + 1, vt_double_to_bits(y))
    vt_uset(table.positions, slot * 3 + 2, vt_double_to_bits(z))
    return 1


public def ventities_position(table: VEntities*, id: int, axis: int) -> double:
    int slot = ventities_find(table, id)
    if slot < 0 or axis < 0 or axis > 2:
        return 0.0
    return vt_bits_to_double(vt_uget(table.positions, slot * 3 + axis))


public def ventities_move_by(table: VEntities*, id: int, dx: double,
                              dy: double, dz: double) -> int:
    int slot = ventities_find(table, id)
    if slot < 0:
        return 0
    int axis = 0
    while axis < 3:
        double delta = dx
        if axis == 1:
            delta = dy
        if axis == 2:
            delta = dz
        double current = vt_bits_to_double(vt_uget(table.positions, slot * 3 + axis))
        vt_uset(table.positions, slot * 3 + axis, vt_double_to_bits(current + delta))
        axis = axis + 1
    return 1


public def ventities_set_motion(table: VEntities*, id: int, dx: double,
                                 dy: double, dz: double) -> int:
    int slot = ventities_touch(table, id)
    if slot < 0:
        return 0
    vt_uset(table.motions, slot * 3, vt_double_to_bits(dx))
    vt_uset(table.motions, slot * 3 + 1, vt_double_to_bits(dy))
    vt_uset(table.motions, slot * 3 + 2, vt_double_to_bits(dz))
    return 1


public def ventities_motion(table: VEntities*, id: int, axis: int) -> double:
    int slot = ventities_find(table, id)
    if slot < 0 or axis < 0 or axis > 2:
        return 0.0
    return vt_bits_to_double(vt_uget(table.motions, slot * 3 + axis))


# Angles travel as unsigned bytes; 256 steps cover a full turn.
public def ventities_set_angle(table: VEntities*, id: int, which: int, raw: int) -> int:
    if table == null or id < 0 or which < 0 or which >= ventity_angle_stride():
        return 0
    int slot = ventities_touch(table, id)
    if slot < 0:
        return 0
    vt_iset(table.angles, slot * ventity_angle_stride() + which, raw & 0xFF)
    return 1


public def ventities_angle(table: VEntities*, id: int, which: int) -> double:
    int slot = ventities_find(table, id)
    if slot < 0 or which < 0 or which >= ventity_angle_stride():
        return 0.0
    int raw = vt_iget(table.angles, slot * ventity_angle_stride() + which)
    return (double)(raw * 360) / 256.0


public def ventities_set_value(table: VEntities*, id: int, index: int, value: int64) -> int:
    if table == null or id < 0 or index < 0 or index >= ventity_value_stride():
        return 0
    int slot = ventities_touch(table, id)
    if slot < 0:
        return 0
    vt_uset(table.values, slot * ventity_value_stride() + index, (uint64)value)
    return 1


public def ventities_value(table: VEntities*, id: int, index: int) -> int64:
    int slot = ventities_find(table, id)
    if slot < 0 or index < 0 or index >= ventity_value_stride():
        return 0
    return (int64)vt_uget(table.values, slot * ventity_value_stride() + index)


public def ventities_set_name(table: VEntities*, id: int,
                              bytes: int64[], length: int64) -> int:
    if table == null or id < 0 or length < 0 or length > len(bytes):
        return 0
    int slot = ventities_touch(table, id)
    if slot < 0:
        return 0
    int limit = ventity_name_stride() - 1
    if length > limit:
        length = limit
    int base = slot * ventity_name_stride()
    int index = 0
    while index < length:
        vt_put(table.names, base + index, (int)bytes[index])
        index = index + 1
    vt_put(table.names, base + index, 0)
    return 1


public def ventities_name_byte(table: VEntities*, id: int, index: int) -> int:
    int slot = ventities_find(table, id)
    if slot < 0 or index < 0:
        return 0
    return vt_at(table.names, slot * ventity_name_stride() + index)


public def ventities_name_length(table: VEntities*, id: int) -> int:
    int slot = ventities_find(table, id)
    if slot < 0:
        return 0
    int base = slot * ventity_name_stride()
    int index = 0
    while index < ventity_name_stride() and vt_at(table.names, base + index) != 0:
        index = index + 1
    return index



# ===== bossbars.cpy =====
# Vortex engine - boss status bars.
#
# Boss bars are keyed by the UUID the server invented for the bar, not by the
# entity that owns it, and updates arrive as separate style/health/options
# packets that patch one bar. There is never more than a handful on screen, so
# a linear scan over a small arena beats hashing sixteen-byte keys.


def vboss_capacity() -> int:
    return 32


def vboss_uuid_stride() -> int:
    return 16


def vboss_name_stride() -> int:
    return 64


# The five actions of the boss-event packet, kept here so the handler and the
# store agree on what a header byte means.
public def vboss_action_add() -> int:
    return 0


public def vboss_action_remove() -> int:
    return 1


public def vboss_action_update_style() -> int:
    return 2


public def vboss_action_update_properties() -> int:
    return 3


public def vboss_action_update_options() -> int:
    return 4


struct VBossBars:
    int count
    char* uuids
    char* names
    uint64* health
    int* color
    int* style
    int* flags


public def vboss_new() -> VBossBars*:
    VBossBars* bars = new VBossBars
    bars.count = 0
    bars.uuids = vt_calloc_char(vboss_capacity() * vboss_uuid_stride())
    bars.names = vt_calloc_char(vboss_capacity() * vboss_name_stride())
    bars.health = vt_calloc_u64(vboss_capacity())
    bars.color = vt_calloc_int(vboss_capacity())
    bars.style = vt_calloc_int(vboss_capacity())
    bars.flags = vt_calloc_int(vboss_capacity())
    return bars


public def vboss_free(bars: VBossBars*) -> void:
    if bars == null:
        return
    vt_free((void*)bars.uuids)
    vt_free((void*)bars.names)
    vt_free((void*)bars.health)
    vt_free((void*)bars.color)
    vt_free((void*)bars.style)
    vt_free((void*)bars.flags)
    del bars


def vboss_uuid_matches(bars: VBossBars*, slot: int, body: int64[],
                       offset: int64) -> int:
    int byte = 0
    while byte < vboss_uuid_stride():
        int stored = vt_at(bars.uuids, slot * vboss_uuid_stride() + byte)
        int wanted = (int)(body[offset + byte] & 0xFF)
        if stored != wanted:
            return 0
        byte = byte + 1
    return 1


public def vboss_find(bars: VBossBars*, body: int64[], offset: int64) -> int:
    if bars == null or offset + vboss_uuid_stride() > len(body):
        return -1
    int slot = 0
    while slot < bars.count:
        if vboss_uuid_matches(bars, slot, body, offset) == 1:
            return slot
        slot = slot + 1
    return -1


def vboss_slot(bars: VBossBars*, body: int64[], offset: int64) -> int:
    int slot = vboss_find(bars, body, offset)
    if slot >= 0:
        return slot
    if bars.count >= vboss_capacity():
        return -1
    slot = bars.count
    bars.count = bars.count + 1
    int byte = 0
    while byte < vboss_uuid_stride():
        vt_put(bars.uuids, slot * vboss_uuid_stride() + byte,
               (int)(body[offset + byte] & 0xFF))
        byte = byte + 1
    vt_put(bars.names, slot * vboss_name_stride(), 0)
    vt_uset(bars.health, slot, 0)
    vt_iset(bars.color, slot, 0)
    vt_iset(bars.style, slot, 0)
    vt_iset(bars.flags, slot, 0)
    return slot


public def vboss_remove(bars: VBossBars*, body: int64[], offset: int64) -> int:
    int slot = vboss_find(bars, body, offset)
    if slot < 0:
        return 0
    int last = bars.count - 1
    while slot < last:
        int byte = 0
        while byte < vboss_uuid_stride():
            vt_put(bars.uuids, slot * vboss_uuid_stride() + byte,
                   vt_at(bars.uuids, (slot + 1) * vboss_uuid_stride() + byte))
            byte = byte + 1
        byte = 0
        while byte < vboss_name_stride():
            vt_put(bars.names, slot * vboss_name_stride() + byte,
                   vt_at(bars.names, (slot + 1) * vboss_name_stride() + byte))
            byte = byte + 1
        vt_uset(bars.health, slot, vt_uget(bars.health, slot + 1))
        vt_iset(bars.color, slot, vt_iget(bars.color, slot + 1))
        vt_iset(bars.style, slot, vt_iget(bars.style, slot + 1))
        vt_iset(bars.flags, slot, vt_iget(bars.flags, slot + 1))
        slot = slot + 1
    bars.count = last
    return 1


public def vboss_set_health(bars: VBossBars*, body: int64[], offset: int64,
                            health: double) -> int:
    int slot = vboss_slot(bars, body, offset)
    if slot < 0:
        return 0
    vt_uset(bars.health, slot, vt_double_to_bits(health))
    return 1


public def vboss_set_appearance(bars: VBossBars*, body: int64[], offset: int64,
                                 color: int, style: int) -> int:
    int slot = vboss_slot(bars, body, offset)
    if slot < 0:
        return 0
    vt_iset(bars.color, slot, color)
    vt_iset(bars.style, slot, style)
    return 1


public def vboss_set_flags(bars: VBossBars*, body: int64[], offset: int64,
                           flags: int) -> int:
    int slot = vboss_slot(bars, body, offset)
    if slot < 0:
        return 0
    vt_iset(bars.flags, slot, flags)
    return 1


public def vboss_set_name(bars: VBossBars*, body: int64[], offset: int64,
                          text: int64[], length: int64) -> int:
    int slot = vboss_slot(bars, body, offset)
    if slot < 0:
        return 0
    int limit = vboss_name_stride() - 1
    if length > limit:
        length = limit
    int base = slot * vboss_name_stride()
    int index = 0
    while index < length:
        vt_put(bars.names, base + index, (int)(text[index] & 0xFF))
        index = index + 1
    vt_put(bars.names, base + index, 0)
    return 1


public def vboss_health(bars: VBossBars*, body: int64[], offset: int64) -> double:
    int slot = vboss_find(bars, body, offset)
    if slot < 0:
        return -1.0
    return vt_bits_to_double(vt_uget(bars.health, slot))


public def vboss_color(bars: VBossBars*, body: int64[], offset: int64) -> int:
    int slot = vboss_find(bars, body, offset)
    if slot < 0:
        return -1
    return vt_iget(bars.color, slot)


public def vboss_style(bars: VBossBars*, body: int64[], offset: int64) -> int:
    int slot = vboss_find(bars, body, offset)
    if slot < 0:
        return -1
    return vt_iget(bars.style, slot)


public def vboss_flags(bars: VBossBars*, body: int64[], offset: int64) -> int:
    int slot = vboss_find(bars, body, offset)
    if slot < 0:
        return -1
    return vt_iget(bars.flags, slot)


public def vboss_name_length(bars: VBossBars*, body: int64[], offset: int64) -> int:
    int slot = vboss_find(bars, body, offset)
    if slot < 0:
        return 0
    int base = slot * vboss_name_stride()
    int index = 0
    while index < vboss_name_stride() and vt_at(bars.names, base + index) != 0:
        index = index + 1
    return index


public def vboss_name_byte(bars: VBossBars*, body: int64[], offset: int64,
                           index: int) -> int:
    int slot = vboss_find(bars, body, offset)
    if slot < 0 or index < 0:
        return 0
    return vt_at(bars.names, slot * vboss_name_stride() + index)


# ===== scoreboard.cpy =====
# Vortex engine - scoreboard: objectives, scores, display slots and teams.
#
# Five packets patch one shared model and each of them can name an entry that
# has not been created yet, so the store keys everything by the text id the
# server uses and tolerates out-of-order arrival. Ids are fixed 32-byte
# NUL-terminated slots in one arena: the wire guarantees a non-empty string, a
# flat arena keeps the module free of per-entry allocations, and a truncated id
# simply cannot collide with a real one.


def vscore_id_stride() -> int:
    return 32


def vscore_text_stride() -> int:
    return 64


public def vscore_objective_capacity() -> int:
    return 64


public def vscore_entry_capacity() -> int:
    return 4096


public def vscore_display_slots() -> int:
    return 20


public def vscore_team_capacity() -> int:
    return 64


public def vscore_team_members() -> int:
    return 16


public def vscore_absent() -> int:
    return -1


# The objective packet actions.
public def vscore_action_create() -> int:
    return 0


public def vscore_action_remove() -> int:
    return 1


public def vscore_action_change() -> int:
    return 2


# The score packet actions.
public def vscore_score_change() -> int:
    return 0


public def vscore_score_remove() -> int:
    return 1


# The team packet modes. These are a different numbering from the objective
# actions even though both ride on a leading byte, so they get their own names.
public def vscore_team_create() -> int:
    return 0


public def vscore_team_remove() -> int:
    return 1


public def vscore_team_update() -> int:
    return 2


public def vscore_team_add_members() -> int:
    return 3


public def vscore_team_remove_members() -> int:
    return 4


struct VScoreboard:
    int objective_count
    char* objective_ids
    char* objective_display
    int* objective_present
    int score_count
    char* score_holders
    char* score_objectives
    int* score_values
    int* score_present
    int* display_slot
    int team_count
    char* team_ids
    char* team_display
    char* team_prefix
    char* team_suffix
    int* team_options
    int* team_nametag
    int* team_collision
    int* team_chat
    int* team_present
    int* team_member_count
    char* team_members


public def vscore_new() -> VScoreboard*:
    VScoreboard* board = new VScoreboard
    board.objective_count = 0
    board.objective_ids = vt_calloc_char(vscore_objective_capacity() * vscore_id_stride())
    board.objective_display = vt_calloc_char(vscore_objective_capacity() * vscore_text_stride())
    board.objective_present = vt_calloc_int(vscore_objective_capacity())
    board.score_count = 0
    board.score_holders = vt_calloc_char(vscore_entry_capacity() * vscore_id_stride())
    board.score_objectives = vt_calloc_char(vscore_entry_capacity() * vscore_id_stride())
    board.score_values = vt_calloc_int(vscore_entry_capacity())
    board.score_present = vt_calloc_int(vscore_entry_capacity())
    board.display_slot = vt_calloc_int(vscore_display_slots())
    int slot = 0
    while slot < vscore_display_slots():
        vt_iset(board.display_slot, slot, vscore_absent())
        slot = slot + 1
    board.team_count = 0
    board.team_ids = vt_calloc_char(vscore_team_capacity() * vscore_id_stride())
    board.team_display = vt_calloc_char(vscore_team_capacity() * vscore_text_stride())
    board.team_prefix = vt_calloc_char(vscore_team_capacity() * vscore_text_stride())
    board.team_suffix = vt_calloc_char(vscore_team_capacity() * vscore_text_stride())
    board.team_options = vt_calloc_int(vscore_team_capacity())
    board.team_nametag = vt_calloc_int(vscore_team_capacity())
    board.team_collision = vt_calloc_int(vscore_team_capacity())
    board.team_chat = vt_calloc_int(vscore_team_capacity())
    board.team_present = vt_calloc_int(vscore_team_capacity())
    board.team_member_count = vt_calloc_int(vscore_team_capacity())
    board.team_members = vt_calloc_char(vscore_team_capacity() * vscore_team_members() * vscore_id_stride())
    return board


public def vscore_free(board: VScoreboard*) -> void:
    if board == null:
        return
    vt_free((void*)board.objective_ids)
    vt_free((void*)board.objective_display)
    vt_free((void*)board.objective_present)
    vt_free((void*)board.score_holders)
    vt_free((void*)board.score_objectives)
    vt_free((void*)board.score_values)
    vt_free((void*)board.score_present)
    vt_free((void*)board.display_slot)
    vt_free((void*)board.team_ids)
    vt_free((void*)board.team_display)
    vt_free((void*)board.team_prefix)
    vt_free((void*)board.team_suffix)
    vt_free((void*)board.team_options)
    vt_free((void*)board.team_nametag)
    vt_free((void*)board.team_collision)
    vt_free((void*)board.team_chat)
    vt_free((void*)board.team_present)
    vt_free((void*)board.team_member_count)
    vt_free((void*)board.team_members)
    del board


# A body slice is [offset, offset+length) of the packet; the id it holds is the
# NUL-terminated bytes in an arena slot. Copying truncates at the stride, and
# comparing requires the stored terminator, so an over-long id never matches.
def vscore_write_id(arena: char*, base: int, body: int64[], offset: int64,
                    length: int64) -> void:
    int64 limit = vscore_id_stride() - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


def vscore_arena_length(arena: char*, base: int, stride: int) -> int:
    int index = 0
    while index < stride and vt_at(arena, base + index) != 0:
        index = index + 1
    return index


def vscore_write_text(arena: char*, base: int, body: int64[], offset: int64,
                      length: int64) -> void:
    int64 limit = vscore_text_stride() - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


def vscore_id_at(arena: char*, base: int, body: int64[], offset: int64,
                 length: int64) -> int:
    int64 limit = vscore_id_stride() - 1
    if length > limit:
        length = limit
    if length < 1:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


# --- objectives ---

def vscore_clear_score(board: VScoreboard*, index: int) -> void:
    vt_iset(board.score_present, index, 0)
    vt_iset(board.score_values, index, 0)
    vt_put(board.score_holders, index * vscore_id_stride(), 0)
    vt_put(board.score_objectives, index * vscore_id_stride(), 0)
    board.score_count = board.score_count - 1


public def vscore_find_objective(board: VScoreboard*, body: int64[],
                                 offset: int64, length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = 0
    while slot < vscore_objective_capacity():
        int present = vt_iget(board.objective_present, slot)
        int same = vscore_id_at(board.objective_ids, slot * vscore_id_stride(),
                                body, offset, length)
        if present == 1 and same == 1:
            return slot
        slot = slot + 1
    return vscore_absent()


# An objective that is referenced before it is announced still needs a place to
# park scores, so lookups that write create the slot.
def vscore_objective_slot(board: VScoreboard*, body: int64[], offset: int64,
                          length: int64) -> int:
    int slot = vscore_find_objective(board, body, offset, length)
    if slot >= 0:
        return slot
    int free = 0
    while free < vscore_objective_capacity():
        if vt_iget(board.objective_present, free) == 0:
            vt_iset(board.objective_present, free, 1)
            vscore_write_id(board.objective_ids, free * vscore_id_stride(),
                            body, offset, length)
            vt_put(board.objective_display, free * vscore_text_stride(), 0)
            board.objective_count = board.objective_count + 1
            return free
        free = free + 1
    return vscore_absent()


public def vscore_clear_objective(board: VScoreboard*, slot: int) -> void:
    if board == null or slot < 0:
        return
    vt_iset(board.objective_present, slot, 0)
    vt_put(board.objective_ids, slot * vscore_id_stride(), 0)
    vt_put(board.objective_display, slot * vscore_text_stride(), 0)
    board.objective_count = board.objective_count - 1


# Removing an objective takes its scores with it, because a score row is keyed
# by (holder, objective) and a dangling objective name would keep matching the
# next objective that lands on the same holder.
def vscore_drop_objective_scores(board: VScoreboard*, objective: int,
                                 body: int64[], offset: int64,
                                 length: int64) -> void:
    int index = 0
    while index < vscore_entry_capacity():
        int present = vt_iget(board.score_present, index)
        int same = vscore_id_at(board.score_objectives,
                                index * vscore_id_stride(), body, offset, length)
        if present == 1 and same == 1:
            vscore_clear_score(board, index)
        index = index + 1


public def vscore_set_objective(board: VScoreboard*, body: int64[], offset: int64,
                                length: int64, action: int, display: int64[],
                                display_at: int64, display_length: int64) -> int:
    if board == null or length < 1:
        return 0
    if action == vscore_action_remove():
        int existing = vscore_find_objective(board, body, offset, length)
        if existing < 0:
            return 1
        vscore_clear_objective(board, existing)
        vscore_drop_objective_scores(board, existing, body, offset, length)
        return 1
    int slot = vscore_objective_slot(board, body, offset, length)
    if slot < 0:
        return 0
    if display_length >= 0:
        vscore_write_text(board.objective_display, slot * vscore_text_stride(),
                          display, display_at, display_length)
    return 1


public def vscore_objective_exists(board: VScoreboard*, body: int64[],
                                   offset: int64, length: int64) -> int:
    if vscore_find_objective(board, body, offset, length) < 0:
        return 0
    return 1


public def vscore_objective_name_byte(board: VScoreboard*, slot: int,
                                      index: int) -> int:
    if board == null or slot < 0 or index < 0:
        return 0
    return vt_at(board.objective_ids, slot * vscore_id_stride() + index)


public def vscore_objective_display_byte(board: VScoreboard*, slot: int,
                                         index: int) -> int:
    if board == null or slot < 0 or index < 0:
        return 0
    return vt_at(board.objective_display, slot * vscore_text_stride() + index)


public def vscore_objective_display_length(board: VScoreboard*, slot: int) -> int:
    if board == null or slot < 0:
        return 0
    return vscore_arena_length(board.objective_display, slot * vscore_text_stride(),
                               vscore_text_stride())


# --- scores ---

# A score row is addressed by the two ids the packet spells out, so the lookup
# takes the body twice rather than a resolved slot: the objective may not exist
# yet and creating it here would invent objectives from stray score updates.
def vscore_find_score(board: VScoreboard*, holder: int64[], holder_at: int64,
                      holder_length: int64, objective: int64[],
                      objective_at: int64, objective_length: int64) -> int:
    if board == null:
        return vscore_absent()
    int index = 0
    while index < vscore_entry_capacity():
        int present = vt_iget(board.score_present, index)
        int same_holder = vscore_id_at(board.score_holders,
                                       index * vscore_id_stride(),
                                       holder, holder_at, holder_length)
        int same_objective = vscore_id_at(board.score_objectives,
                                          index * vscore_id_stride(),
                                          objective, objective_at, objective_length)
        if present == 1 and same_holder == 1 and same_objective == 1:
            return index
        index = index + 1
    return vscore_absent()


def vscore_score_slot(board: VScoreboard*, holder: int64[], holder_at: int64,
                      holder_length: int64, objective: int64[],
                      objective_at: int64, objective_length: int64) -> int:
    int existing = vscore_find_score(board, holder, holder_at, holder_length,
                                     objective, objective_at, objective_length)
    if existing >= 0:
        return existing
    int index = 0
    while index < vscore_entry_capacity():
        if vt_iget(board.score_present, index) == 0:
            vt_iset(board.score_present, index, 1)
            vscore_write_id(board.score_holders, index * vscore_id_stride(),
                            holder, holder_at, holder_length)
            vscore_write_id(board.score_objectives, index * vscore_id_stride(),
                            objective, objective_at, objective_length)
            vt_iset(board.score_values, index, 0)
            board.score_count = board.score_count + 1
            return index
        index = index + 1
    return vscore_absent()


public def vscore_set_score(board: VScoreboard*, holder: int64[], holder_at: int64,
                            holder_length: int64, objective: int64[],
                            objective_at: int64, objective_length: int64,
                            value: int) -> int:
    if board == null or holder_length < 1 or objective_length < 1:
        return 0
    int slot = vscore_score_slot(board, holder, holder_at, holder_length,
                                 objective, objective_at, objective_length)
    if slot < 0:
        return 0
    vt_iset(board.score_values, slot, value)
    return 1


public def vscore_reset_score(board: VScoreboard*, holder: int64[],
                              holder_at: int64, holder_length: int64,
                              objective: int64[], objective_at: int64,
                              objective_length: int64) -> int:
    if board == null:
        return 0
    int slot = vscore_find_score(board, holder, holder_at, holder_length,
                                 objective, objective_at, objective_length)
    if slot < 0:
        return 1
    vscore_clear_score(board, slot)
    return 1


# vscore_score_absent is what a missing row reports: 0 is a legal score, so the
# reader needs a value the wire can never send.
public def vscore_score_absent() -> int:
    return -2147483648


public def vscore_get_score(board: VScoreboard*, holder: int64[], holder_at: int64,
                            holder_length: int64, objective: int64[],
                            objective_at: int64, objective_length: int64) -> int:
    int slot = vscore_find_score(board, holder, holder_at, holder_length,
                                 objective, objective_at, objective_length)
    if slot < 0:
        return vscore_score_absent()
    return vt_iget(board.score_values, slot)


# --- display slots ---

# An empty name clears the slot; a name that has not been announced still owns
# one, because servers send display_objective before the objective itself.
public def vscore_set_display(board: VScoreboard*, slot: int, body: int64[],
                              offset: int64, length: int64) -> int:
    if board == null or slot < 0 or slot >= vscore_display_slots():
        return 0
    if length < 1:
        vt_iset(board.display_slot, slot, vscore_absent())
        return 1
    int objective = vscore_objective_slot(board, body, offset, length)
    if objective < 0:
        return 0
    vt_iset(board.display_slot, slot, objective)
    return 1


public def vscore_display_objective(board: VScoreboard*, slot: int) -> int:
    if board == null or slot < 0 or slot >= vscore_display_slots():
        return vscore_absent()
    return vt_iget(board.display_slot, slot)


public def vscore_display_objective_byte(board: VScoreboard*, slot: int,
                                         index: int) -> int:
    int objective = vscore_display_objective(board, slot)
    if objective < 0 or index < 0:
        return 0
    return vt_at(board.objective_ids, objective * vscore_id_stride() + index)


# --- teams ---

def vscore_find_team(board: VScoreboard*, body: int64[], offset: int64,
                     length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = 0
    while slot < vscore_team_capacity():
        int present = vt_iget(board.team_present, slot)
        int same = vscore_id_at(board.team_ids, slot * vscore_id_stride(),
                                body, offset, length)
        if present == 1 and same == 1:
            return slot
        slot = slot + 1
    return vscore_absent()


def vscore_create_team(board: VScoreboard*, body: int64[], offset: int64,
                       length: int64) -> int:
    int slot = 0
    while slot < vscore_team_capacity():
        if vt_iget(board.team_present, slot) == 0:
            vt_iset(board.team_present, slot, 1)
            vscore_write_id(board.team_ids, slot * vscore_id_stride(),
                            body, offset, length)
            vt_put(board.team_display, slot * vscore_text_stride(), 0)
            vt_put(board.team_prefix, slot * vscore_text_stride(), 0)
            vt_put(board.team_suffix, slot * vscore_text_stride(), 0)
            vt_iset(board.team_options, slot, 0)
            vt_iset(board.team_nametag, slot, 0)
            vt_iset(board.team_collision, slot, 0)
            vt_iset(board.team_chat, slot, 0)
            vt_iset(board.team_member_count, slot, 0)
            board.team_count = board.team_count + 1
            return slot
        slot = slot + 1
    return vscore_absent()


def vscore_clear_team(board: VScoreboard*, slot: int) -> void:
    vt_iset(board.team_present, slot, 0)
    vt_put(board.team_ids, slot * vscore_id_stride(), 0)
    vt_put(board.team_display, slot * vscore_text_stride(), 0)
    vt_put(board.team_prefix, slot * vscore_text_stride(), 0)
    vt_put(board.team_suffix, slot * vscore_text_stride(), 0)
    vt_iset(board.team_options, slot, 0)
    vt_iset(board.team_member_count, slot, 0)
    int index = 0
    int base = slot * vscore_team_members() * vscore_id_stride()
    while index < vscore_team_members() * vscore_id_stride():
        vt_put(board.team_members, base + index, 0)
        index = index + 1
    board.team_count = board.team_count - 1


def vscore_team_member_base(slot: int) -> int:
    return slot * vscore_team_members() * vscore_id_stride()


# Members live in a fixed 16-row block per team. The packet sends them as
# separate strings, so the handler passes the body plus each string's offset.
public def vscore_team_member_at(board: VScoreboard*, slot: int,
                                 index: int) -> int64:
    if board == null or slot < 0 or index < 0:
        return vscore_absent()
    if index >= vt_iget(board.team_member_count, slot):
        return vscore_absent()
    return vscore_arena_length(board.team_members,
                               vscore_team_member_base(slot) + index * vscore_id_stride(),
                               vscore_id_stride())


def vscore_team_member_matches(board: VScoreboard*, slot: int, row: int,
                               body: int64[], offset: int64,
                               length: int64) -> int:
    int base = vscore_team_member_base(slot) + row * vscore_id_stride()
    return vscore_id_at(board.team_members, base, body, offset, length)


# Adding a member already in the team is a no-op: servers re-send the whole
# create payload when a player reconnects, and a duplicate row would make the
# member list grow without bound across a long session.
public def vscore_team_add_member(board: VScoreboard*, slot: int, body: int64[],
                                  offset: int64, length: int64) -> int:
    if board == null or slot < 0 or length < 1:
        return 0
    int count = vt_iget(board.team_member_count, slot)
    int index = 0
    while index < count:
        if vscore_team_member_matches(board, slot, index, body, offset, length) == 1:
            return 1
        index = index + 1
    if count >= vscore_team_members():
        return 0
    vscore_write_id(board.team_members,
                    vscore_team_member_base(slot) + count * vscore_id_stride(),
                    body, offset, length)
    vt_iset(board.team_member_count, slot, count + 1)
    return 1


def vscore_team_shift_members(board: VScoreboard*, slot: int, from: int) -> void:
    int limit = vscore_team_members() - 1
    int index = from * vscore_id_stride()
    int stop = limit * vscore_id_stride()
    int base = vscore_team_member_base(slot)
    while index < stop:
        vt_put(board.team_members, base + index,
               vt_at(board.team_members, base + index + vscore_id_stride()))
        index = index + 1
    vt_put(board.team_members, base + stop, 0)


public def vscore_team_remove_member(board: VScoreboard*, slot: int,
                                     body: int64[], offset: int64,
                                     length: int64) -> int:
    if board == null or slot < 0 or length < 1:
        return 0
    int count = vt_iget(board.team_member_count, slot)
    int index = 0
    while index < count:
        if vscore_team_member_matches(board, slot, index, body, offset, length) == 1:
            vscore_team_shift_members(board, slot, index)
            vt_iset(board.team_member_count, slot, count - 1)
            return 1
        index = index + 1
    return 0


public def vscore_find_team_of(board: VScoreboard*, body: int64[], offset: int64,
                               length: int64) -> int:
    if board == null or length < 1:
        return vscore_absent()
    int slot = 0
    while slot < vscore_team_capacity():
        if vt_iget(board.team_present, slot) == 1:
            int count = vt_iget(board.team_member_count, slot)
            int index = 0
            while index < count:
                int base = vscore_team_member_base(slot) + index * vscore_id_stride()
                if vscore_id_at(board.team_members, base, body, offset, length) == 1:
                    return slot
                index = index + 1
        slot = slot + 1
    return vscore_absent()


# display/prefix/suffix arrive as chat components, which the handler has already
# flattened to text; a negative length means the packet did not carry the field.
public def vscore_set_team(board: VScoreboard*, body: int64[], offset: int64,
                           length: int64, mode: int, display: int64[],
                           display_at: int64, display_length: int64,
                           prefix: int64[], prefix_at: int64, prefix_length: int64,
                           suffix: int64[], suffix_at: int64,
                           suffix_length: int64) -> int:
    if board == null or length < 1:
        return 0
    if mode == vscore_team_remove():
        int gone = vscore_find_team(board, body, offset, length)
        if gone < 0:
            return 1
        vscore_clear_team(board, gone)
        return 1
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        if mode != vscore_team_create():
            return 0
        slot = vscore_create_team(board, body, offset, length)
    if slot < 0:
        return 0
    if display_length >= 0:
        vscore_write_text(board.team_display, slot * vscore_text_stride(),
                          display, display_at, display_length)
    if prefix_length >= 0:
        vscore_write_text(board.team_prefix, slot * vscore_text_stride(),
                          prefix, prefix_at, prefix_length)
    if suffix_length >= 0:
        vscore_write_text(board.team_suffix, slot * vscore_text_stride(),
                          suffix, suffix_at, suffix_length)
    return 1


# The option byte packs name-tag visibility in bits 0-1, collision in 2-3 and
# chat visibility in 4-5; keeping them split means callers never re-derive the
# masks and the values survive a re-send that omits a field.
public def vscore_team_index(board: VScoreboard*, body: int64[], offset: int64,
                             length: int64) -> int:
    return vscore_find_team(board, body, offset, length)


public def vscore_set_team_options(board: VScoreboard*, body: int64[],
                                  offset: int64, length: int64,
                                  nametag: int, collision: int,
                                  chat: int) -> int:
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return 0
    int options = (nametag & 3) | ((collision & 3) << 2) | ((chat & 3) << 4)
    vt_iset(board.team_options, slot, options)
    vt_iset(board.team_nametag, slot, options & 3)
    vt_iset(board.team_collision, slot, (options >> 2) & 3)
    vt_iset(board.team_chat, slot, (options >> 4) & 3)
    return 1


public def vscore_team_exists(board: VScoreboard*, body: int64[], offset: int64,
                              length: int64) -> int:
    if vscore_find_team(board, body, offset, length) < 0:
        return 0
    return 1


public def vscore_team_byte(arena: char*, slot: int, stride: int,
                            index: int) -> int:
    if slot < 0 or index < 0:
        return 0
    return vt_at(arena, slot * stride + index)


public def vscore_team_name_byte(board: VScoreboard*, body: int64[], offset: int64,
                                 length: int64, index: int) -> int:
    return vscore_team_byte(board.team_ids, vscore_find_team(board, body, offset, length),
                            vscore_id_stride(), index)


public def vscore_team_display_byte(board: VScoreboard*, body: int64[],
                                    offset: int64, length: int64,
                                    index: int) -> int:
    return vscore_team_byte(board.team_display, vscore_find_team(board, body, offset, length),
                            vscore_text_stride(), index)


public def vscore_team_prefix_byte(board: VScoreboard*, body: int64[],
                                   offset: int64, length: int64,
                                   index: int) -> int:
    return vscore_team_byte(board.team_prefix, vscore_find_team(board, body, offset, length),
                            vscore_text_stride(), index)


public def vscore_team_suffix_byte(board: VScoreboard*, body: int64[],
                                   offset: int64, length: int64,
                                   index: int) -> int:
    return vscore_team_byte(board.team_suffix, vscore_find_team(board, body, offset, length),
                            vscore_text_stride(), index)


public def vscore_team_options(board: VScoreboard*, body: int64[], offset: int64,
                               length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return vscore_absent()
    return vt_iget(board.team_options, slot)


public def vscore_team_nametag(board: VScoreboard*, body: int64[], offset: int64,
                               length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return vscore_absent()
    return vt_iget(board.team_nametag, slot)


public def vscore_team_collision(board: VScoreboard*, body: int64[], offset: int64,
                                 length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return vscore_absent()
    return vt_iget(board.team_collision, slot)


public def vscore_team_chat(board: VScoreboard*, body: int64[], offset: int64,
                            length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return vscore_absent()
    return vt_iget(board.team_chat, slot)


public def vscore_team_member_count(board: VScoreboard*, body: int64[],
                                    offset: int64, length: int64) -> int:
    if board == null:
        return 0
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return 0
    return vt_iget(board.team_member_count, slot)


public def vscore_team_objective_capacity() -> int:
    return vscore_objective_capacity()


public def vscore_active_objective_count(board: VScoreboard*) -> int:
    if board == null:
        return 0
    return board.objective_count


public def vscore_active_team_count(board: VScoreboard*) -> int:
    if board == null:
        return 0
    return board.team_count


public def vscore_active_score_count(board: VScoreboard*) -> int:
    if board == null:
        return 0
    return board.score_count


# ===== commands.cpy =====
# Vortex engine - the Brigadier command tree the server sends in `commands`.
#
# The tree arrives as one packet describing every node the server knows about,
# so the client has to walk it in a single pass and cannot ask for the rest
# later. It is stored flat: node metadata in parallel arrays, the child edges of
# every node appended to one shared list, and the strings a node can carry in
# fixed stride arenas. Nothing is allocated per node, which keeps a re-send on
# the configuration path cheap and keeps completion lookups in one array walk.
#
# Field readers return [next, value] slices rather than writing through
# out-parameters of locals: Cpyte keeps an address-taken local in a register, so
# a value produced by a callee reads back stale in the very next expression.
#
# Layout this client parses, per protocol 777:
#
#   node_count            VarInt
#   for each node:
#     flags               Byte   bits 0-1 type (0 root, 1 literal, 2 argument),
#                                0x04 executable, 0x08 redirect follows,
#                                0x10 suggestion provider follows
#     child_count         VarInt
#     children            VarInt[child_count]
#     name                String          when the type is not root
#     parser              String          when the type is argument
#     parser properties                   parser dependent, see vcmd_skip_parser
#     redirect            VarInt          when flags & 0x08
#     suggestions         String          when flags & 0x10
#   chain_limit           Byte
#
# A parse that does not land exactly on the end of the body means the assumed
# layout and the server disagree; that is reported as malformed rather than
# half-stored, because a tree with a desynchronised tail completes commands with
# the wrong argument names.


def vcmd_name_stride() -> int:
    return 32


def vcmd_parser_stride() -> int:
    return 48


# Custom chat completions are server-pushed argument suggestions that live
# beside the tree rather than inside it: they have no node and no parser.
public def vcmd_completion_capacity() -> int:
    return 1024


public def vcmd_completion_stride() -> int:
    return 64


public def vcmd_suggestion_capacity() -> int:
    return 1024


public def vcmd_suggestion_stride() -> int:
    return 512


public def vcmd_root() -> int:
    return 0


public def vcmd_absent() -> int:
    return -1


# Vanilla servers send a few hundred nodes; a modded server with a content pack
# can push past a thousand. Anything above capacity is refused rather than
# written past the arenas.
public def vcmd_node_capacity() -> int:
    return 4096


public def vcmd_edge_capacity() -> int:
    return 16384


public def vcmd_type_root() -> int:
    return 0


public def vcmd_type_literal() -> int:
    return 1


public def vcmd_type_argument() -> int:
    return 2


public def vcmd_parser_none() -> int:
    return 0


public def vcmd_parser_byte() -> int:
    return 1


public def vcmd_parser_string() -> int:
    return 2


public def vcmd_parser_varint_bounds() -> int:
    return 3


public def vcmd_parser_fixed_bounds() -> int:
    return 4


struct VCommandTree:
    int node_count
    int edge_count
    int chain_limit
    int truncated
    int completion_count
    char* completions
    int suggestion_id
    int suggestion_start
    int suggestion_length
    int suggestion_count
    char* suggestions
    int* node_flags
    int* node_child_start
    int* node_child_count
    int* node_redirect
    int* edges
    char* node_names
    char* node_parsers


public def vcmd_new() -> VCommandTree*:
    VCommandTree* tree = new VCommandTree
    tree.node_count = 0
    tree.edge_count = 0
    tree.chain_limit = 0
    tree.truncated = 0
    tree.node_flags = vt_calloc_int(vcmd_node_capacity())
    tree.node_child_start = vt_calloc_int(vcmd_node_capacity())
    tree.node_child_count = vt_calloc_int(vcmd_node_capacity())
    tree.node_redirect = vt_calloc_int(vcmd_node_capacity())
    int index = 0
    while index < vcmd_node_capacity():
        vt_iset(tree.node_redirect, index, vcmd_absent())
        index = index + 1
    tree.edges = vt_calloc_int(vcmd_edge_capacity())
    tree.node_names = vt_calloc_char(vcmd_node_capacity() * vcmd_name_stride())
    tree.node_parsers = vt_calloc_char(vcmd_node_capacity() * vcmd_parser_stride())
    tree.completion_count = 0
    tree.completions = vt_calloc_char(vcmd_completion_capacity() * vcmd_completion_stride())
    tree.suggestion_id = 0
    tree.suggestion_start = 0
    tree.suggestion_length = 0
    tree.suggestion_count = 0
    tree.suggestions = vt_calloc_char(vcmd_suggestion_capacity() * vcmd_suggestion_stride())
    return tree


public def vcmd_free(tree: VCommandTree*) -> void:
    if tree == null:
        return
    vt_free((void*)tree.node_flags)
    vt_free((void*)tree.node_child_start)
    vt_free((void*)tree.node_child_count)
    vt_free((void*)tree.node_redirect)
    vt_free((void*)tree.edges)
    vt_free((void*)tree.node_names)
    vt_free((void*)tree.node_parsers)
    vt_free((void*)tree.completions)
    vt_free((void*)tree.suggestions)
    del tree


# The engine half of the bundle is concatenated before protocol.cpy, so the wire
# helpers there are not defined yet at this point; this reader mirrors
# decode_varint and the test suite checks the two agree byte for byte. Node,
# edge and string counts all fit well inside the four bytes it accepts.
def vcmd_take_varint(body: int64[], cursor: int64) -> int64[]:
    int64[] result = new int64[2]
    result[0] = -1
    result[1] = 0
    if cursor < 0:
        return result
    int64 shift = 0
    int64 value = 0
    int64 at = cursor
    int64 walked = 0
    while at < len(body):
        int64 payload = body[at] & 0x7F
        int64 continuation = body[at] & 0x80
        at = at + 1
        walked = walked + 1
        value = value | (payload << shift)
        if continuation == 0:
            if walked > 5:
                return result
            result[0] = at
            result[1] = value
            return result
        shift = shift + 7
    return result


# [next, start, length] for a varint-prefixed string slice of the body.
def vcmd_take_string(body: int64[], cursor: int64) -> int64[]:
    int64[] result = new int64[3]
    result[0] = -1
    int64[] header = vcmd_take_varint(body, cursor)
    if header[0] < 0 or header[1] < 0:
        return result
    int64 stop = header[0] + header[1]
    if stop > len(body):
        return result
    result[0] = stop
    result[1] = header[0]
    result[2] = header[1]
    return result


def vcmd_take_skip(body: int64[], cursor: int64, count: int64) -> int64:
    if cursor < 0 or cursor + count > len(body):
        return i64_failed()
    return cursor + count


# Bounds inside a parser's settings are only skipped, never read, so this walks
# both the 5 byte varint and the 10 byte varlong forms without decoding either.
def vcmd_take_opaque_varint(body: int64[], cursor: int64) -> int64:
    int64 at = cursor
    int64 walked = 0
    while at < len(body):
        int64 continuation = body[at] & 0x80
        at = at + 1
        walked = walked + 1
        if continuation == 0:
            return at
        if walked > 10:
            return i64_failed()
    return i64_failed()


# Compare the parser identifier against a literal without copying it first. The
# string helpers here come from util/strings.cpy rather than the network client's
# C imports, because engine bundles build without src/protocol.cpy.
def vcmd_text_matches(body: int64[], start: int64, length: int64,
                      needle: str) -> int:
    int size = text_len(needle)
    if (int64)size != length:
        return 0
    int index = 0
    while index < size:
        if (body[start + (int64)index] & 0xFF) != code_at(needle, index):
            return 0
        index = index + 1
    return 1


public def vcmd_parser_kind(body: int64[], start: int64, length: int64) -> int:
    if vcmd_text_matches(body, start, length, "brigadier:bool"):
        return vcmd_parser_none()
    if vcmd_text_matches(body, start, length, "brigadier:float"):
        return vcmd_parser_fixed_bounds()
    if vcmd_text_matches(body, start, length, "brigadier:double"):
        return vcmd_parser_fixed_bounds()
    if vcmd_text_matches(body, start, length, "brigadier:integer"):
        return vcmd_parser_varint_bounds()
    if vcmd_text_matches(body, start, length, "brigadier:long"):
        return vcmd_parser_varint_bounds()
    if vcmd_text_matches(body, start, length, "brigadier:string"):
        return vcmd_parser_byte()
    if vcmd_text_matches(body, start, length, "minecraft:entity"):
        return vcmd_parser_byte()
    if vcmd_text_matches(body, start, length, "minecraft:game_profile"):
        return vcmd_parser_none()
    if vcmd_text_matches(body, start, length, "minecraft:item_slot"):
        return vcmd_parser_none()
    if vcmd_text_matches(body, start, length, "minecraft:item_slots"):
        return vcmd_parser_none()
    if vcmd_text_matches(body, start, length, "minecraft:resource"):
        return vcmd_parser_string()
    if vcmd_text_matches(body, start, length, "minecraft:resource_or_tag"):
        return vcmd_parser_string()
    if vcmd_text_matches(body, start, length, "minecraft:time"):
        return vcmd_parser_none()
    return -1


def vcmd_take_bounds(body: int64[], cursor: int64, width: int64) -> int64:
    if cursor < 0 or cursor >= len(body):
        return i64_failed()
    int64 bounds = body[cursor] & 0xFF
    int64 next = cursor + 1
    if (bounds & 1) != 0:
        if width == 0:
            next = vcmd_take_opaque_varint(body, next)
        else:
            next = vcmd_take_skip(body, next, width)
        if next < 0:
            return i64_failed()
    if (bounds & 2) != 0:
        if width == 0:
            next = vcmd_take_opaque_varint(body, next)
        else:
            next = vcmd_take_skip(body, next, width)
        if next < 0:
            return i64_failed()
    return next


# An unrecognised parser is an error rather than something to skip: guessing the
# size of its settings would read the following node out of the middle of them.
def vcmd_skip_parser(body: int64[], cursor: int64, start: int64,
                     length: int64) -> int64:
    int kind = vcmd_parser_kind(body, start, length)
    if kind == vcmd_parser_none():
        return cursor
    if kind == vcmd_parser_string():
        int64[] registry = vcmd_take_string(body, cursor)
        return registry[0]
    if kind == vcmd_parser_byte():
        return vcmd_take_skip(body, cursor, 1)
    if kind == vcmd_parser_varint_bounds():
        return vcmd_take_bounds(body, cursor, 0)
    if kind == vcmd_parser_fixed_bounds():
        int64 width = 4
        if vcmd_text_matches(body, start, length, "brigadier:double"):
            width = 8
        return vcmd_take_bounds(body, cursor, width)
    return i64_failed()


def vcmd_arena_length(arena: char*, base: int, stride: int) -> int:
    int index = 0
    while index < stride and vt_at(arena, base + index) != 0:
        index = index + 1
    return index


def vcmd_write_text(arena: char*, base: int, body: int64[], offset: int64,
                    length: int64, stride: int) -> void:
    int64 limit = stride - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


def vcmd_append_edge(tree: VCommandTree*, child: int) -> void:
    vt_iset(tree.edges, tree.edge_count, child)
    tree.edge_count = tree.edge_count + 1


# Walk one packet and replace the whole tree. Returns 0 when the tree was
# stored exactly, 1 when the body is malformed or exceeded the capacity.
public def vcmd_parse(tree: VCommandTree*, body: int64[], offset: int64) -> int:
    int64[] header = vcmd_take_varint(body, offset)
    int64 cursor = header[0]
    if cursor < 0 or header[1] < 1:
        return 1
    int wanted = (int)header[1]
    if wanted > vcmd_node_capacity():
        tree.truncated = 1
        return 1
    tree.node_count = 0
    tree.edge_count = 0
    tree.truncated = 0
    int node = 0
    while node < wanted:
        if cursor >= len(body):
            return 1
        int flags = (int)body[cursor] & 0xFF
        cursor = cursor + 1
        int64[] child_header = vcmd_take_varint(body, cursor)
        cursor = child_header[0]
        if cursor < 0 or child_header[1] < 0:
            return 1
        int children = (int)child_header[1]
        if tree.edge_count + children > vcmd_edge_capacity():
            tree.truncated = 1
            return 1
        vt_iset(tree.node_child_start, node, tree.edge_count)
        vt_iset(tree.node_child_count, node, children)
        vt_iset(tree.node_flags, node, flags)
        int step = 0
        while step < children:
            int64[] child = vcmd_take_varint(body, cursor)
            cursor = child[0]
            if cursor < 0 or child[1] < 0 or child[1] >= wanted:
                return 1
            vcmd_append_edge(tree, (int)child[1])
            step = step + 1
        int node_type = flags & 3
        if node_type != vcmd_type_root():
            int64[] name = vcmd_take_string(body, cursor)
            cursor = name[0]
            if cursor < 0:
                return 1
            vcmd_write_text(tree.node_names, node * vcmd_name_stride(), body,
                            name[1], name[2], vcmd_name_stride())
        if node_type == vcmd_type_argument():
            int64[] parser = vcmd_take_string(body, cursor)
            cursor = parser[0]
            if cursor < 0:
                return 1
            vcmd_write_text(tree.node_parsers, node * vcmd_parser_stride(),
                            body, parser[1], parser[2], vcmd_parser_stride())
            cursor = vcmd_skip_parser(body, cursor, parser[1], parser[2])
            if cursor < 0:
                return 1
        if (flags & 0x08) != 0:
            int64[] redirect = vcmd_take_varint(body, cursor)
            cursor = redirect[0]
            if cursor < 0 or redirect[1] < 0 or redirect[1] >= wanted:
                return 1
            vt_iset(tree.node_redirect, node, (int)redirect[1])
        if (flags & 0x10) != 0:
            int64[] suggestions = vcmd_take_string(body, cursor)
            cursor = suggestions[0]
            if cursor < 0:
                return 1
        node = node + 1
    if cursor + 1 > len(body):
        return 1
    tree.chain_limit = (int)body[cursor] & 0xFF
    cursor = cursor + 1
    if cursor != len(body):
        return 1
    tree.node_count = wanted
    return 0


public def vcmd_node_total(tree: VCommandTree*) -> int:
    return tree.node_count


public def vcmd_is_truncated(tree: VCommandTree*) -> int:
    return tree.truncated


public def vcmd_chain_limit(tree: VCommandTree*) -> int:
    return tree.chain_limit


public def vcmd_node_type(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return vcmd_absent()
    return vt_iget(tree.node_flags, node) & 3


public def vcmd_is_executable(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    if (vt_iget(tree.node_flags, node) & 4) == 0:
        return 0
    return 1


public def vcmd_redirect(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return vcmd_absent()
    return vt_iget(tree.node_redirect, node)


public def vcmd_child_count(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    return vt_iget(tree.node_child_count, node)


public def vcmd_child(tree: VCommandTree*, node: int, index: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count or index < 0:
        return vcmd_absent()
    if index >= vt_iget(tree.node_child_count, node):
        return vcmd_absent()
    return vt_iget(tree.edges, vt_iget(tree.node_child_start, node) + index)


public def vcmd_name_length(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    return vcmd_arena_length(tree.node_names, node * vcmd_name_stride(),
                             vcmd_name_stride())


public def vcmd_name_byte(tree: VCommandTree*, node: int, index: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count or index < 0:
        return 0
    if index >= vcmd_name_stride():
        return 0
    return vt_at(tree.node_names, node * vcmd_name_stride() + index)


public def vcmd_parser_length(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    return vcmd_arena_length(tree.node_parsers, node * vcmd_parser_stride(),
                             vcmd_parser_stride())


public def vcmd_parser_name_byte(tree: VCommandTree*, node: int, index: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count or index < 0:
        return 0
    if index >= vcmd_parser_stride():
        return 0
    return vt_at(tree.node_parsers, node * vcmd_parser_stride() + index)


# How many children of a node start with the bytes the player has typed so far.
# Completion asks this before it asks for the names, so both walks share the
# stride and the terminator rule of the name arena.
public def vcmd_match_children(tree: VCommandTree*, node: int, prefix: str) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    int size = text_len(prefix)
    if size < 1:
        return vt_iget(tree.node_child_count, node)
    int matched = 0
    int index = 0
    while index < vt_iget(tree.node_child_count, node):
        int child = vt_iget(tree.edges,
                            vt_iget(tree.node_child_start, node) + index)
        int base = child * vcmd_name_stride()
        int same = 1
        int step = 0
        while step < size:
            int64 stored = (int64)vt_at(tree.node_names, base + step)
            int64 wanted_byte = (int64)code_at(prefix, step)
            if stored != wanted_byte:
                same = 0
                step = size
            step = step + 1
        if same == 1:
            matched = matched + 1
        index = index + 1
    return matched


# --- custom chat completions --------------------------------------------------

def vcmd_completion_matches(arena: char*, base: int, body: int64[],
                            offset: int64, length: int64) -> int:
    int64 limit = vcmd_completion_stride() - 1
    if length > limit:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


def vcmd_completion_write(arena: char*, base: int, body: int64[],
                          offset: int64, length: int64) -> void:
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


def vcmd_completion_find(tree: VCommandTree*, body: int64[], offset: int64,
                         length: int64) -> int:
    int row = 0
    while row < tree.completion_count:
        if vcmd_completion_matches(tree.completions,
                                   row * vcmd_completion_stride(),
                                   body, offset, length) == 1:
            return row
        row = row + 1
    return vcmd_absent()


public def vcmd_completions_clear(tree: VCommandTree*) -> void:
    if tree == null:
        return
    tree.completion_count = 0


public def vcmd_completions_add(tree: VCommandTree*, body: int64[],
                                offset: int64, length: int64) -> int:
    if tree == null or length < 0:
        return vcmd_absent()
    if length >= vcmd_completion_stride():
        return vcmd_absent()
    if vcmd_completion_find(tree, body, offset, length) != vcmd_absent():
        return vcmd_absent()
    if tree.completion_count >= vcmd_completion_capacity():
        return vcmd_absent()
    int row = tree.completion_count
    vcmd_completion_write(tree.completions, row * vcmd_completion_stride(),
                          body, offset, length)
    tree.completion_count = row + 1
    return row


public def vcmd_completions_remove(tree: VCommandTree*, body: int64[],
                                   offset: int64, length: int64) -> int:
    if tree == null:
        return 0
    int row = vcmd_completion_find(tree, body, offset, length)
    if row == vcmd_absent():
        return 0
    int last = tree.completion_count - 1
    while row < last:
        int index = 0
        while index < vcmd_completion_stride():
            vt_put(tree.completions, row * vcmd_completion_stride() + index,
                   vt_at(tree.completions,
                         (row + 1) * vcmd_completion_stride() + index))
            index = index + 1
        row = row + 1
    tree.completion_count = last
    return 1


public def vcmd_completion_rows(tree: VCommandTree*) -> int:
    if tree == null:
        return 0
    return tree.completion_count


public def vcmd_completion_length(tree: VCommandTree*, row: int) -> int:
    if tree == null or row < 0 or row >= tree.completion_count:
        return 0
    int base = row * vcmd_completion_stride()
    int index = 0
    while index < vcmd_completion_stride():
        if vt_at(tree.completions, base + index) == 0:
            return index
        index = index + 1
    return index


public def vcmd_completion_byte(tree: VCommandTree*, row: int,
                                index: int) -> int:
    if tree == null or row < 0 or row >= tree.completion_count:
        return 0
    if index < 0 or index >= vcmd_completion_stride():
        return 0
    return vt_at(tree.completions, row * vcmd_completion_stride() + index)


# --- tab-complete suggestions -------------------------------------------------
#
# A suggestions packet replaces the whole list and names the substring it
# applies to, so the range is stored with the rows rather than per row. Tooltips
# are components the client cannot render headlessly and are walked, not kept.

public def vcmd_suggestions_begin(tree: VCommandTree*, id: int, start: int,
                                  length: int) -> int:
    if tree == null or id < 0 or start < 0 or length < 0:
        return 1
    tree.suggestion_id = id
    tree.suggestion_start = start
    tree.suggestion_length = length
    tree.suggestion_count = 0
    return 0


public def vcmd_suggestions_add(tree: VCommandTree*, body: int64[],
                                offset: int64, length: int64) -> int:
    if tree == null or length < 0:
        return vcmd_absent()
    if length >= vcmd_suggestion_stride():
        return vcmd_absent()
    if tree.suggestion_count >= vcmd_suggestion_capacity():
        return vcmd_absent()
    int row = tree.suggestion_count
    vcmd_completion_write(tree.suggestions, row * vcmd_suggestion_stride(),
                          body, offset, length)
    tree.suggestion_count = row + 1
    return row


public def vcmd_suggestion_id(tree: VCommandTree*) -> int:
    if tree == null:
        return vcmd_absent()
    return tree.suggestion_id


public def vcmd_suggestion_start(tree: VCommandTree*) -> int:
    if tree == null:
        return 0
    return tree.suggestion_start


public def vcmd_suggestion_length(tree: VCommandTree*) -> int:
    if tree == null:
        return 0
    return tree.suggestion_length


public def vcmd_suggestion_rows(tree: VCommandTree*) -> int:
    if tree == null:
        return 0
    return tree.suggestion_count


public def vcmd_suggestion_row_length(tree: VCommandTree*, row: int) -> int:
    if tree == null or row < 0 or row >= tree.suggestion_count:
        return 0
    int base = row * vcmd_suggestion_stride()
    int index = 0
    while index < vcmd_suggestion_stride():
        if vt_at(tree.suggestions, base + index) == 0:
            return index
        index = index + 1
    return index


public def vcmd_suggestion_byte(tree: VCommandTree*, row: int, index: int) -> int:
    if tree == null or row < 0 or row >= tree.suggestion_count:
        return 0
    if index < 0 or index >= vcmd_suggestion_stride():
        return 0
    return vt_at(tree.suggestions, row * vcmd_suggestion_stride() + index)


# ===== effects.cpy =====
# Vortex engine - the active status effects a server has applied to entities.
#
# Two packets own this table: update writes or refreshes one (entity, effect)
# pair and remove clears exactly that pair, leaving the rest of the entity's
# effects alone. Rows are keyed by the pair because a mob can carry several
# effects at once and the HUD has to show the strongest amplifier per effect,
# not one effect per entity.
#
# Wire layout this client parses, per protocol 777 (update mob effect):
#
#   entity id     VarInt
#   effect id     VarInt
#   amplifier     VarInt
#   duration      VarInt      -1 means the effect has no visible timer
#   flags         Byte        0x01 ambient, 0x02 show particles,
#                             0x04 an icon override follows,
#                             0x08 a colour follows
#   colour        VarInt      when flags & 0x08
#
# Remove mob effect carries just the entity id and the effect id.


public def vfx_absent() -> int:
    return -1


public def vfx_capacity() -> int:
    return 4096


public def vfx_flag_ambient() -> int:
    return 1


public def vfx_flag_particles() -> int:
    return 2


public def vfx_flag_icon() -> int:
    return 4


public def vfx_flag_colour() -> int:
    return 8


public def vfx_no_duration() -> int:
    return -1


struct VEffects:
    int count
    int* entity_id
    int* effect_id
    int* amplitude
    int* duration
    int* flags
    int* colour
    int* present


public def vfx_new() -> VEffects*:
    VEffects* table = new VEffects
    table.count = 0
    table.entity_id = vt_calloc_int(vfx_capacity())
    table.effect_id = vt_calloc_int(vfx_capacity())
    table.amplitude = vt_calloc_int(vfx_capacity())
    table.duration = vt_calloc_int(vfx_capacity())
    table.flags = vt_calloc_int(vfx_capacity())
    table.colour = vt_calloc_int(vfx_capacity())
    table.present = vt_calloc_int(vfx_capacity())
    return table


public def vfx_free(table: VEffects*) -> void:
    if table == null:
        return
    vt_free((void*)table.entity_id)
    vt_free((void*)table.effect_id)
    vt_free((void*)table.amplitude)
    vt_free((void*)table.duration)
    vt_free((void*)table.flags)
    vt_free((void*)table.colour)
    vt_free((void*)table.present)
    del table


def vfx_find(table: VEffects*, entity: int, effect: int) -> int:
    if table == null:
        return vfx_absent()
    int index = 0
    while index < vfx_capacity():
        if vt_iget(table.present, index) == 1:
            if vt_iget(table.entity_id, index) == entity:
                if vt_iget(table.effect_id, index) == effect:
                    return index
        index = index + 1
    return vfx_absent()


def vfx_slot(table: VEffects*, entity: int, effect: int) -> int:
    int existing = vfx_find(table, entity, effect)
    if existing >= 0:
        return existing
    int index = 0
    while index < vfx_capacity():
        if vt_iget(table.present, index) == 0:
            vt_iset(table.present, index, 1)
            vt_iset(table.entity_id, index, entity)
            vt_iset(table.effect_id, index, effect)
            table.count = table.count + 1
            return index
        index = index + 1
    return vfx_absent()


def vfx_clear(table: VEffects*, index: int) -> void:
    vt_iset(table.present, index, 0)
    vt_iset(table.entity_id, index, 0)
    vt_iset(table.effect_id, index, 0)
    vt_iset(table.amplitude, index, 0)
    vt_iset(table.duration, index, 0)
    vt_iset(table.flags, index, 0)
    vt_iset(table.colour, index, 0)
    table.count = table.count - 1


# An update replaces every field it carries rather than merging, because the
# packet always describes the effect completely; keeping the old colour would
# show a particle that no longer exists.
public def vfx_set(table: VEffects*, entity: int, effect: int, amplifier: int,
                   duration: int, flags: int, colour: int) -> int:
    int slot = vfx_slot(table, entity, effect)
    if slot < 0:
        return 0
    vt_iset(table.amplitude, slot, amplifier)
    vt_iset(table.duration, slot, duration)
    vt_iset(table.flags, slot, flags)
    vt_iset(table.colour, slot, colour)
    return 1


public def vfx_remove(table: VEffects*, entity: int, effect: int) -> int:
    int slot = vfx_find(table, entity, effect)
    if slot < 0:
        return 1
    vfx_clear(table, slot)
    return 1


public def vfx_remove_entity(table: VEffects*, entity: int) -> void:
    if table == null:
        return
    int index = 0
    while index < vfx_capacity():
        if vt_iget(table.present, index) == 1:
            if vt_iget(table.entity_id, index) == entity:
                vfx_clear(table, index)
        index = index + 1


public def vfx_has(table: VEffects*, entity: int, effect: int) -> int:
    if vfx_find(table, entity, effect) < 0:
        return 0
    return 1


public def vfx_amplitude(table: VEffects*, entity: int, effect: int) -> int:
    int slot = vfx_find(table, entity, effect)
    if slot < 0:
        return vfx_absent()
    return vt_iget(table.amplitude, slot)


public def vfx_duration(table: VEffects*, entity: int, effect: int) -> int:
    int slot = vfx_find(table, entity, effect)
    if slot < 0:
        return vfx_absent()
    return vt_iget(table.duration, slot)


public def vfx_colour(table: VEffects*, entity: int, effect: int) -> int:
    int slot = vfx_find(table, entity, effect)
    if slot < 0:
        return vfx_absent()
    return vt_iget(table.colour, slot)


public def vfx_flag(table: VEffects*, entity: int, effect: int,
                    bit: int) -> int:
    int slot = vfx_find(table, entity, effect)
    if slot < 0:
        return 0
    if (vt_iget(table.flags, slot) & bit) == 0:
        return 0
    return 1


public def vfx_active_count(table: VEffects*) -> int:
    if table == null:
        return 0
    return table.count


# ===== attributes.cpy =====
# Vortex engine - the attribute values a server has published for entities.
#
# Update Attributes replaces the whole set it names, and the client needs the
# result rather than the packet: the health bar, the movement speed, the reach
# used for targeting and the scale used for the hitbox all come from here, not
# from entity metadata. Rows are keyed by (entity, attribute id) because one mob
# can carry a dozen attributes and a player's own attributes arrive with the
# player's entity id.
#
# The attributes are named by a registry index, not by an identifier string:
# the packet's key field is a varint into the 35 entry attribute registry, so
# the names in vat_key_by_name below exist only to let the rest of the client
# ask for "minecraft:generic.max_health" without hard-coding 19 at every call.
#
# A modifier is only counted, never replayed: the packet's value field already
# is the total the server wants displayed, so re-deriving it from the modifier
# list would risk disagreeing with the authority that sent it. The count is
# kept because the HUD shows "this number is buffed" only when modifiers exist.


public def vat_absent() -> int:
    return -1


def vat_capacity() -> int:
    return 2048


def vat_missing_value() -> double:
    return -1.0


# The two limits a malformed packet can cross: a server never sends more than
# one property per attribute, and a modifier list longer than this is either
# corrupt or hostile.
public def vat_max_properties() -> int:
    return 64


public def vat_max_list() -> int:
    return 1024


# Attribute ids worth naming because the client reads them for its own state.
public def vat_key_armor() -> int:
    return 0


public def vat_key_attack_damage() -> int:
    return 2


public def vat_key_attack_speed() -> int:
    return 4


public def vat_key_block_reach() -> int:
    return 6


public def vat_key_entity_reach() -> int:
    return 10


public def vat_key_flying_speed() -> int:
    return 12


public def vat_key_follow_range() -> int:
    return 13


public def vat_key_gravity() -> int:
    return 14


public def vat_key_jump_strength() -> int:
    return 15


public def vat_key_max_absorption() -> int:
    return 18


public def vat_key_max_health() -> int:
    return 19


public def vat_key_movement_speed() -> int:
    return 22


public def vat_key_safe_fall_distance() -> int:
    return 24


public def vat_key_scale() -> int:
    return 25


public def vat_key_step_height() -> int:
    return 28


def vat_key_count() -> int:
    return 35


# Maps a namespaced attribute identifier to the registry index the packet
# carries. Both the bare name and the "minecraft:" form resolve.
public def vat_key_by_name(text: str) -> int:
    str name = text
    if str_starts(text, "minecraft:"):
        name = str_slice(text, 10, text_len(text))
    if str_equals(name, "generic.armor"):
        return 0
    if str_equals(name, "generic.armor_toughness"):
        return 1
    if str_equals(name, "generic.attack_damage"):
        return 2
    if str_equals(name, "generic.attack_knockback"):
        return 3
    if str_equals(name, "generic.attack_speed"):
        return 4
    if str_equals(name, "player.block_break_speed"):
        return 5
    if str_equals(name, "player.block_interaction_range"):
        return 6
    if str_equals(name, "burning_time"):
        return 7
    if str_equals(name, "camera_distance"):
        return 8
    if str_equals(name, "explosion_knockback_resistance"):
        return 9
    if str_equals(name, "player.entity_interaction_range"):
        return 10
    if str_equals(name, "generic.fall_damage_multiplier"):
        return 11
    if str_equals(name, "generic.flying_speed"):
        return 12
    if str_equals(name, "generic.follow_range"):
        return 13
    if str_equals(name, "generic.gravity"):
        return 14
    if str_equals(name, "generic.jump_strength"):
        return 15
    if str_equals(name, "generic.knockback_resistance"):
        return 16
    if str_equals(name, "generic.luck"):
        return 17
    if str_equals(name, "generic.max_absorption"):
        return 18
    if str_equals(name, "generic.max_health"):
        return 19
    if str_equals(name, "mining_efficiency"):
        return 20
    if str_equals(name, "movement_efficiency"):
        return 21
    if str_equals(name, "generic.movement_speed"):
        return 22
    if str_equals(name, "oxygen_bonus"):
        return 23
    if str_equals(name, "generic.safe_fall_distance"):
        return 24
    if str_equals(name, "generic.scale"):
        return 25
    if str_equals(name, "sneaking_speed"):
        return 26
    if str_equals(name, "zombie.spawn_reinforcements"):
        return 27
    if str_equals(name, "generic.step_height"):
        return 28
    if str_equals(name, "submerged_mining_speed"):
        return 29
    if str_equals(name, "sweeping_damage_ratio"):
        return 30
    if str_equals(name, "tempt_range"):
        return 31
    if str_equals(name, "water_movement_efficiency"):
        return 32
    if str_equals(name, "waypoint_transmit_range"):
        return 33
    if str_equals(name, "waypoint_receive_range"):
        return 34
    return vat_absent()


struct VAttributes:
    int count
    int* entity_id
    int* key_id
    int* modifier_count
    int* present
    uint64* value


public def vat_new() -> VAttributes*:
    VAttributes* table = new VAttributes
    table.count = 0
    table.entity_id = vt_calloc_int(vat_capacity())
    table.key_id = vt_calloc_int(vat_capacity())
    table.modifier_count = vt_calloc_int(vat_capacity())
    table.present = vt_calloc_int(vat_capacity())
    table.value = vt_calloc_u64(vat_capacity())
    return table


public def vat_free(table: VAttributes*) -> void:
    if table == null:
        return
    vt_free((void*)table.entity_id)
    vt_free((void*)table.key_id)
    vt_free((void*)table.modifier_count)
    vt_free((void*)table.present)
    vt_free((void*)table.value)
    del table


def vat_find(table: VAttributes*, entity: int, key: int) -> int:
    if table == null:
        return vat_absent()
    int index = 0
    while index < vat_capacity():
        if vt_iget(table.present, index) == 1:
            if vt_iget(table.entity_id, index) == entity:
                if vt_iget(table.key_id, index) == key:
                    return index
        index = index + 1
    return vat_absent()


def vat_slot(table: VAttributes*, entity: int, key: int) -> int:
    int existing = vat_find(table, entity, key)
    if existing >= 0:
        return existing
    int index = 0
    while index < vat_capacity():
        if vt_iget(table.present, index) == 0:
            vt_iset(table.present, index, 1)
            vt_iset(table.entity_id, index, entity)
            vt_iset(table.key_id, index, key)
            table.count = table.count + 1
            return index
        index = index + 1
    return vat_absent()


# Stores one published total. An id outside the registry is dropped rather than
# stored: a modded server that adds attributes is free to do so, and the client
# showing a value it cannot name is worse than not showing it.
public def vat_set(table: VAttributes*, entity: int, key: int, value: double,
                   modifier_count: int) -> int:
    if table == null or entity < 0 or key < 0 or key >= vat_key_count():
        return 0
    int slot = vat_slot(table, entity, key)
    if slot < 0:
        return 0
    vt_uset(table.value, slot, vt_double_to_bits(value))
    vt_iset(table.modifier_count, slot, modifier_count)
    return 1


public def vat_value(table: VAttributes*, entity: int, key: int) -> double:
    int slot = vat_find(table, entity, key)
    if slot < 0:
        return vat_missing_value()
    return vt_bits_to_double(vt_uget(table.value, slot))


public def vat_modifier_count(table: VAttributes*, entity: int,
                              key: int) -> int:
    int slot = vat_find(table, entity, key)
    if slot < 0:
        return vat_absent()
    return vt_iget(table.modifier_count, slot)


# The two name-taking entry points the HUD and the tests use; they resolve the
# identifier to the registry index and then fall through to the indexed forms.
public def vat_lookup(table: VAttributes*, entity: int, name: str) -> double:
    int key = vat_key_by_name(name)
    if key < 0:
        return vat_missing_value()
    return vat_value(table, entity, key)


public def vat_lookup_modifier_count(table: VAttributes*, entity: int,
                                     name: str) -> int:
    int key = vat_key_by_name(name)
    if key < 0:
        return vat_absent()
    return vat_modifier_count(table, entity, key)


public def vat_remove(table: VAttributes*, entity: int, key: int) -> int:
    int slot = vat_find(table, entity, key)
    if slot < 0:
        return 1
    vt_iset(table.present, slot, 0)
    vt_iset(table.entity_id, slot, 0)
    vt_iset(table.key_id, slot, 0)
    vt_iset(table.modifier_count, slot, 0)
    vt_uset(table.value, slot, 0)
    table.count = table.count - 1
    return 1


public def vat_remove_entity(table: VAttributes*, entity: int) -> int:
    if table == null:
        return 0
    int dropped = 0
    int index = 0
    while index < vat_capacity():
        if vt_iget(table.present, index) == 1:
            if vt_iget(table.entity_id, index) == entity:
                vt_iset(table.present, index, 0)
                vt_iset(table.entity_id, index, 0)
                vt_iset(table.key_id, index, 0)
                vt_iset(table.modifier_count, index, 0)
                vt_uset(table.value, index, 0)
                table.count = table.count - 1
                dropped = dropped + 1
        index = index + 1
    return dropped


public def vat_active_count(table: VAttributes*) -> int:
    if table == null:
        return 0
    return table.count


public def vat_entity_rows(table: VAttributes*, entity: int) -> int:
    if table == null:
        return 0
    int found = 0
    int index = 0
    while index < vat_capacity():
        if vt_iget(table.present, index) == 1:
            if vt_iget(table.entity_id, index) == entity:
                found = found + 1
        index = index + 1
    return found


# The health the bar shows: the server's published maximum, or the vanilla 20
# when nothing has been published for this entity yet.
public def vat_max_health(table: VAttributes*, entity: int) -> double:
    double published = vat_value(table, entity, vat_key_max_health())
    if published < 0.0:
        return 20.0
    return published


public def vat_row_entity(table: VAttributes*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vat_capacity():
        return vat_absent()
    if vt_iget(table.present, slot) != 1:
        return vat_absent()
    return vt_iget(table.entity_id, slot)


public def vat_row_key(table: VAttributes*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vat_capacity():
        return vat_absent()
    if vt_iget(table.present, slot) != 1:
        return vat_absent()
    return vt_iget(table.key_id, slot)


public def vat_row_modifier_count(table: VAttributes*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vat_capacity():
        return vat_absent()
    if vt_iget(table.present, slot) != 1:
        return vat_absent()
    return vt_iget(table.modifier_count, slot)


public def vat_row_value(table: VAttributes*, slot: int) -> double:
    if table == null or slot < 0 or slot >= vat_capacity():
        return vat_missing_value()
    if vt_iget(table.present, slot) != 1:
        return vat_missing_value()
    return vt_bits_to_double(vt_uget(table.value, slot))


# ---- packet layer ----------------------------------------------------------
#
# Update Attributes, in the layout the current protocol revision sends:
#
#   entity id     VarInt
#   properties    VarInt count
#     key         VarInt     (index into the attribute registry)
#     value       Double     (the post-modifier total)
#     modifiers   VarInt count
#       uuid      16 raw bytes or a prefixed string, depending on the revision
#       amount    Double
#       operation Byte
#
# The modifier uuid is the one field the revisions disagree about, so the walk
# is run twice: prefixed strings first, because that is what the generated
# schema says, then raw uuids, because that is what the vanilla server has
# historically put on the wire. A packet that ends exactly on the body boundary
# under one of them is the answer; neither means the packet is not this layout.

def vat_varint(body: int64[], offset: int64) -> int64[]:
    int64[] result = new int64[2]
    result[0] = -1
    result[1] = 0
    int64 value = 0
    int64 read = 0
    int64 at = offset
    while read < 5:
        if at >= len(body):
            return result
        int64 piece = body[at] & 0x7F
        int64 more = body[at] & 0x80
        value = value | (piece << (read * 7))
        at = at + 1
        read = read + 1
        if more == 0:
            result[0] = at
            result[1] = value
            return result
    return result


def vat_take(body: int64[], cursor: int64, count: int64) -> int64:
    if cursor < 0:
        return i64_failed()
    if cursor + count > len(body):
        return i64_failed()
    return cursor + count


def vat_double(body: int64[], cursor: int64) -> double:
    int64 bits = 0
    int64 index = 0
    while index < 8:
        bits = (bits << 8) | (body[cursor + index] & 0xFF)
        index = index + 1
    return vt_bits_to_double(bits)


# A prefixed string: the modifier uuid when the revision sends it as text.
def vat_string(body: int64[], cursor: int64) -> int64[]:
    int64[] result = new int64[2]
    result[0] = -1
    int64[] size = vat_varint(body, cursor)
    if size[0] < 0 or size[1] < 0 or size[1] > 512:
        return result
    result[0] = vat_take(body, size[0], size[1])
    return result


def vat_modifier(body: int64[], cursor: int64, text_uuid: bool) -> int64:
    if text_uuid:
        int64[] identity = vat_string(body, cursor)
        if identity[0] < 0:
            return i64_failed()
        cursor = identity[0]
    else:
        cursor = vat_take(body, cursor, 16)
    if cursor < 0:
        return i64_failed()
    cursor = vat_take(body, cursor, 9)
    return cursor


def vat_parse_with(table: VAttributes*, body: int64[], offset: int64,
                   text_uuid: bool) -> int:
    int64[] head = vat_varint(body, offset)
    if head[0] < 0 or head[1] < 0:
        return -1
    int entity = (int)head[1]
    int64[] total = vat_varint(body, head[0])
    if total[0] < 0 or total[1] < 0 or total[1] > (int64)vat_max_properties():
        return -1
    int64 cursor = total[0]
    int64 index = 0
    int read = 0
    while index < total[1]:
        int64[] key = vat_varint(body, cursor)
        if key[0] < 0 or key[1] < 0:
            return -1
        cursor = key[0]
        int64 value_at = cursor
        cursor = vat_take(body, cursor, 8)
        if cursor < 0:
            return -1
        double value = vat_double(body, value_at)
        int64[] modifiers = vat_varint(body, cursor)
        int64 allowed = (int64)vat_max_list()
        if modifiers[0] < 0 or modifiers[1] < 0 or modifiers[1] > allowed:
            return -1
        cursor = modifiers[0]
        int64 walked = 0
        while walked < modifiers[1]:
            cursor = vat_modifier(body, cursor, text_uuid)
            if cursor < 0:
                return -1
            walked = walked + 1
        if vat_set(table, entity, (int)key[1], value,
                   (int)modifiers[1]) == 0:
            print("Attribute id is not in the registry this client knows")
        read = read + 1
        index = index + 1
    if cursor != len(body):
        return -1
    return read


# Returns the number of properties published, or -1 when the packet is not an
# attribute update this client can read.
public def vat_parse(table: VAttributes*, body: int64[],
                     offset: int64) -> int:
    int prefixed = vat_parse_with(table, body, offset, true)
    if prefixed >= 0:
        return prefixed
    int raw = vat_parse_with(table, body, offset, false)
    if raw >= 0:
        print("Attribute modifiers carried raw uuids")
        return raw
    return -1


# ===== players.cpy =====
# Vortex engine - the player list the server publishes.
#
# Player Info Update names a subset of fields per entry, so the rows here are
# the union of everything the client can be told about a player: the tab list
# needs the name, the display name, the latency and the hat, the HUD needs the
# game mode, and the chat renderer needs to know whether the sender is listed
# at all. Rows are keyed by the 16 byte uuid because that is the only stable
# identity a server uses; the name can change with a rename while the player is
# online.
#
# An action only writes the columns it carries. That is what makes a
# multi-action packet correct: a server that sends a display name without a
# game mode must not silently reset the game mode the client already shows.
#
# The Add action is the only one allowed to create a row. Every other action
# against an unknown uuid is dropped, which is also what vanilla does - a server
# that updates a player it never added is not followed by a ghost entry.


public def vplayers_absent() -> int:
    return -1


def vplayers_capacity() -> int:
    return 256


def vplayers_uuid_stride() -> int:
    return 16


# Minecraft names are at most 16 characters, so four bytes per character of
# potential multi-byte text is more than enough and keeps the row cheap.
def vplayers_name_stride() -> int:
    return 64


def vplayers_display_stride() -> int:
    return 192


# The action mask bits. The order the bits are numbered in is not the order the
# fields appear in the packet: the entry writes its list-order priority before
# its hat flag, so the walker in src/protocol.cpy follows the field order below
# and not the bit order.
public def vplayers_action_add() -> int:
    return 1


public def vplayers_action_chat() -> int:
    return 2


public def vplayers_action_game_mode() -> int:
    return 4


public def vplayers_action_listed() -> int:
    return 8


public def vplayers_action_latency() -> int:
    return 16


public def vplayers_action_display() -> int:
    return 32


public def vplayers_action_hat() -> int:
    return 64


public def vplayers_action_priority() -> int:
    return 128


def vplayers_all_actions() -> int:
    return 255


struct VPlayers:
    int count
    char* uuids
    char* names
    char* displays
    char* header
    char* footer
    int* game_mode
    int* latency
    int* priority
    int* hat
    int* listed
    int* properties
    int* chat_session


public def vplayers_new() -> VPlayers*:
    VPlayers* table = new VPlayers
    table.count = 0
    table.uuids = vt_calloc_char(vplayers_capacity() * vplayers_uuid_stride())
    table.names = vt_calloc_char(vplayers_capacity() * vplayers_name_stride())
    table.displays = vt_calloc_char(vplayers_capacity() *
                                    vplayers_display_stride())
    table.header = vt_calloc_char(vplayers_display_stride())
    table.footer = vt_calloc_char(vplayers_display_stride())
    table.game_mode = vt_calloc_int(vplayers_capacity())
    table.latency = vt_calloc_int(vplayers_capacity())
    table.priority = vt_calloc_int(vplayers_capacity())
    table.hat = vt_calloc_int(vplayers_capacity())
    table.listed = vt_calloc_int(vplayers_capacity())
    table.properties = vt_calloc_int(vplayers_capacity())
    table.chat_session = vt_calloc_int(vplayers_capacity())
    return table


public def vplayers_free(table: VPlayers*) -> void:
    if table == null:
        return
    vt_free((void*)table.uuids)
    vt_free((void*)table.names)
    vt_free((void*)table.displays)
    vt_free((void*)table.header)
    vt_free((void*)table.footer)
    vt_free((void*)table.game_mode)
    vt_free((void*)table.latency)
    vt_free((void*)table.priority)
    vt_free((void*)table.hat)
    vt_free((void*)table.listed)
    vt_free((void*)table.properties)
    vt_free((void*)table.chat_session)
    del table


def vplayers_uuid_matches(table: VPlayers*, slot: int, body: int64[],
                          offset: int64) -> int:
    int byte = 0
    while byte < vplayers_uuid_stride():
        int stored = vt_at(table.uuids, slot * vplayers_uuid_stride() + byte)
        int wanted = (int)(body[offset + byte] & 0xFF)
        if stored != wanted:
            return 0
        byte = byte + 1
    return 1


public def vplayers_find(table: VPlayers*, body: int64[],
                         offset: int64) -> int:
    if table == null or offset + vplayers_uuid_stride() > len(body):
        return vplayers_absent()
    int slot = 0
    while slot < table.count:
        if vplayers_uuid_matches(table, slot, body, offset) == 1:
            return slot
        slot = slot + 1
    return vplayers_absent()


# Only the Add action creates: see the note above about updates that arrive for
# a player the client has never been introduced to.
def vplayers_add_slot(table: VPlayers*, body: int64[], offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot >= 0:
        return slot
    if table.count >= vplayers_capacity():
        return vplayers_absent()
    slot = table.count
    table.count = table.count + 1
    int byte = 0
    while byte < vplayers_uuid_stride():
        vt_put(table.uuids, slot * vplayers_uuid_stride() + byte,
               (int)(body[offset + byte] & 0xFF))
        byte = byte + 1
    vt_put(table.names, slot * vplayers_name_stride(), 0)
    vt_put(table.displays, slot * vplayers_display_stride(), 0)
    vt_iset(table.game_mode, slot, 0)
    vt_iset(table.latency, slot, 0)
    vt_iset(table.priority, slot, 0)
    vt_iset(table.hat, slot, 0)
    vt_iset(table.listed, slot, 0)
    vt_iset(table.properties, slot, 0)
    vt_iset(table.chat_session, slot, 0)
    return slot


def vplayers_update_slot(table: VPlayers*, body: int64[],
                         offset: int64) -> int:
    return vplayers_find(table, body, offset)


# Copies text into a row, truncating rather than rejecting: a name the client
# cannot fully store is still a name, and the tab list has to show that somebody
# is online. The source is its own array because the display name arrives
# flattened by the component reader rather than as a slice of the packet.
def vplayers_write(dest: char*, stride: int, slot: int, source: int64[],
                   start: int64, length: int64) -> void:
    int limit = stride - 1
    if length > limit:
        length = limit
    int base = slot * stride
    int index = 0
    while index < length:
        vt_put(dest, base + index, (int)(source[start + index] & 0xFF))
        index = index + 1
    vt_put(dest, base + index, 0)


public def vplayers_set_add(table: VPlayers*, body: int64[], uuid_at: int64,
                            name_start: int64, name_length: int64,
                            properties: int, game_mode: int,
                            listed: int) -> int:
    int slot = vplayers_add_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vplayers_write(table.names, vplayers_name_stride(), slot, body,
                   name_start, name_length)
    vt_iset(table.properties, slot, properties)
    vt_iset(table.game_mode, slot, game_mode)
    vt_iset(table.listed, slot, listed)
    return 1


public def vplayers_set_display(table: VPlayers*, body: int64[],
                                uuid_at: int64, source: int64[],
                                length: int64) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vplayers_write(table.displays, vplayers_display_stride(), slot, source,
                   0, length)
    return 1


public def vplayers_set_game_mode(table: VPlayers*, body: int64[],
                                  uuid_at: int64, game_mode: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.game_mode, slot, game_mode)
    return 1


public def vplayers_set_listed(table: VPlayers*, body: int64[],
                               uuid_at: int64, listed: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.listed, slot, listed)
    return 1


public def vplayers_set_latency(table: VPlayers*, body: int64[],
                                uuid_at: int64, latency: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.latency, slot, latency)
    return 1


public def vplayers_set_priority(table: VPlayers*, body: int64[],
                                 uuid_at: int64, priority: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.priority, slot, priority)
    return 1


public def vplayers_set_hat(table: VPlayers*, body: int64[], uuid_at: int64,
                            hat: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.hat, slot, hat)
    return 1


public def vplayers_set_chat(table: VPlayers*, body: int64[],
                             uuid_at: int64, present: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.chat_session, slot, present)
    return 1


def vplayers_copy_down(table: VPlayers*, slot: int) -> void:
    int byte = 0
    while byte < vplayers_uuid_stride():
        vt_put(table.uuids, slot * vplayers_uuid_stride() + byte,
               vt_at(table.uuids, (slot + 1) * vplayers_uuid_stride() + byte))
        byte = byte + 1
    byte = 0
    while byte < vplayers_name_stride():
        vt_put(table.names, slot * vplayers_name_stride() + byte,
               vt_at(table.names, (slot + 1) * vplayers_name_stride() + byte))
        byte = byte + 1
    byte = 0
    while byte < vplayers_display_stride():
        vt_put(table.displays, slot * vplayers_display_stride() + byte,
               vt_at(table.displays,
                     (slot + 1) * vplayers_display_stride() + byte))
        byte = byte + 1
    vt_iset(table.game_mode, slot, vt_iget(table.game_mode, slot + 1))
    vt_iset(table.latency, slot, vt_iget(table.latency, slot + 1))
    vt_iset(table.priority, slot, vt_iget(table.priority, slot + 1))
    vt_iset(table.hat, slot, vt_iget(table.hat, slot + 1))
    vt_iset(table.listed, slot, vt_iget(table.listed, slot + 1))
    vt_iset(table.properties, slot, vt_iget(table.properties, slot + 1))
    vt_iset(table.chat_session, slot, vt_iget(table.chat_session, slot + 1))


# Player Remove carries the uuids of everyone who left, and a stale row would
# keep showing a player in the tab list and let chat resolve a name nobody owns.
public def vplayers_remove(table: VPlayers*, body: int64[],
                           offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return 0
    int last = table.count - 1
    while slot < last:
        vplayers_copy_down(table, slot)
        slot = slot + 1
    table.count = last
    return 1


public def vplayers_active_count(table: VPlayers*) -> int:
    if table == null:
        return 0
    return table.count


public def vplayers_listed_count(table: VPlayers*) -> int:
    if table == null:
        return 0
    int found = 0
    int slot = 0
    while slot < table.count:
        if vt_iget(table.listed, slot) != 0:
            found = found + 1
        slot = slot + 1
    return found


public def vplayers_row_uuid(table: VPlayers*, slot: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return vplayers_absent()
    return (int)(vt_at(table.uuids, slot * vplayers_uuid_stride()) & 0xFF)


public def vplayers_row_name_byte(table: VPlayers*, slot: int,
                                  index: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return 0
    if index < 0 or index >= vplayers_name_stride():
        return 0
    return (int)(vt_at(table.names, slot * vplayers_name_stride() + index)
                 & 0xFF)


public def vplayers_row_display_byte(table: VPlayers*, slot: int,
                                     index: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return 0
    if index < 0 or index >= vplayers_display_stride():
        return 0
    return (int)(vt_at(table.displays, slot * vplayers_display_stride() + index)
                 & 0xFF)


public def vplayers_row_length(table: VPlayers*, slot: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return vplayers_absent()
    int index = 0
    while index < vplayers_name_stride():
        if vt_at(table.names, slot * vplayers_name_stride() + index) == 0:
            return index
        index = index + 1
    return index


public def vplayers_row_display_length(table: VPlayers*, slot: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return vplayers_absent()
    int index = 0
    while index < vplayers_display_stride():
        if vt_at(table.displays,
                 slot * vplayers_display_stride() + index) == 0:
            return index
        index = index + 1
    return index


public def vplayers_game_mode(table: VPlayers*, body: int64[],
                              offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.game_mode, slot)


public def vplayers_latency(table: VPlayers*, body: int64[],
                            offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.latency, slot)


public def vplayers_priority(table: VPlayers*, body: int64[],
                             offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.priority, slot)


public def vplayers_hat(table: VPlayers*, body: int64[], offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.hat, slot)


public def vplayers_is_listed(table: VPlayers*, body: int64[],
                              offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.listed, slot)


public def vplayers_properties(table: VPlayers*, body: int64[],
                               offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.properties, slot)


public def vplayers_has_chat(table: VPlayers*, body: int64[],
                             offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.chat_session, slot)


# Lookup by name, for the paths that only have the chat sender's text: the name
# column is compared byte by byte so no copy is needed.
public def vplayers_slot_by_name(table: VPlayers*, text: str) -> int:
    if table == null:
        return vplayers_absent()
    int wanted = text_len(text)
    if wanted <= 0 or wanted >= vplayers_name_stride():
        return vplayers_absent()
    int slot = 0
    while slot < table.count:
        if vplayers_row_length(table, slot) == wanted:
            int index = 0
            int same = 1
            while index < wanted:
                int stored = vplayers_row_name_byte(table, slot, index)
                if stored != code_at(text, index):
                    same = 0
                    index = wanted
                index = index + 1
            if same == 1:
                return slot
        slot = slot + 1
    return vplayers_absent()


public def vplayers_name_at(table: VPlayers*, slot: int,
                            out: int64[]) -> int:
    int length = vplayers_row_length(table, slot)
    if length < 0:
        return 0
    int capacity = (int)len(out)
    if length > capacity:
        length = capacity
    int index = 0
    while index < length:
        out[index] = vplayers_row_name_byte(table, slot, index)
        index = index + 1
    return length


# The header and footer belong to the list rather than to a row, and the packet
# that carries them is allowed to clear either one by sending an absent
# component - which the caller represents as a zero length.
public def vplayers_set_header(table: VPlayers*, source: int64[],
                              length: int64) -> void:
    vplayers_write(table.header, vplayers_display_stride(), 0, source, 0,
                   length)


public def vplayers_set_footer(table: VPlayers*, source: int64[],
                              length: int64) -> void:
    vplayers_write(table.footer, vplayers_display_stride(), 0, source, 0,
                   length)


public def vplayers_header_length(table: VPlayers*) -> int:
    if table == null:
        return vplayers_absent()
    int index = 0
    while index < vplayers_display_stride():
        if vt_at(table.header, index) == 0:
            return index
        index = index + 1
    return index


public def vplayers_footer_length(table: VPlayers*) -> int:
    if table == null:
        return vplayers_absent()
    int index = 0
    while index < vplayers_display_stride():
        if vt_at(table.footer, index) == 0:
            return index
        index = index + 1
    return index


public def vplayers_header_byte(table: VPlayers*, index: int) -> int:
    if table == null or index < 0 or index >= vplayers_display_stride():
        return 0
    return (int)(vt_at(table.header, index) & 0xFF)


public def vplayers_footer_byte(table: VPlayers*, index: int) -> int:
    if table == null or index < 0 or index >= vplayers_display_stride():
        return 0
    return (int)(vt_at(table.footer, index) & 0xFF)


# ===== blockentities.cpy =====
# Vortex engine - block entity registry.
#
# The Block Entity Data packet says "the tile entity at this position now reads
# like this"; the payload itself is an NBT compound whose fields differ per
# block type, and this backend does not render chests or signs yet. What it does
# need is the set of positions that *have* a block entity, because that is what
# tells the mesher a cube is not the whole story and tells the HUD how many
# tiles are live.
#
# Positions are stored as the three components the protocol unpacks to, not the
# packed 64-bit form: the packed value uses the whole 64-bit range, and a signed
# comparison against it is the kind of thing that quietly stops matching after a
# world border. Three int columns compare exactly and cost one extra load.
#
# The action byte is kept because the vanilla client uses it to pick which
# block-specific handler runs; recording it is enough to drive that dispatch
# later without re-reading the packet.
#
# The compiler resolves calls against what it has already read, so the helpers
# below are ordered bottom up.


def vbes_capacity() -> int:
    return 4096


public def vbes_absent() -> int:
    return -1


# The action values the protocol defines; -1 is the removal marker and is never
# stored, it only clears the row.
public def vbes_action_create() -> int:
    return 0


public def vbes_action_retype() -> int:
    return 1


public def vbes_action_invalidate() -> int:
    return 2


public def vbes_action_query() -> int:
    return 3


public def vbes_max_action() -> int:
    return 3


struct VBlockEntities:
    int count
    int* x
    int* y
    int* z
    int* action
    int* payload
    int* present


public def vbes_new() -> VBlockEntities*:
    VBlockEntities* table = new VBlockEntities
    table.count = 0
    table.x = vt_calloc_int(vbes_capacity())
    table.y = vt_calloc_int(vbes_capacity())
    table.z = vt_calloc_int(vbes_capacity())
    table.action = vt_calloc_int(vbes_capacity())
    table.payload = vt_calloc_int(vbes_capacity())
    table.present = vt_calloc_int(vbes_capacity())
    return table


public def vbes_free(table: VBlockEntities*) -> void:
    if table == null:
        return
    vt_free((void*)table.x)
    vt_free((void*)table.y)
    vt_free((void*)table.z)
    vt_free((void*)table.action)
    vt_free((void*)table.payload)
    vt_free((void*)table.present)
    del table


def vbes_find(table: VBlockEntities*, x: int, y: int, z: int) -> int:
    if table == null:
        return vbes_absent()
    int index = 0
    while index < vbes_capacity():
        if vt_iget(table.present, index) == 1:
            if vt_iget(table.x, index) == x:
                if vt_iget(table.y, index) == y:
                    if vt_iget(table.z, index) == z:
                        return index
        index = index + 1
    return vbes_absent()


def vbes_slot(table: VBlockEntities*, x: int, y: int, z: int) -> int:
    int existing = vbes_find(table, x, y, z)
    if existing >= 0:
        return existing
    int index = 0
    while index < vbes_capacity():
        if vt_iget(table.present, index) == 0:
            vt_iset(table.present, index, 1)
            vt_iset(table.x, index, x)
            vt_iset(table.y, index, y)
            vt_iset(table.z, index, z)
            table.count = table.count + 1
            return index
        index = index + 1
    return vbes_absent()


# An update replaces the action and the payload size rather than merging: the
# packet always describes the tile completely, and a stale size would keep a
# renderer asking for bytes that no longer exist.
public def vbes_set(table: VBlockEntities*, x: int, y: int, z: int,
                   action: int, payload: int) -> int:
    int slot = vbes_slot(table, x, y, z)
    if slot < 0:
        return 0
    vt_iset(table.action, slot, action)
    vt_iset(table.payload, slot, payload)
    return 1


public def vbes_remove(table: VBlockEntities*, x: int, y: int,
                       z: int) -> int:
    int slot = vbes_find(table, x, y, z)
    if slot < 0:
        return 0
    vt_iset(table.present, slot, 0)
    vt_iset(table.x, slot, 0)
    vt_iset(table.y, slot, 0)
    vt_iset(table.z, slot, 0)
    vt_iset(table.action, slot, 0)
    vt_iset(table.payload, slot, 0)
    table.count = table.count - 1
    return 1


public def vbes_has(table: VBlockEntities*, x: int, y: int, z: int) -> int:
    if vbes_find(table, x, y, z) < 0:
        return 0
    return 1


public def vbes_action(table: VBlockEntities*, x: int, y: int,
                       z: int) -> int:
    int slot = vbes_find(table, x, y, z)
    if slot < 0:
        return vbes_absent()
    return vt_iget(table.action, slot)


public def vbes_payload(table: VBlockEntities*, x: int, y: int,
                        z: int) -> int:
    int slot = vbes_find(table, x, y, z)
    if slot < 0:
        return vbes_absent()
    return vt_iget(table.payload, slot)


public def vbes_count(table: VBlockEntities*) -> int:
    if table == null:
        return 0
    return table.count


public def vbes_row_x(table: VBlockEntities*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vbes_capacity():
        return vbes_absent()
    if vt_iget(table.present, slot) != 1:
        return vbes_absent()
    return vt_iget(table.x, slot)


public def vbes_row_y(table: VBlockEntities*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vbes_capacity():
        return vbes_absent()
    if vt_iget(table.present, slot) != 1:
        return vbes_absent()
    return vt_iget(table.y, slot)


public def vbes_row_z(table: VBlockEntities*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vbes_capacity():
        return vbes_absent()
    if vt_iget(table.present, slot) != 1:
        return vbes_absent()
    return vt_iget(table.z, slot)


public def vbes_row_action(table: VBlockEntities*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vbes_capacity():
        return vbes_absent()
    if vt_iget(table.present, slot) != 1:
        return vbes_absent()
    return vt_iget(table.action, slot)


public def vbes_row_payload(table: VBlockEntities*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vbes_capacity():
        return vbes_absent()
    if vt_iget(table.present, slot) != 1:
        return vbes_absent()
    return vt_iget(table.payload, slot)


# ===== particles.cpy =====
# Vortex engine - the particle queue.
#
# World Particles is an emitter description, not a persistent object: the server
# says "put N particles of this kind at this point with these spreads" and the
# renderer owns everything after that. What the backend has to keep is therefore
# a short ring of emitter records, newest overwriting oldest, because a burst
# from a server that spam-particles an area must not grow without bound.
#
# Positions stay double; spreads are quantised to thousandths. An offset is
# always a small fraction of a block, so a third of a millimetre is finer than
# the geometry it jitters, and three ints per record is cheaper than three more
# doubles the renderer would only read once.
#
# The kind-specific payload is stored verbatim rather than reduced to a couple
# of ints: the protocol gives each particle a different record - a blockstate, a
# colour and a scale, an item stack, a target position plus a colour and a
# duration - and the widest one fits in vparts_payload_stride() words, so
# nothing the renderer needs is thrown away. A word holds the field exactly as
# it arrived: a double occupies one word with its wire bit pattern, an integer
# occupies one, and a float is widened to the double it denotes so a renderer
# never has to know which wire width a particular field used.
#
# The compiler resolves calls against what it has already read, so the helpers
# below are ordered bottom up.


public def vparts_capacity() -> int:
    return 1024


public def vparts_absent() -> int:
    return -1


# The no-payload marker for a word index outside the stored record.
public def vparts_no_data() -> int:
    return -1


# Words per record. The widest payload in the 26.3 registry is the vibration
# particle's selector, target, eye height and duration.
public def vparts_payload_stride() -> int:
    return 6


def vparts_quantum() -> int:
    return 1000


public def vparts_flag_long_distance() -> int:
    return 1


public def vparts_flag_always_show() -> int:
    return 2


# The particle ids whose payload is a single blockstate id. The renderer needs
# the model rather than the number, so which ones they are has to be visible
# here; the protocol layer uses this to decide whether to read one varint and
# nothing else.
public def vparts_kind_block() -> int:
    return 1


public def vparts_kind_block_marker() -> int:
    return 2


public def vparts_kind_falling_dust() -> int:
    return 29


public def vparts_kind_dust_pillar() -> int:
    return 111


public def vparts_kind_block_crumble() -> int:
    return 115


public def vparts_kind_dust() -> int:
    return 14


public def vparts_kind_dust_color_transition() -> int:
    return 15


public def vparts_kind_effect() -> int:
    return 16


public def vparts_kind_entity_effect() -> int:
    return 21


public def vparts_kind_dragon_breath() -> int:
    return 23


public def vparts_kind_tinted_leaves() -> int:
    return 36


public def vparts_kind_sculk_charge() -> int:
    return 38


public def vparts_kind_flash() -> int:
    return 42


public def vparts_kind_instant_effect() -> int:
    return 46


public def vparts_kind_item() -> int:
    return 47


public def vparts_kind_vibration() -> int:
    return 48


public def vparts_kind_trail() -> int:
    return 49


public def vparts_kind_shriek() -> int:
    return 105


# The highest id the 26.3 particle registry defines; anything above it means
# the server is speaking a dialect this client has not read.
public def vparts_kind_max() -> int:
    return 116


# A vibration references either a block position or an entity, and the entity
# case is the one that carries an eye height.
public def vparts_vibration_position() -> int:
    return 0


public def vparts_vibration_entity() -> int:
    return 1


# True when a blockstate id is the only thing the kind carries.
public def vparts_kind_is_blockstate(kind: int) -> int:
    if kind == vparts_kind_block():
        return 1
    if kind == vparts_kind_block_marker():
        return 1
    if kind == vparts_kind_falling_dust():
        return 1
    if kind == vparts_kind_dust_pillar():
        return 1
    if kind == vparts_kind_block_crumble():
        return 1
    return 0


# Number of payload words a kind is expected to carry, used both to size the
# storage and to check that the protocol layer stored the whole record.
public def vparts_kind_payload_words(kind: int) -> int:
    if vparts_kind_is_blockstate(kind) == 1:
        return 1
    if kind == vparts_kind_dust():
        return 2
    if kind == vparts_kind_dust_color_transition():
        return 3
    if kind == vparts_kind_effect():
        return 2
    if kind == vparts_kind_instant_effect():
        return 2
    if kind == vparts_kind_entity_effect():
        return 1
    if kind == vparts_kind_tinted_leaves():
        return 1
    if kind == vparts_kind_flash():
        return 1
    if kind == vparts_kind_sculk_charge():
        return 1
    if kind == vparts_kind_dragon_breath():
        return 1
    if kind == vparts_kind_item():
        return 2
    if kind == vparts_kind_shriek():
        return 1
    if kind == vparts_kind_trail():
        return 5
    return 0


struct VParticles:
    int count
    int head
    int* kind
    int* amount
    int* flags
    int* payload_length
    int* offset_x
    int* offset_y
    int* offset_z
    int* velocity
    uint64* payload
    uint64* x
    uint64* y
    uint64* z


public def vparts_new() -> VParticles*:
    VParticles* table = new VParticles
    table.count = 0
    table.head = 0
    table.kind = vt_calloc_int(vparts_capacity())
    table.amount = vt_calloc_int(vparts_capacity())
    table.flags = vt_calloc_int(vparts_capacity())
    table.payload_length = vt_calloc_int(vparts_capacity())
    table.offset_x = vt_calloc_int(vparts_capacity())
    table.offset_y = vt_calloc_int(vparts_capacity())
    table.offset_z = vt_calloc_int(vparts_capacity())
    table.velocity = vt_calloc_int(vparts_capacity())
    table.payload = vt_calloc_u64(vparts_capacity() *
                                  vparts_payload_stride())
    table.x = vt_calloc_u64(vparts_capacity())
    table.y = vt_calloc_u64(vparts_capacity())
    table.z = vt_calloc_u64(vparts_capacity())
    return table


public def vparts_free(table: VParticles*) -> void:
    if table == null:
        return
    vt_free((void*)table.kind)
    vt_free((void*)table.amount)
    vt_free((void*)table.flags)
    vt_free((void*)table.payload_length)
    vt_free((void*)table.offset_x)
    vt_free((void*)table.offset_y)
    vt_free((void*)table.offset_z)
    vt_free((void*)table.velocity)
    vt_free((void*)table.payload)
    vt_free((void*)table.x)
    vt_free((void*)table.y)
    vt_free((void*)table.z)
    del table


# Appending always succeeds: the oldest slot is reused. A renderer that is
# behind by a thousand emitters has already missed them, and refusing the new
# one would keep it drawing a burst that ended minutes ago. A payload wider
# than the stride is the one caller error that is refused, because storing it
# truncated would leave a renderer reading a word that belongs to the
# neighbouring record.
public def vparts_push(table: VParticles*, kind: int, x: double, y: double,
                       z: double, offset_x: int, offset_y: int,
                       offset_z: int, velocity: int, amount: int, flags: int,
                       payload: int64[], payload_length: int) -> int:
    if table == null:
        return vparts_absent()
    if payload_length > vparts_payload_stride():
        return vparts_absent()
    int slot = table.head
    table.head = table.head + 1
    if table.head >= vparts_capacity():
        table.head = 0
    if table.count < vparts_capacity():
        table.count = table.count + 1
    vt_iset(table.kind, slot, kind)
    vt_iset(table.amount, slot, amount)
    vt_iset(table.flags, slot, flags)
    vt_iset(table.payload_length, slot, payload_length)
    vt_iset(table.offset_x, slot, offset_x)
    vt_iset(table.offset_y, slot, offset_y)
    vt_iset(table.offset_z, slot, offset_z)
    vt_iset(table.velocity, slot, velocity)
    vt_uset(table.x, slot, vt_double_to_bits(x))
    vt_uset(table.y, slot, vt_double_to_bits(y))
    vt_uset(table.z, slot, vt_double_to_bits(z))
    int index = 0
    while index < payload_length:
        vt_uset(table.payload, slot * vparts_payload_stride() + index,
                (uint64)payload[index])
        index = index + 1
    return slot


public def vparts_clear(table: VParticles*) -> void:
    if table == null:
        return
    int index = 0
    while index < vparts_capacity():
        vt_iset(table.kind, index, 0)
        vt_iset(table.amount, index, 0)
        vt_iset(table.flags, index, 0)
        vt_iset(table.payload_length, index, 0)
        vt_iset(table.offset_x, index, 0)
        vt_iset(table.offset_y, index, 0)
        vt_iset(table.offset_z, index, 0)
        vt_iset(table.velocity, index, 0)
        vt_uset(table.x, index, 0)
        vt_uset(table.y, index, 0)
        vt_uset(table.z, index, 0)
        int slot = 0
        while slot < vparts_payload_stride():
            vt_uset(table.payload,
                    index * vparts_payload_stride() + slot, 0)
            slot = slot + 1
        index = index + 1
    table.count = 0
    table.head = 0


public def vparts_count(table: VParticles*) -> int:
    if table == null:
        return 0
    return table.count


# Rows are read in the order they were pushed, which is what a renderer
# emitting one batch per frame wants; slot 0 is the record pushed least
# recently once the ring wraps.
public def vparts_row(table: VParticles*, index: int) -> int:
    if table == null or index < 0 or index >= table.count:
        return vparts_absent()
    int slot = table.head - table.count
    slot = slot + index
    while slot < 0:
        slot = slot + vparts_capacity()
    return slot


public def vparts_row_kind(table: VParticles*, index: int) -> int:
    int slot = vparts_row(table, index)
    if slot < 0:
        return vparts_absent()
    return vt_iget(table.kind, slot)


public def vparts_row_amount(table: VParticles*, index: int) -> int:
    int slot = vparts_row(table, index)
    if slot < 0:
        return vparts_absent()
    return vt_iget(table.amount, slot)


public def vparts_row_flags(table: VParticles*, index: int) -> int:
    int slot = vparts_row(table, index)
    if slot < 0:
        return vparts_absent()
    return vt_iget(table.flags, slot)


public def vparts_row_payload_length(table: VParticles*, index: int) -> int:
    int slot = vparts_row(table, index)
    if slot < 0:
        return vparts_absent()
    return vt_iget(table.payload_length, slot)


# Word `word` of the record's kind-specific payload. Reading outside the stored
# length gives back the no-payload marker, so a renderer that guesses a shape
# gets nothing useful rather than the neighbouring record's data.
public def vparts_row_payload(table: VParticles*, index: int,
                              word: int) -> int64:
    int slot = vparts_row(table, index)
    if slot < 0:
        return (int64)vparts_absent()
    if word < 0 or word >= vt_iget(table.payload_length, slot):
        return (int64)vparts_no_data()
    return (int64)vt_uget(table.payload,
                          slot * vparts_payload_stride() + word)


public def vparts_row_payload_double(table: VParticles*, index: int,
                                     word: int) -> double:
    int slot = vparts_row(table, index)
    if slot < 0:
        return 0.0
    if word < 0 or word >= vt_iget(table.payload_length, slot):
        return 0.0
    return vt_bits_to_double(vt_uget(table.payload,
                                     slot * vparts_payload_stride() + word))


public def vparts_row_x(table: VParticles*, index: int) -> double:
    int slot = vparts_row(table, index)
    if slot < 0:
        return 0.0
    return vt_bits_to_double(vt_uget(table.x, slot))


public def vparts_row_y(table: VParticles*, index: int) -> double:
    int slot = vparts_row(table, index)
    if slot < 0:
        return 0.0
    return vt_bits_to_double(vt_uget(table.y, slot))


public def vparts_row_z(table: VParticles*, index: int) -> double:
    int slot = vparts_row(table, index)
    if slot < 0:
        return 0.0
    return vt_bits_to_double(vt_uget(table.z, slot))


public def vparts_quantise(value: double) -> int:
    int scaled = (int)(value * (double)vparts_quantum())
    return scaled


public def vparts_unquantise(scaled: int) -> double:
    return (double)scaled / (double)vparts_quantum()


public def vparts_row_offset_x(table: VParticles*, index: int) -> int:
    int slot = vparts_row(table, index)
    if slot < 0:
        return vparts_absent()
    return vt_iget(table.offset_x, slot)


public def vparts_row_offset_y(table: VParticles*, index: int) -> int:
    int slot = vparts_row(table, index)
    if slot < 0:
        return vparts_absent()
    return vt_iget(table.offset_y, slot)


public def vparts_row_offset_z(table: VParticles*, index: int) -> int:
    int slot = vparts_row(table, index)
    if slot < 0:
        return vparts_absent()
    return vt_iget(table.offset_z, slot)


public def vparts_row_velocity(table: VParticles*, index: int) -> int:
    int slot = vparts_row(table, index)
    if slot < 0:
        return vparts_absent()
    return vt_iget(table.velocity, slot)


# ===== inventory.cpy =====
# Vortex engine - the containers, carried item and equipment the server owns.
#
# Four packets write this table and one closes it:
#
#   open_screen           window id VarInt, inventory type VarInt, title NBT
#   container_set_slot    window id VarInt, state id VarInt, slot Short, Slot
#   container_set_content window id VarInt, state id VarInt, Slot array, Slot
#   set_player_inventory  slot id VarInt, Slot            (the player window)
#   set_cursor_item       Slot                            (the mouse cursor)
#   set_equipment         entity id VarInt, then a top-bit terminated array of
#                         { slot Byte, Slot } where bit 7 of the slot byte
#                         means another entry follows
#   container_close       window id VarInt
#
# Window 0 is the player's own inventory and is always open: 46 slots, of which
# 0 to 8 are the hotbar the held slot indexes. Every other window comes from
# open_screen and lives until the server closes it or the session ends.
#
# The state id is the server's resynchronisation counter. A click echoes the
# last one it saw, so keeping it per window is what lets the client tell a
# stale confirmation from a current one.


public def vinv_window_max() -> int:
    return 16


public def vinv_slot_max() -> int:
    return 128


public def vinv_player_window() -> int:
    return 0


public def vinv_player_slots() -> int:
    return 46


public def vinv_hotbar_slots() -> int:
    return 9


public def vinv_equip_max() -> int:
    return 512


public def vinv_equip_slots() -> int:
    return 8


public def vinv_property_max() -> int:
    return 64


public def vinv_absent() -> int:
    return -1


public def vinv_empty() -> int:
    return 0


struct VInventory:
    int* window_id
    int* window_kind
    int* window_state
    int* window_slots
    int* window_open
    int* item
    int* amount
    int carried_item
    int carried_count
    int held_slot
    int active_window
    int* equip_entity
    int* equip_slot
    int* equip_item
    int* equip_count
    int equip_rows
    int* prop_window
    int* prop_index
    int* prop_value
    int prop_rows


public def vinv_new() -> VInventory*:
    VInventory* table = new VInventory
    table.window_id = vt_calloc_int(vinv_window_max())
    table.window_kind = vt_calloc_int(vinv_window_max())
    table.window_state = vt_calloc_int(vinv_window_max())
    table.window_slots = vt_calloc_int(vinv_window_max())
    table.window_open = vt_calloc_int(vinv_window_max())
    int cells = vinv_window_max() * vinv_slot_max()
    table.item = vt_calloc_int(cells)
    table.amount = vt_calloc_int(cells)
    table.equip_entity = vt_calloc_int(vinv_equip_max())
    table.equip_slot = vt_calloc_int(vinv_equip_max())
    table.equip_item = vt_calloc_int(vinv_equip_max())
    table.equip_count = vt_calloc_int(vinv_equip_max())
    table.prop_window = vt_calloc_int(vinv_property_max())
    table.prop_index = vt_calloc_int(vinv_property_max())
    table.prop_value = vt_calloc_int(vinv_property_max())
    table.carried_item = vinv_empty()
    table.carried_count = 0
    table.held_slot = 0
    table.active_window = vinv_player_window()
    table.equip_rows = 0
    table.prop_rows = 0
    vt_iset(table.window_id, 0, vinv_player_window())
    vt_iset(table.window_open, 0, 1)
    vt_iset(table.window_slots, 0, vinv_player_slots())
    return table


public def vinv_free(table: VInventory*) -> void:
    if table == null:
        return
    vt_free((void*)table.window_id)
    vt_free((void*)table.window_kind)
    vt_free((void*)table.window_state)
    vt_free((void*)table.window_slots)
    vt_free((void*)table.window_open)
    vt_free((void*)table.item)
    vt_free((void*)table.amount)
    vt_free((void*)table.equip_entity)
    vt_free((void*)table.equip_slot)
    vt_free((void*)table.equip_item)
    vt_free((void*)table.equip_count)
    vt_free((void*)table.prop_window)
    vt_free((void*)table.prop_index)
    vt_free((void*)table.prop_value)
    del table


def vinv_cell(table: VInventory*, window: int, slot: int) -> int:
    if window < 0 or window >= vinv_window_max():
        return vinv_absent()
    if slot < 0 or slot >= vt_iget(table.window_slots, window):
        return vinv_absent()
    return window * vinv_slot_max() + slot


public def vinv_find(table: VInventory*, window_id: int) -> int:
    if table == null:
        return vinv_absent()
    int index = 0
    while index < vinv_window_max():
        if vt_iget(table.window_open, index) == 1:
            if vt_iget(table.window_id, index) == window_id:
                return index
        index = index + 1
    return vinv_absent()


def vinv_clear_cells(table: VInventory*, window: int) -> void:
    int slot = 0
    while slot < vinv_slot_max():
        vt_iset(table.item, window * vinv_slot_max() + slot, vinv_empty())
        vt_iset(table.amount, window * vinv_slot_max() + slot, 0)
        slot = slot + 1


def vinv_reserve(table: VInventory*, window_id: int, kind: int,
                 slots: int) -> int:
    if slots < 0 or slots > vinv_slot_max():
        return 1
    int existing = vinv_find(table, window_id)
    if existing >= 0:
        vt_iset(table.window_kind, existing, kind)
        vt_iset(table.window_slots, existing, slots)
        vinv_clear_cells(table, existing)
        return 0
    int index = 0
    while index < vinv_window_max():
        if vt_iget(table.window_open, index) == 0:
            vt_iset(table.window_id, index, window_id)
            vt_iset(table.window_kind, index, kind)
            vt_iset(table.window_slots, index, slots)
            vt_iset(table.window_state, index, 0)
            vt_iset(table.window_open, index, 1)
            vinv_clear_cells(table, index)
            return 0
        index = index + 1
    return 1


public def vinv_open(table: VInventory*, window_id: int, kind: int,
                     slots: int) -> int:
    if table == null or window_id < 0:
        return 1
    if vinv_reserve(table, window_id, kind, slots) != 0:
        return 1
    table.active_window = window_id
    return 0


# The player window is never closed, so a close on window 0 only clears the
# mouse cursor and returns the player to their own inventory.
public def vinv_close(table: VInventory*, window_id: int) -> int:
    if table == null:
        return 1
    int index = vinv_find(table, window_id)
    if index < 0:
        return 1
    if window_id == vinv_player_window():
        table.carried_item = vinv_empty()
        table.carried_count = 0
        table.active_window = vinv_player_window()
        return 0
    vt_iset(table.window_open, index, 0)
    vt_iset(table.window_slots, index, 0)
    vinv_clear_cells(table, index)
    if table.active_window == window_id:
        table.active_window = vinv_player_window()
    return 0


public def vinv_close_all(table: VInventory*) -> void:
    if table == null:
        return
    int index = 1
    while index < vinv_window_max():
        if vt_iget(table.window_open, index) == 1:
            vinv_close(table, vt_iget(table.window_id, index))
        index = index + 1
    table.carried_item = vinv_empty()
    table.carried_count = 0
    table.active_window = vinv_player_window()


public def vinv_is_open(table: VInventory*, window_id: int) -> int:
    if vinv_find(table, window_id) < 0:
        return 0
    return 1


public def vinv_kind(table: VInventory*, window_id: int) -> int:
    int index = vinv_find(table, window_id)
    if index < 0:
        return vinv_absent()
    return vt_iget(table.window_kind, index)


public def vinv_slot_count(table: VInventory*, window_id: int) -> int:
    int index = vinv_find(table, window_id)
    if index < 0:
        return 0
    return vt_iget(table.window_slots, index)


public def vinv_state_id(table: VInventory*, window_id: int) -> int:
    int index = vinv_find(table, window_id)
    if index < 0:
        return 0
    return vt_iget(table.window_state, index)


public def vinv_set_state_id(table: VInventory*, window_id: int,
                             state_id: int) -> int:
    int index = vinv_find(table, window_id)
    if index < 0:
        return 1
    vt_iset(table.window_state, index, state_id)
    return 0


public def vinv_set_slot(table: VInventory*, window_id: int, slot: int,
                         item: int, count: int) -> int:
    if table == null:
        return 1
    int window = vinv_find(table, window_id)
    if window < 0:
        return 1
    int cell = vinv_cell(table, window, slot)
    if cell < 0:
        return 1
    if count <= 0 or item < 0:
        vt_iset(table.item, cell, vinv_empty())
        vt_iset(table.amount, cell, 0)
        return 0
    vt_iset(table.item, cell, item)
    vt_iset(table.amount, cell, count)
    return 0


public def vinv_item(table: VInventory*, window_id: int, slot: int) -> int:
    if table == null:
        return vinv_empty()
    int cell = vinv_cell(table, vinv_find(table, window_id), slot)
    if cell < 0:
        return vinv_empty()
    return vt_iget(table.item, cell)


public def vinv_amount(table: VInventory*, window_id: int, slot: int) -> int:
    if table == null:
        return 0
    int cell = vinv_cell(table, vinv_find(table, window_id), slot)
    if cell < 0:
        return 0
    return vt_iget(table.amount, cell)


public def vinv_filled(table: VInventory*, window_id: int) -> int:
    int window = vinv_find(table, window_id)
    if window < 0:
        return 0
    int slots = vt_iget(table.window_slots, window)
    int filled = 0
    int slot = 0
    while slot < slots:
        if vt_iget(table.amount, window * vinv_slot_max() + slot) > 0:
            filled = filled + 1
        slot = slot + 1
    return filled


# A content packet replaces the whole window, so it also resizes it: the count
# on the wire is the authority on how many slots the container has.
public def vinv_set_content(table: VInventory*, window_id: int, state_id: int,
                            count: int) -> int:
    if table == null or count < 0:
        return 1
    int window = vinv_find(table, window_id)
    int kind = 0
    if window >= 0:
        kind = vt_iget(table.window_kind, window)
    if vinv_reserve(table, window_id, kind, count) != 0:
        return 1
    return vinv_set_state_id(table, window_id, state_id)


public def vinv_set_carried(table: VInventory*, item: int, count: int) -> int:
    if table == null:
        return 1
    if count <= 0 or item < 0:
        table.carried_item = vinv_empty()
        table.carried_count = 0
        return 0
    table.carried_item = item
    table.carried_count = count
    return 0


public def vinv_carried_item(table: VInventory*) -> int:
    if table == null:
        return vinv_empty()
    return table.carried_item


public def vinv_carried_count(table: VInventory*) -> int:
    if table == null:
        return 0
    return table.carried_count


public def vinv_set_held(table: VInventory*, slot: int) -> int:
    if table == null or slot < 0 or slot >= vinv_hotbar_slots():
        return 1
    table.held_slot = slot
    return 0


public def vinv_held(table: VInventory*) -> int:
    if table == null:
        return 0
    return table.held_slot


public def vinv_held_item(table: VInventory*) -> int:
    if table == null:
        return vinv_empty()
    return vinv_item(table, vinv_player_window(), table.held_slot)


public def vinv_held_count(table: VInventory*) -> int:
    if table == null:
        return 0
    return vinv_amount(table, vinv_player_window(), table.held_slot)


public def vinv_active(table: VInventory*) -> int:
    if table == null:
        return vinv_player_window()
    return table.active_window


def vinv_equip_find(table: VInventory*, entity: int, slot: int) -> int:
    int row = 0
    while row < table.equip_rows:
        if vt_iget(table.equip_entity, row) == entity:
            if vt_iget(table.equip_slot, row) == slot:
                return row
        row = row + 1
    return vinv_absent()


public def vinv_set_equipment(table: VInventory*, entity: int, slot: int,
                              item: int, count: int) -> int:
    if table == null or entity < 0:
        return 1
    if slot < 0 or slot >= vinv_equip_slots():
        return 1
    int row = vinv_equip_find(table, entity, slot)
    if row < 0:
        if table.equip_rows >= vinv_equip_max():
            return 1
        row = table.equip_rows
        table.equip_rows = row + 1
        vt_iset(table.equip_entity, row, entity)
        vt_iset(table.equip_slot, row, slot)
    if count <= 0 or item < 0:
        vt_iset(table.equip_item, row, vinv_empty())
        vt_iset(table.equip_count, row, 0)
        return 0
    vt_iset(table.equip_item, row, item)
    vt_iset(table.equip_count, row, count)
    return 0


public def vinv_equipment_item(table: VInventory*, entity: int,
                               slot: int) -> int:
    if table == null:
        return vinv_empty()
    int row = vinv_equip_find(table, entity, slot)
    if row < 0:
        return vinv_empty()
    return vt_iget(table.equip_item, row)


public def vinv_equipment_count(table: VInventory*, entity: int,
                                slot: int) -> int:
    if table == null:
        return 0
    int row = vinv_equip_find(table, entity, slot)
    if row < 0:
        return 0
    return vt_iget(table.equip_count, row)


public def vinv_equipment_rows(table: VInventory*) -> int:
    if table == null:
        return 0
    return table.equip_rows


public def vinv_equipment_row_entity(table: VInventory*, row: int) -> int:
    if table == null or row < 0 or row >= table.equip_rows:
        return vinv_absent()
    return vt_iget(table.equip_entity, row)


public def vinv_equipment_row_slot(table: VInventory*, row: int) -> int:
    if table == null or row < 0 or row >= table.equip_rows:
        return vinv_absent()
    return vt_iget(table.equip_slot, row)


public def vinv_equipment_row_item(table: VInventory*, row: int) -> int:
    if table == null or row < 0 or row >= table.equip_rows:
        return vinv_empty()
    return vt_iget(table.equip_item, row)


public def vinv_equipment_row_count(table: VInventory*, row: int) -> int:
    if table == null or row < 0 or row >= table.equip_rows:
        return 0
    return vt_iget(table.equip_count, row)


public def vinv_clear_equipment(table: VInventory*, entity: int) -> void:
    if table == null:
        return
    int row = 0
    while row < table.equip_rows:
        if vt_iget(table.equip_entity, row) == entity:
            vt_iset(table.equip_item, row, vinv_empty())
            vt_iset(table.equip_count, row, 0)
        row = row + 1


# Craft progress bars and furnace burn times: a window property is a short
# index and a short value, and the renderer reads it by index.
public def vinv_set_property(table: VInventory*, window_id: int, index: int,
                             value: int) -> int:
    if table == null or index < 0:
        return 1
    if vinv_find(table, window_id) < 0:
        return 1
    int row = 0
    while row < table.prop_rows:
        if vt_iget(table.prop_window, row) == window_id:
            if vt_iget(table.prop_index, row) == index:
                vt_iset(table.prop_value, row, value)
                return 0
        row = row + 1
    if table.prop_rows >= vinv_property_max():
        return 1
    row = table.prop_rows
    table.prop_rows = row + 1
    vt_iset(table.prop_window, row, window_id)
    vt_iset(table.prop_index, row, index)
    vt_iset(table.prop_value, row, value)
    return 0


public def vinv_property(table: VInventory*, window_id: int,
                         index: int) -> int:
    if table == null:
        return 0
    int row = 0
    while row < table.prop_rows:
        if vt_iget(table.prop_window, row) == window_id:
            if vt_iget(table.prop_index, row) == index:
                return vt_iget(table.prop_value, row)
        row = row + 1
    return 0


public def vinv_property_rows(table: VInventory*) -> int:
    if table == null:
        return 0
    return table.prop_rows

# ===== border.cpy =====
# Vortex engine - world border state.
#
# The six border packets each carry one field of the same object, so the table
# keeps the whole border and every handler updates its slice. Diameters are
# doubles because the server interpolates them; the transition speed is a
# varlong millisecond count.

public def vborder_default_diameter() -> double:
    return 59999968.0


public def vborder_default_boundary() -> int:
    return 29999984


public def vborder_default_warning_blocks() -> int:
    return 5


public def vborder_default_warning_time() -> int:
    return 15


struct VBorder:
    double center_x
    double center_z
    double diameter
    double old_diameter
    double new_diameter
    int64 lerp_remaining
    int portal_boundary
    int warning_blocks
    int warning_time
    bool initialised


public def vborder_new() -> VBorder*:
    VBorder* border = new VBorder
    border.center_x = 0.0
    border.center_z = 0.0
    border.diameter = vborder_default_diameter()
    border.old_diameter = border.diameter
    border.new_diameter = border.diameter
    border.lerp_remaining = 0
    border.portal_boundary = vborder_default_boundary()
    border.warning_blocks = vborder_default_warning_blocks()
    border.warning_time = vborder_default_warning_time()
    border.initialised = false
    return border


public def vborder_free(border: VBorder*) -> void:
    if border != null:
        del border


public def vborder_initialize(border: VBorder*, x: double, z: double,
                              old_diameter: double, new_diameter: double,
                              speed: int64, boundary: int, warning_blocks: int,
                              warning_time: int) -> int:
    if border == null or old_diameter < 0.0 or new_diameter < 0.0:
        return 1
    if speed < 0 or boundary < 1 or warning_blocks < 0 or warning_time < 0:
        return 1
    border.center_x = x
    border.center_z = z
    border.old_diameter = old_diameter
    border.new_diameter = new_diameter
    border.diameter = old_diameter
    border.lerp_remaining = speed
    border.portal_boundary = boundary
    border.warning_blocks = warning_blocks
    border.warning_time = warning_time
    border.initialised = true
    return 0


public def vborder_set_center(border: VBorder*, x: double, z: double) -> int:
    if border == null:
        return 1
    border.center_x = x
    border.center_z = z
    return 0


public def vborder_set_size(border: VBorder*, diameter: double) -> int:
    if border == null or diameter < 0.0:
        return 1
    border.diameter = diameter
    border.old_diameter = diameter
    border.new_diameter = diameter
    border.lerp_remaining = 0
    return 0


public def vborder_lerp_size(border: VBorder*, old_diameter: double,
                             new_diameter: double, speed: int64) -> int:
    if border == null or old_diameter < 0.0 or new_diameter < 0.0 or speed < 0:
        return 1
    border.old_diameter = old_diameter
    border.new_diameter = new_diameter
    border.diameter = old_diameter
    border.lerp_remaining = speed
    return 0


public def vborder_set_warning_delay(border: VBorder*, seconds: int) -> int:
    if border == null or seconds < 0:
        return 1
    border.warning_time = seconds
    return 0


public def vborder_set_warning_distance(border: VBorder*, blocks: int) -> int:
    if border == null or blocks < 0:
        return 1
    border.warning_blocks = blocks
    return 0


# Half-width of the current border, the distance a client compares against.
public def vborder_radius(border: VBorder*) -> double:
    if border == null:
        return 0.0
    return border.diameter / 2.0


public def vborder_contains(border: VBorder*, x: double, z: double) -> bool:
    if border == null:
        return true
    double radius = vborder_radius(border)
    double dx = x - border.center_x
    double dz = z - border.center_z
    if dx < 0.0:
        dx = 0.0 - dx
    if dz < 0.0:
        dz = 0.0 - dz
    return dx <= radius and dz <= radius

# ===== recipes.cpy =====
# Vortex engine - recipe property sets, the stonecutter list and the recipe book.
#
# 26.3 no longer sends whole recipes: `update_recipes` pushes named item sets
# plus the stonecutter's input/display pairs, and the recipe book streams display
# entries separately. Only the ids and categories are kept here; the display
# trees are walked for validation by src/proto/display.cpy and not retained.

public def vrecipe_set_max() -> int:
    return 64


public def vrecipe_entry_max() -> int:
    return 8192


public def vrecipe_id_stride() -> int:
    return 128


public def vrecipe_pool_max() -> int:
    return 262144


public def vrecipe_book_types() -> int:
    return 4


public def vrecipe_absent() -> int:
    return -1


struct VRecipes:
    char* set_names
    int* set_start
    int* set_count
    int set_rows
    int* pool
    int pool_used
    int* stone_input
    int* stone_display
    int stone_rows
    int* book_id
    int* book_category
    int* book_group
    int* book_flags
    int book_rows
    int* book_open
    int* book_filter


public def vrecipe_new() -> VRecipes*:
    VRecipes* book = new VRecipes
    book.set_names = vt_calloc_char(vrecipe_set_max() * vrecipe_id_stride())
    book.set_start = vt_calloc_int(vrecipe_set_max())
    book.set_count = vt_calloc_int(vrecipe_set_max())
    book.set_rows = 0
    book.pool = vt_calloc_int(vrecipe_pool_max())
    book.pool_used = 0
    book.stone_input = vt_calloc_int(vrecipe_entry_max())
    book.stone_display = vt_calloc_int(vrecipe_entry_max())
    book.stone_rows = 0
    book.book_id = vt_calloc_int(vrecipe_entry_max())
    book.book_category = vt_calloc_int(vrecipe_entry_max())
    book.book_group = vt_calloc_int(vrecipe_entry_max())
    book.book_flags = vt_calloc_int(vrecipe_entry_max())
    book.book_rows = 0
    book.book_open = vt_calloc_int(vrecipe_book_types())
    book.book_filter = vt_calloc_int(vrecipe_book_types())
    return book


public def vrecipe_free(book: VRecipes*) -> void:
    if book == null:
        return
    vt_free(book.set_names)
    vt_free(book.set_start)
    vt_free(book.set_count)
    vt_free(book.pool)
    vt_free(book.stone_input)
    vt_free(book.stone_display)
    vt_free(book.book_id)
    vt_free(book.book_category)
    vt_free(book.book_group)
    vt_free(book.book_flags)
    vt_free(book.book_open)
    vt_free(book.book_filter)
    del book


def vrecipe_name_at(arena: char*, base: int, body: int64[], offset: int64,
                    length: int64) -> int:
    int64 limit = vrecipe_id_stride() - 1
    if length > limit or length < 1:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


def vrecipe_write_name(arena: char*, base: int, body: int64[], offset: int64,
                       length: int64) -> void:
    int64 limit = vrecipe_id_stride() - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


# `update_recipes` replaces every set, so the pool is rewound rather than grown.
public def vrecipe_reset_sets(book: VRecipes*) -> int:
    if book == null:
        return 1
    book.set_rows = 0
    book.pool_used = 0
    book.stone_rows = 0
    return 0


public def vrecipe_add_set(book: VRecipes*, body: int64[], offset: int64,
                           length: int64, items: int64[], count: int) -> int:
    if book == null or count < 0 or count > vrecipe_entry_max():
        return 1
    int row = 0
    while row < book.set_rows:
        if vrecipe_name_at(book.set_names, row * vrecipe_id_stride(),
                           body, offset, length) == 1:
            break
        row = row + 1
    if row >= vrecipe_set_max():
        return 1
    if book.pool_used + count > vrecipe_pool_max():
        return 1
    if row == book.set_rows:
        vrecipe_write_name(book.set_names, row * vrecipe_id_stride(),
                           body, offset, length)
        book.set_rows = row + 1
    int index = 0
    while index < count:
        vt_iset(book.pool, book.pool_used + index, (int)items[index])
        index = index + 1
    vt_iset(book.set_start, row, book.pool_used)
    vt_iset(book.set_count, row, count)
    book.pool_used = book.pool_used + count
    return 0


public def vrecipe_set_rows(book: VRecipes*) -> int:
    if book == null:
        return 0
    return book.set_rows


public def vrecipe_set_item_count(book: VRecipes*, row: int) -> int:
    if book == null or row < 0 or row >= book.set_rows:
        return 0
    return vt_iget(book.set_count, row)


public def vrecipe_set_item(book: VRecipes*, row: int, index: int) -> int:
    if book == null or row < 0 or row >= book.set_rows:
        return vrecipe_absent()
    if index < 0 or index >= vt_iget(book.set_count, row):
        return vrecipe_absent()
    return vt_iget(book.pool, vt_iget(book.set_start, row) + index)


public def vrecipe_set_contains(book: VRecipes*, row: int, item: int) -> bool:
    int count = vrecipe_set_item_count(book, row)
    int index = 0
    while index < count:
        if vrecipe_set_item(book, row, index) == item:
            return true
        index = index + 1
    return false


public def vrecipe_add_stonecutter(book: VRecipes*, ingredient: int,
                                   display: int) -> int:
    if book == null or book.stone_rows >= vrecipe_entry_max():
        return 1
    vt_iset(book.stone_input, book.stone_rows, ingredient)
    vt_iset(book.stone_display, book.stone_rows, display)
    book.stone_rows = book.stone_rows + 1
    return 0


public def vrecipe_stonecutter_rows(book: VRecipes*) -> int:
    if book == null:
        return 0
    return book.stone_rows


def vrecipe_book_find(book: VRecipes*, id: int) -> int:
    int row = 0
    while row < book.book_rows:
        if vt_iget(book.book_id, row) == id:
            return row
        row = row + 1
    return vrecipe_absent()


public def vrecipe_book_clear(book: VRecipes*) -> void:
    if book == null:
        return
    book.book_rows = 0


public def vrecipe_book_add(book: VRecipes*, id: int, category: int, group: int,
                            flags: int) -> int:
    if book == null or id < 0:
        return 1
    int row = vrecipe_book_find(book, id)
    if row == vrecipe_absent():
        if book.book_rows >= vrecipe_entry_max():
            return 1
        row = book.book_rows
        book.book_rows = row + 1
    vt_iset(book.book_id, row, id)
    vt_iset(book.book_category, row, category)
    vt_iset(book.book_group, row, group)
    vt_iset(book.book_flags, row, flags)
    return 0


public def vrecipe_book_remove(book: VRecipes*, id: int) -> int:
    if book == null:
        return 1
    int row = vrecipe_book_find(book, id)
    if row == vrecipe_absent():
        return 0
    int last = book.book_rows - 1
    while row < last:
        vt_iset(book.book_id, row, vt_iget(book.book_id, row + 1))
        vt_iset(book.book_category, row, vt_iget(book.book_category, row + 1))
        vt_iset(book.book_group, row, vt_iget(book.book_group, row + 1))
        vt_iset(book.book_flags, row, vt_iget(book.book_flags, row + 1))
        row = row + 1
    book.book_rows = last
    return 0


public def vrecipe_book_rows(book: VRecipes*) -> int:
    if book == null:
        return 0
    return book.book_rows


public def vrecipe_book_entry_id(book: VRecipes*, row: int) -> int:
    if book == null or row < 0 or row >= book.book_rows:
        return vrecipe_absent()
    return vt_iget(book.book_id, row)


public def vrecipe_book_entry_category(book: VRecipes*, row: int) -> int:
    if book == null or row < 0 or row >= book.book_rows:
        return vrecipe_absent()
    return vt_iget(book.book_category, row)


public def vrecipe_book_entry_flags(book: VRecipes*, row: int) -> int:
    if book == null or row < 0 or row >= book.book_rows:
        return 0
    return vt_iget(book.book_flags, row)


public def vrecipe_book_known(book: VRecipes*, id: int) -> bool:
    if book == null:
        return false
    return vrecipe_book_find(book, id) != vrecipe_absent()


public def vrecipe_set_settings(book: VRecipes*, kind: int, open: bool,
                                filtering: bool) -> int:
    if book == null or kind < 0 or kind >= vrecipe_book_types():
        return 1
    int value = 0
    if open:
        value = 1
    vt_iset(book.book_open, kind, value)
    value = 0
    if filtering:
        value = 1
    vt_iset(book.book_filter, kind, value)
    return 0


public def vrecipe_book_is_open(book: VRecipes*, kind: int) -> bool:
    if book == null or kind < 0 or kind >= vrecipe_book_types():
        return false
    return vt_iget(book.book_open, kind) != 0


public def vrecipe_book_is_filtering(book: VRecipes*, kind: int) -> bool:
    if book == null or kind < 0 or kind >= vrecipe_book_types():
        return false
    return vt_iget(book.book_filter, kind) != 0

# ===== tags.cpy =====
# Vortex engine - registry tag tables.
#
# `update_tags` replaces the whole map: registry id -> tag name -> numeric id
# list. Names live in fixed-stride arenas and the id lists in one pooled array,
# so a replacement is a rewind rather than a reallocation.

public def vtags_registry_max() -> int:
    return 32


public def vtags_tag_max() -> int:
    return 8192


public def vtags_id_stride() -> int:
    return 128


public def vtags_pool_max() -> int:
    return 1048576


public def vtags_absent() -> int:
    return -1


struct VTags:
    char* registry_names
    int registry_rows
    char* tag_names
    int* tag_registry
    int* tag_start
    int* tag_count
    int tag_rows
    int* pool
    int pool_used


public def vtags_new() -> VTags*:
    VTags* table = new VTags
    table.registry_names = vt_calloc_char(vtags_registry_max() * vtags_id_stride())
    table.registry_rows = 0
    table.tag_names = vt_calloc_char(vtags_tag_max() * vtags_id_stride())
    table.tag_registry = vt_calloc_int(vtags_tag_max())
    table.tag_start = vt_calloc_int(vtags_tag_max())
    table.tag_count = vt_calloc_int(vtags_tag_max())
    table.tag_rows = 0
    table.pool = vt_calloc_int(vtags_pool_max())
    table.pool_used = 0
    return table


public def vtags_free(table: VTags*) -> void:
    if table == null:
        return
    vt_free(table.registry_names)
    vt_free(table.tag_names)
    vt_free(table.tag_registry)
    vt_free(table.tag_start)
    vt_free(table.tag_count)
    vt_free(table.pool)
    del table


def vtags_matches(arena: char*, base: int, body: int64[], offset: int64,
                  length: int64) -> int:
    int64 limit = vtags_id_stride() - 1
    if length > limit or length < 1:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


def vtags_store(arena: char*, base: int, body: int64[], offset: int64,
                length: int64) -> void:
    int64 limit = vtags_id_stride() - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


public def vtags_reset(table: VTags*) -> int:
    if table == null:
        return 1
    table.registry_rows = 0
    table.tag_rows = 0
    table.pool_used = 0
    return 0


public def vtags_registry_row(table: VTags*, body: int64[], offset: int64,
                              length: int64) -> int:
    if table == null:
        return vtags_absent()
    int row = 0
    while row < table.registry_rows:
        if vtags_matches(table.registry_names, row * vtags_id_stride(),
                         body, offset, length) == 1:
            return row
        row = row + 1
    if row >= vtags_registry_max():
        return vtags_absent()
    vtags_store(table.registry_names, row * vtags_id_stride(),
                body, offset, length)
    table.registry_rows = row + 1
    return row


public def vtags_add(table: VTags*, registry: int, body: int64[],
                     offset: int64, length: int64, ids: int64[],
                     count: int) -> int:
    if table == null or registry < 0 or registry >= table.registry_rows:
        return 1
    if count < 0 or table.tag_rows >= vtags_tag_max():
        return 1
    if table.pool_used + count > vtags_pool_max():
        return 1
    int row = table.tag_rows
    vtags_store(table.tag_names, row * vtags_id_stride(), body, offset, length)
    vt_iset(table.tag_registry, row, registry)
    vt_iset(table.tag_start, row, table.pool_used)
    vt_iset(table.tag_count, row, count)
    int index = 0
    while index < count:
        vt_iset(table.pool, table.pool_used + index, (int)ids[index])
        index = index + 1
    table.pool_used = table.pool_used + count
    table.tag_rows = row + 1
    return 0


public def vtags_registry_rows(table: VTags*) -> int:
    if table == null:
        return 0
    return table.registry_rows


public def vtags_rows(table: VTags*) -> int:
    if table == null:
        return 0
    return table.tag_rows


public def vtags_entry_count(table: VTags*, row: int) -> int:
    if table == null or row < 0 or row >= table.tag_rows:
        return 0
    return vt_iget(table.tag_count, row)


public def vtags_entry_id(table: VTags*, row: int, index: int) -> int:
    if table == null or row < 0 or row >= table.tag_rows:
        return vtags_absent()
    if index < 0 or index >= vt_iget(table.tag_count, row):
        return vtags_absent()
    return vt_iget(table.pool, vt_iget(table.tag_start, row) + index)


# Tag membership by name, the query the block and item code actually needs.
public def vtags_contains(table: VTags*, registry: int, body: int64[],
                          offset: int64, length: int64, id: int) -> bool:
    if table == null:
        return false
    int row = 0
    while row < table.tag_rows:
        if vt_iget(table.tag_registry, row) == registry:
            if vtags_matches(table.tag_names, row * vtags_id_stride(),
                             body, offset, length) == 1:
                int count = vt_iget(table.tag_count, row)
                int index = 0
                while index < count:
                    if vtags_entry_id(table, row, index) == id:
                        return true
                    index = index + 1
        row = row + 1
    return false

# ===== advancements.cpy =====
# Vortex engine - advancement tree and progress.
#
# The display tree is walked for validation but only the identity, parent, frame
# and coordinates are retained: a headless client needs the graph and the
# criteria completion, not the icons. Progress rows are (advancement, criterion,
# achieved-at) with -1 for an unachieved criterion.

public def vadv_max() -> int:
    return 2048


public def vadv_id_stride() -> int:
    return 128


public def vadv_criterion_max() -> int:
    return 16384


public def vadv_absent() -> int:
    return -1


public def vadv_flag_background() -> int:
    return 1


public def vadv_flag_toast() -> int:
    return 2


public def vadv_flag_hidden() -> int:
    return 4


struct VAdvancements:
    char* keys
    char* parents
    int* frames
    int* flags
    int* icon
    uint64* x
    uint64* y
    int rows
    int* crit_advancement
    char* crit_names
    uint64* crit_progress
    int crit_rows
    char* selected_tab
    bool visible


public def vadv_new() -> VAdvancements*:
    VAdvancements* table = new VAdvancements
    table.keys = vt_calloc_char(vadv_max() * vadv_id_stride())
    table.parents = vt_calloc_char(vadv_max() * vadv_id_stride())
    table.frames = vt_calloc_int(vadv_max())
    table.flags = vt_calloc_int(vadv_max())
    table.icon = vt_calloc_int(vadv_max())
    table.x = vt_calloc_u64(vadv_max())
    table.y = vt_calloc_u64(vadv_max())
    table.rows = 0
    table.crit_advancement = vt_calloc_int(vadv_criterion_max())
    table.crit_names = vt_calloc_char(vadv_criterion_max() * vadv_id_stride())
    table.crit_progress = vt_calloc_u64(vadv_criterion_max())
    table.crit_rows = 0
    table.selected_tab = vt_calloc_char(vadv_id_stride())
    table.visible = true
    return table


public def vadv_free(table: VAdvancements*) -> void:
    if table == null:
        return
    vt_free(table.keys)
    vt_free(table.parents)
    vt_free(table.frames)
    vt_free(table.flags)
    vt_free(table.icon)
    vt_free(table.x)
    vt_free(table.y)
    vt_free(table.crit_advancement)
    vt_free(table.crit_names)
    vt_free(table.crit_progress)
    vt_free(table.selected_tab)
    del table


def vadv_matches(arena: char*, base: int, body: int64[], offset: int64,
                 length: int64) -> int:
    int64 limit = vadv_id_stride() - 1
    if length > limit or length < 0:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


def vadv_store(arena: char*, base: int, body: int64[], offset: int64,
               length: int64) -> void:
    int64 limit = vadv_id_stride() - 1
    if length > limit:
        length = limit
    if length < 0:
        length = 0
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


public def vadv_reset(table: VAdvancements*) -> int:
    if table == null:
        return 1
    table.rows = 0
    table.crit_rows = 0
    vt_put(table.selected_tab, 0, 0)
    return 0


public def vadv_find(table: VAdvancements*, body: int64[], offset: int64,
                     length: int64) -> int:
    int row = 0
    while row < table.rows:
        if vadv_matches(table.keys, row * vadv_id_stride(),
                        body, offset, length) == 1:
            return row
        row = row + 1
    return vadv_absent()


# `parent_length` < 0 records a root advancement.
# Returns the row, or vadv_absent() when the table cannot hold the advancement.
# A row index is never a failure sentinel, so callers must compare against
# vadv_absent() rather than treating any non-zero result as an error.
public def vadv_add(table: VAdvancements*, body: int64[], offset: int64,
                    length: int64, parent: int64[], parent_offset: int64,
                    parent_length: int64, frame: int, flags: int, icon: int,
                    x: double, y: double) -> int:
    if table == null or frame < 0 or frame > 2:
        return vadv_absent()
    int row = vadv_find(table, body, offset, length)
    if row == vadv_absent():
        if table.rows >= vadv_max():
            return vadv_absent()
        row = table.rows
        table.rows = row + 1
        vadv_store(table.keys, row * vadv_id_stride(), body, offset, length)
    vadv_store(table.parents, row * vadv_id_stride(),
               parent, parent_offset, parent_length)
    vt_iset(table.frames, row, frame)
    vt_iset(table.flags, row, flags)
    vt_iset(table.icon, row, icon)
    vt_uset(table.x, row, vt_double_to_bits(x))
    vt_uset(table.y, row, vt_double_to_bits(y))
    return row


public def vadv_remove(table: VAdvancements*, body: int64[], offset: int64,
                       length: int64) -> int:
    if table == null:
        return 1
    int row = vadv_find(table, body, offset, length)
    if row == vadv_absent():
        return 0
    int last = table.rows - 1
    while row < last:
        int src = (row + 1) * vadv_id_stride()
        int dst = row * vadv_id_stride()
        int index = 0
        while index < vadv_id_stride():
            vt_put(table.keys, dst + index, vt_at(table.keys, src + index))
            vt_put(table.parents, dst + index, vt_at(table.parents, src + index))
            index = index + 1
        vt_iset(table.frames, row, vt_iget(table.frames, row + 1))
        vt_iset(table.flags, row, vt_iget(table.flags, row + 1))
        vt_iset(table.icon, row, vt_iget(table.icon, row + 1))
        vt_uset(table.x, row, vt_uget(table.x, row + 1))
        vt_uset(table.y, row, vt_uget(table.y, row + 1))
        row = row + 1
    table.rows = last
    int kept = 0
    int scan = 0
    while scan < table.crit_rows:
        int owner = vt_iget(table.crit_advancement, scan)
        if owner != last:
            if owner > last:
                owner = owner - 1
            if kept != scan:
                vt_iset(table.crit_advancement, kept, owner)
                int index = 0
                while index < vadv_id_stride():
                    vt_put(table.crit_names, kept * vadv_id_stride() + index,
                           vt_at(table.crit_names, scan * vadv_id_stride() + index))
                    index = index + 1
                vt_uset(table.crit_progress, kept, vt_uget(table.crit_progress, scan))
            kept = kept + 1
        scan = scan + 1
    table.crit_rows = kept
    return 0


public def vadv_rows(table: VAdvancements*) -> int:
    if table == null:
        return 0
    return table.rows


public def vadv_frame(table: VAdvancements*, row: int) -> int:
    if table == null or row < 0 or row >= table.rows:
        return vadv_absent()
    return vt_iget(table.frames, row)


public def vadv_flags(table: VAdvancements*, row: int) -> int:
    if table == null or row < 0 or row >= table.rows:
        return 0
    return vt_iget(table.flags, row)


public def vadv_icon(table: VAdvancements*, row: int) -> int:
    if table == null or row < 0 or row >= table.rows:
        return vadv_absent()
    return vt_iget(table.icon, row)


public def vadv_x(table: VAdvancements*, row: int) -> double:
    if table == null or row < 0 or row >= table.rows:
        return 0.0
    return vt_bits_to_double(vt_uget(table.x, row))


public def vadv_y(table: VAdvancements*, row: int) -> double:
    if table == null or row < 0 or row >= table.rows:
        return 0.0
    return vt_bits_to_double(vt_uget(table.y, row))


public def vadv_has_parent(table: VAdvancements*, row: int) -> bool:
    if table == null or row < 0 or row >= table.rows:
        return false
    return vt_at(table.parents, row * vadv_id_stride()) != 0


# `progress` is the achieved-at millisecond stamp, or -1 while unachieved.
public def vadv_set_progress(table: VAdvancements*, row: int, body: int64[],
                             offset: int64, length: int64,
                             progress: int64) -> int:
    if table == null or row < 0 or row >= table.rows:
        return 1
    int scan = 0
    while scan < table.crit_rows:
        if vt_iget(table.crit_advancement, scan) == row:
            if vadv_matches(table.crit_names, scan * vadv_id_stride(),
                            body, offset, length) == 1:
                vt_uset(table.crit_progress, scan, (uint64)progress)
                return 0
        scan = scan + 1
    if table.crit_rows >= vadv_criterion_max():
        return 1
    vt_iset(table.crit_advancement, table.crit_rows, row)
    vadv_store(table.crit_names, table.crit_rows * vadv_id_stride(),
               body, offset, length)
    vt_uset(table.crit_progress, table.crit_rows, (uint64)progress)
    table.crit_rows = table.crit_rows + 1
    return 0


public def vadv_criterion_rows(table: VAdvancements*) -> int:
    if table == null:
        return 0
    return table.crit_rows


public def vadv_criterion_progress(table: VAdvancements*, row: int) -> int64:
    if table == null or row < 0 or row >= table.crit_rows:
        return (int64)-1
    return (int64)vt_uget(table.crit_progress, row)


public def vadv_completed(table: VAdvancements*, row: int) -> bool:
    if table == null or row < 0 or row >= table.rows:
        return false
    int seen = 0
    int done = 0
    int scan = 0
    while scan < table.crit_rows:
        if vt_iget(table.crit_advancement, scan) == row:
            seen = seen + 1
            if (int64)vt_uget(table.crit_progress, scan) >= (int64)0:
                done = done + 1
        scan = scan + 1
    return seen > 0 and seen == done


public def vadv_select_tab(table: VAdvancements*, body: int64[], offset: int64,
                           length: int64) -> int:
    if table == null:
        return 1
    vadv_store(table.selected_tab, 0, body, offset, length)
    return 0


public def vadv_tab_selected(table: VAdvancements*, body: int64[],
                             offset: int64, length: int64) -> bool:
    if table == null:
        return false
    return vadv_matches(table.selected_tab, 0, body, offset, length) == 1


public def vadv_set_visible(table: VAdvancements*, visible: bool) -> int:
    if table == null:
        return 1
    table.visible = visible
    return 0

# ===== debug.cpy =====
# Vortex engine - server debug subscriptions.
#
# The debug/* Play packets carry a registry id plus a value whose shape depends
# on that id. Values are retained as a numeric projection: every scalar in wire
# order, every list count before its elements, and every string as its byte
# length. Diagnostic text is not kept, so a debug overlay can draw positions,
# counts and flags without the client owning a second string arena per value.
#
# Updates are keyed by (kind, subscription, key) and replaced in place; an
# absent optional clears the row's value but keeps the key, matching the
# server's "this position no longer has a value" semantics. Events have no key
# and live in a bounded ring.

public def vdebug_max() -> int:
    return 2048


public def vdebug_value_max() -> int:
    return 128


public def vdebug_event_max() -> int:
    return 256


public def vdebug_absent() -> int:
    return -1


public def vdebug_kind_block() -> int:
    return 0


public def vdebug_kind_chunk() -> int:
    return 1


public def vdebug_kind_entity() -> int:
    return 2


struct VDebug:
    int rows
    int* kind
    int* subscription
    uint64* key_x
    uint64* key_y
    uint64* key_z
    int* present
    int* value_length
    uint64* values
    int event_rows
    int event_head
    int* event_subscription
    int* event_length
    uint64* event_values


# Wire readers append into an accumulator rather than returning a count, so a
# deeply nested value does not have to thread an out parameter through every
# call. `overflow` records that the projection was clipped.
struct VDbgAcc:
    int64[] values
    int used
    int overflow


public def vdbg_acc_new() -> VDbgAcc*:
    VDbgAcc* acc = new VDbgAcc
    acc.values = new int64[vdebug_value_max()]
    acc.used = 0
    acc.overflow = 0
    return acc


public def vdbg_acc_free(acc: VDbgAcc*) -> void:
    if acc == null:
        return
    del acc.values
    del acc


public def vdbg_acc_reset(acc: VDbgAcc*) -> void:
    if acc == null:
        return
    acc.used = 0
    acc.overflow = 0


public def vdbg_acc_push(acc: VDbgAcc*, value: int64) -> void:
    if acc == null:
        return
    if acc.used >= vdebug_value_max():
        acc.overflow = 1
        return
    acc.values[acc.used] = value
    acc.used = acc.used + 1


public def vdbg_acc_used(acc: VDbgAcc*) -> int:
    if acc == null:
        return 0
    return acc.used


public def vdbg_acc_overflow(acc: VDbgAcc*) -> int:
    if acc == null:
        return 0
    return acc.overflow


public def vdbg_acc_value(acc: VDbgAcc*, index: int) -> int64:
    if acc == null or index < 0 or index >= acc.used:
        return (int64)0
    return acc.values[index]


public def vdebug_new() -> VDebug*:
    VDebug* store = new VDebug
    store.rows = 0
    store.kind = vt_calloc_int(vdebug_max())
    store.subscription = vt_calloc_int(vdebug_max())
    store.key_x = vt_calloc_u64(vdebug_max())
    store.key_y = vt_calloc_u64(vdebug_max())
    store.key_z = vt_calloc_u64(vdebug_max())
    store.present = vt_calloc_int(vdebug_max())
    store.value_length = vt_calloc_int(vdebug_max())
    store.values = vt_calloc_u64(vdebug_max() * vdebug_value_max())
    store.event_rows = 0
    store.event_head = 0
    store.event_subscription = vt_calloc_int(vdebug_event_max())
    store.event_length = vt_calloc_int(vdebug_event_max())
    store.event_values = vt_calloc_u64(vdebug_event_max() * vdebug_value_max())
    return store


public def vdebug_free(store: VDebug*) -> void:
    if store == null:
        return
    vt_free(store.kind)
    vt_free(store.subscription)
    vt_free(store.key_x)
    vt_free(store.key_y)
    vt_free(store.key_z)
    vt_free(store.present)
    vt_free(store.value_length)
    vt_free(store.values)
    vt_free(store.event_subscription)
    vt_free(store.event_length)
    vt_free(store.event_values)
    del store


public def vdebug_reset(store: VDebug*) -> int:
    if store == null:
        return 1
    store.rows = 0
    store.event_rows = 0
    store.event_head = 0
    return 0


public def vdebug_find(store: VDebug*, kind: int, subscription: int,
                       x: int64, y: int64, z: int64) -> int:
    if store == null:
        return vdebug_absent()
    int row = 0
    while row < store.rows:
        if vt_iget(store.kind, row) == kind:
            if vt_iget(store.subscription, row) == subscription:
                if (int64)vt_uget(store.key_x, row) == x:
                    if (int64)vt_uget(store.key_y, row) == y:
                        if (int64)vt_uget(store.key_z, row) == z:
                            return row
        row = row + 1
    return vdebug_absent()


def vdebug_copy_projection(dst: uint64*, base: int, acc: VDbgAcc*) -> int:
    int count = acc.used
    if count > vdebug_value_max():
        count = vdebug_value_max()
    int index = 0
    while index < count:
        vt_uset(dst, base + index, (uint64)acc.values[index])
        index = index + 1
    return count


# Returns the row, or vdebug_absent() when the store is full. `present` is 0 for
# an absent optional value, which clears the projection but keeps the key.
public def vdebug_set(store: VDebug*, kind: int, subscription: int,
                      x: int64, y: int64, z: int64, present: int,
                      acc: VDbgAcc*) -> int:
    if store == null or acc == null or kind < 0 or kind > 2:
        return vdebug_absent()
    if subscription < 0:
        return vdebug_absent()
    int row = vdebug_find(store, kind, subscription, x, y, z)
    if row == vdebug_absent():
        if store.rows >= vdebug_max():
            return vdebug_absent()
        row = store.rows
        store.rows = row + 1
    vt_iset(store.kind, row, kind)
    vt_iset(store.subscription, row, subscription)
    vt_uset(store.key_x, row, (uint64)x)
    vt_uset(store.key_y, row, (uint64)y)
    vt_uset(store.key_z, row, (uint64)z)
    vt_iset(store.present, row, present)
    int base = row * vdebug_value_max()
    if present == 0:
        vt_iset(store.value_length, row, 0)
        return row
    vt_iset(store.value_length, row, vdebug_copy_projection(store.values, base, acc))
    return row


public def vdebug_rows(store: VDebug*) -> int:
    if store == null:
        return 0
    return store.rows


public def vdebug_row_kind(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.rows:
        return vdebug_absent()
    return vt_iget(store.kind, row)


public def vdebug_row_subscription(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.rows:
        return vdebug_absent()
    return vt_iget(store.subscription, row)


public def vdebug_row_key_x(store: VDebug*, row: int) -> int64:
    if store == null or row < 0 or row >= store.rows:
        return (int64)0
    return (int64)vt_uget(store.key_x, row)


public def vdebug_row_key_y(store: VDebug*, row: int) -> int64:
    if store == null or row < 0 or row >= store.rows:
        return (int64)0
    return (int64)vt_uget(store.key_y, row)


public def vdebug_row_key_z(store: VDebug*, row: int) -> int64:
    if store == null or row < 0 or row >= store.rows:
        return (int64)0
    return (int64)vt_uget(store.key_z, row)


public def vdebug_row_present(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.rows:
        return 0
    return vt_iget(store.present, row)


public def vdebug_row_length(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.rows:
        return 0
    return vt_iget(store.value_length, row)


public def vdebug_row_value(store: VDebug*, row: int, index: int) -> int64:
    if store == null or row < 0 or row >= store.rows:
        return (int64)0
    if index < 0 or index >= vt_iget(store.value_length, row):
        return (int64)0
    return (int64)vt_uget(store.values, row * vdebug_value_max() + index)


# Events are a ring: the oldest is overwritten once the ring is full, so a
# chatty subscription cannot grow the store without bound.
public def vdebug_push_event(store: VDebug*, subscription: int,
                             acc: VDbgAcc*) -> int:
    if store == null or acc == null or subscription < 0:
        return vdebug_absent()
    int row = store.event_head
    vt_iset(store.event_subscription, row, subscription)
    vt_iset(store.event_length, row,
            vdebug_copy_projection(store.event_values, row * vdebug_value_max(), acc))
    store.event_head = row + 1
    if store.event_head >= vdebug_event_max():
        store.event_head = 0
    if store.event_rows < vdebug_event_max():
        store.event_rows = store.event_rows + 1
    return row


public def vdebug_event_rows(store: VDebug*) -> int:
    if store == null:
        return 0
    return store.event_rows


def vdebug_event_slot(store: VDebug*, row: int) -> int:
    int start = store.event_head - store.event_rows
    if start < 0:
        start = start + vdebug_event_max()
    int slot = start + row
    if slot >= vdebug_event_max():
        slot = slot - vdebug_event_max()
    return slot


public def vdebug_event_subscription(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.event_rows:
        return vdebug_absent()
    return vt_iget(store.event_subscription, vdebug_event_slot(store, row))


public def vdebug_event_length(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.event_rows:
        return 0
    return vt_iget(store.event_length, vdebug_event_slot(store, row))


public def vdebug_event_value(store: VDebug*, row: int, index: int) -> int64:
    if store == null or row < 0 or row >= store.event_rows:
        return (int64)0
    int slot = vdebug_event_slot(store, row)
    if index < 0 or index >= vt_iget(store.event_length, slot):
        return (int64)0
    return (int64)vt_uget(store.event_values, slot * vdebug_value_max() + index)

# ===== serverdata.cpy =====
# Vortex engine - server-pushed session metadata.
#
# Statistics, cooldowns, cookies, resource packs, links, report details, game
# rules, map contents, merchant offers and waypoints share one table because
# they share a shape: the server pushes a small named record set, the client
# keeps it for queries, and none of it drives world simulation. Names live in
# fixed-stride arenas; variable payloads live in pooled byte arrays.

public def vmeta_id_stride() -> int:
    return 128


public def vmeta_text_stride() -> int:
    return 512


public def vmeta_stat_max() -> int:
    return 2048


public def vmeta_named_max() -> int:
    return 256


public def vmeta_trade_max() -> int:
    return 64


public def vmeta_map_max() -> int:
    return 64


public def vmeta_map_pixels() -> int:
    return 16384


public def vmeta_waypoint_max() -> int:
    return 256


public def vmeta_pool_max() -> int:
    return 262144


public def vmeta_absent() -> int:
    return -1


struct VServerMeta:
    int* stat_category
    int* stat_id
    int* stat_value
    int stat_rows
    char* cooldown_names
    int* cooldown_ticks
    uint64* cooldown_started
    int cooldown_rows
    char* cookie_keys
    int* cookie_start
    int* cookie_length
    int cookie_rows
    char* text_pool
    int* text_used
    int* pack_uuid_high
    int* pack_uuid_low
    int* pack_url
    int* pack_hash
    int* pack_required
    int pack_rows
    int* link_type
    int* link_label
    int* link_url
    int link_rows
    char* rule_names
    char* rule_values
    int rule_rows
    char* report_names
    char* report_values
    int report_rows
    int* map_id
    int* map_scale
    int* map_locked
    int* map_pixels
    int map_rows
    int* decoration_map
    int* decoration_type
    int* decoration_x
    int* decoration_y
    int* decoration_rot
    int decoration_rows
    int trade_window
    int* trade_cost_a
    int* trade_cost_a_count
    int* trade_cost_b
    int* trade_cost_b_count
    int* trade_result
    int* trade_result_count
    int* trade_uses
    int* trade_max_uses
    int* trade_disabled
    int trade_rows
    int merchant_level
    int merchant_xp
    bool merchant_progress
    bool merchant_restock
    char* waypoint_names
    int* waypoint_uuid_high
    int* waypoint_uuid_low
    int* waypoint_kind
    int* waypoint_a
    int* waypoint_b
    int* waypoint_c
    int* waypoint_color
    int waypoint_rows
    char* payload_pool
    int payload_used


public def vmeta_new() -> VServerMeta*:
    VServerMeta* meta = new VServerMeta
    meta.stat_category = vt_calloc_int(vmeta_stat_max())
    meta.stat_id = vt_calloc_int(vmeta_stat_max())
    meta.stat_value = vt_calloc_int(vmeta_stat_max())
    meta.stat_rows = 0
    meta.cooldown_names = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.cooldown_ticks = vt_calloc_int(vmeta_named_max())
    meta.cooldown_started = vt_calloc_u64(vmeta_named_max())
    meta.cooldown_rows = 0
    meta.cookie_keys = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.cookie_start = vt_calloc_int(vmeta_named_max())
    meta.cookie_length = vt_calloc_int(vmeta_named_max())
    meta.cookie_rows = 0
    meta.text_pool = vt_calloc_char(vmeta_named_max() * vmeta_text_stride())
    meta.text_used = vt_calloc_int(1)
    meta.pack_uuid_high = vt_calloc_int(vmeta_named_max() * 2)
    meta.pack_uuid_low = vt_calloc_int(vmeta_named_max() * 2)
    meta.pack_url = vt_calloc_int(vmeta_named_max())
    meta.pack_hash = vt_calloc_int(vmeta_named_max())
    meta.pack_required = vt_calloc_int(vmeta_named_max())
    meta.pack_rows = 0
    meta.link_type = vt_calloc_int(vmeta_named_max())
    meta.link_label = vt_calloc_int(vmeta_named_max())
    meta.link_url = vt_calloc_int(vmeta_named_max())
    meta.link_rows = 0
    meta.rule_names = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.rule_values = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.rule_rows = 0
    meta.report_names = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.report_values = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.report_rows = 0
    meta.map_id = vt_calloc_int(vmeta_map_max())
    meta.map_scale = vt_calloc_int(vmeta_map_max())
    meta.map_locked = vt_calloc_int(vmeta_map_max())
    meta.map_pixels = vt_calloc_int(vmeta_map_max() * vmeta_map_pixels())
    meta.map_rows = 0
    meta.decoration_map = vt_calloc_int(vmeta_named_max())
    meta.decoration_type = vt_calloc_int(vmeta_named_max())
    meta.decoration_x = vt_calloc_int(vmeta_named_max())
    meta.decoration_y = vt_calloc_int(vmeta_named_max())
    meta.decoration_rot = vt_calloc_int(vmeta_named_max())
    meta.decoration_rows = 0
    meta.trade_window = vmeta_absent()
    meta.trade_cost_a = vt_calloc_int(vmeta_trade_max())
    meta.trade_cost_a_count = vt_calloc_int(vmeta_trade_max())
    meta.trade_cost_b = vt_calloc_int(vmeta_trade_max())
    meta.trade_cost_b_count = vt_calloc_int(vmeta_trade_max())
    meta.trade_result = vt_calloc_int(vmeta_trade_max())
    meta.trade_result_count = vt_calloc_int(vmeta_trade_max())
    meta.trade_uses = vt_calloc_int(vmeta_trade_max())
    meta.trade_max_uses = vt_calloc_int(vmeta_trade_max())
    meta.trade_disabled = vt_calloc_int(vmeta_trade_max())
    meta.trade_rows = 0
    meta.waypoint_names = vt_calloc_char(vmeta_waypoint_max() * vmeta_id_stride())
    meta.waypoint_uuid_high = vt_calloc_int(vmeta_waypoint_max() * 2)
    meta.waypoint_uuid_low = vt_calloc_int(vmeta_waypoint_max() * 2)
    meta.waypoint_kind = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_a = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_b = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_c = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_color = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_rows = 0
    meta.payload_pool = vt_calloc_char(vmeta_pool_max())
    meta.payload_used = 0
    return meta


public def vmeta_free(meta: VServerMeta*) -> void:
    if meta == null:
        return
    vt_free(meta.stat_category)
    vt_free(meta.stat_id)
    vt_free(meta.stat_value)
    vt_free(meta.cooldown_names)
    vt_free(meta.cooldown_ticks)
    vt_free(meta.cooldown_started)
    vt_free(meta.cookie_keys)
    vt_free(meta.cookie_start)
    vt_free(meta.cookie_length)
    vt_free(meta.text_pool)
    vt_free(meta.text_used)
    vt_free(meta.pack_uuid_high)
    vt_free(meta.pack_uuid_low)
    vt_free(meta.pack_url)
    vt_free(meta.pack_hash)
    vt_free(meta.pack_required)
    vt_free(meta.link_type)
    vt_free(meta.link_label)
    vt_free(meta.link_url)
    vt_free(meta.rule_names)
    vt_free(meta.rule_values)
    vt_free(meta.report_names)
    vt_free(meta.report_values)
    vt_free(meta.map_id)
    vt_free(meta.map_scale)
    vt_free(meta.map_locked)
    vt_free(meta.map_pixels)
    vt_free(meta.decoration_map)
    vt_free(meta.decoration_type)
    vt_free(meta.decoration_x)
    vt_free(meta.decoration_y)
    vt_free(meta.decoration_rot)
    vt_free(meta.trade_cost_a)
    vt_free(meta.trade_cost_a_count)
    vt_free(meta.trade_cost_b)
    vt_free(meta.trade_cost_b_count)
    vt_free(meta.trade_result)
    vt_free(meta.trade_result_count)
    vt_free(meta.trade_uses)
    vt_free(meta.trade_max_uses)
    vt_free(meta.trade_disabled)
    vt_free(meta.waypoint_names)
    vt_free(meta.waypoint_uuid_high)
    vt_free(meta.waypoint_uuid_low)
    vt_free(meta.waypoint_kind)
    vt_free(meta.waypoint_a)
    vt_free(meta.waypoint_b)
    vt_free(meta.waypoint_c)
    vt_free(meta.waypoint_color)
    vt_free(meta.payload_pool)
    del meta


def vmeta_matches(arena: char*, base: int, body: int64[], offset: int64,
                  length: int64, stride: int) -> int:
    int64 limit = stride - 1
    if length > limit or length < 0:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


def vmeta_store(arena: char*, base: int, body: int64[], offset: int64,
                length: int64, stride: int) -> void:
    int64 limit = stride - 1
    if length > limit:
        length = limit
    if length < 0:
        length = 0
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


# Text slots are append-only within a session: the count is small and the
# alternative is a second lifetime to manage for every pushed string.
def vmeta_text_slot(meta: VServerMeta*, body: int64[], offset: int64,
                    length: int64) -> int:
    int used = vt_iget(meta.text_used, 0)
    if used >= vmeta_named_max():
        return vmeta_absent()
    vmeta_store(meta.text_pool, used * vmeta_text_stride(),
                body, offset, length, vmeta_text_stride())
    vt_iset(meta.text_used, 0, used + 1)
    return used


public def vmeta_text_byte(meta: VServerMeta*, slot: int, index: int) -> int:
    if meta == null or slot < 0 or slot >= vt_iget(meta.text_used, 0):
        return 0
    if index < 0 or index >= vmeta_text_stride():
        return 0
    return vt_at(meta.text_pool, slot * vmeta_text_stride() + index)


# --- statistics ---------------------------------------------------------------


public def vmeta_set_stat(meta: VServerMeta*, category: int, id: int,
                          value: int) -> int:
    if meta == null or category < 0 or id < 0:
        return 1
    int row = 0
    while row < meta.stat_rows:
        if vt_iget(meta.stat_category, row) == category:
            if vt_iget(meta.stat_id, row) == id:
                vt_iset(meta.stat_value, row, value)
                return 0
        row = row + 1
    if meta.stat_rows >= vmeta_stat_max():
        return 1
    vt_iset(meta.stat_category, meta.stat_rows, category)
    vt_iset(meta.stat_id, meta.stat_rows, id)
    vt_iset(meta.stat_value, meta.stat_rows, value)
    meta.stat_rows = meta.stat_rows + 1
    return 0


public def vmeta_stat(meta: VServerMeta*, category: int, id: int) -> int:
    if meta == null:
        return 0
    int row = 0
    while row < meta.stat_rows:
        if vt_iget(meta.stat_category, row) == category:
            if vt_iget(meta.stat_id, row) == id:
                return vt_iget(meta.stat_value, row)
        row = row + 1
    return 0


public def vmeta_stat_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.stat_rows


# --- cooldowns ----------------------------------------------------------------


public def vmeta_set_cooldown(meta: VServerMeta*, body: int64[], offset: int64,
                              length: int64, ticks: int, now: int64) -> int:
    if meta == null or ticks < 0:
        return 1
    int row = 0
    while row < meta.cooldown_rows:
        if vmeta_matches(meta.cooldown_names, row * vmeta_id_stride(),
                         body, offset, length, vmeta_id_stride()) == 1:
            break
        row = row + 1
    if row >= vmeta_named_max():
        return 1
    if row == meta.cooldown_rows:
        vmeta_store(meta.cooldown_names, row * vmeta_id_stride(),
                    body, offset, length, vmeta_id_stride())
        meta.cooldown_rows = row + 1
    vt_iset(meta.cooldown_ticks, row, ticks)
    vt_uset(meta.cooldown_started, row, (uint64)now)
    return 0


public def vmeta_cooldown_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.cooldown_rows


public def vmeta_cooldown_ticks(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.cooldown_rows:
        return 0
    return vt_iget(meta.cooldown_ticks, row)


public def vmeta_cooldown_started(meta: VServerMeta*, row: int) -> int64:
    if meta == null or row < 0 or row >= meta.cooldown_rows:
        return (int64)0
    return (int64)vt_uget(meta.cooldown_started, row)


# --- cookies ------------------------------------------------------------------


public def vmeta_set_cookie(meta: VServerMeta*, body: int64[], offset: int64,
                            length: int64, payload: int64[],
                            payload_offset: int64, payload_length: int64) -> int:
    if meta == null or payload_length < 0:
        return 1
    int row = 0
    while row < meta.cookie_rows:
        if vmeta_matches(meta.cookie_keys, row * vmeta_id_stride(),
                         body, offset, length, vmeta_id_stride()) == 1:
            break
        row = row + 1
    if row >= vmeta_named_max():
        return 1
    if meta.payload_used + (int)payload_length > vmeta_pool_max():
        return 1
    if row == meta.cookie_rows:
        vmeta_store(meta.cookie_keys, row * vmeta_id_stride(),
                    body, offset, length, vmeta_id_stride())
        meta.cookie_rows = row + 1
    int64 index = 0
    while index < payload_length:
        vt_put(meta.payload_pool, meta.payload_used + (int)index,
               (int)(payload[payload_offset + index] & 0xFF))
        index = index + 1
    vt_iset(meta.cookie_start, row, meta.payload_used)
    vt_iset(meta.cookie_length, row, (int)payload_length)
    meta.payload_used = meta.payload_used + (int)payload_length
    return 0


public def vmeta_cookie_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.cookie_rows


public def vmeta_cookie_find(meta: VServerMeta*, body: int64[], offset: int64,
                             length: int64) -> int:
    if meta == null:
        return vmeta_absent()
    int row = 0
    while row < meta.cookie_rows:
        if vmeta_matches(meta.cookie_keys, row * vmeta_id_stride(),
                         body, offset, length, vmeta_id_stride()) == 1:
            return row
        row = row + 1
    return vmeta_absent()


public def vmeta_cookie_length(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.cookie_rows:
        return 0
    return vt_iget(meta.cookie_length, row)


public def vmeta_cookie_byte(meta: VServerMeta*, row: int, index: int) -> int:
    if meta == null or row < 0 or row >= meta.cookie_rows:
        return 0
    if index < 0 or index >= vt_iget(meta.cookie_length, row):
        return 0
    return vt_at(meta.payload_pool, vt_iget(meta.cookie_start, row) + index)


# --- resource packs -----------------------------------------------------------


public def vmeta_push_pack(meta: VServerMeta*, uuid_high: int64[],
                           uuid_low: int64[], url: int64[], url_offset: int64,
                           url_length: int64, hash: int64[], hash_offset: int64,
                           hash_length: int64, required: bool) -> int:
    if meta == null:
        return 1
    int row = 0
    while row < meta.pack_rows:
        if vt_iget(meta.pack_uuid_high, row * 2) == (int)uuid_high[0]:
            if vt_iget(meta.pack_uuid_low, row * 2) == (int)uuid_low[0]:
                break
        row = row + 1
    if row >= vmeta_named_max():
        return 1
    int url_slot = vmeta_text_slot(meta, url, url_offset, url_length)
    int hash_slot = vmeta_text_slot(meta, hash, hash_offset, hash_length)
    if url_slot == vmeta_absent() or hash_slot == vmeta_absent():
        return 1
    if row == meta.pack_rows:
        meta.pack_rows = row + 1
    vt_iset(meta.pack_uuid_high, row * 2, (int)uuid_high[0])
    vt_iset(meta.pack_uuid_high, row * 2 + 1, (int)uuid_high[1])
    vt_iset(meta.pack_uuid_low, row * 2, (int)uuid_low[0])
    vt_iset(meta.pack_uuid_low, row * 2 + 1, (int)uuid_low[1])
    vt_iset(meta.pack_url, row, url_slot)
    vt_iset(meta.pack_hash, row, hash_slot)
    int flag = 0
    if required:
        flag = 1
    vt_iset(meta.pack_required, row, flag)
    return row


# A zero UUID pops every pack; the arrays hold two 32-bit halves each.
public def vmeta_pop_pack(meta: VServerMeta*, uuid_high: int64[],
                          uuid_low: int64[], present: bool) -> int:
    if meta == null:
        return 1
    if not present:
        meta.pack_rows = 0
        return 0
    int row = 0
    while row < meta.pack_rows:
        if vt_iget(meta.pack_uuid_high, row * 2) == (int)uuid_high[0]:
            if vt_iget(meta.pack_uuid_low, row * 2) == (int)uuid_low[0]:
                int last = meta.pack_rows - 1
                while row < last:
                    vt_iset(meta.pack_uuid_high, row * 2,
                            vt_iget(meta.pack_uuid_high, (row + 1) * 2))
                    vt_iset(meta.pack_uuid_high, row * 2 + 1,
                            vt_iget(meta.pack_uuid_high, (row + 1) * 2 + 1))
                    vt_iset(meta.pack_uuid_low, row * 2,
                            vt_iget(meta.pack_uuid_low, (row + 1) * 2))
                    vt_iset(meta.pack_uuid_low, row * 2 + 1,
                            vt_iget(meta.pack_uuid_low, (row + 1) * 2 + 1))
                    vt_iset(meta.pack_url, row, vt_iget(meta.pack_url, row + 1))
                    vt_iset(meta.pack_hash, row, vt_iget(meta.pack_hash, row + 1))
                    vt_iset(meta.pack_required, row,
                            vt_iget(meta.pack_required, row + 1))
                    row = row + 1
                meta.pack_rows = last
                return 0
        row = row + 1
    return 0


public def vmeta_pack_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.pack_rows


public def vmeta_pack_required(meta: VServerMeta*, row: int) -> bool:
    if meta == null or row < 0 or row >= meta.pack_rows:
        return false
    return vt_iget(meta.pack_required, row) != 0


public def vmeta_pack_url_slot(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.pack_rows:
        return vmeta_absent()
    return vt_iget(meta.pack_url, row)


# --- links and report details -------------------------------------------------


public def vmeta_reset_links(meta: VServerMeta*) -> int:
    if meta == null:
        return 1
    meta.link_rows = 0
    return 0


public def vmeta_add_link(meta: VServerMeta*, known: int, label: int64[],
                          label_offset: int64, label_length: int64,
                          url: int64[], url_offset: int64,
                          url_length: int64) -> int:
    if meta == null or meta.link_rows >= vmeta_named_max():
        return 1
    int label_slot = 0
    if label_length >= 0:
        label_slot = vmeta_text_slot(meta, label, label_offset, label_length)
        if label_slot == vmeta_absent():
            return 1
    int url_slot = vmeta_text_slot(meta, url, url_offset, url_length)
    if url_slot == vmeta_absent():
        return 1
    vt_iset(meta.link_type, meta.link_rows, known)
    vt_iset(meta.link_label, meta.link_rows, label_slot)
    vt_iset(meta.link_url, meta.link_rows, url_slot)
    meta.link_rows = meta.link_rows + 1
    return 0


public def vmeta_link_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.link_rows


public def vmeta_link_type(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.link_rows:
        return vmeta_absent()
    return vt_iget(meta.link_type, row)


public def vmeta_link_url_slot(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.link_rows:
        return vmeta_absent()
    return vt_iget(meta.link_url, row)


public def vmeta_reset_report(meta: VServerMeta*) -> int:
    if meta == null:
        return 1
    meta.report_rows = 0
    return 0


# Game rules arrive as a partial map the client merges into its own rules, so
# there is no reset: a rule the server stops sending keeps its last value.
public def vmeta_set_pair(meta: VServerMeta*, name: int64[], name_offset: int64,
                          name_length: int64, value: int64[],
                          value_offset: int64, value_length: int64) -> int:
    if meta == null:
        return 1
    int row = 0
    while row < meta.rule_rows:
        if vmeta_matches(meta.rule_names, row * vmeta_id_stride(),
                         name, name_offset, name_length, vmeta_id_stride()) == 1:
            break
        row = row + 1
    if row >= vmeta_named_max():
        return 1
    if row == meta.rule_rows:
        vmeta_store(meta.rule_names, row * vmeta_id_stride(),
                    name, name_offset, name_length, vmeta_id_stride())
        meta.rule_rows = row + 1
    vmeta_store(meta.rule_values, row * vmeta_id_stride(),
                value, value_offset, value_length, vmeta_id_stride())
    return 0


public def vmeta_pair_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.rule_rows


public def vmeta_pair_value_byte(meta: VServerMeta*, row: int,
                                 index: int) -> int:
    if meta == null or row < 0 or row >= meta.rule_rows:
        return 0
    if index < 0 or index >= vmeta_id_stride():
        return 0
    return vt_at(meta.rule_values, row * vmeta_id_stride() + index)


# Report details are a whole-map replacement, unlike game rules, and a server
# sends both in one session, so they get their own arenas.
public def vmeta_set_report_pair(meta: VServerMeta*, name: int64[],
                                 name_offset: int64, name_length: int64,
                                 value: int64[], value_offset: int64,
                                 value_length: int64) -> int:
    if meta == null:
        return 1
    int row = meta.report_rows
    if row >= vmeta_named_max():
        return 1
    vmeta_store(meta.report_names, row * vmeta_id_stride(),
                name, name_offset, name_length, vmeta_id_stride())
    vmeta_store(meta.report_values, row * vmeta_id_stride(),
                value, value_offset, value_length, vmeta_id_stride())
    meta.report_rows = row + 1
    return 0


public def vmeta_report_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.report_rows


public def vmeta_report_value_byte(meta: VServerMeta*, row: int,
                                   index: int) -> int:
    if meta == null or row < 0 or row >= meta.report_rows:
        return 0
    if index < 0 or index >= vmeta_id_stride():
        return 0
    return vt_at(meta.report_values, row * vmeta_id_stride() + index)


# --- maps ---------------------------------------------------------------------


def vmeta_map_row(meta: VServerMeta*, id: int) -> int:
    int row = 0
    while row < meta.map_rows:
        if vt_iget(meta.map_id, row) == id:
            return row
        row = row + 1
    if meta.map_rows >= vmeta_map_max():
        return vmeta_absent()
    row = meta.map_rows
    meta.map_rows = row + 1
    vt_iset(meta.map_id, row, id)
    vt_iset(meta.map_scale, row, 0)
    vt_iset(meta.map_locked, row, 0)
    return row


public def vmeta_map_header(meta: VServerMeta*, id: int, scale: int,
                            locked: bool) -> int:
    if meta == null or id < 0:
        return vmeta_absent()
    int row = vmeta_map_row(meta, id)
    if row == vmeta_absent():
        return vmeta_absent()
    vt_iset(meta.map_scale, row, scale)
    int flag = 0
    if locked:
        flag = 1
    vt_iset(meta.map_locked, row, flag)
    return row


# A colour patch is width x height bytes laid down at (start_x, start_y) in the
# 128x128 map canvas.
public def vmeta_map_patch(meta: VServerMeta*, row: int, start_x: int,
                           start_y: int, width: int, height: int,
                           colors: int64[], offset: int64) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 1
    if start_x < 0 or (start_y < 0 or width < 0 or height < 0):
        return 1
    if start_x + width > 128 or start_y + height > 128:
        return 1
    int y = 0
    while y < height:
        int x = 0
        while x < width:
            int cell = (start_y + y) * 128 + start_x + x
            vt_iset(meta.map_pixels, row * vmeta_map_pixels() + cell,
                    (int)(colors[offset + (int64)y * (int64)width + (int64)x] & 0xFF))
            x = x + 1
        y = y + 1
    return 0


public def vmeta_map_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.map_rows


public def vmeta_map_pixel(meta: VServerMeta*, row: int, x: int, y: int) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 0
    if x < 0 or (x >= 128 or y < 0 or y >= 128):
        return 0
    return vt_iget(meta.map_pixels, row * vmeta_map_pixels() + y * 128 + x)


public def vmeta_map_scale(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 0
    return vt_iget(meta.map_scale, row)


public def vmeta_reset_decorations(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 1
    int kept = 0
    int scan = 0
    while scan < meta.decoration_rows:
        if vt_iget(meta.decoration_map, scan) != row:
            if kept != scan:
                vt_iset(meta.decoration_map, kept, vt_iget(meta.decoration_map, scan))
                vt_iset(meta.decoration_type, kept, vt_iget(meta.decoration_type, scan))
                vt_iset(meta.decoration_x, kept, vt_iget(meta.decoration_x, scan))
                vt_iset(meta.decoration_y, kept, vt_iget(meta.decoration_y, scan))
                vt_iset(meta.decoration_rot, kept, vt_iget(meta.decoration_rot, scan))
            kept = kept + 1
        scan = scan + 1
    meta.decoration_rows = kept
    return 0


public def vmeta_add_decoration(meta: VServerMeta*, row: int, kind: int,
                                x: int, y: int, rot: int) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 1
    if meta.decoration_rows >= vmeta_named_max():
        return 1
    vt_iset(meta.decoration_map, meta.decoration_rows, row)
    vt_iset(meta.decoration_type, meta.decoration_rows, kind)
    vt_iset(meta.decoration_x, meta.decoration_rows, x)
    vt_iset(meta.decoration_y, meta.decoration_rows, y)
    vt_iset(meta.decoration_rot, meta.decoration_rows, rot)
    meta.decoration_rows = meta.decoration_rows + 1
    return 0


public def vmeta_decoration_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.decoration_rows


# --- merchant offers ----------------------------------------------------------


public def vmeta_reset_trades(meta: VServerMeta*, window: int) -> int:
    if meta == null:
        return 1
    meta.trade_window = window
    meta.trade_rows = 0
    return 0


public def vmeta_add_trade(meta: VServerMeta*, cost_a: int, cost_a_count: int,
                           cost_b: int, cost_b_count: int, result: int,
                           result_count: int, uses: int, max_uses: int,
                           disabled: bool) -> int:
    if meta == null or meta.trade_rows >= vmeta_trade_max():
        return 1
    int row = meta.trade_rows
    vt_iset(meta.trade_cost_a, row, cost_a)
    vt_iset(meta.trade_cost_a_count, row, cost_a_count)
    vt_iset(meta.trade_cost_b, row, cost_b)
    vt_iset(meta.trade_cost_b_count, row, cost_b_count)
    vt_iset(meta.trade_result, row, result)
    vt_iset(meta.trade_result_count, row, result_count)
    vt_iset(meta.trade_uses, row, uses)
    vt_iset(meta.trade_max_uses, row, max_uses)
    int flag = 0
    if disabled:
        flag = 1
    vt_iset(meta.trade_disabled, row, flag)
    meta.trade_rows = row + 1
    return 0


public def vmeta_set_merchant(meta: VServerMeta*, level: int, xp: int,
                              progress: bool, restock: bool) -> int:
    if meta == null:
        return 1
    meta.merchant_level = level
    meta.merchant_xp = xp
    meta.merchant_progress = progress
    meta.merchant_restock = restock
    return 0


public def vmeta_trade_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.trade_rows


public def vmeta_trade_result(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.trade_rows:
        return vmeta_absent()
    return vt_iget(meta.trade_result, row)


public def vmeta_trade_available(meta: VServerMeta*, row: int) -> bool:
    if meta == null or row < 0 or row >= meta.trade_rows:
        return false
    if vt_iget(meta.trade_disabled, row) != 0:
        return false
    return vt_iget(meta.trade_uses, row) < vt_iget(meta.trade_max_uses, row)


# --- waypoints ----------------------------------------------------------------


def vmeta_waypoint_find(meta: VServerMeta*, body: int64[], offset: int64,
                        length: int64) -> int:
    int row = 0
    while row < meta.waypoint_rows:
        if vmeta_matches(meta.waypoint_names, row * vmeta_id_stride(),
                         body, offset, length, vmeta_id_stride()) == 1:
            return row
        row = row + 1
    return vmeta_absent()


# `name_length` < 0 keys the waypoint by UUID instead of by name.
public def vmeta_track_waypoint(meta: VServerMeta*, body: int64[], offset: int64,
                                length: int64, uuid_high: int64[],
                                uuid_low: int64[], kind: int, a: int, b: int,
                                c: int, color: int) -> int:
    if meta == null or kind < 0 or kind > 3:
        return 1
    int row = vmeta_absent()
    if length >= 0:
        row = vmeta_waypoint_find(meta, body, offset, length)
    else:
        int scan = 0
        while scan < meta.waypoint_rows:
            if vt_iget(meta.waypoint_uuid_high, scan * 2) == (int)uuid_high[0]:
                if vt_iget(meta.waypoint_uuid_low, scan * 2) == (int)uuid_low[0]:
                    row = scan
                    break
            scan = scan + 1
    if row == vmeta_absent():
        if meta.waypoint_rows >= vmeta_waypoint_max():
            return 1
        row = meta.waypoint_rows
        meta.waypoint_rows = row + 1
        vmeta_store(meta.waypoint_names, row * vmeta_id_stride(),
                    body, offset, length, vmeta_id_stride())
    vt_iset(meta.waypoint_uuid_high, row * 2, (int)uuid_high[0])
    vt_iset(meta.waypoint_uuid_high, row * 2 + 1, (int)uuid_high[1])
    vt_iset(meta.waypoint_uuid_low, row * 2, (int)uuid_low[0])
    vt_iset(meta.waypoint_uuid_low, row * 2 + 1, (int)uuid_low[1])
    vt_iset(meta.waypoint_kind, row, kind)
    vt_iset(meta.waypoint_a, row, a)
    vt_iset(meta.waypoint_b, row, b)
    vt_iset(meta.waypoint_c, row, c)
    vt_iset(meta.waypoint_color, row, color)
    return row


public def vmeta_untrack_waypoint(meta: VServerMeta*, body: int64[],
                                  offset: int64, length: int64,
                                  uuid_high: int64[], uuid_low: int64[]) -> int:
    if meta == null:
        return 1
    int row = vmeta_absent()
    if length >= 0:
        row = vmeta_waypoint_find(meta, body, offset, length)
    else:
        int scan = 0
        while scan < meta.waypoint_rows:
            if vt_iget(meta.waypoint_uuid_high, scan * 2) == (int)uuid_high[0]:
                if vt_iget(meta.waypoint_uuid_low, scan * 2) == (int)uuid_low[0]:
                    row = scan
                    break
            scan = scan + 1
    if row == vmeta_absent():
        return 0
    int last = meta.waypoint_rows - 1
    while row < last:
        int index = 0
        while index < vmeta_id_stride():
            vt_put(meta.waypoint_names, row * vmeta_id_stride() + index,
                   vt_at(meta.waypoint_names, (row + 1) * vmeta_id_stride() + index))
            index = index + 1
        vt_iset(meta.waypoint_kind, row, vt_iget(meta.waypoint_kind, row + 1))
        vt_iset(meta.waypoint_a, row, vt_iget(meta.waypoint_a, row + 1))
        vt_iset(meta.waypoint_b, row, vt_iget(meta.waypoint_b, row + 1))
        vt_iset(meta.waypoint_c, row, vt_iget(meta.waypoint_c, row + 1))
        vt_iset(meta.waypoint_color, row, vt_iget(meta.waypoint_color, row + 1))
        index = 0
        while index < 2:
            vt_iset(meta.waypoint_uuid_high, row * 2 + index,
                    vt_iget(meta.waypoint_uuid_high, (row + 1) * 2 + index))
            vt_iset(meta.waypoint_uuid_low, row * 2 + index,
                    vt_iget(meta.waypoint_uuid_low, (row + 1) * 2 + index))
            index = index + 1
        row = row + 1
    meta.waypoint_rows = last
    return 0


public def vmeta_waypoint_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.waypoint_rows


public def vmeta_waypoint_kind(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.waypoint_rows:
        return vmeta_absent()
    return vt_iget(meta.waypoint_kind, row)


public def vmeta_waypoint_axis(meta: VServerMeta*, row: int, axis: int) -> int:
    if meta == null or row < 0 or row >= meta.waypoint_rows:
        return 0
    if axis == 0:
        return vt_iget(meta.waypoint_a, row)
    if axis == 1:
        return vt_iget(meta.waypoint_b, row)
    if axis == 2:
        return vt_iget(meta.waypoint_c, row)
    return 0

# ===== protocol_chunk.cpy =====
# Vortex engine - protocol PalettedContainer decoder.


def sec_wire_read_varint(b: VBuf*, ok: int*) -> int:
    *ok = 0
    int value = vbuf_take_varint(b, ok)
    if *ok == 0 or value < 0:
        *ok = 0
        return 0
    return value


def sec_wire_read_container(b: VBuf*, c: VContainer*, entries: int,
                            blocks: bool, global_bits: int) -> int:
    if vbuf_avail(b) < 1:
        return 0
    int wire_bits = (int)vbuf_take_u8(b)
    int bits = 0
    bool has_palette = false
    if wire_bits == 0:
        int ok = 0
        int value = sec_wire_read_varint(b, &ok)
        if ok == 0:
            return 0
        vcont_reset(c, value)
        return 1
    if blocks:
        if wire_bits <= 4:
            bits = 4
            has_palette = true
        elif wire_bits <= 8:
            bits = wire_bits
            has_palette = true
        else:
            bits = global_bits
            if bits < wire_bits:
                bits = wire_bits
    else:
        if wire_bits <= 3:
            bits = wire_bits
            has_palette = true
        else:
            bits = global_bits
            if bits < wire_bits:
                bits = wire_bits
    if bits < 1 or bits > 32:
        return 0
    if has_palette:
        int ok = 0
        int palette_count = sec_wire_read_varint(b, &ok)
        if ok == 0 or palette_count < 1 or palette_count > (1 << bits):
            return 0
        vcont_reset(c, 0)
        int i = 0
        while i < palette_count:
            int value = sec_wire_read_varint(b, &ok)
            if ok == 0:
                return 0
            vcont_palette_add(c, value)
            i += 1
        if vcont_palette_len(c) != palette_count:
            return 0
    else:
        c.direct_bits = bits
    int per_word = 64 / bits
    int word_count = (entries + per_word - 1) / per_word
    if vbuf_avail(b) < word_count * 8:
        return 0
    if has_palette:
        vcont_alloc(c, bits)
    else:
        vcont_alloc_direct(c, bits)
    int word = 0
    while word < word_count:
        vcont_set_word(c, word, (uint64)vbuf_take_i64_be(b))
        word += 1
    return 1


public def sec_read_wire_sections(b: VBuf*, count: int, min_section: int,
                                 block_global_bits: int,
                                 biome_global_bits: int,
                                 ok: int*) -> char*:
    *ok = 0
    if b == null or count < 1 or block_global_bits < 1 or biome_global_bits < 1:
        return null
    char* sections = vt_calloc_ptrs(count)
    int i = 0
    while i < count:
        if vbuf_avail(b) < 2:
            vworld_free_column(sections, count)
            return null
        int non_empty = vbuf_take_i16_be(b)
        if non_empty < 0 or non_empty > 4096:
            vworld_free_column(sections, count)
            return null
        VSection* section = sec_new_for_wire(min_section + i,
                                             block_global_bits,
                                             biome_global_bits)
        section.non_empty = non_empty
        int blocks_ok = sec_wire_read_container(b, section.blocks,
                                                sec_block_count(), true,
                                                block_global_bits)
        int biomes_ok = sec_wire_read_container(b, section.biomes,
                                                sec_biome_count(), false,
                                                biome_global_bits)
        if blocks_ok == 0 or biomes_ok == 0:
            sec_free(section)
            vworld_free_column(sections, count)
            return null
        vt_ptr_set(sections, i, (void*)section)
        i += 1
    if vbuf_avail(b) != 0:
        vworld_free_column(sections, count)
        return null
    *ok = 1
    return sections


# Chunks Biomes repeats the biome container of every section in a column, in
# ascending y, with no block container and no light. The decoded values are
# copied into the section already in memory; a column the client has not
# loaded is walked and dropped rather than materialised half-empty.
public def sec_apply_wire_biomes(b: VBuf*, world: VWorld*, chunk_x: int,
                                 chunk_z: int, count: int, min_section: int,
                                 biome_global_bits: int) -> int:
    if b == null or world == null or count < 1:
        return 0
    int i = 0
    while i < count:
        VSection* decoded = sec_new_for_wire(min_section + i,
                                             sec_blocks_direct_bits(),
                                             biome_global_bits)
        int biomes_ok = sec_wire_read_container(b, decoded.biomes,
                                                sec_biome_count(), false,
                                                biome_global_bits)
        if biomes_ok == 0:
            sec_free(decoded)
            return 0
        VSection* target = vworld_section(world, chunk_x, chunk_z,
                                          min_section + i)
        if target != null:
            int at = 0
            while at < sec_biome_count():
                vcont_set(target.biomes, at, vcont_at(decoded.biomes, at))
                at += 1
        sec_free(decoded)
        i += 1
    return 1


# ===== blockdb.cpy =====
# Vortex engine - block facts lookup.
#
# The mesher needs three things for a block state id: whether it is air, what
# geometry it has, and whether it hides the neighbour's face. The block state
# id -> block mapping comes from the vanilla data generator's blocks report,
# packed into a compact binary read by the C layer in src/engine/blockdb.c.
#
# On first launch the executable builds that binary itself: blockdb_setup.c
# discovers a local Minecraft installation, runs its Java data generator and
# writes generated/blockdb.bin. No scripting runtime is involved. tools/ holds
# optional developer equivalents, never required to run the client.
#
# The database is optional. Without it the mesher falls back to state 0 = air
# and every other state = opaque cube, which keeps a world visible even when
# the generated data has not been built.
#
# License boundary: the binary is generated from user-supplied version data and
# lives under generated/; it is not part of the repository. See
# docs/PARITY_BOUNDARY.md.



# ---- classification flags, matching tools/gen_blockdb.py ---------------------

public def block_flag_air() -> int:
    return 1


public def block_flag_fluid() -> int:
    return 2


public def block_flag_cube() -> int:
    return 4


public def block_flag_opaque() -> int:
    return 8


public def block_flag_translucent() -> int:
    return 16


public def block_flag_leaves() -> int:
    return 32


public def block_flag_cross() -> int:
    return 64


# ---- loading -----------------------------------------------------------------

public def blockdb_default_path() -> str:
    return vt_blockdb_path_from_env()


public def blockdb_load(path: str) -> int:
    return vt_blockdb_load(path)


public def blockdb_load_default() -> int:
    return vt_blockdb_load(vt_blockdb_path_from_env())


public def blockdb_unload() -> void:
    vt_blockdb_unload()


public def blockdb_loaded() -> int:
    return vt_blockdb_loaded()


public def blockdb_verify() -> int:
    return vt_blockdb_verify()


public def blockdb_state_count() -> int:
    return vt_blockdb_state_count()


public def blockdb_block_count() -> int:
    return vt_blockdb_block_count()


# ---- state queries -----------------------------------------------------------

# Raw flags, or -1 when the state is unknown or no database is loaded.
public def blockdb_flags(state: int) -> int:
    return vt_blockdb_flags(state)


public def blockdb_protocol(state: int) -> int:
    return vt_blockdb_protocol(state)


# ---- geometry shape and tint (name-based heuristics) -------------------------

public def block_shape_cube() -> int:
    return 0


public def block_shape_skip() -> int:
    return 255


public def block_tint_none() -> int:
    return 0


public def block_tint_grass() -> int:
    return 1


public def block_tint_foliage() -> int:
    return 2


public def block_tint_water() -> int:
    return 3


# Canonical geometry code for a state; see engine/blockdb.c for the table.
public def blockdb_shape(state: int) -> int:
    return ((int)vt_blockdb_shape_tint(state)) & 255


public def blockdb_tint(state: int) -> int:
    return (((int)vt_blockdb_shape_tint(state)) >> 8) & 255


# Packed 0xRRGGBB tint for a biome id and tint kind. Defaults to the plains
# colours until the registry layer fills the override table.
public def biome_color(biome: int, kind: int) -> int:
    return (int)vt_biome_color(biome, kind)


public def biome_color_set(biome: int, grass: int, foliage: int, water: int) -> void:
    vt_biome_color_set(biome, grass, foliage, water)


public def biome_colors_reset() -> void:
    vt_biome_colors_reset()


public def blockdb_has(state: int, flag: int) -> int:
    int flags = vt_blockdb_flags(state)
    if flags < 0:
        if state == 0:
            return 1 if flag == block_flag_air() else 0
        return 1 if flag == block_flag_opaque() or flag == block_flag_cube() else 0
    if (flags & flag) != 0:
        return 1
    return 0


public def blockdb_is_air(state: int) -> int:
    return blockdb_has(state, block_flag_air())


# A full cube, so the mesher emits its six faces (subject to culling).
public def blockdb_is_cube(state: int) -> int:
    return blockdb_has(state, block_flag_cube())


# Opaque enough that a neighbouring full cube's shared face is invisible.
public def blockdb_is_opaque(state: int) -> int:
    return blockdb_has(state, block_flag_opaque())


public def blockdb_is_translucent(state: int) -> int:
    return blockdb_has(state, block_flag_translucent())


public def blockdb_is_leaves(state: int) -> int:
    return blockdb_has(state, block_flag_leaves())


public def blockdb_is_cross(state: int) -> int:
    return blockdb_has(state, block_flag_cross())


public def blockdb_is_fluid(state: int) -> int:
    return blockdb_has(state, block_flag_fluid())


# 1 when two neighbouring states share a face that can be dropped: the near
# block is a full cube and the far one hides the face. Leaves are culled
# against leaves, translucent blocks against their own block, everything else
# only against opaque cubes.
public def blockdb_hides_face(near: int, far: int) -> int:
    if blockdb_is_air(near) == 1 or blockdb_is_cube(near) == 0:
        return 0
    if blockdb_is_air(far) == 1:
        return 0
    if blockdb_is_opaque(far) == 1:
        return 1
    if blockdb_is_leaves(near) == 1 and blockdb_is_leaves(far) == 1:
        return 1
    if blockdb_is_translucent(near) == 1 and blockdb_is_translucent(far) == 1:
        int a = vt_blockdb_protocol(near)
        int b = vt_blockdb_protocol(far)
        if a >= 0 and a == b:
            return 1
    return 0


# Block name without the namespace, or "" when unknown.
public def blockdb_name(state: int) -> str:
    char* buffer = vt_calloc_char(96)
    int length = vt_blockdb_name(state, buffer, 96)
    if length < 0:
        vt_free((void*)buffer)
        return ""
    str out = vt_dup(buffer)
    vt_free((void*)buffer)
    return out


# ---- record view, used by the loader test ------------------------------------

public def blockdb_first_state_at(index: int) -> int:
    return vt_blockdb_first_state_at(index)


public def blockdb_state_count_at(index: int) -> int:
    return vt_blockdb_state_count_at(index)


public def blockdb_flags_at(index: int) -> int:
    return vt_blockdb_flags_at(index)


public def blockdb_protocol_at(index: int) -> int:
    return vt_blockdb_protocol_at(index)


public def blockdb_name_at(index: int) -> str:
    char* buffer = vt_calloc_char(96)
    int length = vt_blockdb_name_at(index, buffer, 96)
    if length < 0:
        vt_free((void*)buffer)
        return ""
    str out = vt_dup(buffer)
    vt_free((void*)buffer)
    return out


public def blockdb_name_length_at(index: int) -> int:
    return vt_blockdb_name_length_at(index)


# ===== anvil.cpy =====
# Vortex engine - Anvil region storage and the chunk NBT schema.
#
# Anvil is the layout every Java Edition world keeps chunks in, so saving a
# world here means producing a file the game can open. The rules:
#
#   offset  size    what
#   0       4096    location table: 1024 big endian entries, three bytes of
#                   sector offset plus one byte of sector count, indexed by
#                   (x & 31) + (z & 31) * 32
#   4096    4096    modification time table: 1024 big endian int32 seconds
#   8192    ...     4 KiB sectors, numbered from 0, chunk data starts at 2
#
#   record          int32 big endian payload length - counting the compression
#                   byte - then the compression byte, then the chunk's NBT
#
# Inside a record the chunk is a TAG_Compound with an empty name. This module
# writes the modern schema: DataVersion, sections of {Y, block_states, biomes,
# BlockLight, SkyLight}, Heightmaps, TileEntities, Entities, Status, Version,
# xPos, yPos, zPos. Reading also accepts the 1.13-1.17 `Level` wrapper, its
# `Palette`/`BlockData` containers and `Light` spelling, and the pre-1.13
# direct `Blocks`/`Add` byte arrays, so an older world still loads.
#
# Palette entries are where compatibility bites. The game writes a block
# palette as compounds of {Name, Properties} and a biome palette as
# namespaced id strings, while the engine's containers hold numeric ids. The
# mapping lives in an optional registry table (anvil_registry_load): one line
# per entry, produced from the vanilla data reports by the same auto-setup
# that builds the block database. Without it a palette is written as plain
# ids, which this engine round-trips but the game does not read, and the
# counter in anvil_lossy_palettes says so rather than hiding it.
#
# Everything this client cannot know - tile entity and entity payloads,
# structures, light population - is kept exactly as the file had it: a chunk
# being replaced starts from a copy of the compound it was stored in, so only
# the fields the engine really models are rewritten. A load, edit and save
# cycle therefore loses nothing it did not deliberately change.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.



# ---- format constants --------------------------------------------------------

public def anvil_sector_bytes() -> int:
    return 4096


public def anvil_region_chunks() -> int:
    return 1024


public def anvil_header_bytes() -> int:
    return 8192


# Chunk sectors start after the two header sectors.
public def anvil_first_sector() -> int:
    return 2


# The location table gives one byte of sector count, and 0 means absent.
public def anvil_max_sectors() -> int:
    return 255


# The `Version` byte the game writes for a chunk it finished generating.
public def anvil_format_version() -> int:
    return 8


public def anvil_status_full() -> str:
    return "minecraft:full"


# Chunk record compression bytes.
public def anvil_comp_gzip() -> int:
    return 32


public def anvil_comp_zlib() -> int:
    return 33


public def anvil_comp_none() -> int:
    return 34


# The DataVersion written when the caller sets none. Chunk upgrades key off
# this number and the value for the 26.3 profile is not published, so it is
# data the caller owns rather than something invented here: 0 claims no
# upgrade history, which is what a client that only reads its own worlds needs.
public def anvil_default_data_version() -> int64:
    return (int64)0


public def anvil_palette_numeric() -> int:
    return 0


public def anvil_palette_named() -> int:
    return 1


public def anvil_palette_string() -> int:
    return 2


# Registry row kinds.
public def anvil_kind_state() -> int:
    return 0


public def anvil_kind_biome() -> int:
    return 1


# The five heightmap kinds, in the order the schema lists them.
public def anvil_hm_count() -> int:
    return 5


def anvil_hm_name(kind: int) -> str:
    if kind == 0:
        return "MOTION_BLOCKING"
    if kind == 1:
        return "MOTION_BLOCKING_NO_LEAVES"
    if kind == 2:
        return "OCEAN_FLOOR"
    if kind == 3:
        return "OCEAN_FLOOR_AGED"
    if kind == 4:
        return "WORLD_SURFACE"
    return ""


# Which heightmap kinds an engine column carries, or -1 for the ones it does
# not store and therefore has to recompute from the blocks.
def anvil_hm_engine_kind(kind: int) -> int:
    if kind == 0:
        return hm_motion_blocking()
    if kind == 4:
        return hm_world_surface()
    return -1


# Chunk record chunk: 4 length bytes, 1 compression byte, then the payload.
def anvil_record_overhead() -> int:
    return 5


# ---- the state and biome name table ------------------------------------------

struct VRegistry:
    int rows
    int state_count           # one past the highest block state id
    int biome_count
    str blob                  # names and property strings, concatenated
    int* kind
    int* id
    int* name_off
    int* name_len
    int* props_off
    int* props_len
    int* state_at             # state id -> row + 1
    int* biome_at             # biome id -> row + 1
    int* slots                # (name, properties) -> row + 1
    int slot_cap


def anvil_registry_stride() -> int:
    return 6


# The bracket codes: core.cpy has no constants for them.
def anvil_code_bracket_open() -> int:
    return 91


def anvil_code_bracket_close() -> int:
    return 93


# One parsed table line. `out` is the six fields anvil_registry_stride counts:
# kind (-1 when the line is not a row), id, name start, name end, properties
# start and properties end, the last four offsets inside `line`.
def anvil_parse_line(line: str, out: int*) -> void:
    int n = vt_strlen(line)
    vt_iset(out, 0, -1)
    vt_iset(out, 1, -1)
    if n < 4:
        return
    int first = vt_at(line, 0)
    int kind = -1
    if first == 66 or first == 98:
        kind = anvil_kind_state()
    if first == 73 or first == 105:
        kind = anvil_kind_biome()
    if kind < 0:
        return
    if vt_at(line, 1) != code_space():
        return
    int space = str_find_code(line, 2, code_space())
    if space < 0:
        return
    int ok = 0
    str id_text = str_slice(line, 2, space)
    int id = parse_int_or(id_text, -1, &ok)
    vt_free((void*)id_text)
    if ok == 0 or id < 0 or id > 1048576:
        return
    int rest = space + 1
    while rest < n and vt_at(line, rest) == code_space():
        rest = rest + 1
    int open = str_find_code(line, rest, anvil_code_bracket_open())
    int name_end = n
    int props_start = n
    int props_end = n
    if open >= 0:
        name_end = open
        props_start = open + 1
        int close = str_find_code(line, props_start, anvil_code_bracket_close())
        if close < 0:
            props_end = n
        else:
            props_end = close
    if rest >= name_end:
        return
    vt_iset(out, 0, kind)
    vt_iset(out, 1, (int)id)
    vt_iset(out, 2, rest)
    vt_iset(out, 3, name_end)
    vt_iset(out, 4, props_start)
    vt_iset(out, 5, props_end)


def anvil_pairs_sorted(pairs: str[]) -> void:
    int n = (int)len(pairs)
    int i = 1
    while i < n:
        str key = pairs[i]
        int j = i - 1
        while j >= 0 and str_compare(pairs[j], key) > 0:
            pairs[j + 1] = pairs[j]
            j = j - 1
        pairs[j + 1] = key
        i = i + 1


# Releases the heap strings a pair array holds. Both producers hand their
# entries over when they call anvil_props_sorted, so the sorted text is built
# and the originals dropped in one place.
def anvil_pairs_release(pairs: str[]) -> void:
    int i = 0
    int n = (int)len(pairs)
    while i < n:
        vt_free((void*)pairs[i])
        i = i + 1


# The canonical property text: every `key=value` pair in alphabetical order by
# key, comma separated. Sorting both sides means a compound written by another
# tool in another order still matches the table.
def anvil_props_sorted(pairs: str[]) -> str:
    int n = (int)len(pairs)
    VStr* sink = vstr_new(64)
    int i = 0
    while i < n:
        if i > 0:
            vstr_put(sink, code_comma())
        vstr_put_text(sink, pairs[i])
        i = i + 1
    str result = vstr_text(sink)
    vstr_free(sink)
    return result


def anvil_props_canonical(text: str, from: int, to: int) -> str:
    str[] pairs = new str[0]
    int at = from
    while at < to:
        int stop = str_find_code(text, at, code_comma())
        if stop < 0 or stop >= to:
            stop = to
        str source = str_slice(text, at, stop)
        str pair = str_trim(source)
        vt_free((void*)source)
        if vt_strlen(pair) > 0:
            append(pairs, pair)
        else:
            vt_free((void*)pair)
        at = stop + 1
    anvil_pairs_sorted(pairs)
    str sorted = anvil_props_sorted(pairs)
    anvil_pairs_release(pairs)
    return sorted


# A property value as text: the game writes strings, and older tools have been
# seen writing bytes or bools, so every scalar form is accepted.
def anvil_prop_text(t: VNbt*) -> str:
    if t == null:
        return ""
    if t.kind == nbt_string():
        return t.val_str
    if t.kind == nbt_byte():
        if t.val_int != 0:
            return "true"
        return "false"
    if t.kind == nbt_short() or t.kind == nbt_int():
        return str(t.val_int)
    if t.kind == nbt_long():
        return str(t.val_long)
    return ""


# The same, from a Properties compound.
def anvil_props_from_compound(t: VNbt*) -> str:
    str[] pairs = new str[0]
    if t == null or t.kind != nbt_compound():
        return ""
    int i = 0
    while i < t.items_len:
        VNbt* child = (VNbt*)vt_ptr_get(t.items, i)
        if child != null:
            str value = anvil_prop_text(child)
            VStr* pair = vstr_new(32)
            vstr_put_text(pair, child.name)
            vstr_put(pair, code_equals())
            vstr_put_text(pair, value)
            append(pairs, vstr_text(pair))
            vstr_free(pair)
        i = i + 1
    anvil_pairs_sorted(pairs)
    str sorted = anvil_props_sorted(pairs)
    anvil_pairs_release(pairs)
    return sorted


def anvil_blob_equals(blob: str, off: int, length: int, query: str) -> int:
    int n = vt_strlen(query)
    if n != length:
        return 0
    int i = 0
    while i < n:
        if vt_at(blob, off + i) != vt_at(query, i):
            return 0
        i = i + 1
    return 1


# -1 when the table has no row for this (name, properties) pair. The probe is a
# linear walk from an FNV slot over `name,properties`, the same text the table
# indexes, so both sides agree on what a row is called.
def anvil_registry_find(a: VAnvil*, kind: int, name: str, props: str) -> int:
    VRegistry* r = null
    if a != null:
        r = a.registry
    if r == null or r.rows <= 0:
        return -1
    int mask = r.slot_cap - 1
    # The probe key is the `name,properties` text the table indexes. Assembling
    # it in a sink that is freed here keeps a lookup from leaving a
    # concatenation behind for every palette entry decoded.
    VStr* key = vstr_new(64)
    vstr_put_text(key, name)
    vstr_put(key, code_comma())
    vstr_put_text(key, props)
    uint64 hash = vstr_hash(key) & (uint64)mask
    vstr_free(key)
    int slot = (int)hash
    int probe = 0
    while probe < r.slot_cap:
        int row = vt_iget(r.slots, slot) - 1
        if row < 0:
            return -1
        if vt_iget(r.kind, row) == kind:
            if anvil_blob_equals(r.blob, vt_iget(r.name_off, row),
                                 vt_iget(r.name_len, row), name) == 1:
                if anvil_blob_equals(r.blob, vt_iget(r.props_off, row),
                                     vt_iget(r.props_len, row), props) == 1:
                    return row
        slot = slot + 1
        if slot >= r.slot_cap:
            slot = 0
        probe = probe + 1
    return -1


def anvil_registry_row_id(r: VRegistry*, row: int) -> int:
    if r == null or row < 0 or row >= r.rows:
        return -1
    return vt_iget(r.id, row)


# The row for a numeric id, or -1.
def anvil_registry_row_of(a: VAnvil*, kind: int, id: int) -> int:
    VRegistry* r = null
    if a != null:
        r = a.registry
    if r == null or id < 0:
        return -1
    if kind == anvil_kind_state():
        if id >= r.state_count:
            return -1
        return vt_iget(r.state_at, id) - 1
    if id >= r.biome_count:
        return -1
    return vt_iget(r.biome_at, id) - 1


def anvil_registry_free(r: VRegistry*) -> void:
    if r == null:
        return
    vt_free((void*)r.kind)
    vt_free((void*)r.id)
    vt_free((void*)r.name_off)
    vt_free((void*)r.name_len)
    vt_free((void*)r.props_off)
    vt_free((void*)r.props_len)
    vt_free((void*)r.state_at)
    vt_free((void*)r.biome_at)
    vt_free((void*)r.slots)
    # vstr_text hands over a heap copy, so the blob belongs to this registry:
    # it holds every name and property string, and dropping the pointer would
    # keep all of them alive.
    vt_free((void*)r.blob)
    r.blob = ""
    r.rows = 0
    del r


# The table's default location, which is the folder the block database lives
# in: the auto-setup writes both files together.
public def anvil_registry_default_path() -> str:
    return vt_env_or("VORTEX_REGISTRY_TABLE", "generated/registry.txt")


# Counted rows, highest state id and highest biome id, so the arrays can be
# sized exactly before the fill pass parses every line a second time.
def anvil_registry_scan(text: str, out: int*) -> void:
    int n = vt_strlen(text)
    VStr* line = vstr_new(256)
    int* line_info = vt_calloc_int(anvil_registry_stride())
    int at = 0
    vt_iset(out, 0, 0)
    vt_iset(out, 1, 0)
    vt_iset(out, 2, 0)
    while at < n:
        int stop = at
        while stop < n and vt_at(text, stop) != code_newline():
            stop = stop + 1
        vstr_clear(line)
        vstr_put_trimmed_slice(line, text, at, stop)
        anvil_parse_line((str)line.data, line_info)
        if vt_iget(line_info, 0) >= 0:
            vt_iset(out, 0, vt_iget(out, 0) + 1)
            if vt_iget(line_info, 0) == anvil_kind_state():
                if vt_iget(line_info, 1) + 1 > vt_iget(out, 1):
                    vt_iset(out, 1, vt_iget(line_info, 1) + 1)
            else:
                if vt_iget(line_info, 1) + 1 > vt_iget(out, 2):
                    vt_iset(out, 2, vt_iget(line_info, 1) + 1)
        at = stop + 1
    vstr_free(line)
    vt_free((void*)line_info)


def anvil_registry_build(text: str) -> VRegistry*:
    int* counts = vt_calloc_int(3)
    anvil_registry_scan(text, counts)
    int rows = vt_iget(counts, 0)
    int state_count = vt_iget(counts, 1)
    int biome_count = vt_iget(counts, 2)
    vt_free((void*)counts)
    if rows <= 0:
        return null
    if state_count > 1048577:
        state_count = 1048577
    if biome_count > 1048577:
        biome_count = 1048577

    VRegistry* r = new VRegistry
    r.rows = 0
    r.state_count = state_count
    r.biome_count = biome_count
    r.kind = vt_calloc_int(rows)
    r.id = vt_calloc_int(rows)
    r.name_off = vt_calloc_int(rows)
    r.name_len = vt_calloc_int(rows)
    r.props_off = vt_calloc_int(rows)
    r.props_len = vt_calloc_int(rows)
    r.state_at = vt_calloc_int(state_count)
    r.biome_at = vt_calloc_int(biome_count)
    r.slot_cap = 64
    while r.slot_cap < rows * 4:
        r.slot_cap = r.slot_cap * 2
    r.slots = vt_calloc_int(r.slot_cap)

    # Names and property strings all live in one blob, so a row is four
    # integers rather than two owned allocations, and the name is copied
    # straight from the table line into it. One reused line buffer serves the
    # whole pass.
    VStr* blob = vstr_new(4096)
    int n = vt_strlen(text)
    int* line_info = vt_calloc_int(anvil_registry_stride())
    VStr* line = vstr_new(256)
    int at = 0
    while at < n:
        int stop = at
        while stop < n and vt_at(text, stop) != code_newline():
            stop = stop + 1
        vstr_clear(line)
        vstr_put_trimmed_slice(line, text, at, stop)
        anvil_parse_line((str)line.data, line_info)
        if vt_iget(line_info, 0) >= 0:
            int row = r.rows
            str props = anvil_props_canonical((str)line.data, vt_iget(line_info, 4),
                                              vt_iget(line_info, 5))
            vt_iset(r.kind, row, vt_iget(line_info, 0))
            vt_iset(r.id, row, vt_iget(line_info, 1))
            vt_iset(r.name_off, row, blob.len)
            vstr_put_slice(blob, (str)line.data, vt_iget(line_info, 2),
                           vt_iget(line_info, 3))
            vt_iset(r.name_len, row, blob.len - vt_iget(r.name_off, row))
            vt_iset(r.props_off, row, blob.len)
            vt_iset(r.props_len, row, vt_strlen(props))
            vstr_put_text(blob, props)
            vt_free((void*)props)
            if vt_iget(line_info, 0) == anvil_kind_state():
                if vt_iget(line_info, 1) < r.state_count:
                    vt_iset(r.state_at, vt_iget(line_info, 1), row + 1)
            else:
                if vt_iget(line_info, 1) < r.biome_count:
                    vt_iset(r.biome_at, vt_iget(line_info, 1), row + 1)
            r.rows = row + 1
        at = stop + 1
    vstr_free(line)
    vt_free((void*)line_info)
    r.blob = vstr_text(blob)
    vstr_free(blob)

    # Slots are indexed by the same `name,properties` text a lookup probes
    # with, assembled here in a sink that is reused for every row.
    int i = 0
    int mask = r.slot_cap - 1
    VStr* key = vstr_new(64)
    while i < r.rows:
        vstr_clear(key)
        vstr_put_slice(key, r.blob, vt_iget(r.name_off, i),
                       vt_iget(r.name_off, i) + vt_iget(r.name_len, i))
        vstr_put(key, code_comma())
        vstr_put_slice(key, r.blob, vt_iget(r.props_off, i),
                       vt_iget(r.props_off, i) + vt_iget(r.props_len, i))
        int slot = (int)(vstr_hash(key) & (uint64)mask)
        int probe = 0
        int placed = 0
        while probe < r.slot_cap and placed == 0:
            if vt_iget(r.slots, slot) == 0:
                vt_iset(r.slots, slot, i + 1)
                placed = 1
            else:
                slot = slot + 1
                if slot >= r.slot_cap:
                    slot = 0
            probe = probe + 1
        i = i + 1
    vstr_free(key)
    return r


# Reads the table from disk and installs it, replacing any previous one. A
# missing or empty file is a failure rather than a silent empty registry,
# because numeric palettes would then be written without anyone noticing.
public def anvil_registry_load(a: VAnvil*, path: str) -> int:
    if a == null:
        return -1
    if vt_file_slurp(path) != 0:
        return -1
    int n = (int)vt_file_buf_len()
    char* raw = vt_file_buf()
    if raw == null or n <= 0:
        vt_file_release()
        return -1
    # The file buffer is reused by every later read, so the table text is
    # copied before anything parses it.
    char* text = vt_calloc_char(n + 1)
    vt_copy_bytes(text, 0, raw, 0, n)
    vt_file_release()
    VRegistry* r = anvil_registry_build((str)text)
    vt_free((void*)text)
    if r == null:
        return -1
    if a.registry != null:
        anvil_registry_free(a.registry)
    a.registry = r
    return r.rows


# ---- the save context --------------------------------------------------------

struct VAnvil:
    VRegistry* registry
    int64 data_version
    str status                # owned heap copy; every writer dups before storing
    int compression
    int level
    int lossy_palettes       # named palettes that fell back to numeric ids
    int unknown_names        # names read that the table does not have


public def anvil_new() -> VAnvil*:
    VAnvil* a = new VAnvil
    a.registry = null
    a.data_version = anvil_default_data_version()
    a.status = vt_dup(anvil_status_full())
    a.compression = anvil_comp_gzip()
    a.level = 1
    a.lossy_palettes = 0
    a.unknown_names = 0
    return a


public def anvil_free(a: VAnvil*) -> void:
    if a == null:
        return
    if a.registry != null:
        anvil_registry_free(a.registry)
        a.registry = null
    vt_free((void*)a.status)
    a.status = ""
    del a


public def anvil_set_data_version(a: VAnvil*, value: int64) -> void:
    if a != null:
        a.data_version = value


public def anvil_set_status(a: VAnvil*, status: str) -> void:
    if a == null:
        return
    # The context owns its copy, so a caller may hand over a literal or a
    # string it releases right after and the Status field still writes out
    # correctly later in the session.
    str copy = vt_dup(status)
    vt_free((void*)a.status)
    a.status = copy


public def anvil_set_compression(a: VAnvil*, compression: int, level: int) -> int:
    if a == null:
        return 0
    if compression != anvil_comp_gzip() and compression != anvil_comp_zlib():
        if compression != anvil_comp_none():
            return 0
        a.compression = compression
        a.level = 0
        return 1
    a.compression = compression
    if level < 0:
        level = 0
    if level > 9:
        level = 9
    a.level = level
    return 1


# Cpyte resolves a field of a pointer struct only from a variable, not from
# `a.registry.field`, so each of these takes the registry into a local first.
public def anvil_registry_rows(a: VAnvil*) -> int:
    if a == null or a.registry == null:
        return 0
    VRegistry* r = a.registry
    return r.rows


public def anvil_lossy_palettes(a: VAnvil*) -> int:
    if a == null:
        return 0
    return a.lossy_palettes


public def anvil_unknown_names(a: VAnvil*) -> int:
    if a == null:
        return 0
    return a.unknown_names


public def anvil_state_name(a: VAnvil*, state: int) -> str:
    int row = anvil_registry_row_of(a, anvil_kind_state(), state)
    if row < 0:
        return ""
    VRegistry* r = a.registry
    int from = vt_iget(r.name_off, row)
    int to = from + vt_iget(r.name_len, row)
    return str_slice(r.blob, from, to)


public def anvil_state_props(a: VAnvil*, state: int) -> str:
    int row = anvil_registry_row_of(a, anvil_kind_state(), state)
    if row < 0:
        return ""
    VRegistry* r = a.registry
    int from = vt_iget(r.props_off, row)
    int to = from + vt_iget(r.props_len, row)
    return str_slice(r.blob, from, to)


public def anvil_biome_name(a: VAnvil*, biome: int) -> str:
    int row = anvil_registry_row_of(a, anvil_kind_biome(), biome)
    if row < 0:
        return ""
    VRegistry* r = a.registry
    int from = vt_iget(r.name_off, row)
    int to = from + vt_iget(r.name_len, row)
    return str_slice(r.blob, from, to)


# The state a saved palette entry names, or -1 when this table does not know
# it. `blocks` picks the compound form the game uses for states from the string
# form it uses for biomes.
def anvil_entry_state(a: VAnvil*, entry: VNbt*, blocks: bool) -> int:
    if entry == null:
        return -1
    if entry.kind == nbt_int() or entry.kind == nbt_short() or entry.kind == nbt_byte():
        return entry.val_int
    if entry.kind == nbt_long():
        return (int)entry.val_long
    if blocks:
        if entry.kind != nbt_compound():
            return -1
        str name = nbt_str_value(nbt_find(entry, "Name"), "")
        if vt_strlen(name) <= 0:
            return -1
        str props = anvil_props_from_compound(nbt_find(entry, "Properties"))
        int row = anvil_registry_find(a, anvil_kind_state(), name, props)
        if row < 0:
            if a != null:
                a.unknown_names = a.unknown_names + 1
            return -1
        VRegistry* states = a.registry
        return vt_iget(states.id, row)
    if entry.kind != nbt_string():
        return -1
    int biome_row = anvil_registry_find(a, anvil_kind_biome(), entry.val_str, "")
    if biome_row < 0:
        if a != null:
            a.unknown_names = a.unknown_names + 1
        return -1
    VRegistry* biomes = a.registry
    return vt_iget(biomes.id, biome_row)


# ---- NBT helpers -------------------------------------------------------------

# A deep copy under a new key. Nothing in the tree is shared with the source,
# so the clone and the original can be freed in any order.
def anvil_nbt_clone(t: VNbt*, name: str) -> VNbt*:
    if t == null:
        return null
    VNbt* c = nbt_new(t.kind, name)
    c.val_int = t.val_int
    c.val_long = t.val_long
    c.val_float = t.val_float
    c.val_double = t.val_double
    # A string payload is owned by the node that holds it, so the copy takes
    # its own rather than sharing the source's and freeing it twice.
    if t.kind == nbt_string():
        c.val_str = vt_dup(t.val_str)
    if t.bytes != null and t.bytes_len > 0:
        nbt_set_bytes(c, t.bytes, t.bytes_len)
    if t.ints != null and t.ints_len > 0:
        nbt_set_ints(c, t.ints_len)
        int i = 0
        while i < t.ints_len:
            nbt_set_int_at(c, i, vt_iget(t.ints, i))
            i = i + 1
    if t.longs != null and t.longs_len > 0:
        nbt_set_longs(c, t.longs_len)
        int j = 0
        while j < t.longs_len:
            nbt_set_long_at(c, j, (int64)vt_uget(t.longs, j))
            j = j + 1
    int k = 0
    while k < t.items_len:
        VNbt* child = (VNbt*)vt_ptr_get(t.items, k)
        if child != null:
            nbt_append(c, anvil_nbt_clone(child, child.name))
        k = k + 1
    return c


# Drops every child of `root` stored under `name`, freeing those subtrees.
# Returns how many went.
public def anvil_nbt_remove(root: VNbt*, name: str) -> int:
    if root == null or root.kind != nbt_compound():
        return 0
    int removed = 0
    VNbt* kept = nbt_compound_of("")
    int i = 0
    while i < root.items_len:
        VNbt* child = (VNbt*)vt_ptr_get(root.items, i)
        if child == null:
            i = i + 1
        else:
            if vt_eq(child.name, name) == 1:
                nbt_free(child)
                removed = removed + 1
            else:
                nbt_append(kept, child)
            i = i + 1
    root.items = kept.items
    root.items_len = kept.items_len
    root.items_cap = kept.items_cap
    kept.items = null
    kept.items_len = 0
    kept.items_cap = 0
    del kept
    return removed


# Replaces the value stored under `name`. A compound is a map, so the new
# entry goes at the end rather than keeping the old position.
def anvil_nbt_replace(root: VNbt*, name: str, value: VNbt*) -> void:
    if root == null or value == null:
        return
    anvil_nbt_remove(root, name)
    # The key is the caller's string; nbt_set_name keeps the node's own copy.
    nbt_set_name(value, name)
    nbt_append(root, value)


# Either spelling of a key: the schema renamed several fields along the way,
# and a world written by an older game still carries the old ones.
def anvil_nbt_find_any(t: VNbt*, first: str, second: str) -> VNbt*:
    if t == null:
        return null
    VNbt* found = nbt_find(t, first)
    if found != null:
        return found
    return nbt_find(t, second)


# ---- containers --------------------------------------------------------------

# 1 when every palette entry has a table row, which is what makes the named
# form the game writes available for the whole container.
def anvil_palette_named_ok(a: VAnvil*, c: VContainer*, blocks: bool) -> int:
    int slots = sec_palette_size(c)
    int i = 0
    int ok = 1
    while i < slots:
        int row = -1
        if blocks:
            row = anvil_registry_row_of(a, anvil_kind_state(), sec_palette_entry(c, i))
        else:
            row = anvil_registry_row_of(a, anvil_kind_biome(), sec_palette_entry(c, i))
        if row < 0:
            ok = 0
        i = i + 1
    return ok


def anvil_container_style(a: VAnvil*, c: VContainer*, blocks: bool) -> int:
    if a == null:
        return anvil_palette_numeric()
    if anvil_registry_rows(a) <= 0:
        return anvil_palette_numeric()
    if anvil_palette_named_ok(a, c, blocks) == 0:
        a.lossy_palettes = a.lossy_palettes + 1
        return anvil_palette_numeric()
    if blocks:
        return anvil_palette_named()
    return anvil_palette_string()


def anvil_props_compound(props: str) -> VNbt*:
    int n = vt_strlen(props)
    if n <= 0:
        return null
    VNbt* root = nbt_compound_of("Properties")
    int at = 0
    while at < n:
        int stop = str_find_code(props, at, code_comma())
        if stop < 0:
            stop = n
        str source = str_slice(props, at, stop)
        str pair = str_trim(source)
        vt_free((void*)source)
        int split = str_find_code(pair, 0, code_equals())
        if split > 0:
            str key_text = str_slice(pair, 0, split)
            str key = str_trim(key_text)
            vt_free((void*)key_text)
            str value_text = str_slice(pair, split + 1, vt_strlen(pair))
            str value = str_trim(value_text)
            vt_free((void*)value_text)
            if vt_strlen(key) > 0:
                # nbt_string_of takes its own copies, so both halves are
                # released here.
                nbt_append(root, nbt_string_of(key, value))
            vt_free((void*)key)
            vt_free((void*)value)
        vt_free((void*)pair)
        at = stop + 1
    if root.items_len <= 0:
        nbt_free(root)
        return null
    return root


# `{Name: "minecraft:stone", Properties: {axis: "y"}}`. The table holds the
# property text already sorted, which is the order this writes them in; the
# reader sorts too, so a compound from another tool matches either way.
def anvil_state_entry(a: VAnvil*, state: int) -> VNbt*:
    VNbt* entry = nbt_compound_of("")
    # The table hands out fresh copies of a row's text; the node keeps its own,
    # so these are released as soon as they are written.
    str name = anvil_state_name(a, state)
    nbt_append(entry, nbt_string_of("Name", name))
    vt_free((void*)name)
    str text = anvil_state_props(a, state)
    VNbt* props = anvil_props_compound(text)
    vt_free((void*)text)
    if props != null:
        nbt_append(entry, props)
    return entry


# The saved form of one container, named `block_states` or `biomes`:
# `{palette: [...], data: [long...]}`. A uniform container writes its single
# entry and no data array, and a container in direct mode is re-packed into
# palette form first, which is what the game does with both.
def anvil_container_to_nbt(a: VAnvil*, c: VContainer*, blocks: bool,
                           name: str) -> VNbt*:
    VContainer* encoded = c
    VContainer* temporary = c
    if vcont_mode(c) == vcont_direct_mode():
        temporary = vcont_new(vcont_count(c), c.min_bits, 30, c.direct_bits)
        int at = 0
        while at < vcont_count(c):
            vcont_set(temporary, at, vcont_at(c, at))
            at = at + 1
        vcont_compact(temporary)
        encoded = temporary

    int style = anvil_container_style(a, encoded, blocks)
    int slots = sec_palette_size(encoded)
    int element = nbt_int()
    if style == anvil_palette_named():
        element = nbt_compound()
    if style == anvil_palette_string():
        element = nbt_string()
    VNbt* root = nbt_compound_of(name)
    VNbt* palette = nbt_list_of("palette", element)
    int i = 0
    while i < slots:
        int value = sec_palette_entry(encoded, i)
        if style == anvil_palette_numeric():
            nbt_append(palette, nbt_int_of("", value))
        else:
            if style == anvil_palette_string():
                str biome = anvil_biome_name(a, value)
                nbt_append(palette, nbt_string_of("", biome))
                vt_free((void*)biome)
            else:
                nbt_append(palette, anvil_state_entry(a, value))
        i = i + 1
    nbt_append(root, palette)

    int bits = vcont_save_bits_for(encoded)
    if bits > 0:
        VNbt* data = nbt_new(nbt_long_array(), "data")
        int words = vcont_save_words_for(encoded, bits)
        nbt_set_longs(data, words)
        int w = 0
        while w < words:
            nbt_set_long_at(data, w, (int64)vcont_save_word(encoded, w))
            w = w + 1
        nbt_append(root, data)
    if temporary != c:
        vcont_free(temporary)
    return root


# Fills one container from the two nodes a saved form uses. Returns 1 for a
# container that decoded, 0 for a malformed one and -1 for a name the table
# does not know, which must not decode into a wrong block.
def anvil_container_from_nbt(a: VAnvil*, palette: VNbt*, data: VNbt*,
                             c: VContainer*, blocks: bool) -> int:
    if palette == null:
        return 0
    int entries = 0
    int element = nbt_end()
    if palette.kind == nbt_list():
        entries = nbt_child_count(palette)
        element = nbt_list_element_kind(palette)
        if element == nbt_end() and entries > 0:
            VNbt* first = nbt_child_at(palette, 0)
            if first != null:
                element = first.kind
    else:
        if palette.kind == nbt_int_array():
            entries = nbt_int_len(palette)
            element = nbt_int()
        else:
            if palette.kind == nbt_byte_array():
                entries = nbt_byte_len(palette)
                element = nbt_byte()
            else:
                return 0
    if entries <= 0:
        return 0

    # The palette resolves before any word is read, so an unknown name fails
    # the whole container instead of half filling it.
    int[] values = new int[entries]
    int i = 0
    int bad = 0
    int unknown = 0
    while i < entries:
        int value = -1
        if palette.kind == nbt_int_array():
            value = nbt_int_at(palette, i)
        else:
            if palette.kind == nbt_byte_array():
                value = nbt_byte_at(palette, i)
            else:
                value = anvil_entry_state(a, nbt_child_at(palette, i), blocks)
                if value < 0:
                    unknown = 1
        if value < 0:
            bad = 1
        values[i] = value
        i = i + 1
    if bad == 1:
        if unknown == 1:
            return -1
        return 0

    # A file wider than this container can index is decoded in a temporary and
    # copied across, which re-encodes it at the engine's own width.
    int bits = vcont_bits_for(entries, c.min_bits)
    vcont_reset(c, values[0])
    VContainer* decoded = c
    VContainer* temp = null
    if bits > c.max_bits:
        temp = vcont_new(vcont_count(c), c.min_bits, 30, c.direct_bits)
        decoded = temp
    i = 0
    while i < entries:
        vcont_palette_add(decoded, values[i])
        i = i + 1
    if data == null:
        # No data means the section holds the one palette entry.
        if entries == 1:
            vcont_free(temp)
            return 1
        vcont_free(temp)
        return 0
    if data.kind != nbt_long_array():
        vcont_free(temp)
        return 0
    vcont_alloc(decoded, bits)
    int words = nbt_long_len(data)
    int want = vcont_save_words_for(decoded, bits)
    if words > want:
        words = want
    int w = 0
    while w < words:
        vcont_set_word(decoded, w, (uint64)nbt_long_at(data, w))
        w = w + 1
    if temp != null:
        int at = 0
        while at < vcont_count(c):
            vcont_set(c, at, vcont_at(temp, at))
            at = at + 1
        vcont_free(temp)
    return 1


# The pre-1.13 form: one byte per block, with the ninth state bit in `Add`.
def anvil_direct_from_tag(t: VNbt*, add: VNbt*, c: VContainer*) -> int:
    if t == null:
        return 0
    int n = 0
    if t.kind == nbt_byte_array():
        n = nbt_byte_len(t)
    else:
        if t.kind == nbt_int_array():
            n = nbt_int_len(t)
        else:
            return 0
    if n != vcont_count(c):
        return 0
    int i = 0
    while i < n:
        int value = 0
        if t.kind == nbt_byte_array():
            value = nbt_byte_at(t, i)
        else:
            value = nbt_int_at(t, i)
        if add != null and add.kind == nbt_byte_array():
            if nbt_byte_len(add) * 2 >= n:
                int high = nbt_byte_at(add, i / 2)
                if (i % 2) == 0:
                    value = value | ((high & 15) << 8)
                else:
                    value = value | (((high >> 4) & 15) << 8)
        vcont_set(c, i, value & 65535)
        i = i + 1
    return 1


# ---- light -------------------------------------------------------------------

# The saved form is one byte per two blocks, exactly the section's own array.
def anvil_light_tag(light: char*, name: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_byte_array(), name)
    nbt_set_bytes(t, light, sec_light_bytes())
    return t


def anvil_light_read(t: VNbt*, light: char*) -> void:
    if light == null:
        return
    if t == null:
        return
    if t.kind == nbt_byte_array():
        int n = nbt_byte_len(t)
        if n > sec_light_bytes():
            n = sec_light_bytes()
        vt_copy_bytes(light, 0, t.bytes, 0, n)
        int i = n
        while i < sec_light_bytes():
            vt_put(light, i, 0)
            i = i + 1
        return
    # The network spelling - 256 longs, eight bytes little endian each - shows
    # up in files written by tools that round-tripped packets.
    if t.kind == nbt_long_array():
        int w = 0
        int words = nbt_long_len(t)
        if words > sec_light_words():
            words = sec_light_words()
        while w < sec_light_words():
            int64 value = (int64)0
            if w < words:
                value = nbt_long_at(t, w)
            int b = 0
            while b < 8:
                vt_put(light, w * 8 + b, (int)((value >> ((int64)b * (int64)8)) & (int64)255))
                b = b + 1
            w = w + 1
    return


# ---- heightmaps --------------------------------------------------------------

# 256 heights at `base` become the nine big endian longs the format uses. The
# packing straddles word boundaries, which is vt_bits_set's job.
def anvil_hm_tag(values: int*, base: int, name: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_long_array(), name)
    uint64* words = vt_calloc_u64(hm_long_count())
    nbt_set_longs(t, hm_long_count())
    int i = 0
    while i < hm_cells():
        vt_bits_set(words, i, hm_bits(), (uint64)vt_iget(values, base + i))
        i = i + 1
    int w = 0
    while w < hm_long_count():
        nbt_set_long_at(t, w, (int64)vt_uget(words, w))
        w = w + 1
    vt_free((void*)words)
    return t


def anvil_hm_read(t: VNbt*, values: int*, base: int) -> int:
    if t == null or values == null or t.kind != nbt_long_array():
        return 0
    if nbt_long_len(t) < hm_long_count():
        return 0
    uint64* words = vt_calloc_u64(hm_long_count())
    int w = 0
    while w < hm_long_count():
        vt_uset(words, w, (uint64)nbt_long_at(t, w))
        w = w + 1
    int i = 0
    while i < hm_cells():
        int64 raw = vt_bits_get(words, i, hm_bits())
        vt_iset(values, base + i, (int)(raw & (int64)511))
        i = i + 1
    vt_free((void*)words)
    return 1


# Whether a state counts for a heightmap kind. The five kinds differ only in
# what they skip: leaves for MOTION_BLOCKING_NO_LEAVES, fluids for the two
# ocean floors.
def anvil_hm_counts(state: int, kind: int) -> int:
    if state == 0:
        return 0
    if blockdb_loaded() == 0:
        return 1
    if blockdb_is_air(state) == 1:
        return 0
    if kind == 1:
        if blockdb_is_leaves(state) == 1:
            return 0
    if kind == 2 or kind == 3:
        if blockdb_is_fluid(state) == 1:
            return 0
    return 1


# One pass over the column fills all five kinds: the scan stops at the highest
# block each kind still needs. Heights are absolute, as on the wire.
def anvil_hm_compute(world: VWorld*, chunk_x: int, chunk_z: int,
                     values: int*) -> void:
    int x = 0
    while x < 16:
        int z = 0
        while z < 16:
            int pending = 0
            int kind = 0
            while kind < anvil_hm_count():
                if vt_iget(values, kind * 256 + z * 16 + x) == -1:
                    pending = pending + 1
                kind = kind + 1
            int found = 0
            int sy = world.min_section + world.section_count - 1
            while sy >= world.min_section and found < pending:
                VSection* s = vworld_section(world, chunk_x, chunk_z, sy)
                if s != null:
                    int y = 15
                    while y >= 0 and found < pending:
                        int state = sec_block_at_index(s, sec_block_index(x, y, z))
                        kind = 0
                        while kind < anvil_hm_count():
                            if vt_iget(values, kind * 256 + z * 16 + x) == -1:
                                if anvil_hm_counts(state, kind) == 1:
                                    vt_iset(values, kind * 256 + z * 16 + x,
                                           sy * 16 + y)
                                    found = found + 1
                            kind = kind + 1
                        y = y - 1
                sy = sy - 1
            # A column with nothing to count gets height 0: the nine bit field
            # cannot hold the negative `min_y - 1` a below-zero dimension would
            # like, and 0 is what the field reads back as empty.
            kind = 0
            while kind < anvil_hm_count():
                if vt_iget(values, kind * 256 + z * 16 + x) == -1:
                    vt_iset(values, kind * 256 + z * 16 + x, 0)
                kind = kind + 1
            z = z + 1
        x = x + 1


# The engine's stored heightmap column, or null when the chunk is not loaded.
def anvil_world_heightmaps(world: VWorld*, chunk_x: int, chunk_z: int) -> int*:
    if world == null:
        return null
    int index = vworld_find(world, chunk_x, chunk_z)
    if index < 0:
        return null
    return (int*)vt_ptr_get(world.heightmaps, index)


def anvil_hm_copy(source: int*, engine_kind: int, values: int*, kind: int) -> void:
    int base = hm_kind_offset(engine_kind)
    int i = 0
    while i < hm_cells():
        int value = vt_iget(source, base + i)
        if value < 0:
            value = 0
        vt_iset(values, kind * hm_cells() + i, value)
        i = i + 1


# The Heightmaps compound for a column: the two kinds the engine keeps come
# from its own table, the rest are recomputed so a saved chunk is complete.
def anvil_heightmaps_to_nbt(world: VWorld*, chunk_x: int, chunk_z: int) -> VNbt*:
    VNbt* root = nbt_compound_of("Heightmaps")
    int* values = vt_calloc_int(anvil_hm_count() * hm_cells())
    int kind = 0
    while kind < anvil_hm_count():
        int i = 0
        while i < hm_cells():
            vt_iset(values, kind * hm_cells() + i, -1)
            i = i + 1
        kind = kind + 1
    int* column = anvil_world_heightmaps(world, chunk_x, chunk_z)
    if column != null:
        anvil_hm_copy(column, hm_motion_blocking(), values, 0)
        anvil_hm_copy(column, hm_world_surface(), values, 4)
    anvil_hm_compute(world, chunk_x, chunk_z, values)
    kind = 0
    while kind < anvil_hm_count():
        nbt_append(root, anvil_hm_tag(values, kind * hm_cells(), anvil_hm_name(kind)))
        kind = kind + 1
    vt_free((void*)values)
    return root


# ---- sections and chunks -----------------------------------------------------

def anvil_section_to_nbt(a: VAnvil*, s: VSection*) -> VNbt*:
    sec_compact(s)
    VNbt* root = nbt_compound_of("")
    nbt_append(root, anvil_container_to_nbt(a, s.blocks, true, "block_states"))
    nbt_append(root, anvil_container_to_nbt(a, s.biomes, false, "biomes"))
    nbt_append(root, nbt_byte_of("Y", s.y))
    nbt_append(root, anvil_light_tag(s.block_light, "BlockLight"))
    nbt_append(root, anvil_light_tag(s.sky_light, "SkyLight"))
    return root


def anvil_sections_to_nbt(a: VAnvil*, world: VWorld*, chunk_x: int,
                          chunk_z: int) -> VNbt*:
    VNbt* list = nbt_list_of("sections", nbt_compound())
    int sy = world.min_section
    while sy < world.min_section + world.section_count:
        VSection* s = vworld_section(world, chunk_x, chunk_z, sy)
        if s != null:
            nbt_append(list, anvil_section_to_nbt(a, s))
        sy = sy + 1
    return list


# A block or biome half, in whichever of the three schema generations the
# compound is written. 1 decoded, 0 malformed, -1 an unknown registry name.
def anvil_side_from_section(a: VAnvil*, t: VNbt*, c: VContainer*, blocks: bool) -> int:
    VNbt* container = null
    if blocks:
        container = anvil_nbt_find_any(t, "block_states", "States")
    else:
        container = nbt_find(t, "biomes")
        if container == null:
            container = nbt_find(t, "Biomes")
    if container != null and container.kind == nbt_compound():
        VNbt* palette = anvil_nbt_find_any(container, "palette", "Palette")
        VNbt* data = anvil_nbt_find_any(container, "data", "BlockData")
        if data == null:
            data = nbt_find(container, "Data")
        int from_container = anvil_container_from_nbt(a, palette, data, c, blocks)
        if from_container != 0:
            return from_container
    if blocks:
        VNbt* palette = nbt_find(t, "Palette")
        if palette != null:
            VNbt* data = anvil_nbt_find_any(t, "BlockData", "Data")
            int legacy = anvil_container_from_nbt(a, palette, data, c, blocks)
            if legacy != 0:
                return legacy
        return anvil_direct_from_tag(nbt_find(t, "Blocks"), nbt_find(t, "Add"), c)
    return anvil_direct_from_tag(container, null, c)


# The two kinds an engine column keeps.
def anvil_hm_engine_read(heightmaps: VNbt*, values: int*) -> void:
    if heightmaps == null or heightmaps.kind != nbt_compound():
        return
    anvil_hm_read(nbt_find(heightmaps, "MOTION_BLOCKING"), values,
                  hm_kind_offset(hm_motion_blocking()))
    anvil_hm_read(nbt_find(heightmaps, "WORLD_SURFACE"), values,
                  hm_kind_offset(hm_world_surface()))


# Pre-1.18 worlds keep one biome per block column, not one per section cell:
# the same 16x16 value fills every cell of every section in the column.
def anvil_column_biomes(t: VNbt*) -> int*:
    int* values = vt_calloc_int(hm_cells())
    int i = 0
    while i < hm_cells():
        vt_iset(values, i, nbt_int_at(t, i))
        i = i + 1
    return values


def anvil_fill_column_biomes(s: VSection*, values: int*, min_section: int) -> void:
    int x = 0
    while x < 4:
        int z = 0
        while z < 4:
            int biome = vt_iget(values, z * 16 + x)
            int y = 0
            while y < 4:
                vcont_set(s.biomes, sec_biome_index(x, y, z), biome)
                y = y + 1
            z = z + 1
        x = x + 1


# One saved section compound, in the world's own layout. The Y byte is signed,
# which is what the format means for sections below the origin.
def anvil_section_from_nbt(a: VAnvil*, t: VNbt*, world: VWorld*, y: int,
                           status: int*) -> VSection*:
    *status = 0
    if t == null or t.kind != nbt_compound():
        return null
    VSection* s = sec_new_for_wire(y, world.block_global_bits, world.biome_global_bits)
    int blocks = anvil_side_from_section(a, t, s.blocks, true)
    int biomes = anvil_side_from_section(a, t, s.biomes, false)
    if blocks < 1 or biomes < 1:
        sec_free(s)
        if blocks < 0 or biomes < 0:
            *status = -1
        return null
    *status = 1
    s.y = nbt_get_int(t, "Y", y)
    anvil_light_read(anvil_nbt_find_any(t, "BlockLight", "Light"), s.block_light)
    anvil_light_read(nbt_find(t, "SkyLight"), s.sky_light)
    return s


# The chunk compound the game reads: modern schema, with every field the
# engine does not model copied out of the record it is replacing.
public def anvil_chunk_to_nbt(a: VAnvil*, world: VWorld*, chunk_x: int,
                              chunk_z: int, keep: VNbt*) -> VNbt*:
    VNbt* root = null
    if keep != null and keep.kind == nbt_compound():
        root = anvil_nbt_clone(keep, "")
    else:
        root = nbt_compound_of("")
    int64 version = anvil_default_data_version()
    str status = anvil_status_full()
    if a != null:
        version = a.data_version
        status = a.status

    anvil_nbt_replace(root, "DataVersion", nbt_long_of("DataVersion", version))
    anvil_nbt_replace(root, "sections", anvil_sections_to_nbt(a, world, chunk_x, chunk_z))
    anvil_nbt_replace(root, "Heightmaps", anvil_heightmaps_to_nbt(world, chunk_x, chunk_z))
    anvil_nbt_replace(root, "Status", nbt_string_of("Status", status))
    anvil_nbt_replace(root, "Version", nbt_byte_of("Version", anvil_format_version()))
    anvil_nbt_replace(root, "xPos", nbt_int_of("xPos", chunk_x))
    anvil_nbt_replace(root, "yPos", nbt_int_of("yPos", world.min_section))
    anvil_nbt_replace(root, "zPos", nbt_int_of("zPos", chunk_z))
    # The superseded spellings, and the pre-1.18 wrapper whose contents this
    # chunk now replaces, go: leaving them would give a reader two answers.
    anvil_nbt_remove(root, "Sections")
    anvil_nbt_remove(root, "Level")
    anvil_nbt_remove(root, "yAxis")
    if nbt_find(root, "TileEntities") == null and nbt_find(root, "Tiles") == null:
        nbt_append(root, nbt_list_of("TileEntities", nbt_end()))
    if nbt_find(root, "Entities") == null:
        nbt_append(root, nbt_list_of("Entities", nbt_end()))
    return root


# Installs a saved chunk into `world`. 1 loaded, 0 malformed, -1 unsupported
# (a name the table does not know, or a column the world cannot hold).
public def anvil_chunk_from_nbt(a: VAnvil*, root: VNbt*, world: VWorld*,
                                chunk_x: int, chunk_z: int) -> int:
    if root == null or root.kind != nbt_compound() or world == null:
        return 0
    VNbt* body = root
    VNbt* level = nbt_find(root, "Level")
    if level != null and level.kind == nbt_compound():
        body = level
    int min_section = nbt_get_int(body, "yPos", world.min_section)
    if min_section < world.min_section:
        return -1
    char* sections = vt_calloc_ptrs(world.section_count)
    int result = 1
    VNbt* list = anvil_nbt_find_any(body, "sections", "Sections")
    if list != null and list.kind == nbt_list():
        int column_biomes = 0
        int* column_values = null
        VNbt* biomes = nbt_find(body, "Biomes")
        if biomes != null and biomes.kind == nbt_int_array():
            if nbt_int_len(biomes) == hm_cells():
                column_values = anvil_column_biomes(biomes)
                column_biomes = 1
        int i = 0
        int side = 0
        while i < nbt_child_count(list) and result == 1:
            VNbt* t = nbt_child_at(list, i)
            int y = nbt_get_int(t, "Y", min_section)
            if y >= world.min_section and y < world.min_section + world.section_count:
                VSection* s = anvil_section_from_nbt(a, t, world, y, &side)
                if s == null:
                    if side < 0:
                        result = -1
                    else:
                        result = 0
                else:
                    if column_biomes == 1:
                        anvil_fill_column_biomes(s, column_values, min_section)
                    vt_ptr_set(sections, y - world.min_section, (void*)s)
            i = i + 1
        if column_values != null:
            vt_free((void*)column_values)
    if result == 1:
        VNbt* heightmaps = nbt_find(body, "Heightmaps")
        int* values = hm_new()
        anvil_hm_engine_read(heightmaps, values)
        if vworld_replace_sections(world, chunk_x, chunk_z, sections) == 0:
            result = 0
            hm_free(values)
        else:
            # The world owns the column from here; a full store cannot fail
            # twice, since the slot the sections call just made is still free.
            if vworld_set_heightmaps(world, chunk_x, chunk_z, values) == 0:
                hm_free(values)
    if result != 1:
        vworld_free_column(sections, world.section_count)
    return result


# ---- the region image --------------------------------------------------------

struct VRegion:
    int region_x
    int region_z
    int present
    int* length             # compressed payload bytes, 0 when absent
    int* compression        # the record's compression byte
    int* sector             # sector it was read from, for reporting
    int* sectors            # how many it took
    int* mtime
    char* payloads          # one malloc'd blob per present slot


public def vregion_new(region_x: int, region_z: int) -> VRegion*:
    VRegion* r = new VRegion
    r.region_x = region_x
    r.region_z = region_z
    r.present = 0
    r.length = vt_calloc_int(anvil_region_chunks())
    r.compression = vt_calloc_int(anvil_region_chunks())
    r.sector = vt_calloc_int(anvil_region_chunks())
    r.sectors = vt_calloc_int(anvil_region_chunks())
    r.mtime = vt_calloc_int(anvil_region_chunks())
    r.payloads = vt_calloc_ptrs(anvil_region_chunks())
    return r


public def vregion_free(r: VRegion*) -> void:
    if r == null:
        return
    int i = 0
    while i < anvil_region_chunks():
        char* blob = (char*)vt_ptr_get(r.payloads, i)
        if blob != null:
            vt_free((void*)blob)
            vt_ptr_set(r.payloads, i, null)
        vt_iset(r.length, i, 0)
        i = i + 1
    vt_free((void*)r.length)
    vt_free((void*)r.compression)
    vt_free((void*)r.sector)
    vt_free((void*)r.sectors)
    vt_free((void*)r.mtime)
    vt_free((void*)r.payloads)
    del r


public def anvil_region_of(coordinate: int) -> int:
    int region = coordinate / 32
    # Integer division in the language truncates, and the format wants floor
    # semantics so that a chunk west of the origin lands in the region whose
    # local index is still 0..31.
    if region * 32 > coordinate:
        region = region - 1
    return region


public def anvil_local_of(coordinate: int) -> int:
    return coordinate - anvil_region_of(coordinate) * 32


public def anvil_chunk_of(region: int, local: int) -> int:
    return region * 32 + local


public def anvil_region_path(base: str, dimension: str, region_x: int,
                             region_z: int) -> str:
    return vt_region_path(base, dimension, (int64)region_x, (int64)region_z)


def vregion_index(local_x: int, local_z: int) -> int:
    if local_x < 0 or local_x >= 32 or local_z < 0 or local_z >= 32:
        return -1
    return local_x + local_z * 32


public def vregion_present(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    if vt_iget(r.length, slot) <= 0:
        return 0
    return 1


public def vregion_chunk_count(r: VRegion*) -> int:
    if r == null:
        return 0
    return r.present


public def vregion_sectors(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.sectors, slot)


public def vregion_sector(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.sector, slot)


public def vregion_time(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.mtime, slot)


public def vregion_payload(r: VRegion*, local_x: int, local_z: int) -> char*:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return null
    if vt_iget(r.length, slot) <= 0:
        return null
    return (char*)vt_ptr_get(r.payloads, slot)


# The compressed payload's length, not counting the compression byte.
public def vregion_payload_length(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.length, slot)


public def vregion_compression(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.compression, slot)


def vregion_drop(r: VRegion*, slot: int) -> void:
    char* blob = (char*)vt_ptr_get(r.payloads, slot)
    if blob != null:
        vt_free((void*)blob)
        vt_ptr_set(r.payloads, slot, null)
    if vt_iget(r.length, slot) > 0:
        r.present = r.present - 1
    vt_iset(r.length, slot, 0)
    vt_iset(r.compression, slot, 0)
    vt_iset(r.sector, slot, 0)
    vt_iset(r.sectors, slot, 0)


public def vregion_forget(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    vregion_drop(r, slot)
    return 1


# Records one chunk in the image: the bytes it holds, where they came from and
# when they were written. `slot` is the table index, so a loader reading the
# location table does not have to split it back into local coordinates.
def vregion_store(r: VRegion*, slot: int, data: char*, from: int, length: int,
                  compression: int, offset: int, count: int, mtime: int) -> void:
    char* blob = vt_calloc_char(length + 1)
    if length > 0:
        vt_copy_bytes(blob, 0, data, from, length)
    char* previous = (char*)vt_ptr_get(r.payloads, slot)
    if previous != null:
        vt_free((void*)previous)
    vt_ptr_set(r.payloads, slot, (void*)blob)
    if vt_iget(r.length, slot) <= 0:
        r.present = r.present + 1
    vt_iset(r.length, slot, length)
    vt_iset(r.compression, slot, compression)
    vt_iset(r.sector, slot, offset)
    vt_iset(r.sectors, slot, count)
    vt_iset(r.mtime, slot, mtime)


# Stores a compressed payload, taking a copy: the codec buffer is reused by
# the next call. The sector fields go blank because the image no longer
# reflects the file on disk until vregion_save has run.
def vregion_set_payload(r: VRegion*, local_x: int, local_z: int, data: char*,
                        length: int, compression: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0 or length < 0:
        return 0
    if length == 0:
        vregion_drop(r, slot)
        return 1
    vregion_store(r, slot, data, 0, length, compression, 0, 0,
                  (int)vt_file_now())
    return 1


def anvil_comp_format(compression: int) -> int:
    if compression == anvil_comp_zlib():
        return 1
    if compression == anvil_comp_none():
        return 2
    return 0


public def vregion_codec_format(compression: int) -> int:
    return anvil_comp_format(compression)


# Serialises, compresses and stores one chunk compound.
public def vregion_set_chunk_nbt(r: VRegion*, a: VAnvil*, local_x: int,
                                 local_z: int, nbt: VNbt*) -> int:
    if r == null or nbt == null:
        return 0
    int compression = anvil_comp_gzip()
    int level = 1
    if a != null:
        compression = a.compression
        level = a.level
    VBuf* b = vbuf_new(4096)
    nbt_write(b, nbt)
    int format = anvil_comp_format(compression)
    int result = 0
    if vt_gz_compress(b.data, (int64)0, (int64)b.len, (int64)format, (int64)level) == 0:
        int length = (int)vt_gz_buf_len()
        if length >= 1 and length <= anvil_max_sectors() * anvil_sector_bytes():
            if vregion_set_payload(r, local_x, local_z, vt_gz_buf(), length,
                                   compression) == 1:
                result = 1
    vbuf_free(b)
    return result


# Reads and decompresses a stored chunk. The caller frees the tree.
public def vregion_chunk_nbt(r: VRegion*, local_x: int, local_z: int) -> VNbt*:
    char* payload = vregion_payload(r, local_x, local_z)
    int length = vregion_payload_length(r, local_x, local_z)
    if payload == null or length <= 0:
        return null
    int format = anvil_comp_format(vregion_compression(r, local_x, local_z))
    if vt_gz_decompress(payload, (int64)0, (int64)length, (int64)format) != 0:
        return null
    int n = (int)vt_gz_buf_len()
    if n <= 0:
        return null
    # nbt_read copies every payload it keeps, but the strings it returns are
    # its own allocations, so the codec buffer can go once the tree is built.
    VBuf* b = vbuf_new(n + 16)
    vbuf_put_bytes(b, vt_gz_buf(), n)
    VNbt* root = nbt_read(b)
    vbuf_free(b)
    if root == null:
        return null
    return root


# Parses the two tables and copies every record the location table names.
# An absent file is an empty image, which is what a new region is; a file that
# is there but does not parse is an error, never a silent empty region.
public def vregion_load(r: VRegion*, path: str) -> int:
    if r == null:
        return 0
    int i = 0
    while i < anvil_region_chunks():
        vregion_drop(r, i)
        i = i + 1
    if vt_file_exists(path) == 0:
        return 0
    if vt_file_slurp(path) != 0:
        return -1
    char* data = vt_file_buf()
    int n = (int)vt_file_buf_len()
    if data == null or n < anvil_header_bytes():
        vt_file_release()
        return -1
    int sectors = n / anvil_sector_bytes()
    int failed = 0
    int i = 0
    while i < anvil_region_chunks() and failed == 0:
        int at = i * 4
        int o0 = vt_at(data, at)
        int o1 = vt_at(data, at + 1)
        int o2 = vt_at(data, at + 2)
        int offset = (o0 << 16) | (o1 << 8) | o2
        int count = vt_at(data, at + 3)
        int time_at = anvil_sector_bytes() + i * 4
        int m0 = vt_at(data, time_at)
        int m1 = vt_at(data, time_at + 1)
        int m2 = vt_at(data, time_at + 2)
        int m3 = vt_at(data, time_at + 3)
        int mtime = (m0 << 24) | (m1 << 16) | (m2 << 8) | m3
        if count > 0:
            if offset < anvil_first_sector() or offset + count > sectors:
                failed = 1
            else:
                int record = offset * anvil_sector_bytes()
                int l0 = vt_at(data, record)
                int l1 = vt_at(data, record + 1)
                int l2 = vt_at(data, record + 2)
                int l3 = vt_at(data, record + 3)
                int length = (l0 << 24) | (l1 << 16) | (l2 << 8) | l3
                int compression = vt_at(data, record + 4)
                int capacity = count * anvil_sector_bytes() - anvil_record_overhead()
                if record + anvil_record_overhead() > n:
                    failed = 1
                else:
                    if length < 2 or length - 1 > capacity:
                        failed = 1
                    else:
                        if record + anvil_record_overhead() + length - 1 > n:
                            failed = 1
                        else:
                            int from = record + anvil_record_overhead()
                            vregion_store(r, i, data, from, length - 1,
                                          compression, offset, count, mtime)
        else:
            vt_iset(r.mtime, i, mtime)
        i = i + 1
    vt_file_release()
    if failed == 1:
        i = 0
        while i < anvil_region_chunks():
            vregion_drop(r, i)
            i = i + 1
        return -1
    return 0


# The copy above is a placeholder: payloads are stored with their real length,
# so this walks the table a second time and keeps the bytes.
# Writes the image out: header first, then each record at its own sector, with
# zero padding so every record starts on a sector boundary.
public def vregion_save(r: VRegion*, path: str) -> int:
    if r == null:
        return 0
    int* offsets = vt_calloc_int(anvil_region_chunks())
    int* sectors = vt_calloc_int(anvil_region_chunks())
    int cursor = anvil_first_sector()
    int i = 0
    int bad = 0
    while i < anvil_region_chunks():
        int length = vt_iget(r.length, i)
        if length > 0:
            int record = length + anvil_record_overhead()
            int needed = (record + anvil_sector_bytes() - 1) / anvil_sector_bytes()
            if needed > anvil_max_sectors():
                bad = 1
            else:
                vt_iset(offsets, i, cursor)
                vt_iset(sectors, i, needed)
                cursor = cursor + needed
        i = i + 1
    if bad == 1:
        vt_free((void*)offsets)
        vt_free((void*)sectors)
        return -1

    VBuf* out = vbuf_new(cursor * anvil_sector_bytes() + anvil_sector_bytes())
    char* padding = vt_calloc_char(anvil_sector_bytes())
    i = 0
    while i < anvil_region_chunks():
        int offset = vt_iget(offsets, i)
        int count = vt_iget(sectors, i)
        int value = 0
        if count > 0:
            value = (int)(((int64)offset << 8) | (int64)count)
        vbuf_put_u32_be(out, (uint64)value)
        i = i + 1
    i = 0
    while i < anvil_region_chunks():
        vbuf_put_i32_be(out, vt_iget(r.mtime, i))
        i = i + 1
    i = 0
    int written = anvil_first_sector()
    while i < anvil_region_chunks():
        int count = vt_iget(sectors, i)
        if count > 0:
            int offset = vt_iget(offsets, i)
            while written < offset:
                vbuf_put_bytes(out, padding, anvil_sector_bytes())
                written = written + 1
            char* payload = (char*)vt_ptr_get(r.payloads, i)
            int length = vt_iget(r.length, i)
            vbuf_put_i32_be(out, length + 1)
            vbuf_put_u8(out, (uint64)vt_iget(r.compression, i))
            vbuf_put_bytes(out, payload, length)
            int record = length + anvil_record_overhead()
            int pad = count * anvil_sector_bytes() - record
            if pad > 0:
                vbuf_put_bytes(out, padding, pad)
            written = written + count
            vt_iset(r.sector, i, offset)
            vt_iset(r.sectors, i, count)
        i = i + 1
    vt_free((void*)padding)
    vt_file_mkdirs(path)
    int result = 0
    if vt_file_spit(path, out.data, (int64)out.len) != 0:
        result = -1
    vbuf_free(out)
    vt_free((void*)offsets)
    vt_free((void*)sectors)
    return result


# ---- the world and the region file -------------------------------------------

public def vregion_save_chunk(a: VAnvil*, r: VRegion*, world: VWorld*,
                              chunk_x: int, chunk_z: int) -> int:
    if r == null or world == null:
        return 0
    if r.region_x != anvil_region_of(chunk_x) or r.region_z != anvil_region_of(chunk_z):
        return 0
    int local_x = anvil_local_of(chunk_x)
    int local_z = anvil_local_of(chunk_z)
    VNbt* keep = vregion_chunk_nbt(r, local_x, local_z)
    VNbt* root = anvil_chunk_to_nbt(a, world, chunk_x, chunk_z, keep)
    int stored = vregion_set_chunk_nbt(r, a, local_x, local_z, root)
    if keep != null:
        nbt_free(keep)
    nbt_free(root)
    if stored == 0:
        return 0
    return 1


public def vregion_load_chunk(a: VAnvil*, r: VRegion*, world: VWorld*,
                              chunk_x: int, chunk_z: int) -> int:
    if r == null or world == null:
        return 0
    if r.region_x != anvil_region_of(chunk_x) or r.region_z != anvil_region_of(chunk_z):
        return 0
    VNbt* root = vregion_chunk_nbt(r, anvil_local_of(chunk_x),
                                   anvil_local_of(chunk_z))
    if root == null:
        return 0
    int result = anvil_chunk_from_nbt(a, root, world, chunk_x, chunk_z)
    nbt_free(root)
    return result


# Loads every chunk a region holds. Returns the count installed, or -1 when
# the file did not parse.
public def anvil_load_region(a: VAnvil*, world: VWorld*, base: str,
                             dimension: str, region_x: int,
                             region_z: int) -> int:
    if world == null:
        return 0
    VRegion* r = vregion_new(region_x, region_z)
    str path = anvil_region_path(base, dimension, region_x, region_z)
    int loaded = 0
    int parsed = vregion_load(r, path)
    if parsed == 0:
        int local_z = 0
        while local_z < 32:
            int local_x = 0
            while local_x < 32:
                if vregion_present(r, local_x, local_z) == 1:
                    int chunk_x = anvil_chunk_of(region_x, local_x)
                    int chunk_z = anvil_chunk_of(region_z, local_z)
                    if vregion_load_chunk(a, r, world, chunk_x, chunk_z) == 1:
                        loaded = loaded + 1
                local_x = local_x + 1
            local_z = local_z + 1
    vregion_free(r)
    if parsed != 0:
        return -1
    return loaded


# Saves every loaded column, one region image per region it touches. Columns
# sharing a region go in one image so the file is rewritten once, which is what
# keeps the sector allocation simple: every record gets fresh sectors.
# Returns the count written, or -1 when a region file could not be written.
public def anvil_save_world(a: VAnvil*, world: VWorld*, base: str,
                            dimension: str) -> int:
    if world == null:
        return 0
    int count = world.count
    if count <= 0:
        return 0
    int* done = vt_calloc_int(count)
    int written = 0
    int failed = 0
    int i = 0
    while i < count and failed == 0:
        if vt_iget(done, i) == 0:
            int chunk_x = vt_iget(world.chunk_x, i)
            int chunk_z = vt_iget(world.chunk_z, i)
            int region_x = anvil_region_of(chunk_x)
            int region_z = anvil_region_of(chunk_z)
            VRegion* r = vregion_new(region_x, region_z)
            str path = anvil_region_path(base, dimension, region_x, region_z)
            if vregion_load(r, path) == 0:
                int j = i
                while j < count:
                    int other_x = vt_iget(world.chunk_x, j)
                    int other_z = vt_iget(world.chunk_z, j)
                    int same = 0
                    if anvil_region_of(other_x) == region_x:
                        if anvil_region_of(other_z) == region_z:
                            same = 1
                    if same == 1:
                        vt_iset(done, j, 1)
                        if vregion_save_chunk(a, r, world, other_x, other_z) == 1:
                            written = written + 1
                        else:
                            failed = 1
                    j = j + 1
                if failed == 0:
                    if vregion_save(r, path) != 0:
                        failed = 1
            else:
                failed = 1
            vregion_free(r)
        i = i + 1
    vt_free((void*)done)
    if failed == 1:
        return -1
    return written


# ---- one-call save/load, with the name table already handled -----------------

# Loads one region file's chunks into `world`, with the same name table. The
# count returned is how many chunks decoded; -1 means the file is there but
# cannot be parsed.
public def anvil_session_load(world: VWorld*, base: str, dimension: str,
                              region_x: int, region_z: int) -> int:
    VAnvil* a = anvil_new()
    anvil_registry_load(a, anvil_registry_default_path())
    int loaded = anvil_load_region(a, world, base, dimension, region_x, region_z)
    anvil_free(a)
    return loaded


# Where a session's recording goes: `saves/vortex` unless told otherwise. The
# overworld is that folder directly and every other dimension gets its own, so
# each one is a complete Anvil world root on its own.
public def anvil_save_base() -> str:
    return vt_env_or("VORTEX_WORLD_SAVE", "saves/vortex")


# Saves the loaded world and reports what the name table could and could not
# name: `named` rows loaded, `numeric` palettes that fell back to ids, and
# `unknown` saved names this table does not have.
public def anvil_world_save(world: VWorld*, named: int*, numeric: int*,
                            unknown: int*) -> int:
    str base = anvil_save_base()
    str folder = base
    int index = vworld_dimension_id(world)
    if index != 0:
        folder = base + ("/dimension" + str(index))
    VAnvil* a = anvil_new()
    int rows = anvil_registry_load(a, anvil_registry_default_path())
    if rows < 0:
        rows = 0
    int written = anvil_save_world(a, world, folder, "")
    int fell_back = anvil_lossy_palettes(a)
    int missed = anvil_unknown_names(a)
    anvil_free(a)
    if named != null:
        *named = rows
    if numeric != null:
        *numeric = fell_back
    if unknown != null:
        *unknown = missed
    return written


# ===== mesher.cpy =====
# Vortex engine - greedy section mesher.
#
# Turns a loaded 16x16x16 section into two vertex/index streams: opaque
# (solid cubes, cutout leaves and cross-shaped plants) and translucent (water,
# lava, glass, ice). The algorithm follows Horizon's terrain mesher in shape:
#
#   * one pass per face direction; each 16x16 slice builds a mask of visible
#     faces, with the neighbour sampled through VWorld so faces on a section
#     or chunk boundary are culled correctly;
#   * equal mask cells are merged into maximal rectangles (width first, then
#     height), so a flat stone section needs six quads, not 24,576;
#   * a mask cell's key is the block's protocol id plus the light of the cell
#     in front of the face, so a merge never crosses a material or light
#     boundary;
#   * translucent faces go to the second stream so a renderer can order them.
#
# Vertices are typed, packed int64 vectors, nine components each:
#
#   0 x, 1 y, 2 z      absolute block corner (integers; a quad is planar)
#   3 u, 4 v           texture coordinates in block units, 0..width/height
#   5 layer            block protocol id (the renderer's texture layer)
#   6 sky_light        0..15
#   7 block_light      0..15
#   8 face             +X -X +Y -Y +Z -Z, or mesh_face_cross()
#
# Indices are int64, two triangles per quad, counter-clockwise from outside.
#
# License boundary: no Mojang-derived code or data. Block classification comes
# from the optional generated database (see world/blockdb.cpy); without it the
# mesher treats state 0 as air and everything else as an opaque cube.
#
# The compiler resolves calls against what it has already read, so the helpers
# below are ordered bottom up.


public def mesh_face_pos_x() -> int:
    return 0


public def mesh_face_neg_x() -> int:
    return 1


public def mesh_face_pos_y() -> int:
    return 2


public def mesh_face_neg_y() -> int:
    return 3


public def mesh_face_pos_z() -> int:
    return 4


public def mesh_face_neg_z() -> int:
    return 5


public def mesh_face_cross() -> int:
    return 6


# Components per vertex, matching the list in the module comment.
public def mesh_vertex_stride() -> int:
    return 9


def mesh_kind_scale() -> int:
    return 1000000000


def mesh_unknown_layer() -> int:
    return 65535


# ---- typed vectors -----------------------------------------------------------

def mesh_empty_ints() -> int64[]:
    int64[] none = new int64[0]
    return none


struct VMesh:
    int64[] verts
    int64[] indices
    int vertex_count
    int index_count
    int quad_count


public def vmesh_new() -> VMesh*:
    VMesh* mesh = new VMesh
    mesh.verts = mesh_empty_ints()
    mesh.indices = mesh_empty_ints()
    mesh.vertex_count = 0
    mesh.index_count = 0
    mesh.quad_count = 0
    return mesh


public def vmesh_free(mesh: VMesh*) -> void:
    if mesh == null:
        return
    del mesh


public def vmesh_vertex_count(mesh: VMesh*) -> int:
    return mesh.vertex_count


public def vmesh_index_count(mesh: VMesh*) -> int:
    return mesh.index_count


public def vmesh_quad_count(mesh: VMesh*) -> int:
    return mesh.quad_count


# Component `component` of vertex `vertex`.
public def vmesh_component(mesh: VMesh*, vertex: int, component: int) -> int64:
    int at = vertex * mesh_vertex_stride() + component
    if at < 0 or at >= (int)len(mesh.verts):
        return (int64)0
    return mesh.verts[at]


public def vmesh_index(mesh: VMesh*, index: int) -> int64:
    if index < 0 or index >= (int)len(mesh.indices):
        return (int64)0
    return mesh.indices[index]


def vmesh_add_vertex(mesh: VMesh*, x: int, y: int, z: int, u: int, v: int,
                     layer: int, sky: int, block: int, face: int) -> void:
    append(mesh.verts, (int64)x)
    append(mesh.verts, (int64)y)
    append(mesh.verts, (int64)z)
    append(mesh.verts, (int64)u)
    append(mesh.verts, (int64)v)
    append(mesh.verts, (int64)layer)
    append(mesh.verts, (int64)sky)
    append(mesh.verts, (int64)block)
    append(mesh.verts, (int64)face)
    mesh.vertex_count += 1


# Four corners in counter-clockwise order seen from outside the block.
def vmesh_add_quad(mesh: VMesh*, x0: int, y0: int, z0: int,
                   x1: int, y1: int, z1: int,
                   x2: int, y2: int, z2: int,
                   x3: int, y3: int, z3: int,
                   width: int, height: int, layer: int, sky: int, block: int,
                   face: int) -> void:
    int base = mesh.vertex_count
    vmesh_add_vertex(mesh, x0, y0, z0, 0, 0, layer, sky, block, face)
    vmesh_add_vertex(mesh, x1, y1, z1, width, 0, layer, sky, block, face)
    vmesh_add_vertex(mesh, x2, y2, z2, width, height, layer, sky, block, face)
    vmesh_add_vertex(mesh, x3, y3, z3, 0, height, layer, sky, block, face)
    append(mesh.indices, (int64)base)
    append(mesh.indices, (int64)(base + 1))
    append(mesh.indices, (int64)(base + 2))
    append(mesh.indices, (int64)base)
    append(mesh.indices, (int64)(base + 2))
    append(mesh.indices, (int64)(base + 3))
    mesh.index_count += 6
    mesh.quad_count += 1


# ---- result ------------------------------------------------------------------

struct VMeshResult:
    VMesh* opaque
    VMesh* translucent
    int sections
    int quads


public def vmesh_result_new() -> VMeshResult*:
    VMeshResult* result = new VMeshResult
    result.opaque = vmesh_new()
    result.translucent = vmesh_new()
    result.sections = 0
    result.quads = 0
    return result


public def vmesh_result_free(result: VMeshResult*) -> void:
    if result == null:
        return
    vmesh_free(result.opaque)
    vmesh_free(result.translucent)
    del result


public def vmesh_result_opaque(result: VMeshResult*) -> VMesh*:
    return result.opaque


public def vmesh_result_translucent(result: VMeshResult*) -> VMesh*:
    return result.translucent


public def vmesh_result_sections(result: VMeshResult*) -> int:
    return result.sections


public def vmesh_result_quads(result: VMeshResult*) -> int:
    VMesh* opaque = result.opaque
    VMesh* translucent = result.translucent
    return opaque.quad_count + translucent.quad_count


# ---- mask --------------------------------------------------------------------

# Cell coordinate for one face slice. `a` runs along the first axis, `b` along
# the second; see the emission table below for the mapping.
def mesh_cell_x(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return slice
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return a
    return a


def mesh_cell_y(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return b
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return slice
    return b


def mesh_cell_z(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return a
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return b
    return slice


def mesh_neighbor_x(dir: int, x: int) -> int:
    if dir == mesh_face_pos_x():
        return x + 1
    if dir == mesh_face_neg_x():
        return x - 1
    return x


def mesh_neighbor_y(dir: int, y: int) -> int:
    if dir == mesh_face_pos_y():
        return y + 1
    if dir == mesh_face_neg_y():
        return y - 1
    return y


def mesh_neighbor_z(dir: int, z: int) -> int:
    if dir == mesh_face_pos_z():
        return z + 1
    if dir == mesh_face_neg_z():
        return z - 1
    return z


# Mask key for the face of the block at (x, y, z) in direction `dir`, or 0
# when the face is absent or hidden. The key packs the render layer, the block
# id and the light of the cell in front of the face.
def mesh_face_key(world: VWorld*, chunk_x: int, chunk_z: int, section_y: int,
                  section: VSection*, x: int, y: int, z: int, dir: int) -> int:
    int state = sec_block_at(section, x, y, z)
    if state == 0:
        return 0
    if blockdb_is_cube(state) == 0:
        return 0
    int nx = mesh_neighbor_x(dir, x)
    int ny = mesh_neighbor_y(dir, y)
    int nz = mesh_neighbor_z(dir, z)
    int wx = chunk_x * 16 + nx
    int wy = section_y * 16 + ny
    int wz = chunk_z * 16 + nz
    int neighbor = vworld_block_at(world, wx, wy, wz)
    if blockdb_hides_face(state, neighbor) == 1:
        return 0
    int light = vworld_light_at(world, wx, wy, wz)
    int layer = blockdb_protocol(state)
    if layer < 0:
        layer = mesh_unknown_layer()
    int kind = 0
    if blockdb_is_translucent(state) == 1:
        kind = 1
    return kind * mesh_kind_scale() + (layer + 1) * 256 + light


def mesh_build_mask(world: VWorld*, chunk_x: int, chunk_z: int, section_y: int,
                    section: VSection*, dir: int, slice: int, mask: int*) -> void:
    int a = 0
    while a < 16:
        int b = 0
        while b < 16:
            int x = mesh_cell_x(dir, slice, a, b)
            int y = mesh_cell_y(dir, slice, a, b)
            int z = mesh_cell_z(dir, slice, a, b)
            int key = mesh_face_key(world, chunk_x, chunk_z, section_y, section,
                                    x, y, z, dir)
            vt_iset(mask, a + b * 16, key)
            b += 1
        a += 1


# ---- emission ----------------------------------------------------------------

# Absolute base of the section, so the vertex vectors need no per-section
# translation later.
def mesh_emit_rect(mesh: VMesh*, dir: int, slice: int, base_x: int, base_y: int,
                   base_z: int, a: int, b: int, width_a: int, width_b: int,
                   layer: int, sky: int, block: int) -> void:
    int x = base_x + slice
    int y = base_y + slice
    int z = base_z + slice
    if dir == mesh_face_pos_x():
        vmesh_add_quad(mesh, x + 1, base_y + b, base_z + a,
                       x + 1, base_y + b + width_b, base_z + a,
                       x + 1, base_y + b + width_b, base_z + a + width_a,
                       x + 1, base_y + b, base_z + a + width_a,
                       width_b, width_a, layer, sky, block, dir)
    elif dir == mesh_face_neg_x():
        vmesh_add_quad(mesh, x, base_y + b, base_z + a + width_a,
                       x, base_y + b + width_b, base_z + a + width_a,
                       x, base_y + b + width_b, base_z + a,
                       x, base_y + b, base_z + a,
                       width_b, width_a, layer, sky, block, dir)
    elif dir == mesh_face_pos_y():
        vmesh_add_quad(mesh, base_x + a, y + 1, base_z + b,
                       base_x + a, y + 1, base_z + b + width_b,
                       base_x + a + width_a, y + 1, base_z + b + width_b,
                       base_x + a + width_a, y + 1, base_z + b,
                       width_a, width_b, layer, sky, block, dir)
    elif dir == mesh_face_neg_y():
        vmesh_add_quad(mesh, base_x + a, y, base_z + b,
                       base_x + a + width_a, y, base_z + b,
                       base_x + a + width_a, y, base_z + b + width_b,
                       base_x + a, y, base_z + b + width_b,
                       width_a, width_b, layer, sky, block, dir)
    elif dir == mesh_face_pos_z():
        vmesh_add_quad(mesh, base_x + a, base_y + b, z + 1,
                       base_x + a + width_a, base_y + b, z + 1,
                       base_x + a + width_a, base_y + b + width_b, z + 1,
                       base_x + a, base_y + b + width_b, z + 1,
                       width_a, width_b, layer, sky, block, dir)
    else:
        vmesh_add_quad(mesh, base_x + a + width_a, base_y + b, z,
                       base_x + a, base_y + b, z,
                       base_x + a, base_y + b + width_b, z,
                       base_x + a + width_a, base_y + b + width_b, z,
                       width_a, width_b, layer, sky, block, dir)


# Merges equal mask cells into maximal rectangles and emits one quad each.
def mesh_greedy(opaque: VMesh*, translucent: VMesh*, mask: int*, dir: int,
                slice: int, base_x: int, base_y: int, base_z: int) -> void:
    int a = 0
    while a < 16:
        int b = 0
        while b < 16:
            int key = vt_iget(mask, a + b * 16)
            if key != 0:
                int width_b = 1
                while b + width_b < 16 and vt_iget(mask, a + (b + width_b) * 16) == key:
                    width_b += 1
                int width_a = 1
                bool grow = true
                while a + width_a < 16 and grow:
                    int i = 0
                    while i < width_b:
                        if vt_iget(mask, (a + width_a) + (b + i) * 16) != key:
                            grow = false
                        i += 1
                    if grow:
                        width_a += 1
                int kind = key / mesh_kind_scale()
                int rest = key % mesh_kind_scale()
                int layer = rest / 256 - 1
                int sky = (rest % 256) / 16
                int block = rest % 16
                VMesh* target = opaque
                if kind == 1:
                    target = translucent
                mesh_emit_rect(target, dir, slice, base_x, base_y, base_z,
                               a, b, width_a, width_b, layer, sky, block)
                int ai = 0
                while ai < width_a:
                    int bi = 0
                    while bi < width_b:
                        vt_iset(mask, (a + ai) + (b + bi) * 16, 0)
                        bi += 1
                    ai += 1
                b += width_b
            else:
                b += 1
        a += 1


# ---- cross geometry ----------------------------------------------------------

def mesh_cross_quads(mesh: VMesh*, base_x: int, base_y: int, base_z: int,
                     x: int, y: int, z: int, layer: int, sky: int, block: int) -> void:
    int x0 = base_x + x
    int y0 = base_y + y
    int z0 = base_z + z
    # Both diagonals, each emitted twice so the quad is visible from either
    # side; plants are not sorted into a back-face stream.
    vmesh_add_quad(mesh, x0, y0, z0, x0 + 1, y0, z0 + 1,
                   x0 + 1, y0 + 1, z0 + 1, x0, y0 + 1, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0, y0 + 1, z0, x0 + 1, y0 + 1, z0 + 1,
                   x0 + 1, y0, z0 + 1, x0, y0, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0 + 1, y0, z0, x0, y0, z0 + 1,
                   x0, y0 + 1, z0 + 1, x0 + 1, y0 + 1, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0 + 1, y0 + 1, z0, x0, y0 + 1, z0 + 1,
                   x0, y0, z0 + 1, x0 + 1, y0, z0,
                   1, 1, layer, sky, block, mesh_face_cross())


def mesh_cross_pass(result: VMeshResult*, world: VWorld*, chunk_x: int,
                    chunk_z: int, section_y: int, section: VSection*) -> void:
    int base_x = chunk_x * 16
    int base_y = section_y * 16
    int base_z = chunk_z * 16
    int x = 0
    while x < 16:
        int y = 0
        while y < 16:
            int z = 0
            while z < 16:
                int state = sec_block_at(section, x, y, z)
                if state != 0 and blockdb_is_cross(state) == 1:
                    int light = vworld_light_at(world, base_x + x, base_y + y,
                                                base_z + z)
                    int layer = blockdb_protocol(state)
                    if layer < 0:
                        layer = mesh_unknown_layer()
                    mesh_cross_quads(result.opaque, base_x, base_y, base_z,
                                     x, y, z, layer, light / 16, light % 16)
                z += 1
            y += 1
        x += 1


# ---- section and world entry points -----------------------------------------

def vmesh_section_into(result: VMeshResult*, world: VWorld*, chunk_x: int,
                       chunk_z: int, section_y: int) -> void:
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return
    int base_x = chunk_x * 16
    int base_y = section_y * 16
    int base_z = chunk_z * 16
    int* mask = vt_calloc_int(256)
    int dir = 0
    while dir < 6:
        int slice = 0
        while slice < 16:
            int i = 0
            while i < 256:
                vt_iset(mask, i, 0)
                i += 1
            mesh_build_mask(world, chunk_x, chunk_z, section_y, section, dir,
                            slice, mask)
            mesh_greedy(result.opaque, result.translucent, mask, dir, slice,
                        base_x, base_y, base_z)
            slice += 1
        dir += 1
    vt_free((void*)mask)
    mesh_cross_pass(result, world, chunk_x, chunk_z, section_y, section)
    result.sections += 1
    result.quads = vmesh_result_quads(result)


# Mesh one section; absolute vertex coordinates.
public def vmesh_section(world: VWorld*, chunk_x: int, chunk_z: int,
                         section_y: int) -> VMeshResult*:
    VMeshResult* result = vmesh_result_new()
    vmesh_section_into(result, world, chunk_x, chunk_z, section_y)
    return result


# Mesh every loaded section of the world into one pair of streams.
public def vmesh_world(world: VWorld*) -> VMeshResult*:
    VMeshResult* result = vmesh_result_new()
    if world == null:
        return result
    int column = 0
    while column < world.count:
        int chunk_x = vt_iget(world.chunk_x, column)
        int chunk_z = vt_iget(world.chunk_z, column)
        int i = 0
        while i < world.section_count:
            vmesh_section_into(result, world, chunk_x, chunk_z,
                               world.min_section + i)
            i += 1
        column += 1
    return result


# ===== mesher_native.cpy =====
# Vortex engine - native parallel mesher binding.
#
# engine/mesher.c is the production worker-pool mesher; world/mesher.cpy is the
# readable single-threaded reference. Importing the C file registers its
# non-static functions for Cpyte, and the wrappers below give them engine types
# (VWorld*, VMeshResult-free batch handles) so the protocol layer can submit
# loaded chunks without touching the raw C ABI.
#
# The worker threads read sections through sec_block_at_index /
# sec_light_packed_index / vt_blockdb_render, which is why those accessors exist
# in section.cpy and blockdb.c. A batch keeps its own malloc'd vertex/index
# buffers; the caller reads them back through the accessors and frees the batch
# on the main thread, so the GC never sees a worker's stack.


public def vmesh_native_thread_count() -> int:
    return vt_mesh_thread_count()


public def vmesh_native_vertex_stride() -> int:
    return vt_mesh_vertex_stride()


public def vmesh_native_batch_new() -> char*:
    return vt_mesh_batch_new()


public def vmesh_native_batch_free(batch: char*) -> void:
    vt_mesh_batch_free(batch)


public def vmesh_native_add_chunk(batch: char*, world: VWorld*, chunk_x: int,
                                  chunk_z: int, min_section: int,
                                  section_count: int) -> void:
    vt_mesh_batch_add_chunk(batch, (char*)world, chunk_x, chunk_z, min_section,
                            section_count)


public def vmesh_native_add_section(batch: char*, world: VWorld*, chunk_x: int,
                                    section_y: int, chunk_z: int) -> void:
    vt_mesh_batch_add_section(batch, (char*)world, chunk_x, section_y, chunk_z)


# The centre section plus its six face neighbours, so a block edit re-meshes
# every section whose boundary faces could have changed.
public def vmesh_native_add_neighborhood(batch: char*, world: VWorld*,
                                         chunk_x: int, section_y: int,
                                         chunk_z: int) -> void:
    vt_mesh_batch_add_neighborhood(batch, (char*)world, chunk_x, section_y,
                                   chunk_z)


public def vmesh_native_run(batch: char*) -> int:
    return vt_mesh_batch_run(batch)


public def vmesh_native_sections(batch: char*) -> int:
    return vt_mesh_batch_sections(batch)


public def vmesh_native_quad_count(batch: char*) -> int:
    return vt_mesh_batch_quad_count(batch)


public def vmesh_native_vertex_count(batch: char*, slot: int,
                                     translucent: int) -> int:
    return vt_mesh_batch_vertex_count(batch, slot, translucent)


public def vmesh_native_index_count(batch: char*, slot: int,
                                    translucent: int) -> int:
    return vt_mesh_batch_index_count(batch, slot, translucent)


public def vmesh_native_vertex_component(batch: char*, slot: int,
                                         translucent: int, vertex: int,
                                         component: int) -> int64:
    return vt_mesh_batch_vertex_component(batch, slot, translucent, vertex,
                                          component)


public def vmesh_native_index_at(batch: char*, slot: int, translucent: int,
                                 index: int) -> int64:
    return vt_mesh_batch_index_at(batch, slot, translucent, index)


public def vmesh_native_checksum(batch: char*, slot: int,
                                 translucent: int) -> int64:
    return vt_mesh_batch_checksum(batch, slot, translucent)


# A meshed batch is handed to the renderer through the C ring above rather than
# by calling into it: publishing takes ownership, so the producer must not free
# the batch. A headless run never drains it, and the ring recycles its oldest
# entry once it is full.
public def vmesh_publish(batch: char*) -> void:
    vt_mesh_batch_publish(batch)


public def vmesh_take() -> char*:
    return vt_mesh_batch_take()


public def vmesh_pending() -> int:
    return vt_mesh_batch_pending()

# ===== shape.cpy =====
# Vortex protocol - packet shapes for protocol 777 (Minecraft 26.3).
#
# GENERATED by tools/gen_shapes.py from the Horizon reference definitions; do
# not edit by hand. One shape string per packet describes its fields as a
# comma separated token list, which src/proto/wire.cpy walks. A packet with
# no shape here is unknown to the codec: it costs one undecoded packet and
# never the connection.
#
# License boundary: these describe Horizon's public MIT packet definitions;
# no Mojang code or data. See docs/PARITY_BOUNDARY.md.


# A composite referenced by name from a shape (`x<name>`, `ar<name>`).
# Primitive tokens pass through so `ar<vi>` needs no table entry.
public def pw_sub_shape(name: str) -> str:
    if str_equals(name, "bo"):
        return "bo"
    if str_equals(name, "bt"):
        return "bt"
    if str_equals(name, "by"):
        return "by"
    if str_equals(name, "cm"):
        return "cm"
    if str_equals(name, "cp"):
        return "cp"
    if str_equals(name, "em"):
        return "em"
    if str_equals(name, "f4"):
        return "f4"
    if str_equals(name, "f8"):
        return "f8"
    if str_equals(name, "i1"):
        return "i1"
    if str_equals(name, "i2"):
        return "i2"
    if str_equals(name, "i4"):
        return "i4"
    if str_equals(name, "i8"):
        return "i8"
    if str_equals(name, "id"):
        return "id"
    if str_equals(name, "lv"):
        return "lv"
    if str_equals(name, "obo"):
        return "obo"
    if str_equals(name, "ovi"):
        return "ovi"
    if str_equals(name, "ovl"):
        return "ovl"
    if str_equals(name, "ps"):
        return "ps"
    if str_equals(name, "sp"):
        return "sp"
    if str_equals(name, "st"):
        return "st"
    if str_equals(name, "u1"):
        return "u1"
    if str_equals(name, "u2"):
        return "u2"
    if str_equals(name, "u4"):
        return "u4"
    if str_equals(name, "u8"):
        return "u8"
    if str_equals(name, "uu"):
        return "uu"
    if str_equals(name, "vd"):
        return "vd"
    if str_equals(name, "vi"):
        return "vi"
    if str_equals(name, "vl"):
        return "vl"
    if str_equals(name, "vv"):
        return "vv"
    if str_equals(name, "attribute_modifier"):
        return "id,f8,vi"
    if str_equals(name, "attribute_snapshot"):
        return "vi,f8,ar<attribute_modifier>"
    if str_equals(name, "book_pages"):
        return "ar<st>"
    if str_equals(name, "c_idarvi"):
        return "id,ar<vi>"
    if str_equals(name, "c_idarxc_idarvi"):
        return "id,ar<x<c_idarvi>>"
    if str_equals(name, "c_idobt"):
        return "id,obt"
    if str_equals(name, "c_st64stost1024"):
        return "st64,st,ost1024"
    if str_equals(name, "c_ststst"):
        return "st,st,st"
    if str_equals(name, "c_uust16arxc_st64stost1024"):
        return "uu,st16,ar<x<c_st64stost1024>>"
    if str_equals(name, "c_viidi8viovibobooxglobal_posvivi"):
        return "vi,id,i8,vi,ovi,bo,bo,ox<global_pos>,vi,vi"
    if str_equals(name, "chat_type_bound"):
        return "vi,bt,obt"
    if str_equals(name, "chunk_biome_data"):
        return "cp,by"
    if str_equals(name, "click_payload"):
        return "by"
    if str_equals(name, "clock_state"):
        return "vi,vl,f4,f4"
    if str_equals(name, "cursor"):
        return "f4,f4,f4"
    if str_equals(name, "entity_event"):
        return "i4,i1"
    if str_equals(name, "filter_mask"):
        return "vi,ar<vl>"
    if str_equals(name, "fixed3"):
        return "u1,u1,u1"
    if str_equals(name, "game_rule_entry"):
        return "id,st"
    if str_equals(name, "global_pos"):
        return "id,ps"
    if str_equals(name, "last_seen_update"):
        return "vi,u1,u1,u1,i1"
    if str_equals(name, "look_at_entity"):
        return "vi,vi"
    if str_equals(name, "map_decoration"):
        return "vi,i1,i1,i1,obt"
    if str_equals(name, "map_decoration_list"):
        return "ar<map_decoration>"
    if str_equals(name, "map_patch"):
        return "u1,u1,u1,u1,vi,rx"
    if str_equals(name, "minecart_step"):
        return "vd,vd,i1,i1,f4"
    if str_equals(name, "packed_signature"):
        return "vi,oby"
    if str_equals(name, "player_info_entry"):
        return "uu"
    if str_equals(name, "server_link"):
        return "bo,ovi@0,bt@0!,st"
    if str_equals(name, "sign_lines"):
        return "st,st,st,st"
    if str_equals(name, "signature"):
        return "by"
    if str_equals(name, "sound_extra"):
        return "id,of4"
    if str_equals(name, "sound_holder"):
        return "vi,ox<sound_extra>"
    if str_equals(name, "stat_entry"):
        return "vi,vi,i4"
    if str_equals(name, "stat_list"):
        return "ar<stat_entry>"
    if str_equals(name, "team_parameters"):
        return "bt,bt,bt,vi,vi,ovi,i1"
    if str_equals(name, "test_instance_data"):
        return "oid,vv,vi,bo,vi,obt"
    return ""


# The shape of one packet, by the name protocol_ids.cpy stores.
public def pw_shape(name: str) -> str:
    if str_equals(name, "accept_code_of_conduct"):
        return ""
    if str_equals(name, "accept_teleportation"):
        return "vi,f8,f8,f8,f4,f4"
    if str_equals(name, "add_entity"):
        return "vi,uu,vi,vd,lv,i1,i1,i1,vi"
    if str_equals(name, "add_transient_block"):
        return "ps,vi"
    if str_equals(name, "animate"):
        return "vi,u1"
    if str_equals(name, "attack"):
        return "vi"
    if str_equals(name, "award_stats"):
        return "x<stat_list>"
    if str_equals(name, "block_changed_ack"):
        return "vi"
    if str_equals(name, "block_destruction"):
        return "vi,ps,u1"
    if str_equals(name, "block_entity_data"):
        return "ps,vi,bt"
    if str_equals(name, "block_entity_tag_query"):
        return "vi,ps"
    if str_equals(name, "block_event"):
        return "ps,u1,u1,vi"
    if str_equals(name, "block_update"):
        return "ps,vi"
    if str_equals(name, "bundle_delimiter"):
        return ""
    if str_equals(name, "bundle_item_selected"):
        return "vi,vi"
    if str_equals(name, "change_difficulty"):
        return "vi"
    if str_equals(name, "change_game_mode"):
        return "vi"
    if str_equals(name, "chat"):
        return "st256,i8,i8,ox<signature>,x<last_seen_update>"
    if str_equals(name, "chat_ack"):
        return "vi"
    if str_equals(name, "chat_command"):
        return "st"
    if str_equals(name, "chat_session_update"):
        return "uu,i8,by,by"
    if str_equals(name, "chunk_batch_finished"):
        return "vi"
    if str_equals(name, "chunk_batch_received"):
        return "f4"
    if str_equals(name, "chunk_batch_start"):
        return ""
    if str_equals(name, "chunks_biomes"):
        return "ar<x<chunk_biome_data>>"
    if str_equals(name, "clear_dialog"):
        return ""
    if str_equals(name, "clear_titles"):
        return "bo"
    if str_equals(name, "client_command"):
        return "vi"
    if str_equals(name, "client_information"):
        return "st,i1,vi,bo,u1,vi,bo,bo,vi"
    if str_equals(name, "client_tick_end"):
        return ""
    if str_equals(name, "code_of_conduct"):
        return "st"
    if str_equals(name, "configuration_acknowledged"):
        return ""
    if str_equals(name, "container_button_click"):
        return "vi,vi"
    if str_equals(name, "container_close"):
        return "vi"
    if str_equals(name, "container_set_data"):
        return "vi,i2,i2"
    if str_equals(name, "container_slot_state_changed"):
        return "vi,vi,bo"
    if str_equals(name, "cookie_request"):
        return "id"
    if str_equals(name, "cookie_response"):
        return "id,oby"
    if str_equals(name, "cooldown"):
        return "id,vi"
    if str_equals(name, "custom_chat_completions"):
        return "vi,ar<st>"
    if str_equals(name, "custom_click_action"):
        return "id,x<click_payload>"
    if str_equals(name, "custom_payload"):
        return "id,rx"
    if str_equals(name, "custom_query"):
        return "vi,id,rx"
    if str_equals(name, "custom_query_answer"):
        return "vi,bo,rx"
    if str_equals(name, "damage_event"):
        return "vi,vi,ovi,ovi,ovd"
    if str_equals(name, "delete_chat"):
        return "x<packed_signature>"
    if str_equals(name, "disconnect"):
        return "st262144"
    if str_equals(name, "disguised_chat"):
        return "bt,x<chat_type_bound>"
    if str_equals(name, "edit_book"):
        return "vi,x<book_pages>,ost32"
    if str_equals(name, "entity_event"):
        return "i4,i1"
    if str_equals(name, "entity_tag_query"):
        return "vi,vi"
    if str_equals(name, "finish_configuration"):
        return ""
    if str_equals(name, "forget_level_chunk"):
        return "cp"
    if str_equals(name, "game_event"):
        return "u1,f4"
    if str_equals(name, "game_rule_values"):
        return "ar<x<game_rule_entry>>"
    if str_equals(name, "game_test_highlight_pos"):
        return "ps,ps"
    if str_equals(name, "hello"):
        return "st16,uu"
    if str_equals(name, "hurt_animation"):
        return "vi,f4"
    if str_equals(name, "initialize_border"):
        return "f8,f8,f8,f8,vl,vi,vi,vi"
    if str_equals(name, "intention"):
        return "vi,st255,u2,vi"
    if str_equals(name, "interact"):
        return "vi,vi,lv,bo"
    if str_equals(name, "jigsaw_generate"):
        return "ps,vi,bo"
    if str_equals(name, "keep_alive"):
        return "i8"
    if str_equals(name, "key"):
        return "by,by"
    if str_equals(name, "level_event"):
        return "i4,ps,i4,bo"
    if str_equals(name, "lock_difficulty"):
        return "bo"
    if str_equals(name, "login"):
        return "i4,bo,ar<id>,vi,vi,vi,bo,bo,bo,x<c_viidi8viovibobooxglobal_posvivi>,bo,bo"
    if str_equals(name, "login_acknowledged"):
        return ""
    if str_equals(name, "login_compression"):
        return "vi"
    if str_equals(name, "login_disconnect"):
        return "st262144"
    if str_equals(name, "login_finished"):
        return "x<c_uust16arxc_st64stost1024>,uu"
    if str_equals(name, "low_disk_space_warning"):
        return ""
    if str_equals(name, "map_item_data"):
        return "vi,i1,bo,ox<map_decoration_list>,ox<map_patch>"
    if str_equals(name, "mount_screen_open"):
        return "vi,vi,i4"
    if str_equals(name, "move_minecart_along_track"):
        return "vi,ar<x<minecart_step>>"
    if str_equals(name, "move_player_pos"):
        return "f8,f8,f8,u1"
    if str_equals(name, "move_player_pos_rot"):
        return "f8,f8,f8,f4,f4,u1"
    if str_equals(name, "move_player_rot"):
        return "f4,f4,u1"
    if str_equals(name, "move_player_status_only"):
        return "u1"
    if str_equals(name, "move_vehicle"):
        return "vd,f4,f4,bo"
    if str_equals(name, "open_book"):
        return "vi"
    if str_equals(name, "open_screen"):
        return "vi,vi,bt"
    if str_equals(name, "open_sign_editor"):
        return "ps,bo"
    if str_equals(name, "paddle_boat"):
        return "bo,bo"
    if str_equals(name, "pick_item_from_block"):
        return "ps,bo"
    if str_equals(name, "pick_item_from_entity"):
        return "vi,bo"
    if str_equals(name, "ping"):
        return "i8"
    if str_equals(name, "ping_request"):
        return "i8"
    if str_equals(name, "player_abilities"):
        return "i1"
    if str_equals(name, "player_action"):
        return "vi,ps,u1,vi"
    if str_equals(name, "player_chat"):
        return "vi,uu,vi,ox<signature>,st256,i8,i8,ar<x<packed_signature>>,obt,x<filter_mask>,x<chat_type_bound>"
    if str_equals(name, "player_combat_kill"):
        return "vi,bt"
    if str_equals(name, "player_command"):
        return "vi,vi,vi"
    if str_equals(name, "player_info_remove"):
        return "ar<uu>"
    if str_equals(name, "player_input"):
        return "u1"
    if str_equals(name, "player_loaded"):
        return ""
    if str_equals(name, "player_look_at"):
        return "vi,vd,ox<look_at_entity>"
    if str_equals(name, "player_position"):
        return "vi,vd,vd,f4,f4,i4"
    if str_equals(name, "player_rotation"):
        return "f4,bo,f4,bo"
    if str_equals(name, "pong"):
        return "i8"
    if str_equals(name, "pong_response"):
        return "i8"
    if str_equals(name, "post_effects"):
        return "ar<id>"
    if str_equals(name, "projectile_power"):
        return "vi,f8"
    if str_equals(name, "punch"):
        return ""
    if str_equals(name, "registry_data"):
        return "id,ar<x<c_idobt>>"
    if str_equals(name, "remove_entities"):
        return "ar<vi>"
    if str_equals(name, "remove_mob_effect"):
        return "vi,vi"
    if str_equals(name, "rename_item"):
        return "st"
    if str_equals(name, "reset_chat"):
        return ""
    if str_equals(name, "reset_score"):
        return "st,ost"
    if str_equals(name, "resource_pack"):
        return "uu,vi"
    if str_equals(name, "resource_pack_pop"):
        return "ouu"
    if str_equals(name, "resource_pack_push"):
        return "uu,st,st40,bo,obt"
    if str_equals(name, "respawn"):
        return "x<c_viidi8viovibobooxglobal_posvivi>,i1"
    if str_equals(name, "rotate_head"):
        return "vi,i1"
    if str_equals(name, "section_blocks_update"):
        return "sp,ar<vl>"
    if str_equals(name, "seen_advancements"):
        return "vi,ost@0=0"
    if str_equals(name, "select_advancements_tab"):
        return "oid"
    if str_equals(name, "select_known_packs"):
        return "ar<x<c_ststst>>"
    if str_equals(name, "select_trade"):
        return "vi"
    if str_equals(name, "server_data"):
        return "bt,oby"
    if str_equals(name, "server_links"):
        return "ar<x<server_link>>"
    if str_equals(name, "set_action_bar_text"):
        return "bt"
    if str_equals(name, "set_beacon"):
        return "ovi,ovi"
    if str_equals(name, "set_border_center"):
        return "f8,f8"
    if str_equals(name, "set_border_lerp_size"):
        return "f8,f8,vl"
    if str_equals(name, "set_border_size"):
        return "f8"
    if str_equals(name, "set_border_warning_delay"):
        return "vi"
    if str_equals(name, "set_border_warning_distance"):
        return "vi"
    if str_equals(name, "set_camera"):
        return "vi"
    if str_equals(name, "set_carried_item"):
        return "i2"
    if str_equals(name, "set_chunk_cache_center"):
        return "vi,vi"
    if str_equals(name, "set_chunk_cache_radius"):
        return "vi"
    if str_equals(name, "set_command_block"):
        return "ps,st,vi,i1"
    if str_equals(name, "set_command_minecart"):
        return "vi,st,bo"
    if str_equals(name, "set_default_spawn_position"):
        return "x<global_pos>,f4,f4"
    if str_equals(name, "set_display_objective"):
        return "vi,st"
    if str_equals(name, "set_entity_data"):
        return "vi,em"
    if str_equals(name, "set_entity_link"):
        return "i4,i4"
    if str_equals(name, "set_entity_motion"):
        return "vi,lv"
    if str_equals(name, "set_experience"):
        return "f4,vi,vi"
    if str_equals(name, "set_game_rule"):
        return "ar<x<game_rule_entry>>"
    if str_equals(name, "set_health"):
        return "f4,vi,f4"
    if str_equals(name, "set_held_slot"):
        return "vi"
    if str_equals(name, "set_jigsaw_block"):
        return "ps,id,id,id,st,st,vi,vi"
    if str_equals(name, "set_passengers"):
        return "vi,ar<vi>"
    if str_equals(name, "set_player_team"):
        return "st,i1,ox<team_parameters>@1&253=0,ar<st>@1=0|3|4"
    if str_equals(name, "set_simulation_distance"):
        return "vi"
    if str_equals(name, "set_structure_block"):
        return "ps,vi,vi,st,i1,i1,i1,i1,i1,i1,vi,vi,st128,f4,vl,i1"
    if str_equals(name, "set_subtitle_text"):
        return "bt"
    if str_equals(name, "set_test_block"):
        return "ps,vi,st"
    if str_equals(name, "set_time"):
        return "i8,ar<x<clock_state>>"
    if str_equals(name, "set_title_text"):
        return "bt"
    if str_equals(name, "set_titles_animation"):
        return "i4,i4,i4"
    if str_equals(name, "show_dialog"):
        return "bt"
    if str_equals(name, "sign_update"):
        return "ps,x<sign_lines>,bo"
    if str_equals(name, "sound"):
        return "x<sound_holder>,vi,i4,i4,i4,f4,f4,i8"
    if str_equals(name, "sound_entity"):
        return "x<sound_holder>,vi,vi,f4,f4,i8"
    if str_equals(name, "spectator_action"):
        return "ovi"
    if str_equals(name, "start_configuration"):
        return ""
    if str_equals(name, "stop_sound"):
        return "u1,ovi@0.0,st@0.1"
    if str_equals(name, "store_cookie"):
        return "id,by"
    if str_equals(name, "swing_animation"):
        return "vi,vi,vi,vi"
    if str_equals(name, "system_chat"):
        return "bt,bo"
    if str_equals(name, "tab_list"):
        return "bt,bt"
    if str_equals(name, "tag_query"):
        return "vi,bt"
    if str_equals(name, "take_item_entity"):
        return "vi,vi,vi"
    if str_equals(name, "teleport_entity"):
        return "vi,vd,vd,f4,f4,i4,bo"
    if str_equals(name, "teleport_to_entity"):
        return "uu"
    if str_equals(name, "test_instance_block_action"):
        return "ps,vi,x<test_instance_data>"
    if str_equals(name, "test_instance_block_status"):
        return "bt,ovv"
    if str_equals(name, "ticking_state"):
        return "f4,bo"
    if str_equals(name, "ticking_step"):
        return "vi"
    if str_equals(name, "transfer"):
        return "st,vi"
    if str_equals(name, "update_attributes"):
        return "vi,ar<x<attribute_snapshot>>"
    if str_equals(name, "update_enabled_features"):
        return "ar<id>"
    if str_equals(name, "update_mob_effect"):
        return "vi,vi,vi,vi,i1"
    if str_equals(name, "update_tags"):
        return "ar<x<c_idarxc_idarvi>>"
    if str_equals(name, "use_item"):
        return "vi,vi,f4,f4"
    if str_equals(name, "use_item_on"):
        return "vi,ps,vi,x<cursor>,bo,bo,vi"
    return ""


def pw_shape_names() -> str[]:
    str[] out = new str[0]
    append(out, "accept_code_of_conduct")
    append(out, "accept_teleportation")
    append(out, "add_entity")
    append(out, "add_transient_block")
    append(out, "animate")
    append(out, "attack")
    append(out, "award_stats")
    append(out, "block_changed_ack")
    append(out, "block_destruction")
    append(out, "block_entity_data")
    append(out, "block_entity_tag_query")
    append(out, "block_event")
    append(out, "block_update")
    append(out, "bundle_delimiter")
    append(out, "bundle_item_selected")
    append(out, "change_difficulty")
    append(out, "change_game_mode")
    append(out, "chat")
    append(out, "chat_ack")
    append(out, "chat_command")
    append(out, "chat_session_update")
    append(out, "chunk_batch_finished")
    append(out, "chunk_batch_received")
    append(out, "chunk_batch_start")
    append(out, "chunks_biomes")
    append(out, "clear_dialog")
    append(out, "clear_titles")
    append(out, "client_command")
    append(out, "client_information")
    append(out, "client_tick_end")
    append(out, "code_of_conduct")
    append(out, "configuration_acknowledged")
    append(out, "container_button_click")
    append(out, "container_close")
    append(out, "container_set_data")
    append(out, "container_slot_state_changed")
    append(out, "cookie_request")
    append(out, "cookie_response")
    append(out, "cooldown")
    append(out, "custom_chat_completions")
    append(out, "custom_click_action")
    append(out, "custom_payload")
    append(out, "custom_query")
    append(out, "custom_query_answer")
    append(out, "damage_event")
    append(out, "delete_chat")
    append(out, "disconnect")
    append(out, "disguised_chat")
    append(out, "edit_book")
    append(out, "entity_event")
    append(out, "entity_tag_query")
    append(out, "finish_configuration")
    append(out, "forget_level_chunk")
    append(out, "game_event")
    append(out, "game_rule_values")
    append(out, "game_test_highlight_pos")
    append(out, "hello")
    append(out, "hurt_animation")
    append(out, "initialize_border")
    append(out, "intention")
    append(out, "interact")
    append(out, "jigsaw_generate")
    append(out, "keep_alive")
    append(out, "key")
    append(out, "level_event")
    append(out, "lock_difficulty")
    append(out, "login")
    append(out, "login_acknowledged")
    append(out, "login_compression")
    append(out, "login_disconnect")
    append(out, "login_finished")
    append(out, "low_disk_space_warning")
    append(out, "map_item_data")
    append(out, "mount_screen_open")
    append(out, "move_minecart_along_track")
    append(out, "move_player_pos")
    append(out, "move_player_pos_rot")
    append(out, "move_player_rot")
    append(out, "move_player_status_only")
    append(out, "move_vehicle")
    append(out, "open_book")
    append(out, "open_screen")
    append(out, "open_sign_editor")
    append(out, "paddle_boat")
    append(out, "pick_item_from_block")
    append(out, "pick_item_from_entity")
    append(out, "ping")
    append(out, "ping_request")
    append(out, "player_abilities")
    append(out, "player_action")
    append(out, "player_chat")
    append(out, "player_combat_kill")
    append(out, "player_command")
    append(out, "player_info_remove")
    append(out, "player_input")
    append(out, "player_loaded")
    append(out, "player_look_at")
    append(out, "player_position")
    append(out, "player_rotation")
    append(out, "pong")
    append(out, "pong_response")
    append(out, "post_effects")
    append(out, "projectile_power")
    append(out, "punch")
    append(out, "registry_data")
    append(out, "remove_entities")
    append(out, "remove_mob_effect")
    append(out, "rename_item")
    append(out, "reset_chat")
    append(out, "reset_score")
    append(out, "resource_pack")
    append(out, "resource_pack_pop")
    append(out, "resource_pack_push")
    append(out, "respawn")
    append(out, "rotate_head")
    append(out, "section_blocks_update")
    append(out, "seen_advancements")
    append(out, "select_advancements_tab")
    append(out, "select_known_packs")
    append(out, "select_trade")
    append(out, "server_data")
    append(out, "server_links")
    append(out, "set_action_bar_text")
    append(out, "set_beacon")
    append(out, "set_border_center")
    append(out, "set_border_lerp_size")
    append(out, "set_border_size")
    append(out, "set_border_warning_delay")
    append(out, "set_border_warning_distance")
    append(out, "set_camera")
    append(out, "set_carried_item")
    append(out, "set_chunk_cache_center")
    append(out, "set_chunk_cache_radius")
    append(out, "set_command_block")
    append(out, "set_command_minecart")
    append(out, "set_default_spawn_position")
    append(out, "set_display_objective")
    append(out, "set_entity_data")
    append(out, "set_entity_link")
    append(out, "set_entity_motion")
    append(out, "set_experience")
    append(out, "set_game_rule")
    append(out, "set_health")
    append(out, "set_held_slot")
    append(out, "set_jigsaw_block")
    append(out, "set_passengers")
    append(out, "set_player_team")
    append(out, "set_simulation_distance")
    append(out, "set_structure_block")
    append(out, "set_subtitle_text")
    append(out, "set_test_block")
    append(out, "set_time")
    append(out, "set_title_text")
    append(out, "set_titles_animation")
    append(out, "show_dialog")
    append(out, "sign_update")
    append(out, "sound")
    append(out, "sound_entity")
    append(out, "spectator_action")
    append(out, "start_configuration")
    append(out, "stop_sound")
    append(out, "store_cookie")
    append(out, "swing_animation")
    append(out, "system_chat")
    append(out, "tab_list")
    append(out, "tag_query")
    append(out, "take_item_entity")
    append(out, "teleport_entity")
    append(out, "teleport_to_entity")
    append(out, "test_instance_block_action")
    append(out, "test_instance_block_status")
    append(out, "ticking_state")
    append(out, "ticking_step")
    append(out, "transfer")
    append(out, "update_attributes")
    append(out, "update_enabled_features")
    append(out, "update_mob_effect")
    append(out, "update_tags")
    append(out, "use_item")
    append(out, "use_item_on")
    return out


public def pw_shape_count() -> int:
    return len(pw_shape_names())


# True when a packet is described (an empty shape is: it carries no fields).
public def pw_shape_known(name: str) -> int:
    str[] names = pw_shape_names()
    int i = 0
    while i < len(names):
        if str_equals(names[i], name):
            return 1
        i += 1
    return 0



# ===== wire.cpy =====
# Vortex protocol - descriptor driven wire codec.
#
# Protocol 777 has two hundred and nine Play packets alone. Hand writing a
# reader for each one is where length validation gets skipped, so a packet is
# described once as a shape string (src/proto/shape.cpy) and this file walks
# that shape. A shape is a comma separated token list, one token per field:
#
#   vi varint   vl varlong   u1 i1 u2 i2 u4 i4 u8 i8   f4 f8   bo
#   st<N> varint-length UTF-8 (default 32767)   id<N> identifier (default 256)
#   uu uuid    ps packed block position    sp packed section position
#   cp chunk position pair    vd three doubles    lv three block velocities
#   vv three varints          cv three floats
#   bt unnamed NBT tag   cm text component   by byte string   rx rest of packet
#   sk<N> skip N fixed bytes    em entity metadata stream
#   o<T> option: one bool, then T only when set
#   ar<Name> varint count then Name repeated inline (flat shapes only)
#   ax<Name> varint count then each element measured, not inlined
#
# A token may end in a gate, `@f` or `@f.b`: the field exists only when field f
# is non zero, or when bit b of field f is set; `@!f` inverts the test. Gates
# must address an earlier token of the same shape, which the walker checks.
# This is how Horizon's conditional codecs - relative movement masks, per
# variant entity payloads - are described without per-packet code.
#
# Field storage, by kind:
#   vi u1 i1 u2 i2 u4 i4 bo    val = value
#   vl u8 i8 f4 f8             val = pool slot holding the raw bits
#   st id by                   val = pool slot, len = byte count
#   uu                         val = pool slot, len = 16
#   ps sp cp vd lv vv cv       val = pool slot, len = 3 components
#   bt cm                      val = byte offset, len = byte count, extra = tag
#   em                         val = byte offset, len = byte count, extra = entries
#   o<primitive>               as the primitive, present only when set
#   o<composite>               kind span: val = byte offset, len = byte count
#   ar<Name> inline            val = sub slot, len = elements, extra = stride
#   ax<Name> / ar<Name> measured   val = pool slot, len = elements, and the pool
#                              holds one (offset, length) pair per element
#
# Failure is soft by design: every packet is length delimited on the wire, so a
# shape that does not match the server costs one undecoded packet, never the
# connection. Only framing errors still end a session.
#
# License boundary: the shapes mirror Horizon's public MIT packet definitions;
# no Mojang code or data. See docs/PARITY_BOUNDARY.md.



# ---- kinds and errors --------------------------------------------------------

def pw_k_none() -> int:
    return 0
def pw_k_varint() -> int:
    return 1
def pw_k_varlong() -> int:
    return 2
def pw_k_int() -> int:
    return 3
def pw_k_float() -> int:
    return 4
def pw_k_double() -> int:
    return 5
def pw_k_bool() -> int:
    return 6
def pw_k_text() -> int:
    return 7
def pw_k_uuid() -> int:
    return 8
def pw_k_position() -> int:
    return 9
def pw_k_vector() -> int:
    return 10
def pw_k_nbt() -> int:
    return 11
def pw_k_bytes() -> int:
    return 12
def pw_k_remainder() -> int:
    return 13
def pw_k_skip() -> int:
    return 14
def pw_k_metadata() -> int:
    return 15
def pw_k_array() -> int:
    return 16
def pw_k_measured() -> int:
    return 17
def pw_k_span() -> int:
    return 18
def pw_k_named() -> int:
    return 19

def pw_err_none() -> int:
    return 0
def pw_err_truncated() -> int:
    return 1
def pw_err_range() -> int:
    return 2
def pw_err_shape() -> int:
    return 3
def pw_err_capacity() -> int:
    return 4
def pw_err_leftover() -> int:
    return 5
def pw_err_gate() -> int:
    return 6

def pw_max_fields() -> int:
    return 64
def pw_max_slots() -> int:
    return 1024
def pw_pool_cap() -> int:
    return 49152
def pw_text_max() -> int:
    return 32767
def pw_ident_max() -> int:
    return 256
def pw_array_max() -> int:
    return 4096
def pw_depth_max() -> int:
    return 3

def pw_code_at() -> int:
    return 64
def pw_code_lt() -> int:
    return 60
def pw_code_gt() -> int:
    return 62
def pw_code_bang() -> int:
    return 33
def pw_code_comma() -> int:
    return 44
def pw_code_dot() -> int:
    return 46
def pw_code_zero() -> int:
    return 48
def pw_code_nine() -> int:
    return 57


struct VWire:
    VBuf* b
    int* kind
    int* present
    int* val
    int* ext
    int* extra
    int* sub_kind
    int* sub_val
    int* sub_ext
    int* sub_present
    uint64* pool
    int fields
    int pool_len
    int error
    int exact


public def pw_reset(w: VWire*) -> void:
    int i = 0
    while i < pw_max_fields():
        vt_iset(w.kind, i, pw_k_none())
        vt_iset(w.present, i, 0)
        vt_iset(w.val, i, 0)
        vt_iset(w.ext, i, 0)
        vt_iset(w.extra, i, 0)
        i += 1
    i = 0
    while i < pw_max_slots():
        vt_iset(w.sub_kind, i, pw_k_none())
        vt_iset(w.sub_val, i, 0)
        vt_iset(w.sub_ext, i, 0)
        vt_iset(w.sub_present, i, 0)
        i += 1
    w.fields = 0
    w.pool_len = 0
    w.error = pw_err_none()
    w.exact = 0


public def pw_new() -> VWire*:
    VWire* w = new VWire
    w.b = vbuf_new(8192)
    w.kind = vt_calloc_int(pw_max_fields())
    w.present = vt_calloc_int(pw_max_fields())
    w.val = vt_calloc_int(pw_max_fields())
    w.ext = vt_calloc_int(pw_max_fields())
    w.extra = vt_calloc_int(pw_max_fields())
    w.sub_kind = vt_calloc_int(pw_max_slots())
    w.sub_val = vt_calloc_int(pw_max_slots())
    w.sub_ext = vt_calloc_int(pw_max_slots())
    w.sub_present = vt_calloc_int(pw_max_slots())
    w.pool = vt_calloc_u64(pw_pool_cap())
    pw_reset(w)
    return w


public def pw_free(w: VWire*) -> void:
    if w == null:
        return
    vbuf_free(w.b)
    vt_free((void*)w.kind)
    vt_free((void*)w.present)
    vt_free((void*)w.val)
    vt_free((void*)w.ext)
    vt_free((void*)w.extra)
    vt_free((void*)w.sub_kind)
    vt_free((void*)w.sub_val)
    vt_free((void*)w.sub_ext)
    vt_free((void*)w.sub_present)
    vt_free((void*)w.pool)
    del w




# Copy one packet body into the walker. The caller keeps its own array, so the
# Play loop's `int64[]` frames need no reshaping.
public def pw_load(w: VWire*, data: int64[], offset: int, length: int) -> int:
    if offset < 0 or length < 0:
        return 0
    if offset + length > (int)len(data):
        return 0
    pw_reset(w)
    vbuf_reset(w.b)
    int i = 0
    while i < length:
        vbuf_put_u8(w.b, (uint64)((uint64)data[offset + i] & (uint64)255))
        i += 1
    return 1


public def pw_error(w: VWire*) -> int:
    return w.error


public def pw_exact(w: VWire*) -> int:
    return w.exact


public def pw_fields(w: VWire*) -> int:
    return w.fields


public def pw_consumed(w: VWire*) -> int:
    return vbuf_len(w.b) - vbuf_avail(w.b)


# ---- storage -----------------------------------------------------------------

def pw_room_pool(w: VWire*, count: int) -> int:
    if count < 0:
        return 0
    if w.pool_len + count > pw_pool_cap():
        w.error = pw_err_capacity()
        return 0
    return 1


def pw_pool_put(w: VWire*, value: int64) -> int:
    if pw_room_pool(w, 1) == 0:
        return -1
    int index = w.pool_len
    vt_uset(w.pool, index, (uint64)value)
    w.pool_len += 1
    return index


def pw_pool_take(w: VWire*, count: int) -> int:
    if count < 0 or vbuf_avail(w.b) < count:
        w.error = pw_err_truncated()
        return -1
    if pw_room_pool(w, count) == 0:
        return -1
    int start = w.pool_len
    int i = 0
    while i < count:
        vt_uset(w.pool, start + i, vbuf_take_u8(w.b))
        i += 1
    w.pool_len += count
    return start


def pw_alloc_field(w: VWire*) -> int:
    if w.fields >= pw_max_fields():
        w.error = pw_err_capacity()
        return -1
    int index = w.fields
    w.fields += 1
    return index


# ---- token parsing -----------------------------------------------------------

def pw_token(shape: str, index: int) -> str:
    return vt_field(shape, pw_code_comma(), index)


def pw_token_count(shape: str) -> int:
    if vt_strlen(shape) == 0:
        return 0
    return vt_count(shape, pw_code_comma()) + 1


def pw_at_index(token: str) -> int:
    return vt_find_code(token, 0, pw_code_at())


def pw_plain(token: str) -> str:
    int at = pw_at_index(token)
    if at < 0:
        return token
    return vt_slice(token, 0, at)


def pw_gate_cut(body: str) -> int:
    int length = vt_strlen(body)
    int i = 0
    while i < length:
        int c = vt_at(body, i)
        if c == pw_code_dot() or c == 61 or c == 38:
            return i
        i += 1
    return length


def pw_gate_field(token: str) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return -1
    str body = vt_slice(token, at + 1, vt_strlen(token))
    if vt_at(body, 0) == pw_code_bang():
        body = vt_slice(body, 1, vt_strlen(body))
    int stop = pw_gate_cut(body)
    body = vt_slice(body, 0, stop)
    return parse_int(body)


# Where the field number ends: the tests that follow start with '.', '&' or '='.


def pw_gate_tail(token: str) -> str:
    # The text after the '@', without a leading invert marker.
    int at = pw_at_index(token)
    if at < 0:
        return ""
    str body = vt_slice(token, at + 1, vt_strlen(token))
    if vt_at(body, 0) == pw_code_bang():
        return vt_slice(body, 1, vt_strlen(body))
    return body


def pw_gate_bit(token: str) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return -1
    str body = vt_slice(token, at + 1, vt_strlen(token))
    int dot = vt_find_code(body, 0, pw_code_dot())
    if dot < 0:
        return -1
    str tail = vt_slice(body, dot + 1, vt_strlen(body))
    int stop = pw_gate_cut(tail)
    return parse_int(vt_slice(tail, 0, stop))


# `@N&MASK=SET` tests (value and MASK) against one of the '|' separated
# numbers in SET; `@N=SET` tests the value itself. A shape uses these for the
# packets whose extra fields depend on an enum, where a bit is not enough.
def pw_gate_mask(token: str) -> int:
    str body = pw_gate_tail(token)
    int and_ = vt_find_code(body, 0, 38)
    if and_ < 0:
        return -1
    int eq = vt_find_code(body, and_, 61)
    if eq < 0:
        return -1
    return parse_int(vt_slice(body, and_ + 1, eq))


def pw_gate_cmp(token: str) -> str:
    str body = pw_gate_tail(token)
    int eq = vt_find_code(body, 0, 61)
    if eq < 0:
        return ""
    return vt_slice(body, eq + 1, vt_strlen(body))


def pw_cmp_matches(value: int64, set_: str) -> int:
    int count = 0
    if vt_strlen(set_) > 0:
        count = vt_count(set_, 124) + 1
    int i = 0
    while i < count:
        if value == (int64)parse_int(vt_field(set_, 124, i)):
            return 1
        i += 1
    return 0


def pw_gate_truth(value: int64, token: str) -> int:
    str cmp_ = pw_gate_cmp(token)
    if vt_strlen(cmp_) > 0:
        int mask = pw_gate_mask(token)
        int64 tested = value
        if mask >= 0:
            tested = (int64)((uint64)value & (uint64)mask)
        return pw_cmp_matches(tested, cmp_)
    int bit = pw_gate_bit(token)
    uint64 bits = (uint64)value
    if bit >= 0:
        uint64 bit_set = (bits >> (uint64)bit) & (uint64)1
        if bit_set != (uint64)0:
            return 1
        return 0
    int mask2 = pw_gate_mask(token)
    if mask2 >= 0:
        uint64 masked = bits & (uint64)mask2
        if masked != (uint64)0:
            return 1
        return 0
    if value != (int64)0:
        return 1
    return 0


def pw_gate_invert(token: str) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return 0
    if vt_at(token, at + 1) == pw_code_bang():
        return 1
    return 0


def pw_digits_after(plain: str, from: int) -> int:
    # The decimal tail of st<N> / id<N> / sk<N>; -1 when there is none.
    int length = vt_strlen(plain)
    if length <= from:
        return -1
    int i = from
    while i < length:
        int c = vt_at(plain, i)
        if c < pw_code_zero() or c > pw_code_nine():
            return -1
        i += 1
    return parse_int(vt_slice(plain, from, length))


def pw_sub_name(plain: str) -> str:
    int mark = vt_find_code(plain, 0, pw_code_lt())
    if mark < 0:
        return ""
    int close = vt_find_code(plain, mark, pw_code_gt())
    if close < 0:
        return ""
    return vt_slice(plain, mark + 1, close)


def pw_kind_of(plain: str) -> int:
    if str_equals(plain, "vi"):
        return pw_k_varint()
    if str_equals(plain, "vl"):
        return pw_k_varlong()
    if str_equals(plain, "u1"):
        return pw_k_int()
    if str_equals(plain, "i1"):
        return pw_k_int()
    if str_equals(plain, "u2"):
        return pw_k_int()
    if str_equals(plain, "i2"):
        return pw_k_int()
    if str_equals(plain, "u4"):
        return pw_k_int()
    if str_equals(plain, "i4"):
        return pw_k_int()
    if str_equals(plain, "u8"):
        return pw_k_varlong()
    if str_equals(plain, "i8"):
        return pw_k_varlong()
    if str_equals(plain, "f4"):
        return pw_k_float()
    if str_equals(plain, "f8"):
        return pw_k_double()
    if str_equals(plain, "bo"):
        return pw_k_bool()
    if str_equals(plain, "uu"):
        return pw_k_uuid()
    if str_equals(plain, "ps"):
        return pw_k_position()
    if str_equals(plain, "sp"):
        return pw_k_position()
    if str_equals(plain, "cp"):
        return pw_k_position()
    if str_equals(plain, "vd"):
        return pw_k_vector()
    if str_equals(plain, "lv"):
        return pw_k_vector()
    if str_equals(plain, "vv"):
        return pw_k_vector()
    if str_equals(plain, "cv"):
        return pw_k_vector()
    if str_equals(plain, "bt"):
        return pw_k_nbt()
    if str_equals(plain, "cm"):
        return pw_k_nbt()
    if str_equals(plain, "by"):
        return pw_k_bytes()
    if str_equals(plain, "rx"):
        return pw_k_remainder()
    if str_equals(plain, "em"):
        return pw_k_metadata()
    if str_starts(plain, "st"):
        return pw_k_text()
    if str_starts(plain, "id"):
        return pw_k_text()
    if str_starts(plain, "sk"):
        return pw_k_skip()
    if str_starts(plain, "ar"):
        return pw_k_array()
    if str_starts(plain, "ax"):
        return pw_k_measured()
    if str_starts(plain, "x<"):
        return pw_k_named()
    return pw_k_none()


# An option is `o` followed by another token. `bo` is a bool, not an option,
# and the array prefixes never start with `o`.
def pw_is_option(plain: str) -> int:
    if vt_strlen(plain) < 3:
        return 0
    if vt_at(plain, 0) != 111:
        return 0
    if str_equals(plain, "bo"):
        return 0
    return 1


def pw_inner(plain: str) -> str:
    return vt_slice(plain, 1, vt_strlen(plain))


def pw_fixed_size(plain: str) -> int:
    # Bytes, with the sign-extend width encoded beside it: `i4` is four bytes
    # sign extended from 32 bits, so its code is 4 plus 100.
    if str_equals(plain, "u1"):
        return 1
    if str_equals(plain, "i1"):
        return 101
    if str_equals(plain, "u2"):
        return 2
    if str_equals(plain, "i2"):
        return 102
    if str_equals(plain, "u4"):
        return 4
    if str_equals(plain, "i4"):
        return 104
    return 0


def pw_text_limit(plain: str) -> int:
    int digits = pw_digits_after(plain, 2)
    if str_starts(plain, "id"):
        if digits > 0:
            return digits
        return pw_ident_max()
    if digits > 0:
        return digits
    return pw_text_max()


# ---- primitive reads ---------------------------------------------------------

def pw_read_int(w: VWire*, size: int) -> int64:
    int bytes = size
    int bits = 0
    if size > 100:
        bytes = size - 100
        bits = bytes * 8
    if vbuf_avail(w.b) < bytes:
        w.error = pw_err_truncated()
        return (int64)0
    uint64 raw = (uint64)0
    int i = 0
    while i < bytes:
        raw = (raw << (uint64)8) | (vbuf_take_u8(w.b) & (uint64)255)
        i += 1
    if bits > 0:
        uint64 half = (uint64)1 << (uint64)bits
        int64 low = (int64)(raw & (half - (uint64)1))
        if raw >= half:
            return low - (int64)(half << (uint64)1)
        return low
    return (int64)raw


def pw_read_varint(w: VWire*) -> int64:
    if vbuf_avail(w.b) == 0:
        w.error = pw_err_truncated()
        return (int64)0
    int ok = 0
    int value = vbuf_take_varint(w.b, &ok)
    if ok == 0:
        w.error = pw_err_truncated()
        return (int64)0
    return (int64)value


def pw_read_varlong(w: VWire*) -> int64:
    if vbuf_avail(w.b) == 0:
        w.error = pw_err_truncated()
        return (int64)0
    int ok = 0
    int64 value = vbuf_take_varlong(w.b, &ok)
    if ok == 0:
        w.error = pw_err_truncated()
        return (int64)0
    return value


def pw_read_float(w: VWire*) -> double:
    int64 raw = pw_read_int(w, 4)
    if w.error != pw_err_none():
        return (double)0
    return (double)vt_bits_to_float((int)raw)


def pw_read_double(w: VWire*) -> double:
    int64 raw = pw_read_int(w, 8)
    if w.error != pw_err_none():
        return (double)0
    return (double)vt_bits_to_double((uint64)raw)


def pw_read_bool(w: VWire*) -> int:
    if vbuf_avail(w.b) < 1:
        w.error = pw_err_truncated()
        return -1
    int raw = (int)vbuf_take_u8(w.b)
    if raw > 1:
        w.error = pw_err_range()
        return -1
    return raw


def pw_read_text(w: VWire*, limit: int) -> int:
    int64 length = pw_read_varint(w)
    if w.error != pw_err_none():
        return -1
    if length < (int64)0 or length > (int64)limit:
        w.error = pw_err_range()
        return -1
    return pw_pool_take(w, (int)length)


def pw_read_bytes(w: VWire*) -> int:
    int64 length = pw_read_varint(w)
    if w.error != pw_err_none():
        return -1
    if length < (int64)0 or length > (int64)vbuf_avail(w.b):
        w.error = pw_err_range()
        return -1
    return pw_pool_take(w, (int)length)


# Positions and vectors all record three pool slots, so one accessor reads the
# components of either.
def pw_read_position(w: VWire*, plain: str) -> int:
    if pw_room_pool(w, 3) == 0:
        return -1
    int start = w.pool_len
    if str_equals(plain, "cp"):
        # ChunkPos is one long: x in the low 32 bits, z in the high 32.
        int64 packed2 = pw_read_int(w, 8)
        if w.error != pw_err_none():
            return -1
        vt_uset(w.pool, start, (uint64)packed2 << (uint64)32 >> (uint64)32)
        vt_uset(w.pool, start + 1, (uint64)0)
        vt_uset(w.pool, start + 2, (uint64)(packed2 >> (int64)32))
        w.pool_len += 3
        return start
    int64 packed = pw_read_int(w, 8)
    if w.error != pw_err_none():
        return -1
    int64 x = (int64)0
    int64 y = (int64)0
    int64 z = (int64)0
    uint64 raw = (uint64)packed
    if str_equals(plain, "ps"):
        x = (int64)(raw >> (uint64)38)
        if x >= (int64)33554432:
            x = x - (int64)67108864
        z = (int64)((raw >> (uint64)12) & (uint64)67108863)
        if z >= (int64)33554432:
            z = z - (int64)67108864
        y = (int64)(raw & (uint64)4095)
        if y >= (int64)2048:
            y = y - (int64)4096
    else:
        if str_equals(plain, "sp") == false:
            w.error = pw_err_shape()
            return -1
        x = (int64)(raw >> (uint64)42)
        if x >= (int64)2097152:
            x = x - (int64)4194304
        y = (int64)(raw & (uint64)1048575)
        if y >= (int64)524288:
            y = y - (int64)1048576
        z = (int64)((raw >> (uint64)20) & (uint64)4194303)
        if z >= (int64)2097152:
            z = z - (int64)4194304
    vt_uset(w.pool, start, (uint64)x)
    vt_uset(w.pool, start + 1, (uint64)y)
    vt_uset(w.pool, start + 2, (uint64)z)
    w.pool_len += 3
    return start


def pw_read_vector(w: VWire*, plain: str) -> int:
    if pw_room_pool(w, 3) == 0:
        return -1
    int start = w.pool_len
    int i = 0
    while i < 3:
        int64 stored = (int64)0
        if str_equals(plain, "vd"):
            stored = (int64)vt_double_to_bits(pw_read_double(w))
        else:
            if str_equals(plain, "cv"):
                # Floats are widened, so every vector component is one shape.
                stored = (int64)vt_double_to_bits(pw_read_float(w))
            else:
                if str_equals(plain, "lv"):
                    stored = pw_read_int(w, 102)
                else:
                    if str_equals(plain, "vv"):
                        stored = pw_read_varint(w)
                    else:
                        w.error = pw_err_shape()
                        return -1
        if w.error != pw_err_none():
            return -1
        vt_uset(w.pool, start + i, (uint64)stored)
        i += 1
    w.pool_len += 3
    return start


def pw_read_nbt(w: VWire*, component: bool, tag_slot: int*) -> int:
    # One unnamed network NBT tag. The tree is walked only to find its end,
    # which is the validation; a handler that needs the values re-reads the
    # recorded span with the NBT module.
    if vbuf_avail(w.b) < 1:
        w.error = pw_err_truncated()
        return -1
    int kind = (int)vbuf_at(w.b, vbuf_pos(w.b))
    if kind == nbt_end():
        w.error = pw_err_range()
        return -1
    if component and (kind != nbt_string() and kind != nbt_compound()):
        w.error = pw_err_range()
        return -1
    int start = vbuf_pos(w.b)
    VNbt* tag = nbt_read_payload(kind, "", w.b, 0)
    if tag == null:
        w.error = pw_err_range()
        return -1
    int length = vbuf_pos(w.b) - start
    nbt_free(tag)
    if length <= 0:
        w.error = pw_err_range()
        return -1
    *tag_slot = kind
    return start


# ---- gates -------------------------------------------------------------------


def pw_gate_value(w: VWire*, index: int) -> int64:
    # The number a gate tests: scalars directly, wide values from the pool, and
    # anything else by whether it was read at all.
    if index < 0 or index >= w.fields:
        w.error = pw_err_gate()
        return (int64)0
    if vt_iget(w.present, index) == 0:
        return (int64)0
    int kind = vt_iget(w.kind, index)
    if kind == pw_k_varint() or kind == pw_k_int() or kind == pw_k_bool() or kind == pw_k_skip():
        return (int64)vt_iget(w.val, index)
    if kind == pw_k_varlong() or kind == pw_k_float() or kind == pw_k_double():
        return (int64)vt_uget(w.pool, vt_iget(w.val, index))
    return (int64)1


def pw_gate_open(w: VWire*, token: str, base: int) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return 1
    int field = pw_gate_field(token)
    if field < 0 or base + field >= w.fields:
        w.error = pw_err_gate()
        return 0
    int64 value = pw_gate_value(w, base + field)
    int truth = pw_gate_truth(value, token)
    if pw_gate_invert(token) == 1:
        if truth == 1:
            return 0
        return 1
    return truth


def pw_gate_open_sub(w: VWire*, token: str, base: int, count: int) -> int:
    int at = pw_at_index(token)
    if at < 0:
        return 1
    int field = pw_gate_field(token)
    if field < 0 or field >= count:
        w.error = pw_err_gate()
        return 0
    int slot = base + field
    if vt_iget(w.sub_present, slot) == 0:
        return 0
    int64 value = (int64)vt_iget(w.sub_val, slot)
    int truth = pw_gate_truth(value, token)
    if pw_gate_invert(token) == 1:
        if truth == 1:
            return 0
        return 1
    return truth

# A flat shape has no option, array or remainder tokens and no nested arrays,
# so its field count is fixed and elements share one stride.
public def pw_flat_slots(shape: str) -> int:
    int count = pw_token_count(shape)
    if count == 0 or count > pw_max_slots():
        return -1
    int i = 0
    while i < count:
        str token = pw_token(shape, i)
        if pw_at_index(token) >= 0:
            return -1
        str plain = pw_plain(token)
        int kind = pw_kind_of(plain)
        if kind == pw_k_none():
            return -1
        if kind == pw_k_array() or kind == pw_k_measured():
            return -1
        if kind == pw_k_remainder() or kind == pw_k_metadata():
            return -1
        if pw_is_option(plain) == 1:
            return -1
        i += 1
    return count

# ---- measuring without recording ---------------------------------------------
#
# pw_walk records fields; pw_measure only advances the cursor. Both apply the
# same gates and the same limits, so a measured span is as validated as a
# decoded field. Nested composites and array elements use the measurement.


def pw_metadata_token(kind: int) -> str:
    # The wire encoding of each live-metadata value type. Types 5 and 19 carry
    # item stacks, which the engine cannot describe until the item component
    # registry lands, so they are deliberately absent.
    if kind == 0:
        return "vi"
    if kind == 1:
        return "i2"
    if kind == 2:
        return "f4"
    if kind == 3:
        return "f8"
    if kind == 4:
        return "st1024"
    if kind == 6:
        return "bt"
    if kind == 7:
        return "bo"
    if kind == 8:
        return "ovi"
    if kind == 9:
        return "ps"
    if kind == 10:
        return "ps"
    if kind == 11:
        return "vi"
    if kind == 12:
        return "vi"
    if kind == 13:
        return "vi,vi"
    if kind == 14:
        return "vi,vi,vi"
    if kind == 15:
        return "vi,i1,i1,i1,i1"
    if kind == 16:
        return "f4,f4,f4,f4"
    if kind == 17:
        return "vi"
    if kind == 18:
        return "ovi"
    return ""


def pw_measure_token(w: VWire*, plain: str, depth: int) -> int:
    if depth > pw_depth_max():
        w.error = pw_err_shape()
        return 0
    if pw_is_option(plain) == 1:
        int set = pw_read_bool(w)
        if w.error != pw_err_none():
            return 0
        if set == 0:
            return 1
        str inner_shape = pw_inner(plain)
        int inner_count = pw_token_count(inner_shape)
        int ii = 0
        while ii < inner_count:
            str itoken = pw_token(inner_shape, ii)
            if pw_gate_open(w, itoken, 0) == 0:
                if w.error != pw_err_none():
                    return 0
            elif pw_measure_token(w, pw_plain(itoken), depth) == 0:
                return 0
            ii += 1
        return 1
    int kind = pw_kind_of(plain)
    int unused = 0
    if kind == pw_k_varint():
        pw_read_varint(w)
    elif kind == pw_k_varlong():
        pw_read_varlong(w)
    elif kind == pw_k_int():
        pw_read_int(w, pw_fixed_size(plain))
    elif kind == pw_k_float():
        pw_read_float(w)
    elif kind == pw_k_double():
        pw_read_double(w)
    elif kind == pw_k_bool():
        pw_read_bool(w)
    elif kind == pw_k_text():
        pw_read_text(w, pw_text_limit(plain))
    elif kind == pw_k_bytes():
        pw_read_bytes(w)
    elif kind == pw_k_uuid():
        pw_pool_take(w, 16)
    elif kind == pw_k_position():
        pw_read_position(w, plain)
    elif kind == pw_k_vector():
        pw_read_vector(w, plain)
    elif kind == pw_k_nbt():
        pw_read_nbt(w, str_equals(plain, "cm"), &unused)
    elif kind == pw_k_skip():
        int bytes = pw_digits_after(plain, 2)
        if bytes < 0:
            w.error = pw_err_shape()
            return 0
        vbuf_skip(w.b, bytes)
    elif kind == pw_k_remainder():
        vbuf_skip(w.b, vbuf_avail(w.b))
    elif kind == pw_k_metadata():
        int md_entries = 0
        while true:
            if vbuf_avail(w.b) < 2:
                w.error = pw_err_truncated()
                return 0
            int md_index = (int)vbuf_take_u8(w.b)
            if md_index == 255:
                break
            int md_kind = (int)pw_read_varint(w)
            if w.error != pw_err_none():
                return 0
            str md_shape = pw_metadata_token(md_kind)
            if vt_strlen(md_shape) == 0:
                w.error = pw_err_shape()
                return 0
            int md_n = pw_token_count(md_shape)
            int md_i = 0
            while md_i < md_n:
                if pw_measure_token(w, pw_plain(pw_token(md_shape, md_i)), depth + 1) == 0:
                    return 0
                md_i += 1
            md_entries += 1
            if md_entries > pw_array_max():
                w.error = pw_err_range()
                return 0
        return 1
    elif kind == pw_k_named():
        str named = pw_sub_shape(pw_sub_name(plain))
        if vt_strlen(named) == 0:
            w.error = pw_err_shape()
            return 0
        int nn = pw_token_count(named)
        int nk = 0
        while nk < nn:
            str ntoken = pw_token(named, nk)
            if pw_gate_open(w, ntoken, 0) == 0:
                if w.error != pw_err_none():
                    return 0
            elif pw_measure_token(w, pw_plain(ntoken), depth + 1) == 0:
                return 0
            nk += 1
        return 1
    elif kind == pw_k_array() or kind == pw_k_measured():
        str sub = pw_sub_shape(pw_sub_name(plain))
        if vt_strlen(sub) == 0:
            w.error = pw_err_shape()
            return 0
        int64 sub_count = pw_read_varint(w)
        if w.error != pw_err_none():
            return 0
        if sub_count < (int64)0 or sub_count > (int64)pw_array_max():
            w.error = pw_err_range()
            return 0
        int sn = pw_token_count(sub)
        int e = 0
        while e < (int)sub_count:
            int sk = 0
            while sk < sn:
                str stoken = pw_token(sub, sk)
                if pw_gate_open(w, stoken, 0) == 0:
                    if w.error != pw_err_none():
                        return 0
                elif pw_measure_token(w, pw_plain(stoken), depth + 1) == 0:
                    return 0
                sk += 1
            e += 1
        return 1
    else:
        w.error = pw_err_shape()
        return 0
    if w.error != pw_err_none():
        return 0
    return 1


public def pw_measure(w: VWire*, shape: str, depth: int) -> int:
    if depth > pw_depth_max():
        w.error = pw_err_shape()
        return 0
    int count = pw_token_count(shape)
    int i = 0
    while i < count:
        str token = pw_token(shape, i)
        if pw_gate_open(w, token, 0) == 0:
            if w.error != pw_err_none():
                return 0
            i += 1
            continue
        if pw_measure_token(w, pw_plain(token), depth) == 0:
            return 0
        i += 1
    return 1


def pw_measure_array(w: VWire*, plain: str, depth: int) -> int:
    str sub = pw_sub_shape(pw_sub_name(plain))
    if vt_strlen(sub) == 0:
        w.error = pw_err_shape()
        return 0
    int64 count = pw_read_varint(w)
    if w.error != pw_err_none():
        return 0
    if count < (int64)0 or count > (int64)pw_array_max():
        w.error = pw_err_range()
        return 0
    int i = 0
    while i < (int)count:
        if pw_measure(w, sub, depth + 1) == 0:
            return 0
        i += 1
    return 1




def pw_read_metadata(w: VWire*, count_slot: int*) -> int:
    int start = vbuf_pos(w.b)
    int entries = 0
    while true:
        if vbuf_avail(w.b) < 2:
            w.error = pw_err_truncated()
            return -1
        int index = (int)vbuf_take_u8(w.b)
        if index == 255:
            break
        int kind = (int)pw_read_varint(w)
        if w.error != pw_err_none():
            return -1
        str token = pw_metadata_token(kind)
        if vt_strlen(token) == 0:
            w.error = pw_err_shape()
            return -1
        if pw_measure(w, token, 0) == 0:
            return -1
        entries += 1
        if entries > pw_array_max():
            w.error = pw_err_range()
            return -1
    *count_slot = entries
    return start


# ---- recording reads ---------------------------------------------------------


def pw_record_scalar(w: VWire*, index: int, kind: int, value: int64) -> void:
    vt_iset(w.kind, index, kind)
    vt_iset(w.val, index, (int)value)
    vt_iset(w.ext, index, 0)
    vt_iset(w.extra, index, 0)
    vt_iset(w.present, index, 1)


def pw_record_slot(w: VWire*, index: int, kind: int, slot: int,
                   length: int) -> void:
    vt_iset(w.kind, index, kind)
    vt_iset(w.val, index, slot)
    vt_iset(w.ext, index, length)
    vt_iset(w.present, index, 1)


def pw_record_wide(w: VWire*, index: int, kind: int, value: int64) -> void:
    int slot = pw_pool_put(w, value)
    if slot < 0:
        return
    pw_record_slot(w, index, kind, slot, 0)


def pw_record_span(w: VWire*, index: int, kind: int, start: int, length: int,
                   extra: int) -> void:
    vt_iset(w.kind, index, kind)
    vt_iset(w.val, index, start)
    vt_iset(w.ext, index, length)
    vt_iset(w.extra, index, extra)
    vt_iset(w.present, index, 1)


def pw_record_flat(w: VWire*, slot: int, kind: int, value: int64,
                   length: int) -> void:
    vt_iset(w.sub_kind, slot, kind)
    vt_iset(w.sub_val, slot, (int)value)
    vt_iset(w.sub_ext, slot, length)
    vt_iset(w.sub_present, slot, 1)

def pw_read_flat_token(w: VWire*, plain: str, slot: int) -> int:
    int kind = pw_kind_of(plain)
    if kind == pw_k_varint():
        pw_record_flat(w, slot, kind, pw_read_varint(w), 0)
    elif kind == pw_k_varlong():
        pw_record_flat(w, slot, kind, pw_read_varlong(w), 0)
    elif kind == pw_k_int():
        pw_record_flat(w, slot, kind, pw_read_int(w, pw_fixed_size(plain)), 0)
    elif kind == pw_k_float():
        pw_record_flat(w, slot, kind,
                       (int64)vt_float_to_bits((float)pw_read_float(w)), 0)
    elif kind == pw_k_double():
        pw_record_flat(w, slot, kind,
                       (int64)vt_double_to_bits(pw_read_double(w)), 0)
    elif kind == pw_k_bool():
        pw_record_flat(w, slot, kind, (int64)pw_read_bool(w), 0)
    elif kind == pw_k_text():
        int start = pw_read_text(w, pw_text_limit(plain))
        pw_record_flat(w, slot, kind, (int64)start, w.pool_len - start)
    elif kind == pw_k_bytes():
        int start = pw_read_bytes(w)
        pw_record_flat(w, slot, kind, (int64)start, w.pool_len - start)
    elif kind == pw_k_uuid():
        int start = pw_pool_take(w, 16)
        pw_record_flat(w, slot, kind, (int64)start, 16)
    elif kind == pw_k_position():
        int start = pw_read_position(w, plain)
        pw_record_flat(w, slot, kind, (int64)start, 3)
    elif kind == pw_k_vector():
        int start = pw_read_vector(w, plain)
        pw_record_flat(w, slot, kind, (int64)start, 3)
    elif kind == pw_k_metadata() or kind == pw_k_array() or kind == pw_k_measured():
        w.error = pw_err_shape()
        return 0
    elif kind == pw_k_nbt():
        int tag = 0
        int start = pw_read_nbt(w, str_equals(plain, "cm"), &tag)
        pw_record_flat(w, slot, kind, (int64)start, tag)
    else:
        w.error = pw_err_shape()
        return 0
    if w.error != pw_err_none():
        return 0
    return 1


# The sub table holds one record per element field. Element shapes are flat, so
# a field index is `base + element * stride + field`.
def pw_read_flat(w: VWire*, shape: str, base: int) -> int:
    int count = pw_token_count(shape)
    int i = 0
    while i < count:
        int slot = base + i
        if slot >= pw_max_slots():
            w.error = pw_err_capacity()
            return 0
        str token = pw_token(shape, i)
        if pw_gate_open_sub(w, token, base, count) == 0:
            if w.error != pw_err_none():
                return 0
            i += 1
            continue
        if pw_read_flat_token(w, pw_plain(token), slot) == 0:
            return 0
        i += 1
    return 1


def pw_array_sub(plain: str) -> str:
    return pw_sub_shape(pw_sub_name(plain))


# Inline an array of a flat composite: each element occupies `stride` slots in
# the sub table, so element access is arithmetic and needs no second walk.
def pw_read_array(w: VWire*, plain: str, index: int, depth: int,
                  prefer_inline: int) -> int:
    str sub = pw_array_sub(plain)
    if vt_strlen(sub) == 0:
        w.error = pw_err_shape()
        return 0
    int64 count = pw_read_varint(w)
    if w.error != pw_err_none():
        return 0
    if count < (int64)0 or count > (int64)pw_array_max():
        w.error = pw_err_range()
        return 0
    int stride = pw_flat_slots(sub)
    int base = w.fields
    if prefer_inline == 1 and stride > 0 and stride * (int)count <= pw_max_slots():
        vt_iset(w.kind, index, pw_k_array())
        vt_iset(w.val, index, base)
        vt_iset(w.ext, index, (int)count)
        vt_iset(w.extra, index, stride)
        vt_iset(w.present, index, 1)
        int e = 0
        while e < (int)count:
            if pw_read_flat(w, sub, base + e * stride) == 0:
                return 0
            e += 1
        return 1
    vt_iset(w.kind, index, pw_k_measured())
    vt_iset(w.present, index, 1)
    int start_slot = w.pool_len
    if pw_room_pool(w, (int)count * 2) == 0:
        return 0
    vt_iset(w.val, index, start_slot)
    vt_iset(w.ext, index, (int)count)
    int i = 0
    while i < (int)count:
        int element_start = vbuf_pos(w.b)
        if pw_measure(w, sub, depth + 1) == 0:
            return 0
        vt_uset(w.pool, start_slot + i * 2, (uint64)element_start)
        vt_uset(w.pool, start_slot + i * 2 + 1, (uint64)(vbuf_pos(w.b) - element_start))
        i += 1
    return 1

# One token, recorded into field `index`. Options of a primitive keep the
# primitive's own kind, so a handler reads them the same way and only has to
# test pw_present.
def pw_read_field(w: VWire*, plain: str, index: int, depth: int) -> int:
    if pw_is_option(plain) == 1:
        str inner = pw_inner(plain)
        int set = pw_read_bool(w)
        if w.error != pw_err_none():
            return 0
        if set == 0:
            vt_iset(w.kind, index, pw_k_none())
            vt_iset(w.present, index, 0)
            return 1
        if pw_token_count(inner) == 1 and pw_is_option(inner) == 0 and pw_kind_of(inner) != pw_k_none():
            return pw_read_field(w, inner, index, depth)
        int start = vbuf_pos(w.b)
        if pw_measure(w, inner, depth) == 0:
            return 0
        pw_record_span(w, index, pw_k_span(), start, vbuf_pos(w.b) - start, 0)
        return 1
    int kind = pw_kind_of(plain)
    if kind == pw_k_varint():
        pw_record_scalar(w, index, kind, pw_read_varint(w))
    elif kind == pw_k_varlong():
        pw_record_wide(w, index, kind, pw_read_varlong(w))
    elif kind == pw_k_int():
        pw_record_scalar(w, index, kind, pw_read_int(w, pw_fixed_size(plain)))
    elif kind == pw_k_float():
        pw_record_wide(w, index, kind, (int64)vt_float_to_bits((float)pw_read_float(w)))
    elif kind == pw_k_double():
        pw_record_wide(w, index, kind, (int64)vt_double_to_bits(pw_read_double(w)))
    elif kind == pw_k_bool():
        pw_record_scalar(w, index, kind, (int64)pw_read_bool(w))
    elif kind == pw_k_text():
        int slot = pw_read_text(w, pw_text_limit(plain))
        pw_record_slot(w, index, kind, slot, w.pool_len - slot)
    elif kind == pw_k_bytes():
        int slot = pw_read_bytes(w)
        pw_record_slot(w, index, kind, slot, w.pool_len - slot)
    elif kind == pw_k_uuid():
        int slot = pw_pool_take(w, 16)
        pw_record_slot(w, index, kind, slot, 16)
    elif kind == pw_k_position():
        int slot = pw_read_position(w, plain)
        pw_record_slot(w, index, kind, slot, 3)
    elif kind == pw_k_vector():
        int slot = pw_read_vector(w, plain)
        pw_record_slot(w, index, kind, slot, 3)
    elif kind == pw_k_nbt():
        int tag = 0
        int start = pw_read_nbt(w, str_equals(plain, "cm"), &tag)
        pw_record_span(w, index, kind, start, vbuf_pos(w.b) - start, tag)
    elif kind == pw_k_metadata():
        int entries = 0
        int start = pw_read_metadata(w, &entries)
        pw_record_span(w, index, kind, start, vbuf_pos(w.b) - start, entries)
    elif kind == pw_k_skip():
        int bytes = pw_digits_after(plain, 2)
        if bytes < 0:
            w.error = pw_err_shape()
            return 0
        vbuf_skip(w.b, bytes)
        pw_record_scalar(w, index, kind, (int64)bytes)
    elif kind == pw_k_remainder():
        pw_record_span(w, index, kind, vbuf_pos(w.b), vbuf_avail(w.b), 0)
        vbuf_skip(w.b, vbuf_avail(w.b))
    elif kind == pw_k_named():
        # A named composite becomes a validated byte span; a handler that needs
        # its values re-walks the span with its own reader.
        str named = pw_sub_shape(pw_sub_name(plain))
        if vt_strlen(named) == 0:
            w.error = pw_err_shape()
            return 0
        int from = vbuf_pos(w.b)
        if pw_measure(w, named, depth) == 0:
            return 0
        pw_record_span(w, index, kind, from, vbuf_pos(w.b) - from, 0)
    elif kind == pw_k_array() or kind == pw_k_measured():
        return pw_read_array(w, plain, index, depth, kind == pw_k_array())
    else:
        w.error = pw_err_shape()
        return 0
    if w.error != pw_err_none():
        return 0
    return 1


# ---- walking a packet --------------------------------------------------------

public def pw_walk(w: VWire*, shape: str) -> int:
    if vt_strlen(shape) == 0:
        return 0
    int count = pw_token_count(shape)
    int i = 0
    while i < count:
        int index = pw_alloc_field(w)
        if index < 0:
            return 0
        str token = pw_token(shape, i)
        if pw_gate_open(w, token, 0) == 0:
            if w.error != pw_err_none():
                return 0
            vt_iset(w.kind, index, pw_k_none())
            vt_iset(w.present, index, 0)
            i += 1
            continue
        if pw_read_field(w, pw_plain(token), index, 0) == 0:
            return 0
        i += 1
    if w.exact == 0:
        w.exact = 0
    if vbuf_avail(w.b) != 0:
        w.error = pw_err_leftover()
        return 1
    w.exact = 1
    return 1


# ---- field access ------------------------------------------------------------

public def pw_present(w: VWire*, index: int) -> int:
    if index < 0 or index >= w.fields:
        return 0
    return vt_iget(w.present, index)


public def pw_kind(w: VWire*, index: int) -> int:
    if index < 0 or index >= w.fields:
        return pw_k_none()
    return vt_iget(w.kind, index)


public def pw_int(w: VWire*, index: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    return vt_iget(w.val, index)


public def pw_bool(w: VWire*, index: int) -> int:
    return pw_int(w, index)


public def pw_long(w: VWire*, index: int) -> int64:
    if pw_present(w, index) == 0:
        return (int64)0
    return (int64)vt_uget(w.pool, vt_iget(w.val, index))


public def pw_float(w: VWire*, index: int) -> double:
    if pw_present(w, index) == 0:
        return (double)0
    return (double)vt_bits_to_float((int)vt_uget(w.pool, vt_iget(w.val, index)))


public def pw_double(w: VWire*, index: int) -> double:
    if pw_present(w, index) == 0:
        return (double)0
    return (double)vt_bits_to_double((uint64)vt_uget(w.pool, vt_iget(w.val, index)))


# Byte count of a text, identifier or byte string; byte count of an NBT span;
# element count of an array; 16 for a uuid; 3 for a position or vector.
public def pw_len(w: VWire*, index: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    return vt_iget(w.ext, index)


# The NBT tag kind of a `bt`/`cm` field, or the metadata entry count of `em`.
public def pw_extra(w: VWire*, index: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    return vt_iget(w.extra, index)


public def pw_pool_int(w: VWire*, slot: int) -> int:
    if slot < 0 or slot >= w.pool_len:
        return 0
    return (int)vt_uget(w.pool, slot)


public def pw_pool_double(w: VWire*, slot: int) -> double:
    if slot < 0 or slot >= w.pool_len:
        return (double)0
    return (double)vt_bits_to_double((uint64)vt_uget(w.pool, slot))


public def pw_pool_float(w: VWire*, slot: int) -> double:
    if slot < 0 or slot >= w.pool_len:
        return (double)0
    return (double)vt_bits_to_float((int)vt_uget(w.pool, slot))


public def pw_pool_byte(w: VWire*, slot: int) -> int:
    if slot < 0 or slot >= w.pool_len:
        return 0
    return (int)vt_uget(w.pool, slot) & 255


# One of the three components of a packed position, section position, chunk
# pair, vector or velocity.
public def pw_axis(w: VWire*, index: int, axis: int) -> int:
    if pw_present(w, index) == 0 or axis < 0 or axis > 2:
        return 0
    return pw_pool_int(w, vt_iget(w.val, index) + axis)


# Vector components are doubles (`vd`) or floats (`cv`): the kind of the token
# decides, so both are read through the right cast.
public def pw_vec_axis(w: VWire*, index: int, axis: int) -> double:
    if pw_present(w, index) == 0 or axis < 0 or axis > 2:
        return (double)0
    return (double)vt_bits_to_double(
        (uint64)vt_uget(w.pool, vt_iget(w.val, index) + axis))


# Block velocity is stored as 1/8000 of a block per tick, as on the wire.
public def pw_velocity_axis(w: VWire*, index: int, axis: int) -> double:
    if pw_present(w, index) == 0 or axis < 0 or axis > 2:
        return (double)0
    return (double)pw_pool_int(w, vt_iget(w.val, index) + axis) / (double)8000.0


# ---- text --------------------------------------------------------------------

public def pw_byte_at(w: VWire*, index: int, at: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    if at < 0 or at >= vt_iget(w.ext, index):
        return 0
    return pw_pool_byte(w, vt_iget(w.val, index) + at)


public def pw_text(w: VWire*, index: int) -> str:
    int length = pw_len(w, index)
    if length <= 0:
        return ""
    VStr* out = vstr_new(length + 1)
    int i = 0
    while i < length:
        vstr_put(out, pw_byte_at(w, index, i))
        i += 1
    str text = vstr_text(out)
    vstr_free(out)
    return text


public def pw_print_text(w: VWire*, index: int) -> void:
    int length = pw_len(w, index)
    int i = 0
    while i < length:
        mc_write_byte(pw_byte_at(w, index, i))
        i += 1
    mc_write_byte(10)


# ---- element access ----------------------------------------------------------

public def pw_count(w: VWire*, index: int) -> int:
    if pw_present(w, index) == 0:
        return 0
    return vt_iget(w.ext, index)


public def pw_stride(w: VWire*, index: int) -> int:
    if pw_kind(w, index) != pw_k_array():
        return 0
    return pw_extra(w, index)


def pw_elem_slot(w: VWire*, index: int, elem: int, field: int) -> int:
    int stride = pw_stride(w, index)
    if stride <= 0 or elem < 0 or elem >= pw_count(w, index):
        return -1
    int slot = vt_iget(w.val, index) + elem * stride + field
    if slot < 0 or slot >= pw_max_slots():
        return -1
    if vt_iget(w.sub_present, slot) == 0:
        return -1
    return slot


public def pw_elem_int(w: VWire*, index: int, elem: int, field: int) -> int:
    int slot = pw_elem_slot(w, index, elem, field)
    if slot < 0:
        return 0
    return vt_iget(w.sub_val, slot)


public def pw_elem_len(w: VWire*, index: int, elem: int, field: int) -> int:
    int slot = pw_elem_slot(w, index, elem, field)
    if slot < 0:
        return 0
    return vt_iget(w.sub_ext, slot)


public def pw_elem_byte(w: VWire*, index: int, elem: int, field: int,
                        at: int) -> int:
    int slot = pw_elem_slot(w, index, elem, field)
    if slot < 0:
        return 0
    if at < 0 or at >= vt_iget(w.sub_ext, slot):
        return 0
    return pw_pool_byte(w, vt_iget(w.sub_val, slot) + at)


# ---- measured spans ----------------------------------------------------------

public def pw_span_start(w: VWire*, index: int, elem: int) -> int:
    int count = pw_count(w, index)
    if pw_present(w, index) == 0 or elem < 0 or elem >= count:
        return -1
    return pw_pool_int(w, vt_iget(w.val, index) + elem * 2)


public def pw_span_len(w: VWire*, index: int, elem: int) -> int:
    int count = pw_count(w, index)
    if pw_present(w, index) == 0 or elem < 0 or elem >= count:
        return -1
    return pw_pool_int(w, vt_iget(w.val, index) + elem * 2 + 1)


# Re-walk one measured element, or an option-of-composite field, into `child`.
public def pw_walk_span(w: VWire*, child: VWire*, start: int, length: int,
                        shape: str) -> int:
    if start < 0 or length <= 0 or start + length > vbuf_len(w.b):
        return 0
    pw_reset(child)
    int i = start
    while i < start + length:
        vbuf_put_u8(child.b, vbuf_at(w.b, i))
        i += 1
    return pw_walk(child, shape)


public def pw_option_span(w: VWire*, index: int, child: VWire*,
                          shape: str) -> int:
    if pw_kind(w, index) != pw_k_span():
        return 0
    return pw_walk_span(w, child, pw_int(w, index), pw_len(w, index), shape)


# ---- shape tables ------------------------------------------------------------

public def pw_error_text(code: int) -> str:
    if code == pw_err_none():
        return "ok"
    if code == pw_err_truncated():
        return "truncated"
    if code == pw_err_range():
        return "out of range length"
    if code == pw_err_shape():
        return "unknown token"
    if code == pw_err_capacity():
        return "shape too wide"
    if code == pw_err_leftover():
        return "trailing bytes"
    if code == pw_err_gate():
        return "bad gate"
    return "unknown"


# ===== protocol.cpy =====

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
    pl_print_bytes(body, message[2], message[1])
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


# ===== harness.cpy =====
# Vortex engine - the shared assertion harness for the test bundles.
#
# A test target's manifest lists the engine, this file, and the test itself;
# failures count up through an `int*` out parameter because Cpyte module-level
# variables are only reachable from `main()`.


def check(label: str, cond: bool, fails: int*) -> void:
    if cond:
        print("  ok   " + label)
    else:
        print("  FAIL " + label)
        *fails = *fails + 1


def check_int(label: str, got: int, want: int, fails: int*) -> void:
    if got == want:
        print("  ok   " + label)
    else:
        print("  FAIL " + label + ": got " + str(got) + " want " + str(want))
        *fails = *fails + 1


def check_str(label: str, got: str, want: str, fails: int*) -> void:
    if str_equals(got, want):
        print("  ok   " + label)
    else:
        print("  FAIL " + label + ": got '" + got + "' want '" + want + "'")
        *fails = *fails + 1


# Runs the suite and returns the process exit code.
public def report(title: str, fails: int) -> int:
    if fails == 0:
        print(title + ": all passed")
        return 0
    print(title + ": " + str(fails) + " failure(s)")
    return 1


# ===== test_registry.cpy =====

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

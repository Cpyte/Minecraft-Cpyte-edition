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

import stdlib


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

# Vortex engine - client-side entity registry.
#
# The Play stream refers to entities by id long before it describes them: a
# move packet can arrive for an entity the server never spawned in a way this
# client understands, and metadata updates only carry the fields that changed.
# This module is the accumulated answer to "what does the client currently
# believe about entity N", so handlers can merge partial packets instead of
# throwing them away.

import stdlib


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


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

import stdlib


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
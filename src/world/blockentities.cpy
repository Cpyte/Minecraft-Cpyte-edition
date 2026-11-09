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

import stdlib


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

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

import stdlib


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

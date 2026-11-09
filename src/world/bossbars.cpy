# Vortex engine - boss status bars.
#
# Boss bars are keyed by the UUID the server invented for the bar, not by the
# entity that owns it, and updates arrive as separate style/health/options
# packets that patch one bar. There is never more than a handful on screen, so
# a linear scan over a small arena beats hashing sixteen-byte keys.

import stdlib


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

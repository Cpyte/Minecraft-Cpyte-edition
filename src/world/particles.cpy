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

import stdlib


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

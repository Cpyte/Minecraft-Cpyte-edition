# Vortex engine - chunk column heightmaps.
#
# A server sends one height value per block column, packed 9 bits at a time
# least significant bit first across a big endian long array, so 256 values
# occupy 36 longs. The values are absolute world Y, which is why a dimension
# that starts below y = 0 still reports heights above its minimum: the packing
# carries no offset. Cpyte shifts and masks `int64` correctly but compares an
# unsigned value as signed, so the unpack loops stay in `int64` and only ever
# test the low nine bits after the mask.

import stdlib


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

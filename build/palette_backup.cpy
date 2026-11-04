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
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.

import stdlib


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
    int bits              # current indirect width; 0 while uniform
    int uniform_value
    int* palette          # palette slot -> stored value
    int palette_len
    int palette_cap
    uint64* words         # packed indices (indirect) or values (direct)
    int words_len


# Smallest width whose range covers `needed` values, never below `min_bits`.
def vcont_bits_for(needed: int, min_bits: int) -> int:
    int bits = min_bits
    int cap = 1
    int i = 0
    while i < bits:
        cap = cap * 2
        i += 1
    while cap < needed and bits < 30:
        bits += 1
        cap = cap * 2
    return bits


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


public def vcont_reset(c: VContainer*, value: int) -> void:
    c.mode = vcont_uniform_mode()
    c.bits = 0
    c.uniform_value = value
    c.palette_len = 0
    c.words_len = 0


# Width the container currently encodes at: 0 for a uniform section, which is
# exactly what the saved form records.
public def vcont_bits(c: VContainer*) -> int:
    return c.bits


public def vcont_mode(c: VContainer*) -> int:
    return c.mode


public def vcont_palette_len(c: VContainer*) -> int:
    return c.palette_len


public def vcont_palette_value(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.palette_len:
        return 0
    return vt_iget(c.palette, index)


# The saved word count for the current encoding.
public def vcont_word_count(c: VContainer*) -> int:
    int bits = c.bits
    if c.mode == vcont_direct_mode():
        bits = c.direct_bits
    if bits <= 0:
        return 0
    return vt_packed_words(c.count, bits)


public def vcont_word(c: VContainer*, index: int) -> uint64:
    if c.words == null or index < 0 or index >= c.words_len:
        return (uint64)0
    return (uint64)vt_uget(c.words, index)


# Installs a palette and packed words read from storage.
public def vcont_load(c: VContainer*, bits: int, word_count: int) -> void:
    if c.words != null:
        vt_free((void*)c.words)
    c.words = vt_calloc_u64(word_count)
    c.words_len = word_count
    c.bits = bits
    c.mode = vcont_indirect_mode()


# ---- internal helpers --------------------------------------------------------

def vcont_palette_capacity(c: VContainer*) -> int:
    return 1 << c.max_bits


# Ensures the slot array can hold `needed` palette entries.
def vcont_grow_palette(c: VContainer*) -> void:
    if c.palette_len < c.palette_cap:
        return
    int cap = c.palette_cap * 2
    if cap < 8:
        cap = 8
    int limit = vcont_palette_capacity(c)
    if cap > limit:
        cap = limit
    int* next = vt_calloc_int(cap)
    int i = 0
    while i < c.palette_len:
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


# Allocates words for `bits`, discarding whatever was stored before.
def vcont_alloc_words(c: VContainer*, bits: int) -> void:
    int need = vt_packed_words(c.count, bits)
    if c.words != null:
        vt_free((void*)c.words)
    c.words = vt_calloc_u64(need)
    c.words_len = need
    c.bits = bits


# Re-encodes every entry at `new_bits`, keeping the palette unchanged.
def vcont_repack(c: VContainer*, new_bits: int) -> void:
    uint64* old = c.words
    int old_len = c.words_len
    int old_bits = c.bits
    c.words = null
    c.words_len = 0
    vcont_alloc_words(c, new_bits)
    int i = 0
    while i < c.count and old != null:
        uint64 slot = vt_packed_get(old, i, old_bits)
        vt_packed_set(c.words, i, new_bits, slot)
        i += 1
    if old != null:
        vt_free((void*)old)


# Leaves uniform storage: both the old and the new value enter the palette and
# every entry is re-encoded as an index.
def vcont_leave_uniform(c: VContainer*, value: int) -> void:
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
    vt_packed_set(c.words, 0, bits, (uint64)second)


# Drops the palette and stores values at the full direct width. Every entry
# keeps the value its palette slot pointed at.
def vcont_promote(c: VContainer*) -> void:
    int bits = c.direct_bits
    uint64* old = c.words
    int old_bits = c.bits
    c.words = null
    c.words_len = 0
    vcont_alloc_words(c, bits)
    int i = 0
    while i < c.count and old != null:
        int slot = (int)vt_packed_get(old, i, old_bits)
        uint64 value = (uint64)vcont_palette_value(c, slot)
        vt_packed_set(c.words, i, bits, value)
        i += 1
    if old != null:
        vt_free((void*)old)
    c.palette_len = 0
    c.mode = vcont_direct_mode()


# ---- public access -----------------------------------------------------------

public def vcont_at(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.count:
        return 0
    if c.mode == vcont_uniform_mode():
        return c.uniform_value
    int bits = c.bits
    if c.mode == vcont_direct_mode():
        bits = c.direct_bits
    return (int)vt_packed_get(c.words, index, bits)


public def vcont_set(c: VContainer*, index: int, value: int) -> void:
    if index < 0 or index >= c.count:
        return
    if c.mode == vcont_uniform_mode():
        if value == c.uniform_value:
            return
        vcont_leave_uniform(c, value)
        return
    if c.mode == vcont_direct_mode():
        vt_packed_set(c.words, index, c.direct_bits, (uint64)value)
        return
    int slot = vcont_palette_index_of(c, value)
    if slot >= 0:
        vt_packed_set(c.words, index, c.bits, (uint64)slot)
        return
    int needed = c.palette_len + 1
    if needed > vcont_palette_capacity(c):
        vcont_promote(c)
        vt_packed_set(c.words, index, c.direct_bits, (uint64)value)
        return
    int new_bits = vcont_bits_for(needed, c.bits)
    if new_bits > c.bits:
        vcont_repack(c, new_bits)
    int added = vcont_palette_push(c, value)
    vt_packed_set(c.words, index, c.bits, (uint64)added)


# True when every entry holds `value`.
public def vcont_is_uniform(c: VContainer*, value: int) -> bool:
    int i = 0
    while i < c.count:
        if vcont_at(c, i) != value:
            return false
        i += 1
    return true


# Rebuilds the encoding from the values it currently holds, collapsing to
# uniform when there is only one distinct value and shrinking the width when
# the palette has room. Storage calls this before writing a section.
public def vcont_compact(c: VContainer*) -> void:
    if c.mode == vcont_uniform_mode():
        return
    int* values = vt_calloc_int(c.count)
    int distinct = 0
    int i = 0
    while i < c.count:
        int value = vcont_at(c, i)
        if vcont_direct_mode() == c.mode:
            vt_iset(values, i, value)
        else:
            vt_iset(values, i, vcont_palette_value(c, value))
        i += 1
    int probe = 0
    while probe < c.count:
        int candidate = vt_iget(values, probe)
        int seen = 0
        int j = 0
        while j < probe:
            if vt_iget(values, j) == candidate:
                seen = 1
            j += 1
        if seen == 0:
            distinct += 1
        probe += 1

    # Rebuild from scratch so the width, palette and word array all shrink.
    int mode = c.mode
    vcont_reset(c, vt_iget(values, 0))
    if distinct == 1:
        vt_free((void*)values)
        return
    int bits = vcont_bits_for(distinct, c.min_bits)
    if bits > c.max_bits then:
        vcont_alloc_words(c, c.direct_bits)
        c.mode = vcont_direct_mode()
        int k = 0
        while k < c.count:
            vt_packed_set(c.words, k, c.direct_bits, (uint64)vt_iget(values, k))
            k += 1
        vt_free((void*)values)
        return
    vcont_alloc_words(c, bits)
    c.mode = vcont_indirect_mode()
    int m = 0
    while m < c.count:
        int value = vt_iget(values, m)
        int slot = vcont_palette_index_of(c, value)
        if slot < 0:
            slot = vcont_palette_push(c, value)
        vt_packed_set(c.words, m, bits, (uint64)slot)
        m += 1
    vt_free((void*)values)
    if mode == c.mode:
        return

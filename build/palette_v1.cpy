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
# Definitions are ordered so that every helper appears before its callers: the
# compiler resolves a call only against what it has already read.
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
    int bits              # current encoding width; 0 while uniform
    int uniform_value
    int* palette          # palette slot -> stored value
    int palette_len
    int palette_cap
    int palette_limit     # most palette slots the encoding may use
    uint64* words         # packed indices (indirect) or values (direct)
    int words_len


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
def vcont_bits_for(needed: int, min_bits: int) -> int:
    int bits = min_bits
    int cap = vcont_pow2(bits)
    while cap < needed and bits < 30:
        bits += 1
        cap = cap * 2
    return bits


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


# Leaves uniform storage: both the old and the new value enter the palette,
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


# Counting the distinct values held, in first appearance order, into `values`.
# Returns the number of distinct values; `values` must hold `count` slots.
def vcont_collect_values(c: VContainer*, values: int*) -> int:
    int distinct = 0
    int i = 0
    while i < c.count:
        int stored = vcont_at(c, i)
        int value = stored
        if c.mode == vcont_indirect_mode():
            value = vcont_palette_value(c, stored)
        vt_iset(values, i, value)
        int seen = 0
        int j = 0
        while j < i:
            if vt_iget(values, j) == value:
                seen = 1
            j += 1
        if seen == 0:
            distinct += 1
        i += 1
    return distinct


def vcont_rebuild_indirect(c: VContainer*, values: int*, bits: int) -> void:
    vcont_reset(c, vt_iget(values, 0))
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


# ---- public API --------------------------------------------------------------

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


# Back to uniform storage holding `value`; the old arrays stay allocated and
# are reused by the next encoding.
public def vcont_reset(c: VContainer*, value: int) -> void:
    c.mode = vcont_uniform_mode()
    c.bits = 0
    c.uniform_value = value
    c.palette_len = 0
    c.words_len = 0
    c.palette_limit = vcont_capacity_bits(c.max_bits)


# Width the container encodes at: 0 while uniform, which is what the saved form
# records for a single valued palette.
public def vcont_bits(c: VContainer*) -> int:
    return c.bits


public def vcont_mode(c: VContainer*) -> int:
    return c.mode


public def vcont_count(c: VContainer*) -> int:
    return c.count


public def vcont_palette_len(c: VContainer*) -> int:
    return c.palette_len


public def vcont_palette_value(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.palette_len:
        return 0
    return vt_iget(c.palette, index)


# Word count the current encoding stores.
public def vcont_word_count(c: VContainer*) -> int:
    if c.bits <= 0:
        return 0
    return vt_packed_words(c.count, c.bits)


public def vcont_word(c: VContainer*, index: int) -> uint64:
    if c.words == null or index < 0 or index >= c.words_len:
        return (uint64)0
    return (uint64)vt_uget(c.words, index)


# Prepares an indirect container for `word_count` packed words read at `bits`.
# The caller fills the words with vcont_set_word and the palette with
# vcont_palette_add, in the order the saved tags carry them.
public def vcont_load(c: VContainer*, bits: int, word_count: int) -> void:
    if c.words != null:
        vt_free((void*)c.words)
    int need = word_count
    if need < 1:
        need = 1
    c.words = vt_calloc_u64(need)
    c.words_len = word_count
    c.bits = bits
    c.palette_len = 0
    c.palette_limit = vcont_capacity_bits(c.max_bits)
    c.mode = vcont_indirect_mode()


public def vcont_set_word(c: VContainer*, index: int, value: uint64) -> void:
    if c.words == null or index < 0 or index >= c.words_len:
        return
    vt_uset(c.words, index, (uint64)value)


# Adds a palette entry while loading. Entries past what the encoding can index
# are dropped so a malformed tag cannot write outside the array.
public def vcont_palette_add(c: VContainer*, value: int) -> void:
    if c.palette_len >= c.palette_limit:
        return
    vcont_palette_push(c, value)


public def vcont_at(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.count:
        return 0
    if c.mode == vcont_uniform_mode():
        return c.uniform_value
    if c.mode == vcont_direct_mode():
        return (int)vt_packed_get(c.words, index, c.direct_bits)
    return (int)vt_packed_get(c.words, index, c.bits)


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


# 1 when every entry holds the same value, which is when the container can be
# saved as a single valued palette.
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


# Number of distinct values held.
public def vcont_distinct_count(c: VContainer*) -> int:
    if c.mode == vcont_uniform_mode():
        return 1
    if c.mode == vcont_indirect_mode():
        return c.palette_len
    int* values = vt_calloc_int(c.count)
    int distinct = vcont_collect_values(c, values)
    vt_free((void*)values)
    return distinct


# Rebuilds the encoding from the values it currently holds: uniform for one
# distinct value, the narrowest width that fits the palette otherwise. Storage
# calls this before writing a section.
public def vcont_compact(c: VContainer*) -> void:
    if c.mode == vcont_uniform_mode():
        return
    int* values = vt_calloc_int(c.count)
    int distinct = vcont_collect_values(c, values)
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


# A direct container carries no palette, but a saved section always has one, so
# the values are re-collected at `save_bits` before writing. Returns 0 when the
# distinct values do not fit that width, leaving the container as it was.
public def vcont_save_prepare(c: VContainer*, save_bits: int) -> int:
    if c.mode != vcont_direct_mode():
        return 1
    int* values = vt_calloc_int(c.count)
    int distinct = vcont_collect_values(c, values)
    int needed = vcont_bits_for(distinct, 1)
    if needed > save_bits:
        vt_free((void*)values)
        return 0
    vcont_rebuild_indirect(c, values, save_bits)
    vt_free((void*)values)
    return 1

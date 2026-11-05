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
# Reading a section is a one way trip: vcont_reset, vcont_palette_add for each
# palette entry, vcont_alloc_words, then vcont_set_word for each stored word.
# The palette may be added before or after the words because only vcont_at
# reads them.
#
# The compiler resolves a call against what it has already read, so this module
# is ordered bottom up: every helper is defined before its callers.
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


# ---- arithmetic helpers ------------------------------------------------------

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
public def vcont_bits_for(needed: int, min_bits: int) -> int:
    int bits = min_bits
    int cap = vcont_pow2(bits)
    while cap < needed and bits < 30:
        bits += 1
        cap = cap * 2
    return bits


# ---- slots and words ---------------------------------------------------------

# Ensures the slot array can hold one more entry within palette_limit.
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


def vcont_palette_get(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.palette_len:
        return 0
    return vt_iget(c.palette, index)


# Allocates words for `bits`, discarding whatever was stored before.
def vcont_alloc_words(c: VContainer*, bits: int) -> void:
    int need = vt_packed_words(c.count, bits)
    if c.words != null:
        vt_free((void*)c.words)
    if need < 1:
        need = 1
    c.words = vt_calloc_u64(need)
    c.words_len = need
    c.bits = bits


# The value at `index`, whatever the current mode. An indirect container stores
# palette slots, so the slot has to be resolved before returning.
def vcont_at(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.count:
        return 0
    if c.mode == vcont_uniform_mode():
        return c.uniform_value
    if c.mode == vcont_direct_mode():
        return (int)vt_packed_get(c.words, index, c.direct_bits)
    int slot = (int)vt_packed_get(c.words, index, c.bits)
    return vcont_palette_get(c, slot)


# ---- mode transitions --------------------------------------------------------

# Back to uniform storage holding `value`. The palette and word arrays stay
# allocated for the next encoding to reuse.
public def vcont_reset(c: VContainer*, value: int) -> void:
    c.mode = vcont_uniform_mode()
    c.bits = 0
    c.uniform_value = value
    c.palette_len = 0
    c.words_len = 0
    c.palette_limit = vcont_capacity_bits(c.max_bits)


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


# Leaves uniform storage: the old value and the new one enter the palette,
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


# ---- rebuild from values -----------------------------------------------------

# Reads every entry into `values` as the value it denotes; `values` needs
# `count` slots.
def vcont_collect(c: VContainer*, values: int*) -> void:
    int i = 0
    while i < c.count:
        vt_iset(values, i, vcont_at(c, i))
        i += 1


# Counts distinct values in linear expected time; section compaction calls this
# on all 4096 block entries, so a pairwise scan is prohibitively slow.
def vcont_count_distinct(values: int*, count: int) -> int:
    if count <= 0:
        return 0
    int capacity = 1
    while capacity < count * 2:
        capacity *= 2
    int* slots = vt_calloc_int(capacity)
    char* occupied = vt_calloc_char(capacity)
    int distinct = 0
    int probe = 0
    while probe < count:
        int candidate = vt_iget(values, probe)
        uint64 key = (uint64)candidate
        key = key ^ (key >> (uint64)16)
        key = key * (uint64)2654435761
        key = key ^ (key >> (uint64)13)
        int slot = (int)(key & (uint64)(capacity - 1))
        while vt_at(occupied, slot) != 0 and vt_iget(slots, slot) != candidate:
            slot = (slot + 1) & (capacity - 1)
        if vt_at(occupied, slot) == 0:
            vt_put(occupied, slot, 1)
            vt_iset(slots, slot, candidate)
            distinct += 1
        probe += 1
    vt_free((void*)slots)
    vt_free((void*)occupied)
    return distinct


# Number of distinct values held, which a save needs to size its palette.
public def vcont_distinct_count(c: VContainer*) -> int:
    if c.mode == vcont_uniform_mode():
        return 1
    if c.mode == vcont_indirect_mode():
        return c.palette_len
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
    vt_free((void*)values)
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


# ---- writing -----------------------------------------------------------------

# Width and word count the section records for this container.
def vcont_save_bits(c: VContainer*) -> int:
    int distinct = vcont_distinct_count(c)
    if distinct <= 1:
        return 0
    int bits = vcont_bits_for(distinct, c.min_bits)
    if bits > c.max_bits:
        return c.direct_bits
    return bits


def vcont_save_word_count(c: VContainer*, bits: int) -> int:
    if bits <= 0:
        return 0
    return vt_packed_words(c.count, bits)


# Collapses the encoding to its narrowest form: uniform for one distinct
# value, otherwise the smallest width that indexes the palette.
public def vcont_compact(c: VContainer*) -> void:
    if c.mode == vcont_uniform_mode():
        return
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
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


# ---- palette view ------------------------------------------------------------

public def vcont_palette_len(c: VContainer*) -> int:
    return c.palette_len


# 1 when `index` is a palette slot, so vcont_palette_at returns its value.
public def vcont_has_palette(c: VContainer*, index: int) -> int:
    if index < 0 or index >= c.palette_len:
        return 0
    return 1


public def vcont_palette_at(c: VContainer*, index: int) -> int:
    return vcont_palette_get(c, index)


# ---- word view ---------------------------------------------------------------

# 1 when the container is uniform, which is when a save writes no words at all.
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


public def vcont_save_bits_for(c: VContainer*) -> int:
    return vcont_save_bits(c)


public def vcont_save_words_for(c: VContainer*, bits: int) -> int:
    return vcont_save_word_count(c, bits)


# 1 when `index` is a stored word; the caller reads it with vcont_save_word.
public def vcont_has_save_word(c: VContainer*, index: int) -> int:
    if c.words == null or c.bits <= 0 or index < 0:
        return 0
    if index >= vcont_save_word_count(c, c.bits):
        return 0
    return 1


public def vcont_save_word(c: VContainer*, index: int) -> uint64:
    if c.words == null or index < 0 or index >= c.words_len:
        return (uint64)0
    return (uint64)vt_uget(c.words, index)


# ---- accessors ---------------------------------------------------------------

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


public def vcont_bits(c: VContainer*) -> int:
    return c.bits


public def vcont_mode(c: VContainer*) -> int:
    return c.mode


public def vcont_count(c: VContainer*) -> int:
    return c.count


# A uniform container stores no words, which is what the saved form records.
public def vcont_word_count(c: VContainer*) -> int:
    return vcont_save_word_count(c, c.bits)


# Appends a value read from the saved palette; the words can be filled before
# or after, only vcont_at reads them.
public def vcont_palette_add(c: VContainer*, value: int) -> void:
    if c.palette_len >= c.palette_limit:
        return
    vcont_palette_push(c, value)


# Allocates and clears the data words for `bits`; pairs with vcont_set_word and
# vcont_palette_add.
public def vcont_alloc(c: VContainer*, bits: int) -> void:
    vcont_alloc_words(c, bits)
    c.mode = vcont_indirect_mode()


public def vcont_alloc_direct(c: VContainer*, bits: int) -> void:
    vcont_alloc_words(c, bits)
    c.mode = vcont_direct_mode()


public def vcont_set_word(c: VContainer*, index: int, value: uint64) -> void:
    if c.words == null or index < 0 or index >= c.words_len:
        return
    vt_uset(c.words, index, (uint64)value)


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


# A direct container carries no palette, but a saved section always has one,
# so the values are re-collected at `save_bits` before writing. Returns 0 when
# the distinct values do not fit that width, leaving the container untouched.
public def vcont_save_prepare(c: VContainer*, save_bits: int) -> int:
    if c.mode != vcont_direct_mode():
        return 1
    int* values = vt_calloc_int(c.count)
    vcont_collect(c, values)
    int distinct = vcont_count_distinct(values, c.count)
    int needed = vcont_bits_for(distinct, 1)
    if needed > save_bits:
        vt_free((void*)values)
        return 0
    vcont_rebuild_indirect(c, values, save_bits)
    vt_free((void*)values)
    return 1

# Vortex engine - protocol PalettedContainer decoder.

import stdlib


def sec_wire_read_varint(b: VBuf*, ok: int*) -> int:
    *ok = 0
    int value = vbuf_take_varint(b, ok)
    if *ok == 0 or value < 0:
        *ok = 0
        return 0
    return value


def sec_wire_read_container(b: VBuf*, c: VContainer*, entries: int,
                            blocks: bool, global_bits: int) -> int:
    if vbuf_avail(b) < 1:
        return 0
    int wire_bits = (int)vbuf_take_u8(b)
    int bits = 0
    bool has_palette = false
    if wire_bits == 0:
        int ok = 0
        int value = sec_wire_read_varint(b, &ok)
        if ok == 0:
            return 0
        vcont_reset(c, value)
        return 1
    if blocks:
        if wire_bits <= 4:
            bits = 4
            has_palette = true
        elif wire_bits <= 8:
            bits = wire_bits
            has_palette = true
        else:
            bits = global_bits
            if bits < wire_bits:
                bits = wire_bits
    else:
        if wire_bits <= 3:
            bits = wire_bits
            has_palette = true
        else:
            bits = global_bits
            if bits < wire_bits:
                bits = wire_bits
    if bits < 1 or bits > 32:
        return 0
    if has_palette:
        int ok = 0
        int palette_count = sec_wire_read_varint(b, &ok)
        if ok == 0 or palette_count < 1 or palette_count > (1 << bits):
            return 0
        vcont_reset(c, 0)
        int i = 0
        while i < palette_count:
            int value = sec_wire_read_varint(b, &ok)
            if ok == 0:
                return 0
            vcont_palette_add(c, value)
            i += 1
        if vcont_palette_len(c) != palette_count:
            return 0
    else:
        c.direct_bits = bits
    int per_word = 64 / bits
    int word_count = (entries + per_word - 1) / per_word
    if vbuf_avail(b) < word_count * 8:
        return 0
    if has_palette:
        vcont_alloc(c, bits)
    else:
        vcont_alloc_direct(c, bits)
    int word = 0
    while word < word_count:
        vcont_set_word(c, word, (uint64)vbuf_take_i64_be(b))
        word += 1
    return 1


public def sec_read_wire_sections(b: VBuf*, count: int, min_section: int,
                                 block_global_bits: int,
                                 biome_global_bits: int,
                                 ok: int*) -> char*:
    *ok = 0
    if b == null or count < 1 or block_global_bits < 1 or biome_global_bits < 1:
        return null
    char* sections = vt_calloc_ptrs(count)
    int i = 0
    while i < count:
        if vbuf_avail(b) < 2:
            vworld_free_column(sections, count)
            return null
        int non_empty = vbuf_take_i16_be(b)
        if non_empty < 0 or non_empty > 4096:
            vworld_free_column(sections, count)
            return null
        VSection* section = sec_new_for_wire(min_section + i,
                                             block_global_bits,
                                             biome_global_bits)
        section.non_empty = non_empty
        int blocks_ok = sec_wire_read_container(b, section.blocks,
                                                sec_block_count(), true,
                                                block_global_bits)
        int biomes_ok = sec_wire_read_container(b, section.biomes,
                                                sec_biome_count(), false,
                                                biome_global_bits)
        if blocks_ok == 0 or biomes_ok == 0:
            sec_free(section)
            vworld_free_column(sections, count)
            return null
        vt_ptr_set(sections, i, (void*)section)
        i += 1
    if vbuf_avail(b) != 0:
        vworld_free_column(sections, count)
        return null
    *ok = 1
    return sections


# Chunks Biomes repeats the biome container of every section in a column, in
# ascending y, with no block container and no light. The decoded values are
# copied into the section already in memory; a column the client has not
# loaded is walked and dropped rather than materialised half-empty.
public def sec_apply_wire_biomes(b: VBuf*, world: VWorld*, chunk_x: int,
                                 chunk_z: int, count: int, min_section: int,
                                 biome_global_bits: int) -> int:
    if b == null or world == null or count < 1:
        return 0
    int i = 0
    while i < count:
        VSection* decoded = sec_new_for_wire(min_section + i,
                                             sec_blocks_direct_bits(),
                                             biome_global_bits)
        int biomes_ok = sec_wire_read_container(b, decoded.biomes,
                                                sec_biome_count(), false,
                                                biome_global_bits)
        if biomes_ok == 0:
            sec_free(decoded)
            return 0
        VSection* target = vworld_section(world, chunk_x, chunk_z,
                                          min_section + i)
        if target != null:
            int at = 0
            while at < sec_biome_count():
                vcont_set(target.biomes, at, vcont_at(decoded.biomes, at))
                at += 1
        sec_free(decoded)
        i += 1
    return 1

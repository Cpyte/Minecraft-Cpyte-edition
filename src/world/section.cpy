# Vortex engine - chunk section.
#
# One 16x16x16 slice of the world: 4096 block states plus, following Horizon's
# split of the biome container, 64 biomes at 4x4x4 resolution, and the two
# four bit light masks.
#
# Entries are addressed the way the game lays a section out in memory:
#   block (x, y, z) -> x + z * 16 + y * 256
#   biome (x, y, z) -> x + z *  4 + y *  16
#
# Block states and biomes are held as ids chosen by the caller's registry; the
# engine never numbers them itself, so the NBT mapping here records the palette
# as ids. The io layer that owns a registry turns those ids into the
# Name/Properties compounds the game writes, and can read them back, through
# vcont_palette_at and sec_load_palette - the seams this module leaves open.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.

import stdlib


public def sec_size() -> int:
    return 16


public def sec_block_count() -> int:
    return 4096


public def sec_biome_count() -> int:
    return 64


# Two 4 bit light levels per byte.
public def sec_light_bytes() -> int:
    return 2048


def sec_block_index(x: int, y: int, z: int) -> int:
    return x + z * 16 + y * 256


def sec_biome_index(x: int, y: int, z: int) -> int:
    return x + z * 4 + y * 16


# The block and biome containers differ only in entry count and width bounds.
def sec_blocks_min_bits() -> int:
    return 4


def sec_blocks_max_bits() -> int:
    return 8


def sec_blocks_direct_bits() -> int:
    return 16


def sec_biomes_min_bits() -> int:
    return 1


def sec_biomes_max_bits() -> int:
    return 3


def sec_biomes_direct_bits() -> int:
    return 7


struct VSection:
    int y                 # section index in the column, not a block coordinate
    int non_empty         # non-air block count from a network section, if known
    VContainer* blocks
    VContainer* biomes
    char* block_light     # 2048 bytes, two 4 bit levels per byte
    char* sky_light


# ---- light -------------------------------------------------------------------

def sec_light_at(light: char*, index: int) -> int:
    if light == null or index < 0 or index >= 4096:
        return 0
    int byte = (int)vt_at(light, index / 2)
    if index % 2 == 0:
        return byte & 15
    return (byte >> 4) & 15


def sec_light_set(light: char*, index: int, level: int) -> void:
    if light == null or index < 0 or index >= 4096:
        return
    int at = index / 2
    int other = 0
    if index % 2 == 0:
        other = sec_light_at(light, index + 1) << 4
        vt_put(light, at, other | (level & 15))
    else:
        other = sec_light_at(light, index - 1)
        vt_put(light, at, other | ((level & 15) << 4))


# 256 longs, each holding eight bytes little endian.
def sec_light_words() -> int:
    return 256


def sec_light_to_tag(light: char*, name: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_long_array(), name)
    nbt_set_longs(t, sec_light_words())
    int w = 0
    while w < sec_light_words():
        int64 value = (int64)0
        int b = 0
        while b < 8:
            int byte = (int)vt_at(light, w * 8 + b) & 255
            value = value | ((int64)byte << ((int64)b * (int64)8))
            b += 1
        nbt_set_long_at(t, w, value)
        w += 1
    return t


def sec_light_from_tag(t: VNbt*, light: char*) -> void:
    if t == null or light == null:
        return
    int count = nbt_long_len(t)
    if count > sec_light_words():
        count = sec_light_words()
    int w = 0
    while w < count:
        int64 value = nbt_long_at(t, w)
        int b = 0
        while b < 8:
            int byte = (int)((value >> ((int64)b * (int64)8)) & (int64)255)
            vt_put(light, w * 8 + b, byte)
            b += 1
        w += 1
    while w < sec_light_words():
        int b = 0
        while b < 8:
            vt_put(light, w * 8 + b, 0)
            b += 1
        w += 1
    return


# ---- container to and from NBT -----------------------------------------------

# Palette entry count, whether the tag is a list of ints or an int array. A
# list of Name/Properties compounds is the registry layer's to read, so it is
# reported as no palette here rather than silently decoding to zeros.
def sec_palette_slots(t: VNbt*) -> int:
    VNbt* palette = nbt_find(t, "palette")
    if palette == null:
        return 0
    if palette.kind == nbt_list():
        int elem = nbt_list_element_kind(palette)
        if elem != nbt_int() and elem != nbt_byte() and elem != nbt_short():
            return 0
        return nbt_child_count(palette)
    if palette.kind == nbt_int_array():
        return nbt_int_len(palette)
    return 0


# Appends each palette entry to `c`, in tag order.
def sec_load_palette(palette: VNbt*, c: VContainer*) -> void:
    if palette == null:
        return
    int count = nbt_child_count(palette)
    if palette.kind == nbt_int_array():
        count = nbt_int_len(palette)
    int i = 0
    while i < count:
        if palette.kind == nbt_int_array():
            vcont_palette_add(c, nbt_int_at(palette, i))
        else:
            vcont_palette_add(c, nbt_int_value(nbt_child_at(palette, i), 0))
        i += 1
    return


# The palette the saved form records: one entry while the container is uniform,
# otherwise its own. An io layer translating ids to Name compounds walks these,
# so it sees exactly what the tag will hold.
public def sec_palette_size(c: VContainer*) -> int:
    if vcont_mode(c) == vcont_uniform_mode():
        return 1
    return vcont_palette_len(c)


public def sec_palette_entry(c: VContainer*, index: int) -> int:
    if vcont_mode(c) == vcont_uniform_mode():
        return vcont_uniform_value(c)
    return vcont_palette_at(c, index)


# TAG_Compound `{palette: [...], data: [long...]}` for one container. A uniform
# container writes the single palette entry and no data array, which is exactly
# what the game does.
def sec_container_to_nbt(c: VContainer*, name: str) -> VNbt*:
    VContainer* encoded = c
    VContainer* temporary = c
    if vcont_mode(c) == vcont_direct_mode():
        temporary = vcont_new(vcont_count(c), c.min_bits, 30, c.direct_bits)
        int at = 0
        while at < vcont_count(c):
            vcont_set(temporary, at, vcont_at(c, at))
            at += 1
        vcont_compact(temporary)
        encoded = temporary

    VNbt* root = nbt_compound_of(name)
    VNbt* palette = nbt_list_of("palette", nbt_int())
    int slots = sec_palette_size(encoded)
    int i = 0
    while i < slots:
        nbt_append(palette, nbt_int_of("", sec_palette_entry(encoded, i)))
        i += 1
    nbt_append(root, palette)

    int bits = vcont_save_bits_for(encoded)
    if bits <= 0:
        if temporary != c:
            vcont_free(temporary)
        return root
    VNbt* data = nbt_new(nbt_long_array(), "data")
    int words = vcont_save_words_for(encoded, bits)
    nbt_set_longs(data, words)
    int w = 0
    while w < words:
        nbt_set_long_at(data, w, (int64)vcont_save_word(encoded, w))
        w += 1
    nbt_append(root, data)
    if temporary != c:
        vcont_free(temporary)
    return root


# Fills `c` from a `{palette, data}` compound. Returns 0 when the tag is not a
# compound or carries no palette.
def sec_container_from_nbt(t: VNbt*, c: VContainer*, min_bits: int) -> int:
    if t == null:
        return 0
    if t.kind != nbt_compound():
        return 0
    int slots = sec_palette_slots(t)
    if slots <= 0:
        return 0
    int bits = vcont_bits_for(slots, min_bits)
    vcont_reset(c, 0)
    VNbt* palette = nbt_find(t, "palette")
    VNbt* data = nbt_find(t, "data")
    if data == null:
        sec_load_palette(palette, c)
        if vcont_palette_len(c) <= 0:
            return 0
        # A single valued palette needs no data array: the whole section holds
        # the one entry.
        if vcont_palette_len(c) == 1:
            vcont_reset(c, vcont_palette_at(c, 0))
            return 1
        return 0
    if data.kind != nbt_long_array():
        return 0
    VContainer* decoded = c
    VContainer* temporary = c
    if bits > c.max_bits:
        temporary = vcont_new(vcont_count(c), min_bits, 30, c.direct_bits)
        decoded = temporary
    sec_load_palette(palette, decoded)

    vcont_alloc(decoded, bits)
    int words = nbt_long_len(data)
    int want = vcont_save_words_for(decoded, bits)
    if words > want:
        words = want
    int w = 0
    while w < words:
        vcont_set_word(decoded, w, (uint64)nbt_long_at(data, w))
        w += 1

    if temporary != c:
        int at = 0
        while at < vcont_count(c):
            vcont_set(c, at, vcont_at(decoded, at))
            at += 1
        vcont_free(temporary)
    return 1


# ---- the section itself ------------------------------------------------------

public def sec_new_for_wire(y: int, block_global_bits: int, biome_global_bits: int) -> VSection*:
    VSection* s = new VSection
    s.y = y
    s.non_empty = 0
    s.blocks = vcont_new(sec_block_count(), sec_blocks_min_bits(),
                         sec_blocks_max_bits(), block_global_bits)
    s.biomes = vcont_new(sec_biome_count(), sec_biomes_min_bits(),
                         sec_biomes_max_bits(), biome_global_bits)
    s.block_light = vt_calloc_char(sec_light_bytes())
    s.sky_light = vt_calloc_char(sec_light_bytes())
    return s


public def sec_new(y: int) -> VSection*:
    return sec_new_for_wire(y, sec_blocks_direct_bits(), sec_biomes_direct_bits())


public def sec_free(s: VSection*) -> void:
    if s == null:
        return
    vcont_free(s.blocks)
    vcont_free(s.biomes)
    if s.block_light != null:
        vt_free((void*)s.block_light)
    if s.sky_light != null:
        vt_free((void*)s.sky_light)
    del s


public def sec_index_ok(x: int, y: int, z: int, stride: int) -> int:
    if x < 0 or x >= stride:
        return 0
    if y < 0 or y >= stride:
        return 0
    if z < 0 or z >= stride:
        return 0
    return 1


public def sec_block_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return vcont_at(s.blocks, sec_block_index(x, y, z))


public def sec_block_set(s: VSection*, x: int, y: int, z: int, state: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    vcont_set(s.blocks, sec_block_index(x, y, z), state)


public def sec_biome_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 4) == 0:
        return 0
    return vcont_at(s.biomes, sec_biome_index(x, y, z))


public def sec_biome_set(s: VSection*, x: int, y: int, z: int, biome: int) -> void:
    if sec_index_ok(x, y, z, 4) == 0:
        return
    vcont_set(s.biomes, sec_biome_index(x, y, z), biome)


public def sec_block_light_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return sec_light_at(s.block_light, sec_block_index(x, y, z))


public def sec_block_light_set(s: VSection*, x: int, y: int, z: int, level: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    sec_light_set(s.block_light, sec_block_index(x, y, z), level)


public def sec_sky_light_at(s: VSection*, x: int, y: int, z: int) -> int:
    if sec_index_ok(x, y, z, 16) == 0:
        return 0
    return sec_light_at(s.sky_light, sec_block_index(x, y, z))


public def sec_sky_light_set(s: VSection*, x: int, y: int, z: int, level: int) -> void:
    if sec_index_ok(x, y, z, 16) == 0:
        return
    sec_light_set(s.sky_light, sec_block_index(x, y, z), level)


# Shrinks both containers before a save so the palette and data width are the
# narrowest the contents allow.
public def sec_compact(s: VSection*) -> void:
    vcont_compact(s.blocks)
    vcont_compact(s.biomes)
    return


# The whole section compound: `block_states`, `biomes`, the Y index and the
# light masks. `AltValues` is the block light array and `SkyLight` the sky one.
public def sec_to_nbt(s: VSection*, name: str) -> VNbt*:
    sec_compact(s)
    VNbt* root = nbt_compound_of(name)
    nbt_append(root, sec_container_to_nbt(s.blocks, "block_states"))
    nbt_append(root, sec_container_to_nbt(s.biomes, "biomes"))
    nbt_append(root, nbt_byte_of("Y", s.y))
    nbt_append(root, sec_light_to_tag(s.block_light, "AltValues"))
    nbt_append(root, sec_light_to_tag(s.sky_light, "SkyLight"))
    return root


# Accepts either tag spelling for the light arrays, which differ between
# versions of the format.
public def sec_from_nbt(t: VNbt*, y: int) -> VSection*:
    VSection* s = sec_new(y)
    VNbt* blocks = nbt_find(t, "block_states")
    if sec_container_from_nbt(blocks, s.blocks, sec_blocks_min_bits()) == 0:
        sec_free(s)
        return null
    VNbt* biomes = nbt_find(t, "biomes")
    if sec_container_from_nbt(biomes, s.biomes, sec_biomes_min_bits()) == 0:
        sec_free(s)
        return null
    s.y = nbt_get_int(t, "Y", y)
    VNbt* light = nbt_find(t, "AltValues")
    if light == null:
        light = nbt_find(t, "BlockLight")
    sec_light_from_tag(light, s.block_light)
    sec_light_from_tag(nbt_find(t, "SkyLight"), s.sky_light)
    return s

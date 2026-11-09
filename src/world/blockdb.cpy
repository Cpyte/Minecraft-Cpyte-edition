# Vortex engine - block facts lookup.
#
# The mesher needs three things for a block state id: whether it is air, what
# geometry it has, and whether it hides the neighbour's face. The block state
# id -> block mapping comes from the vanilla data generator's blocks report,
# packed into a compact binary read by the C layer in src/engine/blockdb.c.
#
# On first launch the executable builds that binary itself: blockdb_setup.c
# discovers a local Minecraft installation, runs its Java data generator and
# writes generated/blockdb.bin. No scripting runtime is involved. tools/ holds
# optional developer equivalents, never required to run the client.
#
# The database is optional. Without it the mesher falls back to state 0 = air
# and every other state = opaque cube, which keeps a world visible even when
# the generated data has not been built.
#
# License boundary: the binary is generated from user-supplied version data and
# lives under generated/; it is not part of the repository. See
# docs/PARITY_BOUNDARY.md.

import "../engine/blockdb.c"
import "../engine/blockdb_setup.c"


# ---- classification flags, matching tools/gen_blockdb.py ---------------------

public def block_flag_air() -> int:
    return 1


public def block_flag_fluid() -> int:
    return 2


public def block_flag_cube() -> int:
    return 4


public def block_flag_opaque() -> int:
    return 8


public def block_flag_translucent() -> int:
    return 16


public def block_flag_leaves() -> int:
    return 32


public def block_flag_cross() -> int:
    return 64


# ---- loading -----------------------------------------------------------------

public def blockdb_default_path() -> str:
    return vt_blockdb_path_from_env()


public def blockdb_load(path: str) -> int:
    return vt_blockdb_load(path)


public def blockdb_load_default() -> int:
    return vt_blockdb_load(vt_blockdb_path_from_env())


public def blockdb_unload() -> void:
    vt_blockdb_unload()


public def blockdb_loaded() -> int:
    return vt_blockdb_loaded()


public def blockdb_verify() -> int:
    return vt_blockdb_verify()


public def blockdb_state_count() -> int:
    return vt_blockdb_state_count()


public def blockdb_block_count() -> int:
    return vt_blockdb_block_count()


# ---- state queries -----------------------------------------------------------

# Raw flags, or -1 when the state is unknown or no database is loaded.
public def blockdb_flags(state: int) -> int:
    return vt_blockdb_flags(state)


public def blockdb_protocol(state: int) -> int:
    return vt_blockdb_protocol(state)


# ---- geometry shape and tint (name-based heuristics) -------------------------

public def block_shape_cube() -> int:
    return 0


public def block_shape_skip() -> int:
    return 255


public def block_tint_none() -> int:
    return 0


public def block_tint_grass() -> int:
    return 1


public def block_tint_foliage() -> int:
    return 2


public def block_tint_water() -> int:
    return 3


# Canonical geometry code for a state; see engine/blockdb.c for the table.
public def blockdb_shape(state: int) -> int:
    return ((int)vt_blockdb_shape_tint(state)) & 255


public def blockdb_tint(state: int) -> int:
    return (((int)vt_blockdb_shape_tint(state)) >> 8) & 255


# Packed 0xRRGGBB tint for a biome id and tint kind. Defaults to the plains
# colours until the registry layer fills the override table.
public def biome_color(biome: int, kind: int) -> int:
    return (int)vt_biome_color(biome, kind)


public def biome_color_set(biome: int, grass: int, foliage: int, water: int) -> void:
    vt_biome_color_set(biome, grass, foliage, water)


public def biome_colors_reset() -> void:
    vt_biome_colors_reset()


public def blockdb_has(state: int, flag: int) -> int:
    int flags = vt_blockdb_flags(state)
    if flags < 0:
        if state == 0:
            return 1 if flag == block_flag_air() else 0
        return 1 if flag == block_flag_opaque() or flag == block_flag_cube() else 0
    if (flags & flag) != 0:
        return 1
    return 0


public def blockdb_is_air(state: int) -> int:
    return blockdb_has(state, block_flag_air())


# A full cube, so the mesher emits its six faces (subject to culling).
public def blockdb_is_cube(state: int) -> int:
    return blockdb_has(state, block_flag_cube())


# Opaque enough that a neighbouring full cube's shared face is invisible.
public def blockdb_is_opaque(state: int) -> int:
    return blockdb_has(state, block_flag_opaque())


public def blockdb_is_translucent(state: int) -> int:
    return blockdb_has(state, block_flag_translucent())


public def blockdb_is_leaves(state: int) -> int:
    return blockdb_has(state, block_flag_leaves())


public def blockdb_is_cross(state: int) -> int:
    return blockdb_has(state, block_flag_cross())


public def blockdb_is_fluid(state: int) -> int:
    return blockdb_has(state, block_flag_fluid())


# 1 when two neighbouring states share a face that can be dropped: the near
# block is a full cube and the far one hides the face. Leaves are culled
# against leaves, translucent blocks against their own block, everything else
# only against opaque cubes.
public def blockdb_hides_face(near: int, far: int) -> int:
    if blockdb_is_air(near) == 1 or blockdb_is_cube(near) == 0:
        return 0
    if blockdb_is_air(far) == 1:
        return 0
    if blockdb_is_opaque(far) == 1:
        return 1
    if blockdb_is_leaves(near) == 1 and blockdb_is_leaves(far) == 1:
        return 1
    if blockdb_is_translucent(near) == 1 and blockdb_is_translucent(far) == 1:
        int a = vt_blockdb_protocol(near)
        int b = vt_blockdb_protocol(far)
        if a >= 0 and a == b:
            return 1
    return 0


# Block name without the namespace, or "" when unknown.
public def blockdb_name(state: int) -> str:
    char* buffer = vt_calloc_char(96)
    int length = vt_blockdb_name(state, buffer, 96)
    if length < 0:
        vt_free((void*)buffer)
        return ""
    str out = vt_dup(buffer)
    vt_free((void*)buffer)
    return out


# ---- record view, used by the loader test ------------------------------------

public def blockdb_first_state_at(index: int) -> int:
    return vt_blockdb_first_state_at(index)


public def blockdb_state_count_at(index: int) -> int:
    return vt_blockdb_state_count_at(index)


public def blockdb_flags_at(index: int) -> int:
    return vt_blockdb_flags_at(index)


public def blockdb_protocol_at(index: int) -> int:
    return vt_blockdb_protocol_at(index)


public def blockdb_name_at(index: int) -> str:
    char* buffer = vt_calloc_char(96)
    int length = vt_blockdb_name_at(index, buffer, 96)
    if length < 0:
        vt_free((void*)buffer)
        return ""
    str out = vt_dup(buffer)
    vt_free((void*)buffer)
    return out


public def blockdb_name_length_at(index: int) -> int:
    return vt_blockdb_name_length_at(index)

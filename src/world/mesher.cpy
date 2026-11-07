# Vortex engine - greedy section mesher.
#
# Turns a loaded 16x16x16 section into two vertex/index streams: opaque
# (solid cubes, cutout leaves and cross-shaped plants) and translucent (water,
# lava, glass, ice). The algorithm follows Horizon's terrain mesher in shape:
#
#   * one pass per face direction; each 16x16 slice builds a mask of visible
#     faces, with the neighbour sampled through VWorld so faces on a section
#     or chunk boundary are culled correctly;
#   * equal mask cells are merged into maximal rectangles (width first, then
#     height), so a flat stone section needs six quads, not 24,576;
#   * a mask cell's key is the block's protocol id plus the light of the cell
#     in front of the face, so a merge never crosses a material or light
#     boundary;
#   * translucent faces go to the second stream so a renderer can order them.
#
# Vertices are typed, packed int64 vectors, nine components each:
#
#   0 x, 1 y, 2 z      absolute block corner (integers; a quad is planar)
#   3 u, 4 v           texture coordinates in block units, 0..width/height
#   5 layer            block protocol id (the renderer's texture layer)
#   6 sky_light        0..15
#   7 block_light      0..15
#   8 face             +X -X +Y -Y +Z -Z, or mesh_face_cross()
#
# Indices are int64, two triangles per quad, counter-clockwise from outside.
#
# License boundary: no Mojang-derived code or data. Block classification comes
# from the optional generated database (see world/blockdb.cpy); without it the
# mesher treats state 0 as air and everything else as an opaque cube.
#
# The compiler resolves calls against what it has already read, so the helpers
# below are ordered bottom up.

import stdlib


public def mesh_face_pos_x() -> int:
    return 0


public def mesh_face_neg_x() -> int:
    return 1


public def mesh_face_pos_y() -> int:
    return 2


public def mesh_face_neg_y() -> int:
    return 3


public def mesh_face_pos_z() -> int:
    return 4


public def mesh_face_neg_z() -> int:
    return 5


public def mesh_face_cross() -> int:
    return 6


# Components per vertex, matching the list in the module comment.
public def mesh_vertex_stride() -> int:
    return 9


def mesh_kind_scale() -> int:
    return 1000000000


def mesh_unknown_layer() -> int:
    return 65535


# ---- typed vectors -----------------------------------------------------------

def mesh_empty_ints() -> int64[]:
    int64[] none = new int64[0]
    return none


struct VMesh:
    int64[] verts
    int64[] indices
    int vertex_count
    int index_count
    int quad_count


public def vmesh_new() -> VMesh*:
    VMesh* mesh = new VMesh
    mesh.verts = mesh_empty_ints()
    mesh.indices = mesh_empty_ints()
    mesh.vertex_count = 0
    mesh.index_count = 0
    mesh.quad_count = 0
    return mesh


public def vmesh_free(mesh: VMesh*) -> void:
    if mesh == null:
        return
    del mesh


public def vmesh_vertex_count(mesh: VMesh*) -> int:
    return mesh.vertex_count


public def vmesh_index_count(mesh: VMesh*) -> int:
    return mesh.index_count


public def vmesh_quad_count(mesh: VMesh*) -> int:
    return mesh.quad_count


# Component `component` of vertex `vertex`.
public def vmesh_component(mesh: VMesh*, vertex: int, component: int) -> int64:
    int at = vertex * mesh_vertex_stride() + component
    if at < 0 or at >= (int)len(mesh.verts):
        return (int64)0
    return mesh.verts[at]


public def vmesh_index(mesh: VMesh*, index: int) -> int64:
    if index < 0 or index >= (int)len(mesh.indices):
        return (int64)0
    return mesh.indices[index]


def vmesh_add_vertex(mesh: VMesh*, x: int, y: int, z: int, u: int, v: int,
                     layer: int, sky: int, block: int, face: int) -> void:
    append(mesh.verts, (int64)x)
    append(mesh.verts, (int64)y)
    append(mesh.verts, (int64)z)
    append(mesh.verts, (int64)u)
    append(mesh.verts, (int64)v)
    append(mesh.verts, (int64)layer)
    append(mesh.verts, (int64)sky)
    append(mesh.verts, (int64)block)
    append(mesh.verts, (int64)face)
    mesh.vertex_count += 1


# Four corners in counter-clockwise order seen from outside the block.
def vmesh_add_quad(mesh: VMesh*, x0: int, y0: int, z0: int,
                   x1: int, y1: int, z1: int,
                   x2: int, y2: int, z2: int,
                   x3: int, y3: int, z3: int,
                   width: int, height: int, layer: int, sky: int, block: int,
                   face: int) -> void:
    int base = mesh.vertex_count
    vmesh_add_vertex(mesh, x0, y0, z0, 0, 0, layer, sky, block, face)
    vmesh_add_vertex(mesh, x1, y1, z1, width, 0, layer, sky, block, face)
    vmesh_add_vertex(mesh, x2, y2, z2, width, height, layer, sky, block, face)
    vmesh_add_vertex(mesh, x3, y3, z3, 0, height, layer, sky, block, face)
    append(mesh.indices, (int64)base)
    append(mesh.indices, (int64)(base + 1))
    append(mesh.indices, (int64)(base + 2))
    append(mesh.indices, (int64)base)
    append(mesh.indices, (int64)(base + 2))
    append(mesh.indices, (int64)(base + 3))
    mesh.index_count += 6
    mesh.quad_count += 1


# ---- result ------------------------------------------------------------------

struct VMeshResult:
    VMesh* opaque
    VMesh* translucent
    int sections
    int quads


public def vmesh_result_new() -> VMeshResult*:
    VMeshResult* result = new VMeshResult
    result.opaque = vmesh_new()
    result.translucent = vmesh_new()
    result.sections = 0
    result.quads = 0
    return result


public def vmesh_result_free(result: VMeshResult*) -> void:
    if result == null:
        return
    vmesh_free(result.opaque)
    vmesh_free(result.translucent)
    del result


public def vmesh_result_opaque(result: VMeshResult*) -> VMesh*:
    return result.opaque


public def vmesh_result_translucent(result: VMeshResult*) -> VMesh*:
    return result.translucent


public def vmesh_result_sections(result: VMeshResult*) -> int:
    return result.sections


public def vmesh_result_quads(result: VMeshResult*) -> int:
    VMesh* opaque = result.opaque
    VMesh* translucent = result.translucent
    return opaque.quad_count + translucent.quad_count


# ---- mask --------------------------------------------------------------------

# Cell coordinate for one face slice. `a` runs along the first axis, `b` along
# the second; see the emission table below for the mapping.
def mesh_cell_x(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return slice
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return a
    return a


def mesh_cell_y(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return b
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return slice
    return b


def mesh_cell_z(dir: int, slice: int, a: int, b: int) -> int:
    if dir == mesh_face_pos_x() or dir == mesh_face_neg_x():
        return a
    if dir == mesh_face_pos_y() or dir == mesh_face_neg_y():
        return b
    return slice


def mesh_neighbor_x(dir: int, x: int) -> int:
    if dir == mesh_face_pos_x():
        return x + 1
    if dir == mesh_face_neg_x():
        return x - 1
    return x


def mesh_neighbor_y(dir: int, y: int) -> int:
    if dir == mesh_face_pos_y():
        return y + 1
    if dir == mesh_face_neg_y():
        return y - 1
    return y


def mesh_neighbor_z(dir: int, z: int) -> int:
    if dir == mesh_face_pos_z():
        return z + 1
    if dir == mesh_face_neg_z():
        return z - 1
    return z


# Mask key for the face of the block at (x, y, z) in direction `dir`, or 0
# when the face is absent or hidden. The key packs the render layer, the block
# id and the light of the cell in front of the face.
def mesh_face_key(world: VWorld*, chunk_x: int, chunk_z: int, section_y: int,
                  section: VSection*, x: int, y: int, z: int, dir: int) -> int:
    int state = sec_block_at(section, x, y, z)
    if state == 0:
        return 0
    if blockdb_is_cube(state) == 0:
        return 0
    int nx = mesh_neighbor_x(dir, x)
    int ny = mesh_neighbor_y(dir, y)
    int nz = mesh_neighbor_z(dir, z)
    int wx = chunk_x * 16 + nx
    int wy = section_y * 16 + ny
    int wz = chunk_z * 16 + nz
    int neighbor = vworld_block_at(world, wx, wy, wz)
    if blockdb_hides_face(state, neighbor) == 1:
        return 0
    int light = vworld_light_at(world, wx, wy, wz)
    int layer = blockdb_protocol(state)
    if layer < 0:
        layer = mesh_unknown_layer()
    int kind = 0
    if blockdb_is_translucent(state) == 1:
        kind = 1
    return kind * mesh_kind_scale() + (layer + 1) * 256 + light


def mesh_build_mask(world: VWorld*, chunk_x: int, chunk_z: int, section_y: int,
                    section: VSection*, dir: int, slice: int, mask: int*) -> void:
    int a = 0
    while a < 16:
        int b = 0
        while b < 16:
            int x = mesh_cell_x(dir, slice, a, b)
            int y = mesh_cell_y(dir, slice, a, b)
            int z = mesh_cell_z(dir, slice, a, b)
            int key = mesh_face_key(world, chunk_x, chunk_z, section_y, section,
                                    x, y, z, dir)
            vt_iset(mask, a + b * 16, key)
            b += 1
        a += 1


# ---- emission ----------------------------------------------------------------

# Absolute base of the section, so the vertex vectors need no per-section
# translation later.
def mesh_emit_rect(mesh: VMesh*, dir: int, slice: int, base_x: int, base_y: int,
                   base_z: int, a: int, b: int, width_a: int, width_b: int,
                   layer: int, sky: int, block: int) -> void:
    int x = base_x + slice
    int y = base_y + slice
    int z = base_z + slice
    if dir == mesh_face_pos_x():
        vmesh_add_quad(mesh, x + 1, base_y + b, base_z + a,
                       x + 1, base_y + b + width_b, base_z + a,
                       x + 1, base_y + b + width_b, base_z + a + width_a,
                       x + 1, base_y + b, base_z + a + width_a,
                       width_b, width_a, layer, sky, block, dir)
    elif dir == mesh_face_neg_x():
        vmesh_add_quad(mesh, x, base_y + b, base_z + a + width_a,
                       x, base_y + b + width_b, base_z + a + width_a,
                       x, base_y + b + width_b, base_z + a,
                       x, base_y + b, base_z + a,
                       width_b, width_a, layer, sky, block, dir)
    elif dir == mesh_face_pos_y():
        vmesh_add_quad(mesh, base_x + a, y + 1, base_z + b,
                       base_x + a, y + 1, base_z + b + width_b,
                       base_x + a + width_a, y + 1, base_z + b + width_b,
                       base_x + a + width_a, y + 1, base_z + b,
                       width_a, width_b, layer, sky, block, dir)
    elif dir == mesh_face_neg_y():
        vmesh_add_quad(mesh, base_x + a, y, base_z + b,
                       base_x + a + width_a, y, base_z + b,
                       base_x + a + width_a, y, base_z + b + width_b,
                       base_x + a, y, base_z + b + width_b,
                       width_a, width_b, layer, sky, block, dir)
    elif dir == mesh_face_pos_z():
        vmesh_add_quad(mesh, base_x + a, base_y + b, z + 1,
                       base_x + a + width_a, base_y + b, z + 1,
                       base_x + a + width_a, base_y + b + width_b, z + 1,
                       base_x + a, base_y + b + width_b, z + 1,
                       width_a, width_b, layer, sky, block, dir)
    else:
        vmesh_add_quad(mesh, base_x + a + width_a, base_y + b, z,
                       base_x + a, base_y + b, z,
                       base_x + a, base_y + b + width_b, z,
                       base_x + a + width_a, base_y + b + width_b, z,
                       width_a, width_b, layer, sky, block, dir)


# Merges equal mask cells into maximal rectangles and emits one quad each.
def mesh_greedy(opaque: VMesh*, translucent: VMesh*, mask: int*, dir: int,
                slice: int, base_x: int, base_y: int, base_z: int) -> void:
    int a = 0
    while a < 16:
        int b = 0
        while b < 16:
            int key = vt_iget(mask, a + b * 16)
            if key != 0:
                int width_b = 1
                while b + width_b < 16 and vt_iget(mask, a + (b + width_b) * 16) == key:
                    width_b += 1
                int width_a = 1
                bool grow = true
                while a + width_a < 16 and grow:
                    int i = 0
                    while i < width_b:
                        if vt_iget(mask, (a + width_a) + (b + i) * 16) != key:
                            grow = false
                        i += 1
                    if grow:
                        width_a += 1
                int kind = key / mesh_kind_scale()
                int rest = key % mesh_kind_scale()
                int layer = rest / 256 - 1
                int sky = (rest % 256) / 16
                int block = rest % 16
                VMesh* target = opaque
                if kind == 1:
                    target = translucent
                mesh_emit_rect(target, dir, slice, base_x, base_y, base_z,
                               a, b, width_a, width_b, layer, sky, block)
                int ai = 0
                while ai < width_a:
                    int bi = 0
                    while bi < width_b:
                        vt_iset(mask, (a + ai) + (b + bi) * 16, 0)
                        bi += 1
                    ai += 1
                b += width_b
            else:
                b += 1
        a += 1


# ---- cross geometry ----------------------------------------------------------

def mesh_cross_quads(mesh: VMesh*, base_x: int, base_y: int, base_z: int,
                     x: int, y: int, z: int, layer: int, sky: int, block: int) -> void:
    int x0 = base_x + x
    int y0 = base_y + y
    int z0 = base_z + z
    # Both diagonals, each emitted twice so the quad is visible from either
    # side; plants are not sorted into a back-face stream.
    vmesh_add_quad(mesh, x0, y0, z0, x0 + 1, y0, z0 + 1,
                   x0 + 1, y0 + 1, z0 + 1, x0, y0 + 1, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0, y0 + 1, z0, x0 + 1, y0 + 1, z0 + 1,
                   x0 + 1, y0, z0 + 1, x0, y0, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0 + 1, y0, z0, x0, y0, z0 + 1,
                   x0, y0 + 1, z0 + 1, x0 + 1, y0 + 1, z0,
                   1, 1, layer, sky, block, mesh_face_cross())
    vmesh_add_quad(mesh, x0 + 1, y0 + 1, z0, x0, y0 + 1, z0 + 1,
                   x0, y0, z0 + 1, x0 + 1, y0, z0,
                   1, 1, layer, sky, block, mesh_face_cross())


def mesh_cross_pass(result: VMeshResult*, world: VWorld*, chunk_x: int,
                    chunk_z: int, section_y: int, section: VSection*) -> void:
    int base_x = chunk_x * 16
    int base_y = section_y * 16
    int base_z = chunk_z * 16
    int x = 0
    while x < 16:
        int y = 0
        while y < 16:
            int z = 0
            while z < 16:
                int state = sec_block_at(section, x, y, z)
                if state != 0 and blockdb_is_cross(state) == 1:
                    int light = vworld_light_at(world, base_x + x, base_y + y,
                                                base_z + z)
                    int layer = blockdb_protocol(state)
                    if layer < 0:
                        layer = mesh_unknown_layer()
                    mesh_cross_quads(result.opaque, base_x, base_y, base_z,
                                     x, y, z, layer, light / 16, light % 16)
                z += 1
            y += 1
        x += 1


# ---- section and world entry points -----------------------------------------

def vmesh_section_into(result: VMeshResult*, world: VWorld*, chunk_x: int,
                       chunk_z: int, section_y: int) -> void:
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return
    int base_x = chunk_x * 16
    int base_y = section_y * 16
    int base_z = chunk_z * 16
    int* mask = vt_calloc_int(256)
    int dir = 0
    while dir < 6:
        int slice = 0
        while slice < 16:
            int i = 0
            while i < 256:
                vt_iset(mask, i, 0)
                i += 1
            mesh_build_mask(world, chunk_x, chunk_z, section_y, section, dir,
                            slice, mask)
            mesh_greedy(result.opaque, result.translucent, mask, dir, slice,
                        base_x, base_y, base_z)
            slice += 1
        dir += 1
    vt_free((void*)mask)
    mesh_cross_pass(result, world, chunk_x, chunk_z, section_y, section)
    result.sections += 1
    result.quads = vmesh_result_quads(result)


# Mesh one section; absolute vertex coordinates.
public def vmesh_section(world: VWorld*, chunk_x: int, chunk_z: int,
                         section_y: int) -> VMeshResult*:
    VMeshResult* result = vmesh_result_new()
    vmesh_section_into(result, world, chunk_x, chunk_z, section_y)
    return result


# Mesh every loaded section of the world into one pair of streams.
public def vmesh_world(world: VWorld*) -> VMeshResult*:
    VMeshResult* result = vmesh_result_new()
    if world == null:
        return result
    int column = 0
    while column < world.count:
        int chunk_x = vt_iget(world.chunk_x, column)
        int chunk_z = vt_iget(world.chunk_z, column)
        int i = 0
        while i < world.section_count:
            vmesh_section_into(result, world, chunk_x, chunk_z,
                               world.min_section + i)
            i += 1
        column += 1
    return result

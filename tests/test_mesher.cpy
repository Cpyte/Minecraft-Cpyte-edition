# Vortex engine - greedy mesher tests.
#
# The fixture database in tests/fixtures/blockdb.bin is synthetic (air, stone,
# log, water, glass, leaves, grass, slab); it exercises the loader and every
# classification path without shipping generated game data.

import stdlib


def fixture_path() -> str:
    return "tests/fixtures/blockdb.bin"


def make_world() -> VWorld*:
    VWorld* world = vworld_new(4, 0, 1, 15, 6)
    char* sections = vt_calloc_ptrs(1)
    vt_ptr_set(sections, 0, (void*)sec_new(0))
    vworld_replace_sections(world, 0, 0, sections)
    return world


def fill(world: VWorld*, state: int) -> void:
    VSection* section = vworld_section(world, 0, 0, 0)
    int x = 0
    while x < 16:
        int y = 0
        while y < 16:
            int z = 0
            while z < 16:
                sec_block_set(section, x, y, z, state)
                z += 1
            y += 1
        x += 1


def clear(world: VWorld*) -> void:
    fill(world, 0)


def first_face_vertex(mesh: VMesh*, face: int) -> int:
    int count = vmesh_vertex_count(mesh)
    int i = 0
    while i < count:
        if (int)vmesh_component(mesh, i, 8) == face:
            return i
        i += 1
    return -1


def count_face(mesh: VMesh*, face: int) -> int:
    int count = vmesh_vertex_count(mesh)
    int i = 0
    int quads = 0
    while i < count:
        if (int)vmesh_component(mesh, i, 8) == face:
            quads += 1
        i += 4
    return quads


def test_database(fails: int*) -> void:
    print("block database:")
    check_int("fixture loads", blockdb_load(fixture_path()), 1, fails)
    check_int("loader validates", blockdb_verify(), 1, fails)
    check_int("state count", blockdb_state_count(), 12, fails)
    check_int("block count", blockdb_block_count(), 8, fails)
    check_str("air name", blockdb_name(0), "air", fails)
    check_str("stone name", blockdb_name(1), "stone", fails)
    check_int("log state 2 is log", blockdb_protocol(2), 2, fails)
    check_int("log state 4 is still log", blockdb_protocol(4), 2, fails)
    check_int("water is fluid", blockdb_is_fluid(5), 1, fails)
    check_int("water is translucent", blockdb_is_translucent(5), 1, fails)
    check_int("glass is translucent", blockdb_is_translucent(7), 1, fails)
    check_int("leaves are leaves", blockdb_is_leaves(8), 1, fails)
    check_int("grass is cross", blockdb_is_cross(9), 1, fails)
    check_int("slab is not a cube", blockdb_is_cube(10), 0, fails)
    check_int("stone is opaque", blockdb_is_opaque(1), 1, fails)
    check_int("stone hides stone faces", blockdb_hides_face(1, 1), 1, fails)
    check_int("glass hides glass faces", blockdb_hides_face(7, 7), 1, fails)
    check_int("stone does not hide glass faces", blockdb_hides_face(1, 7), 0, fails)
    check_int("record order", blockdb_first_state_at(0), 0, fails)
    check_int("record two starts at 2", blockdb_first_state_at(2), 2, fails)
    check_str("record name", blockdb_name_at(3), "water", fails)


def test_greedy_fill(fails: int*) -> void:
    print("mesher: filled section:")
    VWorld* world = make_world()
    fill(world, 1)
    VMeshResult* result = vmesh_section(world, 0, 0, 0)
    VMesh* opaque = vmesh_result_opaque(result)
    check_int("one rebuilt section", vmesh_result_sections(result), 1, fails)
    check_int("six greedy quads", vmesh_result_quads(result), 6, fails)
    check_int("all opaque", vmesh_quad_count(opaque), 6, fails)
    check_int("no translucent quads", vmesh_quad_count(vmesh_result_translucent(result)), 0, fails)
    check_int("24 vertices", vmesh_vertex_count(opaque), 24, fails)
    check_int("36 indices", vmesh_index_count(opaque), 36, fails)
    check_int("one merged top face", count_face(opaque, mesh_face_pos_y()), 1, fails)
    int top = first_face_vertex(opaque, mesh_face_pos_y())
    check_int("top face height", (int)vmesh_component(opaque, top, 1), 16, fails)
    check("top face spans x", (int)vmesh_component(opaque, top + 2, 0) == 16, fails)
    check("top face spans z", (int)vmesh_component(opaque, top + 2, 2) == 16, fails)
    vmesh_result_free(result)
    vworld_free(world)


def test_single_block(fails: int*) -> void:
    print("mesher: single block:")
    VWorld* world = make_world()
    VSection* section = vworld_section(world, 0, 0, 0)
    clear(world)
    sec_block_set(section, 8, 8, 8, 1)
    VMeshResult* result = vmesh_section(world, 0, 0, 0)
    check_int("six faces of one block", vmesh_result_quads(result), 6, fails)
    check_int("one quad per direction", count_face(vmesh_result_opaque(result), mesh_face_pos_x()), 1, fails)
    vmesh_result_free(result)

    clear(world)
    sec_block_set(section, 8, 8, 8, 1)
    sec_block_set(section, 9, 8, 8, 1)
    result = vmesh_section(world, 0, 0, 0)
    # Ten exposed block faces merge into six rectangles: the four 1x1 outer
    # faces plus one 2x1 top and one 2x1 bottom.
    check_int("two blocks merge to six quads", vmesh_result_quads(result), 6, fails)
    int top = first_face_vertex(vmesh_result_opaque(result), mesh_face_pos_y())
    check_int("merged top starts at x=8", (int)vmesh_component(vmesh_result_opaque(result), top, 0), 8, fails)
    check_int("merged top reaches x=10", (int)vmesh_component(vmesh_result_opaque(result), top + 2, 0), 10, fails)
    vmesh_result_free(result)
    vworld_free(world)


def test_layers(fails: int*) -> void:
    print("mesher: layers and light:")
    VWorld* world = make_world()
    VSection* section = vworld_section(world, 0, 0, 0)
    clear(world)
    sec_block_set(section, 8, 8, 8, 7)
    sec_block_set(section, 9, 8, 8, 7)
    VMeshResult* result = vmesh_section(world, 0, 0, 0)
    check_int("glass goes to translucent", vmesh_quad_count(vmesh_result_translucent(result)), 6, fails)
    check_int("glass leaves opaque empty", vmesh_quad_count(vmesh_result_opaque(result)), 0, fails)
    vmesh_result_free(result)

    # Different light above one of the two glass blocks splits the merged top
    # face; every other rectangle still merges.
    sec_block_light_set(section, 9, 9, 8, 15)
    result = vmesh_section(world, 0, 0, 0)
    check_int("light boundary splits a merge", vmesh_quad_count(vmesh_result_translucent(result)), 7, fails)
    int top = first_face_vertex(vmesh_result_translucent(result), mesh_face_pos_y())
    check_int("first top face is the dark one", (int)vmesh_component(vmesh_result_translucent(result), top, 7), 0, fails)
    check_int("second top face carries light", (int)vmesh_component(vmesh_result_translucent(result), top + 4, 7), 15, fails)
    vmesh_result_free(result)

    clear(world)
    sec_block_set(section, 8, 8, 8, 1)
    sec_block_set(section, 9, 8, 8, 7)
    result = vmesh_section(world, 0, 0, 0)
    check_int("stone keeps six faces beside glass", vmesh_quad_count(vmesh_result_opaque(result)), 6, fails)
    check_int("glass loses the stone-facing side", vmesh_quad_count(vmesh_result_translucent(result)), 5, fails)
    check_int("stone and glass do not merge", vmesh_result_quads(result), 11, fails)
    vmesh_result_free(result)
    vworld_free(world)


def test_cross(fails: int*) -> void:
    print("mesher: cross geometry:")
    VWorld* world = make_world()
    VSection* section = vworld_section(world, 0, 0, 0)
    clear(world)
    sec_block_set(section, 4, 4, 4, 9)
    VMeshResult* result = vmesh_section(world, 0, 0, 0)
    check_int("two diagonals, both windings", vmesh_quad_count(vmesh_result_opaque(result)), 4, fails)
    check_int("cross quads are tagged", count_face(vmesh_result_opaque(result), mesh_face_cross()), 4, fails)
    check_int("cross quads do not cull", vmesh_result_quads(result), 4, fails)
    vmesh_result_free(result)
    vworld_free(world)


def test_cross_chunk_culling(fails: int*) -> void:
    print("mesher: cross-chunk culling:")
    VWorld* world = vworld_new(4, 0, 1, 15, 6)
    char* first = vt_calloc_ptrs(1)
    vt_ptr_set(first, 0, (void*)sec_new(0))
    vworld_replace_sections(world, 0, 0, first)
    char* second = vt_calloc_ptrs(1)
    vt_ptr_set(second, 0, (void*)sec_new(0))
    vworld_replace_sections(world, 1, 0, second)
    VSection* left = vworld_section(world, 0, 0, 0)
    VSection* right = vworld_section(world, 1, 0, 0)
    int y = 0
    while y < 16:
        int z = 0
        while z < 16:
            sec_block_set(left, 15, y, z, 1)
            sec_block_set(right, 0, y, z, 1)
            z += 1
        y += 1
    VMeshResult* result = vmesh_section(world, 0, 0, 0)
    check_int("neighbouring chunk hides the boundary face", count_face(vmesh_result_opaque(result), mesh_face_pos_x()), 0, fails)
    check_int("five remaining greedy quads", vmesh_result_quads(result), 5, fails)
    vmesh_result_free(result)
    result = vmesh_section(world, 1, 0, 0)
    check_int("culling works from the other side", count_face(vmesh_result_opaque(result), mesh_face_neg_x()), 0, fails)
    vmesh_result_free(result)
    vworld_free(world)


def test_world_and_fallback(fails: int*) -> void:
    print("mesher: world and fallback:")
    VWorld* world = make_world()
    fill(world, 1)
    VMeshResult* result = vmesh_world(world)
    check_int("world mesh visits the section", vmesh_result_sections(result), 1, fails)
    check_int("world mesh matches section mesh", vmesh_result_quads(result), 6, fails)
    vmesh_result_free(result)

    blockdb_unload()
    check_int("database unloaded", blockdb_loaded(), 0, fails)
    clear(world)
    sec_block_set(vworld_section(world, 0, 0, 0), 3, 3, 3, 42)
    result = vmesh_section(world, 0, 0, 0)
    check_int("fallback keeps unknown blocks visible", vmesh_result_quads(result), 6, fails)
    check_int("fallback treats state 0 as air", blockdb_is_air(0), 1, fails)
    vmesh_result_free(result)
    vworld_free(world)


def main() -> int:
    int fails = 0
    test_database(&fails)
    if blockdb_loaded() == 0:
        print("mesher: fixture missing, remaining tests skipped")
        return report("mesher", fails)
    test_greedy_fill(&fails)
    test_single_block(&fails)
    test_layers(&fails)
    test_cross(&fails)
    test_cross_chunk_culling(&fails)
    test_world_and_fallback(&fails)
    return report("mesher", fails)

# Vortex engine - bounded loaded-chunk store.

import stdlib


struct VWorld:
    int capacity
    int count
    int min_section
    int section_count
    int block_global_bits
    int biome_global_bits
    int* chunk_x
    int* chunk_z
    char* columns
    char* heightmaps


struct VDimensionRegistry:
    int capacity
    int dimension_count
    int dimension_registry_seen
    int biome_registry_seen
    int block_global_bits
    int biome_global_bits
    int* min_sections
    int* section_counts


public def vdimension_registry_new() -> VDimensionRegistry*:
    VDimensionRegistry* registry = new VDimensionRegistry
    registry.capacity = 256
    registry.dimension_count = 0
    registry.dimension_registry_seen = 0
    registry.biome_registry_seen = 0
    registry.block_global_bits = 15
    registry.biome_global_bits = 6
    registry.min_sections = vt_calloc_int(registry.capacity)
    registry.section_counts = vt_calloc_int(registry.capacity)
    return registry


public def vdimension_registry_free(registry: VDimensionRegistry*) -> void:
    if registry == null:
        return
    vt_free((void*)registry.min_sections)
    vt_free((void*)registry.section_counts)
    del registry


public def vdimension_registry_add_dimension(registry: VDimensionRegistry*,
                                             index: int, min_y: int,
                                             height: int) -> int:
    if registry == null or index < 0 or index >= registry.capacity:
        return 0
    if height < 16 or height > 4096 or height % 16 != 0 or min_y % 16 != 0:
        return 0
    vt_iset(registry.min_sections, index, min_y / 16)
    vt_iset(registry.section_counts, index, height / 16)
    if registry.dimension_count <= index:
        registry.dimension_count = index + 1
    return 1


public def vdimension_registry_finish_dimensions(registry: VDimensionRegistry*,
                                                  count: int) -> int:
    if registry == null or count < 0 or count > registry.capacity:
        return 0
    registry.dimension_count = count
    registry.dimension_registry_seen = 1
    return 1


public def vdimension_registry_dimension(registry: VDimensionRegistry*,
                                         index: int) -> int64[]:
    int64[] result = new int64[3]
    if registry == null or index < 0 or index >= registry.dimension_count:
        return result
    result[0] = vt_iget(registry.section_counts, index) > 0
    result[1] = vt_iget(registry.min_sections, index)
    result[2] = vt_iget(registry.section_counts, index)
    return result


public def vdimension_registry_set_biome_count(registry: VDimensionRegistry*,
                                                count: int) -> int:
    if registry == null or count < 1 or count > 1048576:
        return 0
    int bits = 0
    int capacity = 1
    while capacity < count:
        bits += 1
        capacity *= 2
    if bits < 1:
        bits = 1
    if bits > 32:
        return 0
    registry.biome_global_bits = bits
    registry.biome_registry_seen = 1
    return 1


def vworld_find(world: VWorld*, x: int, z: int) -> int:
    int i = 0
    while i < world.count:
        if vt_iget(world.chunk_x, i) == x and vt_iget(world.chunk_z, i) == z:
            return i
        i += 1
    return -1


def vworld_free_column(sections: char*, count: int) -> void:
    if sections == null:
        return
    int i = 0
    while i < count:
        sec_free((VSection*)vt_ptr_get(sections, i))
        i += 1
    vt_free((void*)sections)


public def vworld_new(capacity: int, min_section: int, section_count: int,
                      block_global_bits: int, biome_global_bits: int) -> VWorld*:
    if capacity < 1:
        capacity = 1
    if section_count < 1:
        section_count = 1
    VWorld* world = new VWorld
    world.capacity = capacity
    world.count = 0
    world.min_section = min_section
    world.section_count = section_count
    world.block_global_bits = block_global_bits
    world.biome_global_bits = biome_global_bits
    world.chunk_x = vt_calloc_int(capacity)
    world.chunk_z = vt_calloc_int(capacity)
    world.columns = vt_calloc_ptrs(capacity)
    world.heightmaps = vt_calloc_ptrs(capacity)
    return world


public def vworld_free(world: VWorld*) -> void:
    if world == null:
        return
    int i = 0
    while i < world.count:
        vworld_free_column((char*)vt_ptr_get(world.columns, i), world.section_count)
        hm_free((int*)vt_ptr_get(world.heightmaps, i))
        i += 1
    vt_free((void*)world.chunk_x)
    vt_free((void*)world.chunk_z)
    vt_free((void*)world.columns)
    vt_free((void*)world.heightmaps)
    del world


public def vworld_chunk_count(world: VWorld*) -> int:
    return world.count


public def vworld_set_dimension(world: VWorld*, min_section: int,
                                section_count: int,
                                block_global_bits: int,
                                biome_global_bits: int) -> int:
    if world == null or world.count != 0 or section_count < 1 or section_count > 256:
        return 0
    if block_global_bits < 1 or block_global_bits > 32 or biome_global_bits < 1 or biome_global_bits > 32:
        return 0
    world.min_section = min_section
    world.section_count = section_count
    world.block_global_bits = block_global_bits
    world.biome_global_bits = biome_global_bits
    return 1


# The column slot for (x, z), inserting an empty one when the chunk is new and
# returning -1 once the store is full. A fresh slot has neither sections nor
# heightmaps, so either half of the chunk packet may arrive first.
def vworld_slot(world: VWorld*, x: int, z: int) -> int:
    int index = vworld_find(world, x, z)
    if index >= 0:
        return index
    if world.count >= world.capacity:
        return -1
    index = world.count
    world.count += 1
    vt_iset(world.chunk_x, index, x)
    vt_iset(world.chunk_z, index, z)
    return index


public def vworld_replace_sections(world: VWorld*, x: int, z: int,
                                   sections: char*) -> int:
    if world == null or sections == null:
        return 0
    int index = vworld_slot(world, x, z)
    if index < 0:
        return 0
    vworld_free_column((char*)vt_ptr_get(world.columns, index), world.section_count)
    vt_ptr_set(world.columns, index, (void*)sections)
    return 1


# Takes ownership of `values`, one packed heightmap column of `hm_values()`
# entries, and frees whatever the chunk held before.
public def vworld_set_heightmaps(world: VWorld*, x: int, z: int,
                                 values: int*) -> int:
    if world == null or values == null:
        return 0
    int index = vworld_slot(world, x, z)
    if index < 0:
        return 0
    hm_free((int*)vt_ptr_get(world.heightmaps, index))
    vt_ptr_set(world.heightmaps, index, (void*)values)
    return 1


public def vworld_unload_chunk(world: VWorld*, x: int, z: int) -> int:
    if world == null:
        return 0
    int index = vworld_find(world, x, z)
    if index < 0:
        return 0
    vworld_free_column((char*)vt_ptr_get(world.columns, index), world.section_count)
    hm_free((int*)vt_ptr_get(world.heightmaps, index))
    int i = index + 1
    while i < world.count:
        vt_iset(world.chunk_x, i - 1, vt_iget(world.chunk_x, i))
        vt_iset(world.chunk_z, i - 1, vt_iget(world.chunk_z, i))
        vt_ptr_set(world.columns, i - 1, vt_ptr_get(world.columns, i))
        vt_ptr_set(world.heightmaps, i - 1, vt_ptr_get(world.heightmaps, i))
        i += 1
    world.count -= 1
    vt_ptr_set(world.columns, world.count, null)
    vt_ptr_set(world.heightmaps, world.count, null)
    return 1


public def vworld_section(world: VWorld*, chunk_x: int, chunk_z: int,
                          section_y: int) -> VSection*:
    if world == null:
        return null
    int column_index = vworld_find(world, chunk_x, chunk_z)
    int section_index = section_y - world.min_section
    if column_index < 0 or section_index < 0 or section_index >= world.section_count:
        return null
    char* sections = (char*)vt_ptr_get(world.columns, column_index)
    if sections == null:
        return null
    return (VSection*)vt_ptr_get(sections, section_index)


public def vworld_block_at(world: VWorld*, x: int, y: int, z: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 0
    return sec_block_at(section, local_x, local_y, local_z)


public def vworld_biome_at(world: VWorld*, x: int, y: int, z: int) -> int:
    int chunk_x = x / 16
    int local_x = x % 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int chunk_z = z / 16
    int local_z = z % 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int section_y = y / 16
    int local_y = y % 16
    if local_y < 0:
        section_y -= 1
        local_y += 16
    VSection* section = vworld_section(world, chunk_x, chunk_z, section_y)
    if section == null:
        return 0
    return sec_biome_at(section, local_x / 4, local_y / 4, local_z / 4)


# The stored height for one world block column, or -1 while the chunk is not
# loaded or the server sent no heightmap of that kind. Heights are absolute
# world Y as packed on the wire, so a negative minimum build height does not
# shift them.
public def vworld_height_at(world: VWorld*, kind: int, x: int, z: int) -> int:
    if world == null:
        return -1
    int local_x = x % 16
    int chunk_x = x / 16
    if local_x < 0:
        chunk_x -= 1
        local_x += 16
    int local_z = z % 16
    int chunk_z = z / 16
    if local_z < 0:
        chunk_z -= 1
        local_z += 16
    int column_index = vworld_find(world, chunk_x, chunk_z)
    if column_index < 0:
        return -1
    int* values = (int*)vt_ptr_get(world.heightmaps, column_index)
    if values == null:
        return -1
    return hm_get(values, kind, local_x, local_z)

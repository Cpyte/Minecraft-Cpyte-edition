# Vortex engine - native parallel mesher binding.
#
# engine/mesher.c is the production worker-pool mesher; world/mesher.cpy is the
# readable single-threaded reference. Importing the C file registers its
# non-static functions for Cpyte, and the wrappers below give them engine types
# (VWorld*, VMeshResult-free batch handles) so the protocol layer can submit
# loaded chunks without touching the raw C ABI.
#
# The worker threads read sections through sec_block_at_index /
# sec_light_packed_index / vt_blockdb_render, which is why those accessors exist
# in section.cpy and blockdb.c. A batch keeps its own malloc'd vertex/index
# buffers; the caller reads them back through the accessors and frees the batch
# on the main thread, so the GC never sees a worker's stack.

import "mesher.c"


public def vmesh_native_thread_count() -> int:
    return vt_mesh_thread_count()


public def vmesh_native_vertex_stride() -> int:
    return vt_mesh_vertex_stride()


public def vmesh_native_batch_new() -> char*:
    return vt_mesh_batch_new()


public def vmesh_native_batch_free(batch: char*) -> void:
    vt_mesh_batch_free(batch)


public def vmesh_native_add_chunk(batch: char*, world: VWorld*, chunk_x: int,
                                  chunk_z: int, min_section: int,
                                  section_count: int) -> void:
    vt_mesh_batch_add_chunk(batch, (char*)world, chunk_x, chunk_z, min_section,
                            section_count)


public def vmesh_native_add_section(batch: char*, world: VWorld*, chunk_x: int,
                                    section_y: int, chunk_z: int) -> void:
    vt_mesh_batch_add_section(batch, (char*)world, chunk_x, section_y, chunk_z)


# The centre section plus its six face neighbours, so a block edit re-meshes
# every section whose boundary faces could have changed.
public def vmesh_native_add_neighborhood(batch: char*, world: VWorld*,
                                         chunk_x: int, section_y: int,
                                         chunk_z: int) -> void:
    vt_mesh_batch_add_neighborhood(batch, (char*)world, chunk_x, section_y,
                                   chunk_z)


public def vmesh_native_run(batch: char*) -> int:
    return vt_mesh_batch_run(batch)


public def vmesh_native_sections(batch: char*) -> int:
    return vt_mesh_batch_sections(batch)


public def vmesh_native_quad_count(batch: char*) -> int:
    return vt_mesh_batch_quad_count(batch)


public def vmesh_native_vertex_count(batch: char*, slot: int,
                                     translucent: int) -> int:
    return vt_mesh_batch_vertex_count(batch, slot, translucent)


public def vmesh_native_index_count(batch: char*, slot: int,
                                    translucent: int) -> int:
    return vt_mesh_batch_index_count(batch, slot, translucent)


public def vmesh_native_vertex_component(batch: char*, slot: int,
                                         translucent: int, vertex: int,
                                         component: int) -> int64:
    return vt_mesh_batch_vertex_component(batch, slot, translucent, vertex,
                                          component)


public def vmesh_native_index_at(batch: char*, slot: int, translucent: int,
                                 index: int) -> int64:
    return vt_mesh_batch_index_at(batch, slot, translucent, index)


public def vmesh_native_checksum(batch: char*, slot: int,
                                 translucent: int) -> int64:
    return vt_mesh_batch_checksum(batch, slot, translucent)


# A meshed batch is handed to the renderer through the C ring above rather than
# by calling into it: publishing takes ownership, so the producer must not free
# the batch. A headless run never drains it, and the ring recycles its oldest
# entry once it is full.
public def vmesh_publish(batch: char*) -> void:
    vt_mesh_batch_publish(batch)


public def vmesh_take() -> char*:
    return vt_mesh_batch_take()


public def vmesh_pending() -> int:
    return vt_mesh_batch_pending()
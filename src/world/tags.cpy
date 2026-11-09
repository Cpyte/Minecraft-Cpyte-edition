# Vortex engine - registry tag tables.
#
# `update_tags` replaces the whole map: registry id -> tag name -> numeric id
# list. Names live in fixed-stride arenas and the id lists in one pooled array,
# so a replacement is a rewind rather than a reallocation.

public def vtags_registry_max() -> int:
    return 32


public def vtags_tag_max() -> int:
    return 8192


public def vtags_id_stride() -> int:
    return 128


public def vtags_pool_max() -> int:
    return 1048576


public def vtags_absent() -> int:
    return -1


struct VTags:
    char* registry_names
    int registry_rows
    char* tag_names
    int* tag_registry
    int* tag_start
    int* tag_count
    int tag_rows
    int* pool
    int pool_used


public def vtags_new() -> VTags*:
    VTags* table = new VTags
    table.registry_names = vt_calloc_char(vtags_registry_max() * vtags_id_stride())
    table.registry_rows = 0
    table.tag_names = vt_calloc_char(vtags_tag_max() * vtags_id_stride())
    table.tag_registry = vt_calloc_int(vtags_tag_max())
    table.tag_start = vt_calloc_int(vtags_tag_max())
    table.tag_count = vt_calloc_int(vtags_tag_max())
    table.tag_rows = 0
    table.pool = vt_calloc_int(vtags_pool_max())
    table.pool_used = 0
    return table


public def vtags_free(table: VTags*) -> void:
    if table == null:
        return
    vt_free(table.registry_names)
    vt_free(table.tag_names)
    vt_free(table.tag_registry)
    vt_free(table.tag_start)
    vt_free(table.tag_count)
    vt_free(table.pool)
    del table


def vtags_matches(arena: char*, base: int, body: int64[], offset: int64,
                  length: int64) -> int:
    int64 limit = vtags_id_stride() - 1
    if length > limit or length < 1:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


def vtags_store(arena: char*, base: int, body: int64[], offset: int64,
                length: int64) -> void:
    int64 limit = vtags_id_stride() - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


public def vtags_reset(table: VTags*) -> int:
    if table == null:
        return 1
    table.registry_rows = 0
    table.tag_rows = 0
    table.pool_used = 0
    return 0


public def vtags_registry_row(table: VTags*, body: int64[], offset: int64,
                              length: int64) -> int:
    if table == null:
        return vtags_absent()
    int row = 0
    while row < table.registry_rows:
        if vtags_matches(table.registry_names, row * vtags_id_stride(),
                         body, offset, length) == 1:
            return row
        row = row + 1
    if row >= vtags_registry_max():
        return vtags_absent()
    vtags_store(table.registry_names, row * vtags_id_stride(),
                body, offset, length)
    table.registry_rows = row + 1
    return row


public def vtags_add(table: VTags*, registry: int, body: int64[],
                     offset: int64, length: int64, ids: int64[],
                     count: int) -> int:
    if table == null or registry < 0 or registry >= table.registry_rows:
        return 1
    if count < 0 or table.tag_rows >= vtags_tag_max():
        return 1
    if table.pool_used + count > vtags_pool_max():
        return 1
    int row = table.tag_rows
    vtags_store(table.tag_names, row * vtags_id_stride(), body, offset, length)
    vt_iset(table.tag_registry, row, registry)
    vt_iset(table.tag_start, row, table.pool_used)
    vt_iset(table.tag_count, row, count)
    int index = 0
    while index < count:
        vt_iset(table.pool, table.pool_used + index, (int)ids[index])
        index = index + 1
    table.pool_used = table.pool_used + count
    table.tag_rows = row + 1
    return 0


public def vtags_registry_rows(table: VTags*) -> int:
    if table == null:
        return 0
    return table.registry_rows


public def vtags_rows(table: VTags*) -> int:
    if table == null:
        return 0
    return table.tag_rows


public def vtags_entry_count(table: VTags*, row: int) -> int:
    if table == null or row < 0 or row >= table.tag_rows:
        return 0
    return vt_iget(table.tag_count, row)


public def vtags_entry_id(table: VTags*, row: int, index: int) -> int:
    if table == null or row < 0 or row >= table.tag_rows:
        return vtags_absent()
    if index < 0 or index >= vt_iget(table.tag_count, row):
        return vtags_absent()
    return vt_iget(table.pool, vt_iget(table.tag_start, row) + index)


# Tag membership by name, the query the block and item code actually needs.
public def vtags_contains(table: VTags*, registry: int, body: int64[],
                          offset: int64, length: int64, id: int) -> bool:
    if table == null:
        return false
    int row = 0
    while row < table.tag_rows:
        if vt_iget(table.tag_registry, row) == registry:
            if vtags_matches(table.tag_names, row * vtags_id_stride(),
                             body, offset, length) == 1:
                int count = vt_iget(table.tag_count, row)
                int index = 0
                while index < count:
                    if vtags_entry_id(table, row, index) == id:
                        return true
                    index = index + 1
        row = row + 1
    return false
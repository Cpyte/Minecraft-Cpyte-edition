# Vortex engine - advancement tree and progress.
#
# The display tree is walked for validation but only the identity, parent, frame
# and coordinates are retained: a headless client needs the graph and the
# criteria completion, not the icons. Progress rows are (advancement, criterion,
# achieved-at) with -1 for an unachieved criterion.

public def vadv_max() -> int:
    return 2048


public def vadv_id_stride() -> int:
    return 128


public def vadv_criterion_max() -> int:
    return 16384


public def vadv_absent() -> int:
    return -1


public def vadv_flag_background() -> int:
    return 1


public def vadv_flag_toast() -> int:
    return 2


public def vadv_flag_hidden() -> int:
    return 4


struct VAdvancements:
    char* keys
    char* parents
    int* frames
    int* flags
    int* icon
    uint64* x
    uint64* y
    int rows
    int* crit_advancement
    char* crit_names
    uint64* crit_progress
    int crit_rows
    char* selected_tab
    bool visible


public def vadv_new() -> VAdvancements*:
    VAdvancements* table = new VAdvancements
    table.keys = vt_calloc_char(vadv_max() * vadv_id_stride())
    table.parents = vt_calloc_char(vadv_max() * vadv_id_stride())
    table.frames = vt_calloc_int(vadv_max())
    table.flags = vt_calloc_int(vadv_max())
    table.icon = vt_calloc_int(vadv_max())
    table.x = vt_calloc_u64(vadv_max())
    table.y = vt_calloc_u64(vadv_max())
    table.rows = 0
    table.crit_advancement = vt_calloc_int(vadv_criterion_max())
    table.crit_names = vt_calloc_char(vadv_criterion_max() * vadv_id_stride())
    table.crit_progress = vt_calloc_u64(vadv_criterion_max())
    table.crit_rows = 0
    table.selected_tab = vt_calloc_char(vadv_id_stride())
    table.visible = true
    return table


public def vadv_free(table: VAdvancements*) -> void:
    if table == null:
        return
    vt_free(table.keys)
    vt_free(table.parents)
    vt_free(table.frames)
    vt_free(table.flags)
    vt_free(table.icon)
    vt_free(table.x)
    vt_free(table.y)
    vt_free(table.crit_advancement)
    vt_free(table.crit_names)
    vt_free(table.crit_progress)
    vt_free(table.selected_tab)
    del table


def vadv_matches(arena: char*, base: int, body: int64[], offset: int64,
                 length: int64) -> int:
    int64 limit = vadv_id_stride() - 1
    if length > limit or length < 0:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


def vadv_store(arena: char*, base: int, body: int64[], offset: int64,
               length: int64) -> void:
    int64 limit = vadv_id_stride() - 1
    if length > limit:
        length = limit
    if length < 0:
        length = 0
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


public def vadv_reset(table: VAdvancements*) -> int:
    if table == null:
        return 1
    table.rows = 0
    table.crit_rows = 0
    vt_put(table.selected_tab, 0, 0)
    return 0


public def vadv_find(table: VAdvancements*, body: int64[], offset: int64,
                     length: int64) -> int:
    int row = 0
    while row < table.rows:
        if vadv_matches(table.keys, row * vadv_id_stride(),
                        body, offset, length) == 1:
            return row
        row = row + 1
    return vadv_absent()


# `parent_length` < 0 records a root advancement.
# Returns the row, or vadv_absent() when the table cannot hold the advancement.
# A row index is never a failure sentinel, so callers must compare against
# vadv_absent() rather than treating any non-zero result as an error.
public def vadv_add(table: VAdvancements*, body: int64[], offset: int64,
                    length: int64, parent: int64[], parent_offset: int64,
                    parent_length: int64, frame: int, flags: int, icon: int,
                    x: double, y: double) -> int:
    if table == null or frame < 0 or frame > 2:
        return vadv_absent()
    int row = vadv_find(table, body, offset, length)
    if row == vadv_absent():
        if table.rows >= vadv_max():
            return vadv_absent()
        row = table.rows
        table.rows = row + 1
        vadv_store(table.keys, row * vadv_id_stride(), body, offset, length)
    vadv_store(table.parents, row * vadv_id_stride(),
               parent, parent_offset, parent_length)
    vt_iset(table.frames, row, frame)
    vt_iset(table.flags, row, flags)
    vt_iset(table.icon, row, icon)
    vt_uset(table.x, row, vt_double_to_bits(x))
    vt_uset(table.y, row, vt_double_to_bits(y))
    return row


public def vadv_remove(table: VAdvancements*, body: int64[], offset: int64,
                       length: int64) -> int:
    if table == null:
        return 1
    int row = vadv_find(table, body, offset, length)
    if row == vadv_absent():
        return 0
    int last = table.rows - 1
    while row < last:
        int src = (row + 1) * vadv_id_stride()
        int dst = row * vadv_id_stride()
        int index = 0
        while index < vadv_id_stride():
            vt_put(table.keys, dst + index, vt_at(table.keys, src + index))
            vt_put(table.parents, dst + index, vt_at(table.parents, src + index))
            index = index + 1
        vt_iset(table.frames, row, vt_iget(table.frames, row + 1))
        vt_iset(table.flags, row, vt_iget(table.flags, row + 1))
        vt_iset(table.icon, row, vt_iget(table.icon, row + 1))
        vt_uset(table.x, row, vt_uget(table.x, row + 1))
        vt_uset(table.y, row, vt_uget(table.y, row + 1))
        row = row + 1
    table.rows = last
    int kept = 0
    int scan = 0
    while scan < table.crit_rows:
        int owner = vt_iget(table.crit_advancement, scan)
        if owner != last:
            if owner > last:
                owner = owner - 1
            if kept != scan:
                vt_iset(table.crit_advancement, kept, owner)
                int index = 0
                while index < vadv_id_stride():
                    vt_put(table.crit_names, kept * vadv_id_stride() + index,
                           vt_at(table.crit_names, scan * vadv_id_stride() + index))
                    index = index + 1
                vt_uset(table.crit_progress, kept, vt_uget(table.crit_progress, scan))
            kept = kept + 1
        scan = scan + 1
    table.crit_rows = kept
    return 0


public def vadv_rows(table: VAdvancements*) -> int:
    if table == null:
        return 0
    return table.rows


public def vadv_frame(table: VAdvancements*, row: int) -> int:
    if table == null or row < 0 or row >= table.rows:
        return vadv_absent()
    return vt_iget(table.frames, row)


public def vadv_flags(table: VAdvancements*, row: int) -> int:
    if table == null or row < 0 or row >= table.rows:
        return 0
    return vt_iget(table.flags, row)


public def vadv_icon(table: VAdvancements*, row: int) -> int:
    if table == null or row < 0 or row >= table.rows:
        return vadv_absent()
    return vt_iget(table.icon, row)


public def vadv_x(table: VAdvancements*, row: int) -> double:
    if table == null or row < 0 or row >= table.rows:
        return 0.0
    return vt_bits_to_double(vt_uget(table.x, row))


public def vadv_y(table: VAdvancements*, row: int) -> double:
    if table == null or row < 0 or row >= table.rows:
        return 0.0
    return vt_bits_to_double(vt_uget(table.y, row))


public def vadv_has_parent(table: VAdvancements*, row: int) -> bool:
    if table == null or row < 0 or row >= table.rows:
        return false
    return vt_at(table.parents, row * vadv_id_stride()) != 0


# `progress` is the achieved-at millisecond stamp, or -1 while unachieved.
public def vadv_set_progress(table: VAdvancements*, row: int, body: int64[],
                             offset: int64, length: int64,
                             progress: int64) -> int:
    if table == null or row < 0 or row >= table.rows:
        return 1
    int scan = 0
    while scan < table.crit_rows:
        if vt_iget(table.crit_advancement, scan) == row:
            if vadv_matches(table.crit_names, scan * vadv_id_stride(),
                            body, offset, length) == 1:
                vt_uset(table.crit_progress, scan, (uint64)progress)
                return 0
        scan = scan + 1
    if table.crit_rows >= vadv_criterion_max():
        return 1
    vt_iset(table.crit_advancement, table.crit_rows, row)
    vadv_store(table.crit_names, table.crit_rows * vadv_id_stride(),
               body, offset, length)
    vt_uset(table.crit_progress, table.crit_rows, (uint64)progress)
    table.crit_rows = table.crit_rows + 1
    return 0


public def vadv_criterion_rows(table: VAdvancements*) -> int:
    if table == null:
        return 0
    return table.crit_rows


public def vadv_criterion_progress(table: VAdvancements*, row: int) -> int64:
    if table == null or row < 0 or row >= table.crit_rows:
        return (int64)-1
    return (int64)vt_uget(table.crit_progress, row)


public def vadv_completed(table: VAdvancements*, row: int) -> bool:
    if table == null or row < 0 or row >= table.rows:
        return false
    int seen = 0
    int done = 0
    int scan = 0
    while scan < table.crit_rows:
        if vt_iget(table.crit_advancement, scan) == row:
            seen = seen + 1
            if (int64)vt_uget(table.crit_progress, scan) >= (int64)0:
                done = done + 1
        scan = scan + 1
    return seen > 0 and seen == done


public def vadv_select_tab(table: VAdvancements*, body: int64[], offset: int64,
                           length: int64) -> int:
    if table == null:
        return 1
    vadv_store(table.selected_tab, 0, body, offset, length)
    return 0


public def vadv_tab_selected(table: VAdvancements*, body: int64[],
                             offset: int64, length: int64) -> bool:
    if table == null:
        return false
    return vadv_matches(table.selected_tab, 0, body, offset, length) == 1


public def vadv_set_visible(table: VAdvancements*, visible: bool) -> int:
    if table == null:
        return 1
    table.visible = visible
    return 0
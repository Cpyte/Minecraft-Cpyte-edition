# Vortex engine - recipe property sets, the stonecutter list and the recipe book.
#
# 26.3 no longer sends whole recipes: `update_recipes` pushes named item sets
# plus the stonecutter's input/display pairs, and the recipe book streams display
# entries separately. Only the ids and categories are kept here; the display
# trees are walked for validation by src/proto/display.cpy and not retained.

public def vrecipe_set_max() -> int:
    return 64


public def vrecipe_entry_max() -> int:
    return 8192


public def vrecipe_id_stride() -> int:
    return 128


public def vrecipe_pool_max() -> int:
    return 262144


public def vrecipe_book_types() -> int:
    return 4


public def vrecipe_absent() -> int:
    return -1


struct VRecipes:
    char* set_names
    int* set_start
    int* set_count
    int set_rows
    int* pool
    int pool_used
    int* stone_input
    int* stone_display
    int stone_rows
    int* book_id
    int* book_category
    int* book_group
    int* book_flags
    int book_rows
    int* book_open
    int* book_filter


public def vrecipe_new() -> VRecipes*:
    VRecipes* book = new VRecipes
    book.set_names = vt_calloc_char(vrecipe_set_max() * vrecipe_id_stride())
    book.set_start = vt_calloc_int(vrecipe_set_max())
    book.set_count = vt_calloc_int(vrecipe_set_max())
    book.set_rows = 0
    book.pool = vt_calloc_int(vrecipe_pool_max())
    book.pool_used = 0
    book.stone_input = vt_calloc_int(vrecipe_entry_max())
    book.stone_display = vt_calloc_int(vrecipe_entry_max())
    book.stone_rows = 0
    book.book_id = vt_calloc_int(vrecipe_entry_max())
    book.book_category = vt_calloc_int(vrecipe_entry_max())
    book.book_group = vt_calloc_int(vrecipe_entry_max())
    book.book_flags = vt_calloc_int(vrecipe_entry_max())
    book.book_rows = 0
    book.book_open = vt_calloc_int(vrecipe_book_types())
    book.book_filter = vt_calloc_int(vrecipe_book_types())
    return book


public def vrecipe_free(book: VRecipes*) -> void:
    if book == null:
        return
    vt_free(book.set_names)
    vt_free(book.set_start)
    vt_free(book.set_count)
    vt_free(book.pool)
    vt_free(book.stone_input)
    vt_free(book.stone_display)
    vt_free(book.book_id)
    vt_free(book.book_category)
    vt_free(book.book_group)
    vt_free(book.book_flags)
    vt_free(book.book_open)
    vt_free(book.book_filter)
    del book


def vrecipe_name_at(arena: char*, base: int, body: int64[], offset: int64,
                    length: int64) -> int:
    int64 limit = vrecipe_id_stride() - 1
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


def vrecipe_write_name(arena: char*, base: int, body: int64[], offset: int64,
                       length: int64) -> void:
    int64 limit = vrecipe_id_stride() - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


# `update_recipes` replaces every set, so the pool is rewound rather than grown.
public def vrecipe_reset_sets(book: VRecipes*) -> int:
    if book == null:
        return 1
    book.set_rows = 0
    book.pool_used = 0
    book.stone_rows = 0
    return 0


public def vrecipe_add_set(book: VRecipes*, body: int64[], offset: int64,
                           length: int64, items: int64[], count: int) -> int:
    if book == null or count < 0 or count > vrecipe_entry_max():
        return 1
    int row = 0
    while row < book.set_rows:
        if vrecipe_name_at(book.set_names, row * vrecipe_id_stride(),
                           body, offset, length) == 1:
            break
        row = row + 1
    if row >= vrecipe_set_max():
        return 1
    if book.pool_used + count > vrecipe_pool_max():
        return 1
    if row == book.set_rows:
        vrecipe_write_name(book.set_names, row * vrecipe_id_stride(),
                           body, offset, length)
        book.set_rows = row + 1
    int index = 0
    while index < count:
        vt_iset(book.pool, book.pool_used + index, (int)items[index])
        index = index + 1
    vt_iset(book.set_start, row, book.pool_used)
    vt_iset(book.set_count, row, count)
    book.pool_used = book.pool_used + count
    return 0


public def vrecipe_set_rows(book: VRecipes*) -> int:
    if book == null:
        return 0
    return book.set_rows


public def vrecipe_set_item_count(book: VRecipes*, row: int) -> int:
    if book == null or row < 0 or row >= book.set_rows:
        return 0
    return vt_iget(book.set_count, row)


public def vrecipe_set_item(book: VRecipes*, row: int, index: int) -> int:
    if book == null or row < 0 or row >= book.set_rows:
        return vrecipe_absent()
    if index < 0 or index >= vt_iget(book.set_count, row):
        return vrecipe_absent()
    return vt_iget(book.pool, vt_iget(book.set_start, row) + index)


public def vrecipe_set_contains(book: VRecipes*, row: int, item: int) -> bool:
    int count = vrecipe_set_item_count(book, row)
    int index = 0
    while index < count:
        if vrecipe_set_item(book, row, index) == item:
            return true
        index = index + 1
    return false


public def vrecipe_add_stonecutter(book: VRecipes*, ingredient: int,
                                   display: int) -> int:
    if book == null or book.stone_rows >= vrecipe_entry_max():
        return 1
    vt_iset(book.stone_input, book.stone_rows, ingredient)
    vt_iset(book.stone_display, book.stone_rows, display)
    book.stone_rows = book.stone_rows + 1
    return 0


public def vrecipe_stonecutter_rows(book: VRecipes*) -> int:
    if book == null:
        return 0
    return book.stone_rows


def vrecipe_book_find(book: VRecipes*, id: int) -> int:
    int row = 0
    while row < book.book_rows:
        if vt_iget(book.book_id, row) == id:
            return row
        row = row + 1
    return vrecipe_absent()


public def vrecipe_book_clear(book: VRecipes*) -> void:
    if book == null:
        return
    book.book_rows = 0


public def vrecipe_book_add(book: VRecipes*, id: int, category: int, group: int,
                            flags: int) -> int:
    if book == null or id < 0:
        return 1
    int row = vrecipe_book_find(book, id)
    if row == vrecipe_absent():
        if book.book_rows >= vrecipe_entry_max():
            return 1
        row = book.book_rows
        book.book_rows = row + 1
    vt_iset(book.book_id, row, id)
    vt_iset(book.book_category, row, category)
    vt_iset(book.book_group, row, group)
    vt_iset(book.book_flags, row, flags)
    return 0


public def vrecipe_book_remove(book: VRecipes*, id: int) -> int:
    if book == null:
        return 1
    int row = vrecipe_book_find(book, id)
    if row == vrecipe_absent():
        return 0
    int last = book.book_rows - 1
    while row < last:
        vt_iset(book.book_id, row, vt_iget(book.book_id, row + 1))
        vt_iset(book.book_category, row, vt_iget(book.book_category, row + 1))
        vt_iset(book.book_group, row, vt_iget(book.book_group, row + 1))
        vt_iset(book.book_flags, row, vt_iget(book.book_flags, row + 1))
        row = row + 1
    book.book_rows = last
    return 0


public def vrecipe_book_rows(book: VRecipes*) -> int:
    if book == null:
        return 0
    return book.book_rows


public def vrecipe_book_entry_id(book: VRecipes*, row: int) -> int:
    if book == null or row < 0 or row >= book.book_rows:
        return vrecipe_absent()
    return vt_iget(book.book_id, row)


public def vrecipe_book_entry_category(book: VRecipes*, row: int) -> int:
    if book == null or row < 0 or row >= book.book_rows:
        return vrecipe_absent()
    return vt_iget(book.book_category, row)


public def vrecipe_book_entry_flags(book: VRecipes*, row: int) -> int:
    if book == null or row < 0 or row >= book.book_rows:
        return 0
    return vt_iget(book.book_flags, row)


public def vrecipe_book_known(book: VRecipes*, id: int) -> bool:
    if book == null:
        return false
    return vrecipe_book_find(book, id) != vrecipe_absent()


public def vrecipe_set_settings(book: VRecipes*, kind: int, open: bool,
                                filtering: bool) -> int:
    if book == null or kind < 0 or kind >= vrecipe_book_types():
        return 1
    int value = 0
    if open:
        value = 1
    vt_iset(book.book_open, kind, value)
    value = 0
    if filtering:
        value = 1
    vt_iset(book.book_filter, kind, value)
    return 0


public def vrecipe_book_is_open(book: VRecipes*, kind: int) -> bool:
    if book == null or kind < 0 or kind >= vrecipe_book_types():
        return false
    return vt_iget(book.book_open, kind) != 0


public def vrecipe_book_is_filtering(book: VRecipes*, kind: int) -> bool:
    if book == null or kind < 0 or kind >= vrecipe_book_types():
        return false
    return vt_iget(book.book_filter, kind) != 0
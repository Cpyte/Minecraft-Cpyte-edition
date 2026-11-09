# Vortex engine - server debug subscriptions.
#
# The debug/* Play packets carry a registry id plus a value whose shape depends
# on that id. Values are retained as a numeric projection: every scalar in wire
# order, every list count before its elements, and every string as its byte
# length. Diagnostic text is not kept, so a debug overlay can draw positions,
# counts and flags without the client owning a second string arena per value.
#
# Updates are keyed by (kind, subscription, key) and replaced in place; an
# absent optional clears the row's value but keeps the key, matching the
# server's "this position no longer has a value" semantics. Events have no key
# and live in a bounded ring.

public def vdebug_max() -> int:
    return 2048


public def vdebug_value_max() -> int:
    return 128


public def vdebug_event_max() -> int:
    return 256


public def vdebug_absent() -> int:
    return -1


public def vdebug_kind_block() -> int:
    return 0


public def vdebug_kind_chunk() -> int:
    return 1


public def vdebug_kind_entity() -> int:
    return 2


struct VDebug:
    int rows
    int* kind
    int* subscription
    uint64* key_x
    uint64* key_y
    uint64* key_z
    int* present
    int* value_length
    uint64* values
    int event_rows
    int event_head
    int* event_subscription
    int* event_length
    uint64* event_values


# Wire readers append into an accumulator rather than returning a count, so a
# deeply nested value does not have to thread an out parameter through every
# call. `overflow` records that the projection was clipped.
struct VDbgAcc:
    int64[] values
    int used
    int overflow


public def vdbg_acc_new() -> VDbgAcc*:
    VDbgAcc* acc = new VDbgAcc
    acc.values = new int64[vdebug_value_max()]
    acc.used = 0
    acc.overflow = 0
    return acc


public def vdbg_acc_free(acc: VDbgAcc*) -> void:
    if acc == null:
        return
    del acc.values
    del acc


public def vdbg_acc_reset(acc: VDbgAcc*) -> void:
    if acc == null:
        return
    acc.used = 0
    acc.overflow = 0


public def vdbg_acc_push(acc: VDbgAcc*, value: int64) -> void:
    if acc == null:
        return
    if acc.used >= vdebug_value_max():
        acc.overflow = 1
        return
    acc.values[acc.used] = value
    acc.used = acc.used + 1


public def vdbg_acc_used(acc: VDbgAcc*) -> int:
    if acc == null:
        return 0
    return acc.used


public def vdbg_acc_overflow(acc: VDbgAcc*) -> int:
    if acc == null:
        return 0
    return acc.overflow


public def vdbg_acc_value(acc: VDbgAcc*, index: int) -> int64:
    if acc == null or index < 0 or index >= acc.used:
        return (int64)0
    return acc.values[index]


public def vdebug_new() -> VDebug*:
    VDebug* store = new VDebug
    store.rows = 0
    store.kind = vt_calloc_int(vdebug_max())
    store.subscription = vt_calloc_int(vdebug_max())
    store.key_x = vt_calloc_u64(vdebug_max())
    store.key_y = vt_calloc_u64(vdebug_max())
    store.key_z = vt_calloc_u64(vdebug_max())
    store.present = vt_calloc_int(vdebug_max())
    store.value_length = vt_calloc_int(vdebug_max())
    store.values = vt_calloc_u64(vdebug_max() * vdebug_value_max())
    store.event_rows = 0
    store.event_head = 0
    store.event_subscription = vt_calloc_int(vdebug_event_max())
    store.event_length = vt_calloc_int(vdebug_event_max())
    store.event_values = vt_calloc_u64(vdebug_event_max() * vdebug_value_max())
    return store


public def vdebug_free(store: VDebug*) -> void:
    if store == null:
        return
    vt_free(store.kind)
    vt_free(store.subscription)
    vt_free(store.key_x)
    vt_free(store.key_y)
    vt_free(store.key_z)
    vt_free(store.present)
    vt_free(store.value_length)
    vt_free(store.values)
    vt_free(store.event_subscription)
    vt_free(store.event_length)
    vt_free(store.event_values)
    del store


public def vdebug_reset(store: VDebug*) -> int:
    if store == null:
        return 1
    store.rows = 0
    store.event_rows = 0
    store.event_head = 0
    return 0


public def vdebug_find(store: VDebug*, kind: int, subscription: int,
                       x: int64, y: int64, z: int64) -> int:
    if store == null:
        return vdebug_absent()
    int row = 0
    while row < store.rows:
        if vt_iget(store.kind, row) == kind:
            if vt_iget(store.subscription, row) == subscription:
                if (int64)vt_uget(store.key_x, row) == x:
                    if (int64)vt_uget(store.key_y, row) == y:
                        if (int64)vt_uget(store.key_z, row) == z:
                            return row
        row = row + 1
    return vdebug_absent()


def vdebug_copy_projection(dst: uint64*, base: int, acc: VDbgAcc*) -> int:
    int count = acc.used
    if count > vdebug_value_max():
        count = vdebug_value_max()
    int index = 0
    while index < count:
        vt_uset(dst, base + index, (uint64)acc.values[index])
        index = index + 1
    return count


# Returns the row, or vdebug_absent() when the store is full. `present` is 0 for
# an absent optional value, which clears the projection but keeps the key.
public def vdebug_set(store: VDebug*, kind: int, subscription: int,
                      x: int64, y: int64, z: int64, present: int,
                      acc: VDbgAcc*) -> int:
    if store == null or acc == null or kind < 0 or kind > 2:
        return vdebug_absent()
    if subscription < 0:
        return vdebug_absent()
    int row = vdebug_find(store, kind, subscription, x, y, z)
    if row == vdebug_absent():
        if store.rows >= vdebug_max():
            return vdebug_absent()
        row = store.rows
        store.rows = row + 1
    vt_iset(store.kind, row, kind)
    vt_iset(store.subscription, row, subscription)
    vt_uset(store.key_x, row, (uint64)x)
    vt_uset(store.key_y, row, (uint64)y)
    vt_uset(store.key_z, row, (uint64)z)
    vt_iset(store.present, row, present)
    int base = row * vdebug_value_max()
    if present == 0:
        vt_iset(store.value_length, row, 0)
        return row
    vt_iset(store.value_length, row, vdebug_copy_projection(store.values, base, acc))
    return row


public def vdebug_rows(store: VDebug*) -> int:
    if store == null:
        return 0
    return store.rows


public def vdebug_row_kind(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.rows:
        return vdebug_absent()
    return vt_iget(store.kind, row)


public def vdebug_row_subscription(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.rows:
        return vdebug_absent()
    return vt_iget(store.subscription, row)


public def vdebug_row_key_x(store: VDebug*, row: int) -> int64:
    if store == null or row < 0 or row >= store.rows:
        return (int64)0
    return (int64)vt_uget(store.key_x, row)


public def vdebug_row_key_y(store: VDebug*, row: int) -> int64:
    if store == null or row < 0 or row >= store.rows:
        return (int64)0
    return (int64)vt_uget(store.key_y, row)


public def vdebug_row_key_z(store: VDebug*, row: int) -> int64:
    if store == null or row < 0 or row >= store.rows:
        return (int64)0
    return (int64)vt_uget(store.key_z, row)


public def vdebug_row_present(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.rows:
        return 0
    return vt_iget(store.present, row)


public def vdebug_row_length(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.rows:
        return 0
    return vt_iget(store.value_length, row)


public def vdebug_row_value(store: VDebug*, row: int, index: int) -> int64:
    if store == null or row < 0 or row >= store.rows:
        return (int64)0
    if index < 0 or index >= vt_iget(store.value_length, row):
        return (int64)0
    return (int64)vt_uget(store.values, row * vdebug_value_max() + index)


# Events are a ring: the oldest is overwritten once the ring is full, so a
# chatty subscription cannot grow the store without bound.
public def vdebug_push_event(store: VDebug*, subscription: int,
                             acc: VDbgAcc*) -> int:
    if store == null or acc == null or subscription < 0:
        return vdebug_absent()
    int row = store.event_head
    vt_iset(store.event_subscription, row, subscription)
    vt_iset(store.event_length, row,
            vdebug_copy_projection(store.event_values, row * vdebug_value_max(), acc))
    store.event_head = row + 1
    if store.event_head >= vdebug_event_max():
        store.event_head = 0
    if store.event_rows < vdebug_event_max():
        store.event_rows = store.event_rows + 1
    return row


public def vdebug_event_rows(store: VDebug*) -> int:
    if store == null:
        return 0
    return store.event_rows


def vdebug_event_slot(store: VDebug*, row: int) -> int:
    int start = store.event_head - store.event_rows
    if start < 0:
        start = start + vdebug_event_max()
    int slot = start + row
    if slot >= vdebug_event_max():
        slot = slot - vdebug_event_max()
    return slot


public def vdebug_event_subscription(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.event_rows:
        return vdebug_absent()
    return vt_iget(store.event_subscription, vdebug_event_slot(store, row))


public def vdebug_event_length(store: VDebug*, row: int) -> int:
    if store == null or row < 0 or row >= store.event_rows:
        return 0
    return vt_iget(store.event_length, vdebug_event_slot(store, row))


public def vdebug_event_value(store: VDebug*, row: int, index: int) -> int64:
    if store == null or row < 0 or row >= store.event_rows:
        return (int64)0
    int slot = vdebug_event_slot(store, row)
    if index < 0 or index >= vt_iget(store.event_length, slot):
        return (int64)0
    return (int64)vt_uget(store.event_values, slot * vdebug_value_max() + index)
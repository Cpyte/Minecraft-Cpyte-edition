# Vortex engine - SlotDisplay and RecipeDisplay readers (protocol 777).
#
# Both are registry-dispatched: a varint registry id selects the payload. The
# ids below are the bootstrap registration order in SlotDisplays / RecipeDisplays,
# which is what the wire carries. SlotDisplay nests, so sd_read is the single
# recursive function; RecipeDisplay only ever calls into it.


public def sd_type_count() -> int:
    return 11


public def rd_type_count() -> int:
    return 5


public def sd_depth_max() -> int:
    return 16


public def sd_list_max() -> int64:
    return 4096


def sd_fail() -> int64:
    return (int64)-1


def sd_varint(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64[] field = decode_varint(data, cursor)
    if field[0] != 1:
        return sd_fail()
    scratch[0] = field[1]
    return field[2]


# One SlotDisplay. Returns the offset after it, or -1 when the bytes do not
# describe a display this client knows.
def sd_read(data: int64[], cursor: int64, depth: int, scratch: int64[]) -> int64:
    if depth > sd_depth_max():
        return sd_fail()
    int64 at = sd_varint(data, cursor, scratch)
    if at < 0:
        return sd_fail()
    int64 kind = scratch[0]
    if kind == (int64)0 or kind == (int64)1:
        return at
    if kind == (int64)2:
        return sd_read(data, at, depth + 1, scratch)
    if kind == (int64)3:
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        # DataComponentType travels as a plain registry id.
        return sd_varint(data, at, scratch)
    if kind == (int64)4:
        return sd_varint(data, at, scratch)
    if kind == (int64)5:
        int64[] stack = new int64[3]
        return sl_read_template(data, at, stack)
    if kind == (int64)6:
        return sl_read_holder_set(data, at)
    if kind == (int64)7 or kind == (int64)9:
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        return sd_read(data, at, depth + 1, scratch)
    if kind == (int64)8:
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        return sl_read_holder(data, at, 226)
    if kind == (int64)10:
        at = sd_varint(data, at, scratch)
        if at < 0:
            return sd_fail()
        int64 count = scratch[0]
        if count < (int64)0 or count > sd_list_max():
            return sd_fail()
        int64 index = 0
        while index < count:
            at = sd_read(data, at, depth + 1, scratch)
            if at < 0:
                return sd_fail()
            index = index + 1
        return at
    return sd_fail()


public def sd_skip(data: int64[], cursor: int64) -> int64:
    int64[] scratch = new int64[1]
    return sd_read(data, cursor, 0, scratch)


def sd_list(data: int64[], cursor: int64, depth: int,
            scratch: int64[]) -> int64:
    int64 at = sd_varint(data, cursor, scratch)
    if at < 0:
        return sd_fail()
    int64 count = scratch[0]
    if count < (int64)0 or count > sd_list_max():
        return sd_fail()
    int64 index = 0
    while index < count:
        at = sd_read(data, at, depth + 1, scratch)
        if at < 0:
            return sd_fail()
        index = index + 1
    return at


# One RecipeDisplay. `out` receives {type id, result item hint} where the hint
# is only filled for the item-stack result form; callers that need the real
# result re-read the recorded span.
public def rd_read(data: int64[], cursor: int64, out: int64[]) -> int64:
    out[0] = -1
    int64[] scratch = new int64[1]
    int64 at = sd_varint(data, cursor, scratch)
    if at < 0:
        return sd_fail()
    int64 kind = scratch[0]
    if kind < (int64)0 or kind >= (int64)rd_type_count():
        return sd_fail()
    out[0] = kind
    if kind == (int64)0:
        at = sd_list(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        at = sd_read(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        return sd_read(data, at, 0, scratch)
    if kind == (int64)1:
        at = sd_varint(data, at, scratch)
        if at < 0:
            return sd_fail()
        int64 width = scratch[0]
        at = sd_varint(data, at, scratch)
        if at < 0:
            return sd_fail()
        int64 height = scratch[0]
        if width < (int64)1 or (width > (int64)3 or height < (int64)1):
            return sd_fail()
        if height > (int64)3:
            return sd_fail()
        at = sd_list(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        at = sd_read(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        return sd_read(data, at, 0, scratch)
    if kind == (int64)2:
        int step = 0
        while step < 4:
            at = sd_read(data, at, 0, scratch)
            if at < 0:
                return sd_fail()
            step = step + 1
        at = sd_varint(data, at, scratch)
        if at < 0:
            return sd_fail()
        return pl_take(data, at, 4)
    if kind == (int64)3:
        int step = 0
        while step < 3:
            at = sd_read(data, at, 0, scratch)
            if at < 0:
                return sd_fail()
            step = step + 1
        return at
    int step = 0
    while step < 5:
        at = sd_read(data, at, 0, scratch)
        if at < 0:
            return sd_fail()
        step = step + 1
    return at
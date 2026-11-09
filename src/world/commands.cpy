# Vortex engine - the Brigadier command tree the server sends in `commands`.
#
# The tree arrives as one packet describing every node the server knows about,
# so the client has to walk it in a single pass and cannot ask for the rest
# later. It is stored flat: node metadata in parallel arrays, the child edges of
# every node appended to one shared list, and the strings a node can carry in
# fixed stride arenas. Nothing is allocated per node, which keeps a re-send on
# the configuration path cheap and keeps completion lookups in one array walk.
#
# Field readers return [next, value] slices rather than writing through
# out-parameters of locals: Cpyte keeps an address-taken local in a register, so
# a value produced by a callee reads back stale in the very next expression.
#
# Layout this client parses, per protocol 777:
#
#   node_count            VarInt
#   for each node:
#     flags               Byte   bits 0-1 type (0 root, 1 literal, 2 argument),
#                                0x04 executable, 0x08 redirect follows,
#                                0x10 suggestion provider follows
#     child_count         VarInt
#     children            VarInt[child_count]
#     name                String          when the type is not root
#     parser              String          when the type is argument
#     parser properties                   parser dependent, see vcmd_skip_parser
#     redirect            VarInt          when flags & 0x08
#     suggestions         String          when flags & 0x10
#   chain_limit           Byte
#
# A parse that does not land exactly on the end of the body means the assumed
# layout and the server disagree; that is reported as malformed rather than
# half-stored, because a tree with a desynchronised tail completes commands with
# the wrong argument names.

import stdlib


def vcmd_name_stride() -> int:
    return 32


def vcmd_parser_stride() -> int:
    return 48


# Custom chat completions are server-pushed argument suggestions that live
# beside the tree rather than inside it: they have no node and no parser.
public def vcmd_completion_capacity() -> int:
    return 1024


public def vcmd_completion_stride() -> int:
    return 64


public def vcmd_suggestion_capacity() -> int:
    return 1024


public def vcmd_suggestion_stride() -> int:
    return 512


public def vcmd_root() -> int:
    return 0


public def vcmd_absent() -> int:
    return -1


# Vanilla servers send a few hundred nodes; a modded server with a content pack
# can push past a thousand. Anything above capacity is refused rather than
# written past the arenas.
public def vcmd_node_capacity() -> int:
    return 4096


public def vcmd_edge_capacity() -> int:
    return 16384


public def vcmd_type_root() -> int:
    return 0


public def vcmd_type_literal() -> int:
    return 1


public def vcmd_type_argument() -> int:
    return 2


public def vcmd_parser_none() -> int:
    return 0


public def vcmd_parser_byte() -> int:
    return 1


public def vcmd_parser_string() -> int:
    return 2


public def vcmd_parser_varint_bounds() -> int:
    return 3


public def vcmd_parser_fixed_bounds() -> int:
    return 4


struct VCommandTree:
    int node_count
    int edge_count
    int chain_limit
    int truncated
    int completion_count
    char* completions
    int suggestion_id
    int suggestion_start
    int suggestion_length
    int suggestion_count
    char* suggestions
    int* node_flags
    int* node_child_start
    int* node_child_count
    int* node_redirect
    int* edges
    char* node_names
    char* node_parsers


public def vcmd_new() -> VCommandTree*:
    VCommandTree* tree = new VCommandTree
    tree.node_count = 0
    tree.edge_count = 0
    tree.chain_limit = 0
    tree.truncated = 0
    tree.node_flags = vt_calloc_int(vcmd_node_capacity())
    tree.node_child_start = vt_calloc_int(vcmd_node_capacity())
    tree.node_child_count = vt_calloc_int(vcmd_node_capacity())
    tree.node_redirect = vt_calloc_int(vcmd_node_capacity())
    int index = 0
    while index < vcmd_node_capacity():
        vt_iset(tree.node_redirect, index, vcmd_absent())
        index = index + 1
    tree.edges = vt_calloc_int(vcmd_edge_capacity())
    tree.node_names = vt_calloc_char(vcmd_node_capacity() * vcmd_name_stride())
    tree.node_parsers = vt_calloc_char(vcmd_node_capacity() * vcmd_parser_stride())
    tree.completion_count = 0
    tree.completions = vt_calloc_char(vcmd_completion_capacity() * vcmd_completion_stride())
    tree.suggestion_id = 0
    tree.suggestion_start = 0
    tree.suggestion_length = 0
    tree.suggestion_count = 0
    tree.suggestions = vt_calloc_char(vcmd_suggestion_capacity() * vcmd_suggestion_stride())
    return tree


public def vcmd_free(tree: VCommandTree*) -> void:
    if tree == null:
        return
    vt_free((void*)tree.node_flags)
    vt_free((void*)tree.node_child_start)
    vt_free((void*)tree.node_child_count)
    vt_free((void*)tree.node_redirect)
    vt_free((void*)tree.edges)
    vt_free((void*)tree.node_names)
    vt_free((void*)tree.node_parsers)
    vt_free((void*)tree.completions)
    vt_free((void*)tree.suggestions)
    del tree


# The engine half of the bundle is concatenated before protocol.cpy, so the wire
# helpers there are not defined yet at this point; this reader mirrors
# decode_varint and the test suite checks the two agree byte for byte. Node,
# edge and string counts all fit well inside the four bytes it accepts.
def vcmd_take_varint(body: int64[], cursor: int64) -> int64[]:
    int64[] result = new int64[2]
    result[0] = -1
    result[1] = 0
    if cursor < 0:
        return result
    int64 shift = 0
    int64 value = 0
    int64 at = cursor
    int64 walked = 0
    while at < len(body):
        int64 payload = body[at] & 0x7F
        int64 continuation = body[at] & 0x80
        at = at + 1
        walked = walked + 1
        value = value | (payload << shift)
        if continuation == 0:
            if walked > 5:
                return result
            result[0] = at
            result[1] = value
            return result
        shift = shift + 7
    return result


# [next, start, length] for a varint-prefixed string slice of the body.
def vcmd_take_string(body: int64[], cursor: int64) -> int64[]:
    int64[] result = new int64[3]
    result[0] = -1
    int64[] header = vcmd_take_varint(body, cursor)
    if header[0] < 0 or header[1] < 0:
        return result
    int64 stop = header[0] + header[1]
    if stop > len(body):
        return result
    result[0] = stop
    result[1] = header[0]
    result[2] = header[1]
    return result


def vcmd_take_skip(body: int64[], cursor: int64, count: int64) -> int64:
    if cursor < 0 or cursor + count > len(body):
        return i64_failed()
    return cursor + count


# Bounds inside a parser's settings are only skipped, never read, so this walks
# both the 5 byte varint and the 10 byte varlong forms without decoding either.
def vcmd_take_opaque_varint(body: int64[], cursor: int64) -> int64:
    int64 at = cursor
    int64 walked = 0
    while at < len(body):
        int64 continuation = body[at] & 0x80
        at = at + 1
        walked = walked + 1
        if continuation == 0:
            return at
        if walked > 10:
            return i64_failed()
    return i64_failed()


# Compare the parser identifier against a literal without copying it first. The
# string helpers here come from util/strings.cpy rather than the network client's
# C imports, because engine bundles build without src/protocol.cpy.
def vcmd_text_matches(body: int64[], start: int64, length: int64,
                      needle: str) -> int:
    int size = text_len(needle)
    if (int64)size != length:
        return 0
    int index = 0
    while index < size:
        if (body[start + (int64)index] & 0xFF) != code_at(needle, index):
            return 0
        index = index + 1
    return 1


public def vcmd_parser_kind(body: int64[], start: int64, length: int64) -> int:
    if vcmd_text_matches(body, start, length, "brigadier:bool"):
        return vcmd_parser_none()
    if vcmd_text_matches(body, start, length, "brigadier:float"):
        return vcmd_parser_fixed_bounds()
    if vcmd_text_matches(body, start, length, "brigadier:double"):
        return vcmd_parser_fixed_bounds()
    if vcmd_text_matches(body, start, length, "brigadier:integer"):
        return vcmd_parser_varint_bounds()
    if vcmd_text_matches(body, start, length, "brigadier:long"):
        return vcmd_parser_varint_bounds()
    if vcmd_text_matches(body, start, length, "brigadier:string"):
        return vcmd_parser_byte()
    if vcmd_text_matches(body, start, length, "minecraft:entity"):
        return vcmd_parser_byte()
    if vcmd_text_matches(body, start, length, "minecraft:game_profile"):
        return vcmd_parser_none()
    if vcmd_text_matches(body, start, length, "minecraft:item_slot"):
        return vcmd_parser_none()
    if vcmd_text_matches(body, start, length, "minecraft:item_slots"):
        return vcmd_parser_none()
    if vcmd_text_matches(body, start, length, "minecraft:resource"):
        return vcmd_parser_string()
    if vcmd_text_matches(body, start, length, "minecraft:resource_or_tag"):
        return vcmd_parser_string()
    if vcmd_text_matches(body, start, length, "minecraft:time"):
        return vcmd_parser_none()
    return -1


def vcmd_take_bounds(body: int64[], cursor: int64, width: int64) -> int64:
    if cursor < 0 or cursor >= len(body):
        return i64_failed()
    int64 bounds = body[cursor] & 0xFF
    int64 next = cursor + 1
    if (bounds & 1) != 0:
        if width == 0:
            next = vcmd_take_opaque_varint(body, next)
        else:
            next = vcmd_take_skip(body, next, width)
        if next < 0:
            return i64_failed()
    if (bounds & 2) != 0:
        if width == 0:
            next = vcmd_take_opaque_varint(body, next)
        else:
            next = vcmd_take_skip(body, next, width)
        if next < 0:
            return i64_failed()
    return next


# An unrecognised parser is an error rather than something to skip: guessing the
# size of its settings would read the following node out of the middle of them.
def vcmd_skip_parser(body: int64[], cursor: int64, start: int64,
                     length: int64) -> int64:
    int kind = vcmd_parser_kind(body, start, length)
    if kind == vcmd_parser_none():
        return cursor
    if kind == vcmd_parser_string():
        int64[] registry = vcmd_take_string(body, cursor)
        return registry[0]
    if kind == vcmd_parser_byte():
        return vcmd_take_skip(body, cursor, 1)
    if kind == vcmd_parser_varint_bounds():
        return vcmd_take_bounds(body, cursor, 0)
    if kind == vcmd_parser_fixed_bounds():
        int64 width = 4
        if vcmd_text_matches(body, start, length, "brigadier:double"):
            width = 8
        return vcmd_take_bounds(body, cursor, width)
    return i64_failed()


def vcmd_arena_length(arena: char*, base: int, stride: int) -> int:
    int index = 0
    while index < stride and vt_at(arena, base + index) != 0:
        index = index + 1
    return index


def vcmd_write_text(arena: char*, base: int, body: int64[], offset: int64,
                    length: int64, stride: int) -> void:
    int64 limit = stride - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


def vcmd_append_edge(tree: VCommandTree*, child: int) -> void:
    vt_iset(tree.edges, tree.edge_count, child)
    tree.edge_count = tree.edge_count + 1


# Walk one packet and replace the whole tree. Returns 0 when the tree was
# stored exactly, 1 when the body is malformed or exceeded the capacity.
public def vcmd_parse(tree: VCommandTree*, body: int64[], offset: int64) -> int:
    int64[] header = vcmd_take_varint(body, offset)
    int64 cursor = header[0]
    if cursor < 0 or header[1] < 1:
        return 1
    int wanted = (int)header[1]
    if wanted > vcmd_node_capacity():
        tree.truncated = 1
        return 1
    tree.node_count = 0
    tree.edge_count = 0
    tree.truncated = 0
    int node = 0
    while node < wanted:
        if cursor >= len(body):
            return 1
        int flags = (int)body[cursor] & 0xFF
        cursor = cursor + 1
        int64[] child_header = vcmd_take_varint(body, cursor)
        cursor = child_header[0]
        if cursor < 0 or child_header[1] < 0:
            return 1
        int children = (int)child_header[1]
        if tree.edge_count + children > vcmd_edge_capacity():
            tree.truncated = 1
            return 1
        vt_iset(tree.node_child_start, node, tree.edge_count)
        vt_iset(tree.node_child_count, node, children)
        vt_iset(tree.node_flags, node, flags)
        int step = 0
        while step < children:
            int64[] child = vcmd_take_varint(body, cursor)
            cursor = child[0]
            if cursor < 0 or child[1] < 0 or child[1] >= wanted:
                return 1
            vcmd_append_edge(tree, (int)child[1])
            step = step + 1
        int node_type = flags & 3
        if node_type != vcmd_type_root():
            int64[] name = vcmd_take_string(body, cursor)
            cursor = name[0]
            if cursor < 0:
                return 1
            vcmd_write_text(tree.node_names, node * vcmd_name_stride(), body,
                            name[1], name[2], vcmd_name_stride())
        if node_type == vcmd_type_argument():
            int64[] parser = vcmd_take_string(body, cursor)
            cursor = parser[0]
            if cursor < 0:
                return 1
            vcmd_write_text(tree.node_parsers, node * vcmd_parser_stride(),
                            body, parser[1], parser[2], vcmd_parser_stride())
            cursor = vcmd_skip_parser(body, cursor, parser[1], parser[2])
            if cursor < 0:
                return 1
        if (flags & 0x08) != 0:
            int64[] redirect = vcmd_take_varint(body, cursor)
            cursor = redirect[0]
            if cursor < 0 or redirect[1] < 0 or redirect[1] >= wanted:
                return 1
            vt_iset(tree.node_redirect, node, (int)redirect[1])
        if (flags & 0x10) != 0:
            int64[] suggestions = vcmd_take_string(body, cursor)
            cursor = suggestions[0]
            if cursor < 0:
                return 1
        node = node + 1
    if cursor + 1 > len(body):
        return 1
    tree.chain_limit = (int)body[cursor] & 0xFF
    cursor = cursor + 1
    if cursor != len(body):
        return 1
    tree.node_count = wanted
    return 0


public def vcmd_node_total(tree: VCommandTree*) -> int:
    return tree.node_count


public def vcmd_is_truncated(tree: VCommandTree*) -> int:
    return tree.truncated


public def vcmd_chain_limit(tree: VCommandTree*) -> int:
    return tree.chain_limit


public def vcmd_node_type(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return vcmd_absent()
    return vt_iget(tree.node_flags, node) & 3


public def vcmd_is_executable(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    if (vt_iget(tree.node_flags, node) & 4) == 0:
        return 0
    return 1


public def vcmd_redirect(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return vcmd_absent()
    return vt_iget(tree.node_redirect, node)


public def vcmd_child_count(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    return vt_iget(tree.node_child_count, node)


public def vcmd_child(tree: VCommandTree*, node: int, index: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count or index < 0:
        return vcmd_absent()
    if index >= vt_iget(tree.node_child_count, node):
        return vcmd_absent()
    return vt_iget(tree.edges, vt_iget(tree.node_child_start, node) + index)


public def vcmd_name_length(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    return vcmd_arena_length(tree.node_names, node * vcmd_name_stride(),
                             vcmd_name_stride())


public def vcmd_name_byte(tree: VCommandTree*, node: int, index: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count or index < 0:
        return 0
    if index >= vcmd_name_stride():
        return 0
    return vt_at(tree.node_names, node * vcmd_name_stride() + index)


public def vcmd_parser_length(tree: VCommandTree*, node: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    return vcmd_arena_length(tree.node_parsers, node * vcmd_parser_stride(),
                             vcmd_parser_stride())


public def vcmd_parser_name_byte(tree: VCommandTree*, node: int, index: int) -> int:
    if tree == null or node < 0 or node >= tree.node_count or index < 0:
        return 0
    if index >= vcmd_parser_stride():
        return 0
    return vt_at(tree.node_parsers, node * vcmd_parser_stride() + index)


# How many children of a node start with the bytes the player has typed so far.
# Completion asks this before it asks for the names, so both walks share the
# stride and the terminator rule of the name arena.
public def vcmd_match_children(tree: VCommandTree*, node: int, prefix: str) -> int:
    if tree == null or node < 0 or node >= tree.node_count:
        return 0
    int size = text_len(prefix)
    if size < 1:
        return vt_iget(tree.node_child_count, node)
    int matched = 0
    int index = 0
    while index < vt_iget(tree.node_child_count, node):
        int child = vt_iget(tree.edges,
                            vt_iget(tree.node_child_start, node) + index)
        int base = child * vcmd_name_stride()
        int same = 1
        int step = 0
        while step < size:
            int64 stored = (int64)vt_at(tree.node_names, base + step)
            int64 wanted_byte = (int64)code_at(prefix, step)
            if stored != wanted_byte:
                same = 0
                step = size
            step = step + 1
        if same == 1:
            matched = matched + 1
        index = index + 1
    return matched


# --- custom chat completions --------------------------------------------------

def vcmd_completion_matches(arena: char*, base: int, body: int64[],
                            offset: int64, length: int64) -> int:
    int64 limit = vcmd_completion_stride() - 1
    if length > limit:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


def vcmd_completion_write(arena: char*, base: int, body: int64[],
                          offset: int64, length: int64) -> void:
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


def vcmd_completion_find(tree: VCommandTree*, body: int64[], offset: int64,
                         length: int64) -> int:
    int row = 0
    while row < tree.completion_count:
        if vcmd_completion_matches(tree.completions,
                                   row * vcmd_completion_stride(),
                                   body, offset, length) == 1:
            return row
        row = row + 1
    return vcmd_absent()


public def vcmd_completions_clear(tree: VCommandTree*) -> void:
    if tree == null:
        return
    tree.completion_count = 0


public def vcmd_completions_add(tree: VCommandTree*, body: int64[],
                                offset: int64, length: int64) -> int:
    if tree == null or length < 0:
        return vcmd_absent()
    if length >= vcmd_completion_stride():
        return vcmd_absent()
    if vcmd_completion_find(tree, body, offset, length) != vcmd_absent():
        return vcmd_absent()
    if tree.completion_count >= vcmd_completion_capacity():
        return vcmd_absent()
    int row = tree.completion_count
    vcmd_completion_write(tree.completions, row * vcmd_completion_stride(),
                          body, offset, length)
    tree.completion_count = row + 1
    return row


public def vcmd_completions_remove(tree: VCommandTree*, body: int64[],
                                   offset: int64, length: int64) -> int:
    if tree == null:
        return 0
    int row = vcmd_completion_find(tree, body, offset, length)
    if row == vcmd_absent():
        return 0
    int last = tree.completion_count - 1
    while row < last:
        int index = 0
        while index < vcmd_completion_stride():
            vt_put(tree.completions, row * vcmd_completion_stride() + index,
                   vt_at(tree.completions,
                         (row + 1) * vcmd_completion_stride() + index))
            index = index + 1
        row = row + 1
    tree.completion_count = last
    return 1


public def vcmd_completion_rows(tree: VCommandTree*) -> int:
    if tree == null:
        return 0
    return tree.completion_count


public def vcmd_completion_length(tree: VCommandTree*, row: int) -> int:
    if tree == null or row < 0 or row >= tree.completion_count:
        return 0
    int base = row * vcmd_completion_stride()
    int index = 0
    while index < vcmd_completion_stride():
        if vt_at(tree.completions, base + index) == 0:
            return index
        index = index + 1
    return index


public def vcmd_completion_byte(tree: VCommandTree*, row: int,
                                index: int) -> int:
    if tree == null or row < 0 or row >= tree.completion_count:
        return 0
    if index < 0 or index >= vcmd_completion_stride():
        return 0
    return vt_at(tree.completions, row * vcmd_completion_stride() + index)


# --- tab-complete suggestions -------------------------------------------------
#
# A suggestions packet replaces the whole list and names the substring it
# applies to, so the range is stored with the rows rather than per row. Tooltips
# are components the client cannot render headlessly and are walked, not kept.

public def vcmd_suggestions_begin(tree: VCommandTree*, id: int, start: int,
                                  length: int) -> int:
    if tree == null or id < 0 or start < 0 or length < 0:
        return 1
    tree.suggestion_id = id
    tree.suggestion_start = start
    tree.suggestion_length = length
    tree.suggestion_count = 0
    return 0


public def vcmd_suggestions_add(tree: VCommandTree*, body: int64[],
                                offset: int64, length: int64) -> int:
    if tree == null or length < 0:
        return vcmd_absent()
    if length >= vcmd_suggestion_stride():
        return vcmd_absent()
    if tree.suggestion_count >= vcmd_suggestion_capacity():
        return vcmd_absent()
    int row = tree.suggestion_count
    vcmd_completion_write(tree.suggestions, row * vcmd_suggestion_stride(),
                          body, offset, length)
    tree.suggestion_count = row + 1
    return row


public def vcmd_suggestion_id(tree: VCommandTree*) -> int:
    if tree == null:
        return vcmd_absent()
    return tree.suggestion_id


public def vcmd_suggestion_start(tree: VCommandTree*) -> int:
    if tree == null:
        return 0
    return tree.suggestion_start


public def vcmd_suggestion_length(tree: VCommandTree*) -> int:
    if tree == null:
        return 0
    return tree.suggestion_length


public def vcmd_suggestion_rows(tree: VCommandTree*) -> int:
    if tree == null:
        return 0
    return tree.suggestion_count


public def vcmd_suggestion_row_length(tree: VCommandTree*, row: int) -> int:
    if tree == null or row < 0 or row >= tree.suggestion_count:
        return 0
    int base = row * vcmd_suggestion_stride()
    int index = 0
    while index < vcmd_suggestion_stride():
        if vt_at(tree.suggestions, base + index) == 0:
            return index
        index = index + 1
    return index


public def vcmd_suggestion_byte(tree: VCommandTree*, row: int, index: int) -> int:
    if tree == null or row < 0 or row >= tree.suggestion_count:
        return 0
    if index < 0 or index >= vcmd_suggestion_stride():
        return 0
    return vt_at(tree.suggestions, row * vcmd_suggestion_stride() + index)

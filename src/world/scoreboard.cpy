# Vortex engine - scoreboard: objectives, scores, display slots and teams.
#
# Five packets patch one shared model and each of them can name an entry that
# has not been created yet, so the store keys everything by the text id the
# server uses and tolerates out-of-order arrival. Ids are fixed 32-byte
# NUL-terminated slots in one arena: the wire guarantees a non-empty string, a
# flat arena keeps the module free of per-entry allocations, and a truncated id
# simply cannot collide with a real one.

import stdlib


def vscore_id_stride() -> int:
    return 32


def vscore_text_stride() -> int:
    return 64


public def vscore_objective_capacity() -> int:
    return 64


public def vscore_entry_capacity() -> int:
    return 4096


public def vscore_display_slots() -> int:
    return 20


public def vscore_team_capacity() -> int:
    return 64


public def vscore_team_members() -> int:
    return 16


public def vscore_absent() -> int:
    return -1


# The objective packet actions.
public def vscore_action_create() -> int:
    return 0


public def vscore_action_remove() -> int:
    return 1


public def vscore_action_change() -> int:
    return 2


# The score packet actions.
public def vscore_score_change() -> int:
    return 0


public def vscore_score_remove() -> int:
    return 1


# The team packet modes. These are a different numbering from the objective
# actions even though both ride on a leading byte, so they get their own names.
public def vscore_team_create() -> int:
    return 0


public def vscore_team_remove() -> int:
    return 1


public def vscore_team_update() -> int:
    return 2


public def vscore_team_add_members() -> int:
    return 3


public def vscore_team_remove_members() -> int:
    return 4


struct VScoreboard:
    int objective_count
    char* objective_ids
    char* objective_display
    int* objective_present
    int score_count
    char* score_holders
    char* score_objectives
    int* score_values
    int* score_present
    int* display_slot
    int team_count
    char* team_ids
    char* team_display
    char* team_prefix
    char* team_suffix
    int* team_options
    int* team_nametag
    int* team_collision
    int* team_chat
    int* team_present
    int* team_member_count
    char* team_members


public def vscore_new() -> VScoreboard*:
    VScoreboard* board = new VScoreboard
    board.objective_count = 0
    board.objective_ids = vt_calloc_char(vscore_objective_capacity() * vscore_id_stride())
    board.objective_display = vt_calloc_char(vscore_objective_capacity() * vscore_text_stride())
    board.objective_present = vt_calloc_int(vscore_objective_capacity())
    board.score_count = 0
    board.score_holders = vt_calloc_char(vscore_entry_capacity() * vscore_id_stride())
    board.score_objectives = vt_calloc_char(vscore_entry_capacity() * vscore_id_stride())
    board.score_values = vt_calloc_int(vscore_entry_capacity())
    board.score_present = vt_calloc_int(vscore_entry_capacity())
    board.display_slot = vt_calloc_int(vscore_display_slots())
    int slot = 0
    while slot < vscore_display_slots():
        vt_iset(board.display_slot, slot, vscore_absent())
        slot = slot + 1
    board.team_count = 0
    board.team_ids = vt_calloc_char(vscore_team_capacity() * vscore_id_stride())
    board.team_display = vt_calloc_char(vscore_team_capacity() * vscore_text_stride())
    board.team_prefix = vt_calloc_char(vscore_team_capacity() * vscore_text_stride())
    board.team_suffix = vt_calloc_char(vscore_team_capacity() * vscore_text_stride())
    board.team_options = vt_calloc_int(vscore_team_capacity())
    board.team_nametag = vt_calloc_int(vscore_team_capacity())
    board.team_collision = vt_calloc_int(vscore_team_capacity())
    board.team_chat = vt_calloc_int(vscore_team_capacity())
    board.team_present = vt_calloc_int(vscore_team_capacity())
    board.team_member_count = vt_calloc_int(vscore_team_capacity())
    board.team_members = vt_calloc_char(vscore_team_capacity() * vscore_team_members() * vscore_id_stride())
    return board


public def vscore_free(board: VScoreboard*) -> void:
    if board == null:
        return
    vt_free((void*)board.objective_ids)
    vt_free((void*)board.objective_display)
    vt_free((void*)board.objective_present)
    vt_free((void*)board.score_holders)
    vt_free((void*)board.score_objectives)
    vt_free((void*)board.score_values)
    vt_free((void*)board.score_present)
    vt_free((void*)board.display_slot)
    vt_free((void*)board.team_ids)
    vt_free((void*)board.team_display)
    vt_free((void*)board.team_prefix)
    vt_free((void*)board.team_suffix)
    vt_free((void*)board.team_options)
    vt_free((void*)board.team_nametag)
    vt_free((void*)board.team_collision)
    vt_free((void*)board.team_chat)
    vt_free((void*)board.team_present)
    vt_free((void*)board.team_member_count)
    vt_free((void*)board.team_members)
    del board


# A body slice is [offset, offset+length) of the packet; the id it holds is the
# NUL-terminated bytes in an arena slot. Copying truncates at the stride, and
# comparing requires the stored terminator, so an over-long id never matches.
def vscore_write_id(arena: char*, base: int, body: int64[], offset: int64,
                    length: int64) -> void:
    int64 limit = vscore_id_stride() - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


def vscore_arena_length(arena: char*, base: int, stride: int) -> int:
    int index = 0
    while index < stride and vt_at(arena, base + index) != 0:
        index = index + 1
    return index


def vscore_write_text(arena: char*, base: int, body: int64[], offset: int64,
                      length: int64) -> void:
    int64 limit = vscore_text_stride() - 1
    if length > limit:
        length = limit
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


def vscore_id_at(arena: char*, base: int, body: int64[], offset: int64,
                 length: int64) -> int:
    int64 limit = vscore_id_stride() - 1
    if length > limit:
        length = limit
    if length < 1:
        return 0
    int64 index = 0
    while index < length:
        if vt_at(arena, base + (int)index) != (int)(body[offset + index] & 0xFF):
            return 0
        index = index + 1
    if vt_at(arena, base + (int)length) != 0:
        return 0
    return 1


# --- objectives ---

def vscore_clear_score(board: VScoreboard*, index: int) -> void:
    vt_iset(board.score_present, index, 0)
    vt_iset(board.score_values, index, 0)
    vt_put(board.score_holders, index * vscore_id_stride(), 0)
    vt_put(board.score_objectives, index * vscore_id_stride(), 0)
    board.score_count = board.score_count - 1


public def vscore_find_objective(board: VScoreboard*, body: int64[],
                                 offset: int64, length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = 0
    while slot < vscore_objective_capacity():
        int present = vt_iget(board.objective_present, slot)
        int same = vscore_id_at(board.objective_ids, slot * vscore_id_stride(),
                                body, offset, length)
        if present == 1 and same == 1:
            return slot
        slot = slot + 1
    return vscore_absent()


# An objective that is referenced before it is announced still needs a place to
# park scores, so lookups that write create the slot.
def vscore_objective_slot(board: VScoreboard*, body: int64[], offset: int64,
                          length: int64) -> int:
    int slot = vscore_find_objective(board, body, offset, length)
    if slot >= 0:
        return slot
    int free = 0
    while free < vscore_objective_capacity():
        if vt_iget(board.objective_present, free) == 0:
            vt_iset(board.objective_present, free, 1)
            vscore_write_id(board.objective_ids, free * vscore_id_stride(),
                            body, offset, length)
            vt_put(board.objective_display, free * vscore_text_stride(), 0)
            board.objective_count = board.objective_count + 1
            return free
        free = free + 1
    return vscore_absent()


public def vscore_clear_objective(board: VScoreboard*, slot: int) -> void:
    if board == null or slot < 0:
        return
    vt_iset(board.objective_present, slot, 0)
    vt_put(board.objective_ids, slot * vscore_id_stride(), 0)
    vt_put(board.objective_display, slot * vscore_text_stride(), 0)
    board.objective_count = board.objective_count - 1


# Removing an objective takes its scores with it, because a score row is keyed
# by (holder, objective) and a dangling objective name would keep matching the
# next objective that lands on the same holder.
def vscore_drop_objective_scores(board: VScoreboard*, objective: int,
                                 body: int64[], offset: int64,
                                 length: int64) -> void:
    int index = 0
    while index < vscore_entry_capacity():
        int present = vt_iget(board.score_present, index)
        int same = vscore_id_at(board.score_objectives,
                                index * vscore_id_stride(), body, offset, length)
        if present == 1 and same == 1:
            vscore_clear_score(board, index)
        index = index + 1


public def vscore_set_objective(board: VScoreboard*, body: int64[], offset: int64,
                                length: int64, action: int, display: int64[],
                                display_at: int64, display_length: int64) -> int:
    if board == null or length < 1:
        return 0
    if action == vscore_action_remove():
        int existing = vscore_find_objective(board, body, offset, length)
        if existing < 0:
            return 1
        vscore_clear_objective(board, existing)
        vscore_drop_objective_scores(board, existing, body, offset, length)
        return 1
    int slot = vscore_objective_slot(board, body, offset, length)
    if slot < 0:
        return 0
    if display_length >= 0:
        vscore_write_text(board.objective_display, slot * vscore_text_stride(),
                          display, display_at, display_length)
    return 1


public def vscore_objective_exists(board: VScoreboard*, body: int64[],
                                   offset: int64, length: int64) -> int:
    if vscore_find_objective(board, body, offset, length) < 0:
        return 0
    return 1


public def vscore_objective_name_byte(board: VScoreboard*, slot: int,
                                      index: int) -> int:
    if board == null or slot < 0 or index < 0:
        return 0
    return vt_at(board.objective_ids, slot * vscore_id_stride() + index)


public def vscore_objective_display_byte(board: VScoreboard*, slot: int,
                                         index: int) -> int:
    if board == null or slot < 0 or index < 0:
        return 0
    return vt_at(board.objective_display, slot * vscore_text_stride() + index)


public def vscore_objective_display_length(board: VScoreboard*, slot: int) -> int:
    if board == null or slot < 0:
        return 0
    return vscore_arena_length(board.objective_display, slot * vscore_text_stride(),
                               vscore_text_stride())


# --- scores ---

# A score row is addressed by the two ids the packet spells out, so the lookup
# takes the body twice rather than a resolved slot: the objective may not exist
# yet and creating it here would invent objectives from stray score updates.
def vscore_find_score(board: VScoreboard*, holder: int64[], holder_at: int64,
                      holder_length: int64, objective: int64[],
                      objective_at: int64, objective_length: int64) -> int:
    if board == null:
        return vscore_absent()
    int index = 0
    while index < vscore_entry_capacity():
        int present = vt_iget(board.score_present, index)
        int same_holder = vscore_id_at(board.score_holders,
                                       index * vscore_id_stride(),
                                       holder, holder_at, holder_length)
        int same_objective = vscore_id_at(board.score_objectives,
                                          index * vscore_id_stride(),
                                          objective, objective_at, objective_length)
        if present == 1 and same_holder == 1 and same_objective == 1:
            return index
        index = index + 1
    return vscore_absent()


def vscore_score_slot(board: VScoreboard*, holder: int64[], holder_at: int64,
                      holder_length: int64, objective: int64[],
                      objective_at: int64, objective_length: int64) -> int:
    int existing = vscore_find_score(board, holder, holder_at, holder_length,
                                     objective, objective_at, objective_length)
    if existing >= 0:
        return existing
    int index = 0
    while index < vscore_entry_capacity():
        if vt_iget(board.score_present, index) == 0:
            vt_iset(board.score_present, index, 1)
            vscore_write_id(board.score_holders, index * vscore_id_stride(),
                            holder, holder_at, holder_length)
            vscore_write_id(board.score_objectives, index * vscore_id_stride(),
                            objective, objective_at, objective_length)
            vt_iset(board.score_values, index, 0)
            board.score_count = board.score_count + 1
            return index
        index = index + 1
    return vscore_absent()


public def vscore_set_score(board: VScoreboard*, holder: int64[], holder_at: int64,
                            holder_length: int64, objective: int64[],
                            objective_at: int64, objective_length: int64,
                            value: int) -> int:
    if board == null or holder_length < 1 or objective_length < 1:
        return 0
    int slot = vscore_score_slot(board, holder, holder_at, holder_length,
                                 objective, objective_at, objective_length)
    if slot < 0:
        return 0
    vt_iset(board.score_values, slot, value)
    return 1


public def vscore_reset_score(board: VScoreboard*, holder: int64[],
                              holder_at: int64, holder_length: int64,
                              objective: int64[], objective_at: int64,
                              objective_length: int64) -> int:
    if board == null:
        return 0
    int slot = vscore_find_score(board, holder, holder_at, holder_length,
                                 objective, objective_at, objective_length)
    if slot < 0:
        return 1
    vscore_clear_score(board, slot)
    return 1


# vscore_score_absent is what a missing row reports: 0 is a legal score, so the
# reader needs a value the wire can never send.
public def vscore_score_absent() -> int:
    return -2147483648


public def vscore_get_score(board: VScoreboard*, holder: int64[], holder_at: int64,
                            holder_length: int64, objective: int64[],
                            objective_at: int64, objective_length: int64) -> int:
    int slot = vscore_find_score(board, holder, holder_at, holder_length,
                                 objective, objective_at, objective_length)
    if slot < 0:
        return vscore_score_absent()
    return vt_iget(board.score_values, slot)


# --- display slots ---

# An empty name clears the slot; a name that has not been announced still owns
# one, because servers send display_objective before the objective itself.
public def vscore_set_display(board: VScoreboard*, slot: int, body: int64[],
                              offset: int64, length: int64) -> int:
    if board == null or slot < 0 or slot >= vscore_display_slots():
        return 0
    if length < 1:
        vt_iset(board.display_slot, slot, vscore_absent())
        return 1
    int objective = vscore_objective_slot(board, body, offset, length)
    if objective < 0:
        return 0
    vt_iset(board.display_slot, slot, objective)
    return 1


public def vscore_display_objective(board: VScoreboard*, slot: int) -> int:
    if board == null or slot < 0 or slot >= vscore_display_slots():
        return vscore_absent()
    return vt_iget(board.display_slot, slot)


public def vscore_display_objective_byte(board: VScoreboard*, slot: int,
                                         index: int) -> int:
    int objective = vscore_display_objective(board, slot)
    if objective < 0 or index < 0:
        return 0
    return vt_at(board.objective_ids, objective * vscore_id_stride() + index)


# --- teams ---

def vscore_find_team(board: VScoreboard*, body: int64[], offset: int64,
                     length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = 0
    while slot < vscore_team_capacity():
        int present = vt_iget(board.team_present, slot)
        int same = vscore_id_at(board.team_ids, slot * vscore_id_stride(),
                                body, offset, length)
        if present == 1 and same == 1:
            return slot
        slot = slot + 1
    return vscore_absent()


def vscore_create_team(board: VScoreboard*, body: int64[], offset: int64,
                       length: int64) -> int:
    int slot = 0
    while slot < vscore_team_capacity():
        if vt_iget(board.team_present, slot) == 0:
            vt_iset(board.team_present, slot, 1)
            vscore_write_id(board.team_ids, slot * vscore_id_stride(),
                            body, offset, length)
            vt_put(board.team_display, slot * vscore_text_stride(), 0)
            vt_put(board.team_prefix, slot * vscore_text_stride(), 0)
            vt_put(board.team_suffix, slot * vscore_text_stride(), 0)
            vt_iset(board.team_options, slot, 0)
            vt_iset(board.team_nametag, slot, 0)
            vt_iset(board.team_collision, slot, 0)
            vt_iset(board.team_chat, slot, 0)
            vt_iset(board.team_member_count, slot, 0)
            board.team_count = board.team_count + 1
            return slot
        slot = slot + 1
    return vscore_absent()


def vscore_clear_team(board: VScoreboard*, slot: int) -> void:
    vt_iset(board.team_present, slot, 0)
    vt_put(board.team_ids, slot * vscore_id_stride(), 0)
    vt_put(board.team_display, slot * vscore_text_stride(), 0)
    vt_put(board.team_prefix, slot * vscore_text_stride(), 0)
    vt_put(board.team_suffix, slot * vscore_text_stride(), 0)
    vt_iset(board.team_options, slot, 0)
    vt_iset(board.team_member_count, slot, 0)
    int index = 0
    int base = slot * vscore_team_members() * vscore_id_stride()
    while index < vscore_team_members() * vscore_id_stride():
        vt_put(board.team_members, base + index, 0)
        index = index + 1
    board.team_count = board.team_count - 1


def vscore_team_member_base(slot: int) -> int:
    return slot * vscore_team_members() * vscore_id_stride()


# Members live in a fixed 16-row block per team. The packet sends them as
# separate strings, so the handler passes the body plus each string's offset.
public def vscore_team_member_at(board: VScoreboard*, slot: int,
                                 index: int) -> int64:
    if board == null or slot < 0 or index < 0:
        return vscore_absent()
    if index >= vt_iget(board.team_member_count, slot):
        return vscore_absent()
    return vscore_arena_length(board.team_members,
                               vscore_team_member_base(slot) + index * vscore_id_stride(),
                               vscore_id_stride())


def vscore_team_member_matches(board: VScoreboard*, slot: int, row: int,
                               body: int64[], offset: int64,
                               length: int64) -> int:
    int base = vscore_team_member_base(slot) + row * vscore_id_stride()
    return vscore_id_at(board.team_members, base, body, offset, length)


# Adding a member already in the team is a no-op: servers re-send the whole
# create payload when a player reconnects, and a duplicate row would make the
# member list grow without bound across a long session.
public def vscore_team_add_member(board: VScoreboard*, slot: int, body: int64[],
                                  offset: int64, length: int64) -> int:
    if board == null or slot < 0 or length < 1:
        return 0
    int count = vt_iget(board.team_member_count, slot)
    int index = 0
    while index < count:
        if vscore_team_member_matches(board, slot, index, body, offset, length) == 1:
            return 1
        index = index + 1
    if count >= vscore_team_members():
        return 0
    vscore_write_id(board.team_members,
                    vscore_team_member_base(slot) + count * vscore_id_stride(),
                    body, offset, length)
    vt_iset(board.team_member_count, slot, count + 1)
    return 1


def vscore_team_shift_members(board: VScoreboard*, slot: int, from: int) -> void:
    int limit = vscore_team_members() - 1
    int index = from * vscore_id_stride()
    int stop = limit * vscore_id_stride()
    int base = vscore_team_member_base(slot)
    while index < stop:
        vt_put(board.team_members, base + index,
               vt_at(board.team_members, base + index + vscore_id_stride()))
        index = index + 1
    vt_put(board.team_members, base + stop, 0)


public def vscore_team_remove_member(board: VScoreboard*, slot: int,
                                     body: int64[], offset: int64,
                                     length: int64) -> int:
    if board == null or slot < 0 or length < 1:
        return 0
    int count = vt_iget(board.team_member_count, slot)
    int index = 0
    while index < count:
        if vscore_team_member_matches(board, slot, index, body, offset, length) == 1:
            vscore_team_shift_members(board, slot, index)
            vt_iset(board.team_member_count, slot, count - 1)
            return 1
        index = index + 1
    return 0


public def vscore_find_team_of(board: VScoreboard*, body: int64[], offset: int64,
                               length: int64) -> int:
    if board == null or length < 1:
        return vscore_absent()
    int slot = 0
    while slot < vscore_team_capacity():
        if vt_iget(board.team_present, slot) == 1:
            int count = vt_iget(board.team_member_count, slot)
            int index = 0
            while index < count:
                int base = vscore_team_member_base(slot) + index * vscore_id_stride()
                if vscore_id_at(board.team_members, base, body, offset, length) == 1:
                    return slot
                index = index + 1
        slot = slot + 1
    return vscore_absent()


# display/prefix/suffix arrive as chat components, which the handler has already
# flattened to text; a negative length means the packet did not carry the field.
public def vscore_set_team(board: VScoreboard*, body: int64[], offset: int64,
                           length: int64, mode: int, display: int64[],
                           display_at: int64, display_length: int64,
                           prefix: int64[], prefix_at: int64, prefix_length: int64,
                           suffix: int64[], suffix_at: int64,
                           suffix_length: int64) -> int:
    if board == null or length < 1:
        return 0
    if mode == vscore_team_remove():
        int gone = vscore_find_team(board, body, offset, length)
        if gone < 0:
            return 1
        vscore_clear_team(board, gone)
        return 1
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        if mode != vscore_team_create():
            return 0
        slot = vscore_create_team(board, body, offset, length)
    if slot < 0:
        return 0
    if display_length >= 0:
        vscore_write_text(board.team_display, slot * vscore_text_stride(),
                          display, display_at, display_length)
    if prefix_length >= 0:
        vscore_write_text(board.team_prefix, slot * vscore_text_stride(),
                          prefix, prefix_at, prefix_length)
    if suffix_length >= 0:
        vscore_write_text(board.team_suffix, slot * vscore_text_stride(),
                          suffix, suffix_at, suffix_length)
    return 1


# The option byte packs name-tag visibility in bits 0-1, collision in 2-3 and
# chat visibility in 4-5; keeping them split means callers never re-derive the
# masks and the values survive a re-send that omits a field.
public def vscore_team_index(board: VScoreboard*, body: int64[], offset: int64,
                             length: int64) -> int:
    return vscore_find_team(board, body, offset, length)


public def vscore_set_team_options(board: VScoreboard*, body: int64[],
                                  offset: int64, length: int64,
                                  nametag: int, collision: int,
                                  chat: int) -> int:
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return 0
    int options = (nametag & 3) | ((collision & 3) << 2) | ((chat & 3) << 4)
    vt_iset(board.team_options, slot, options)
    vt_iset(board.team_nametag, slot, options & 3)
    vt_iset(board.team_collision, slot, (options >> 2) & 3)
    vt_iset(board.team_chat, slot, (options >> 4) & 3)
    return 1


public def vscore_team_exists(board: VScoreboard*, body: int64[], offset: int64,
                              length: int64) -> int:
    if vscore_find_team(board, body, offset, length) < 0:
        return 0
    return 1


public def vscore_team_byte(arena: char*, slot: int, stride: int,
                            index: int) -> int:
    if slot < 0 or index < 0:
        return 0
    return vt_at(arena, slot * stride + index)


public def vscore_team_name_byte(board: VScoreboard*, body: int64[], offset: int64,
                                 length: int64, index: int) -> int:
    return vscore_team_byte(board.team_ids, vscore_find_team(board, body, offset, length),
                            vscore_id_stride(), index)


public def vscore_team_display_byte(board: VScoreboard*, body: int64[],
                                    offset: int64, length: int64,
                                    index: int) -> int:
    return vscore_team_byte(board.team_display, vscore_find_team(board, body, offset, length),
                            vscore_text_stride(), index)


public def vscore_team_prefix_byte(board: VScoreboard*, body: int64[],
                                   offset: int64, length: int64,
                                   index: int) -> int:
    return vscore_team_byte(board.team_prefix, vscore_find_team(board, body, offset, length),
                            vscore_text_stride(), index)


public def vscore_team_suffix_byte(board: VScoreboard*, body: int64[],
                                   offset: int64, length: int64,
                                   index: int) -> int:
    return vscore_team_byte(board.team_suffix, vscore_find_team(board, body, offset, length),
                            vscore_text_stride(), index)


public def vscore_team_options(board: VScoreboard*, body: int64[], offset: int64,
                               length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return vscore_absent()
    return vt_iget(board.team_options, slot)


public def vscore_team_nametag(board: VScoreboard*, body: int64[], offset: int64,
                               length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return vscore_absent()
    return vt_iget(board.team_nametag, slot)


public def vscore_team_collision(board: VScoreboard*, body: int64[], offset: int64,
                                 length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return vscore_absent()
    return vt_iget(board.team_collision, slot)


public def vscore_team_chat(board: VScoreboard*, body: int64[], offset: int64,
                            length: int64) -> int:
    if board == null:
        return vscore_absent()
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return vscore_absent()
    return vt_iget(board.team_chat, slot)


public def vscore_team_member_count(board: VScoreboard*, body: int64[],
                                    offset: int64, length: int64) -> int:
    if board == null:
        return 0
    int slot = vscore_find_team(board, body, offset, length)
    if slot < 0:
        return 0
    return vt_iget(board.team_member_count, slot)


public def vscore_team_objective_capacity() -> int:
    return vscore_objective_capacity()


public def vscore_active_objective_count(board: VScoreboard*) -> int:
    if board == null:
        return 0
    return board.objective_count


public def vscore_active_team_count(board: VScoreboard*) -> int:
    if board == null:
        return 0
    return board.team_count


public def vscore_active_score_count(board: VScoreboard*) -> int:
    if board == null:
        return 0
    return board.score_count

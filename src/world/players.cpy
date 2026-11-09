# Vortex engine - the player list the server publishes.
#
# Player Info Update names a subset of fields per entry, so the rows here are
# the union of everything the client can be told about a player: the tab list
# needs the name, the display name, the latency and the hat, the HUD needs the
# game mode, and the chat renderer needs to know whether the sender is listed
# at all. Rows are keyed by the 16 byte uuid because that is the only stable
# identity a server uses; the name can change with a rename while the player is
# online.
#
# An action only writes the columns it carries. That is what makes a
# multi-action packet correct: a server that sends a display name without a
# game mode must not silently reset the game mode the client already shows.
#
# The Add action is the only one allowed to create a row. Every other action
# against an unknown uuid is dropped, which is also what vanilla does - a server
# that updates a player it never added is not followed by a ghost entry.

import stdlib


public def vplayers_absent() -> int:
    return -1


def vplayers_capacity() -> int:
    return 256


def vplayers_uuid_stride() -> int:
    return 16


# Minecraft names are at most 16 characters, so four bytes per character of
# potential multi-byte text is more than enough and keeps the row cheap.
def vplayers_name_stride() -> int:
    return 64


def vplayers_display_stride() -> int:
    return 192


# The action mask bits. The order the bits are numbered in is not the order the
# fields appear in the packet: the entry writes its list-order priority before
# its hat flag, so the walker in src/protocol.cpy follows the field order below
# and not the bit order.
public def vplayers_action_add() -> int:
    return 1


public def vplayers_action_chat() -> int:
    return 2


public def vplayers_action_game_mode() -> int:
    return 4


public def vplayers_action_listed() -> int:
    return 8


public def vplayers_action_latency() -> int:
    return 16


public def vplayers_action_display() -> int:
    return 32


public def vplayers_action_hat() -> int:
    return 64


public def vplayers_action_priority() -> int:
    return 128


def vplayers_all_actions() -> int:
    return 255


struct VPlayers:
    int count
    char* uuids
    char* names
    char* displays
    char* header
    char* footer
    int* game_mode
    int* latency
    int* priority
    int* hat
    int* listed
    int* properties
    int* chat_session


public def vplayers_new() -> VPlayers*:
    VPlayers* table = new VPlayers
    table.count = 0
    table.uuids = vt_calloc_char(vplayers_capacity() * vplayers_uuid_stride())
    table.names = vt_calloc_char(vplayers_capacity() * vplayers_name_stride())
    table.displays = vt_calloc_char(vplayers_capacity() *
                                    vplayers_display_stride())
    table.header = vt_calloc_char(vplayers_display_stride())
    table.footer = vt_calloc_char(vplayers_display_stride())
    table.game_mode = vt_calloc_int(vplayers_capacity())
    table.latency = vt_calloc_int(vplayers_capacity())
    table.priority = vt_calloc_int(vplayers_capacity())
    table.hat = vt_calloc_int(vplayers_capacity())
    table.listed = vt_calloc_int(vplayers_capacity())
    table.properties = vt_calloc_int(vplayers_capacity())
    table.chat_session = vt_calloc_int(vplayers_capacity())
    return table


public def vplayers_free(table: VPlayers*) -> void:
    if table == null:
        return
    vt_free((void*)table.uuids)
    vt_free((void*)table.names)
    vt_free((void*)table.displays)
    vt_free((void*)table.header)
    vt_free((void*)table.footer)
    vt_free((void*)table.game_mode)
    vt_free((void*)table.latency)
    vt_free((void*)table.priority)
    vt_free((void*)table.hat)
    vt_free((void*)table.listed)
    vt_free((void*)table.properties)
    vt_free((void*)table.chat_session)
    del table


def vplayers_uuid_matches(table: VPlayers*, slot: int, body: int64[],
                          offset: int64) -> int:
    int byte = 0
    while byte < vplayers_uuid_stride():
        int stored = vt_at(table.uuids, slot * vplayers_uuid_stride() + byte)
        int wanted = (int)(body[offset + byte] & 0xFF)
        if stored != wanted:
            return 0
        byte = byte + 1
    return 1


public def vplayers_find(table: VPlayers*, body: int64[],
                         offset: int64) -> int:
    if table == null or offset + vplayers_uuid_stride() > len(body):
        return vplayers_absent()
    int slot = 0
    while slot < table.count:
        if vplayers_uuid_matches(table, slot, body, offset) == 1:
            return slot
        slot = slot + 1
    return vplayers_absent()


# Only the Add action creates: see the note above about updates that arrive for
# a player the client has never been introduced to.
def vplayers_add_slot(table: VPlayers*, body: int64[], offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot >= 0:
        return slot
    if table.count >= vplayers_capacity():
        return vplayers_absent()
    slot = table.count
    table.count = table.count + 1
    int byte = 0
    while byte < vplayers_uuid_stride():
        vt_put(table.uuids, slot * vplayers_uuid_stride() + byte,
               (int)(body[offset + byte] & 0xFF))
        byte = byte + 1
    vt_put(table.names, slot * vplayers_name_stride(), 0)
    vt_put(table.displays, slot * vplayers_display_stride(), 0)
    vt_iset(table.game_mode, slot, 0)
    vt_iset(table.latency, slot, 0)
    vt_iset(table.priority, slot, 0)
    vt_iset(table.hat, slot, 0)
    vt_iset(table.listed, slot, 0)
    vt_iset(table.properties, slot, 0)
    vt_iset(table.chat_session, slot, 0)
    return slot


def vplayers_update_slot(table: VPlayers*, body: int64[],
                         offset: int64) -> int:
    return vplayers_find(table, body, offset)


# Copies text into a row, truncating rather than rejecting: a name the client
# cannot fully store is still a name, and the tab list has to show that somebody
# is online. The source is its own array because the display name arrives
# flattened by the component reader rather than as a slice of the packet.
def vplayers_write(dest: char*, stride: int, slot: int, source: int64[],
                   start: int64, length: int64) -> void:
    int limit = stride - 1
    if length > limit:
        length = limit
    int base = slot * stride
    int index = 0
    while index < length:
        vt_put(dest, base + index, (int)(source[start + index] & 0xFF))
        index = index + 1
    vt_put(dest, base + index, 0)


public def vplayers_set_add(table: VPlayers*, body: int64[], uuid_at: int64,
                            name_start: int64, name_length: int64,
                            properties: int, game_mode: int,
                            listed: int) -> int:
    int slot = vplayers_add_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vplayers_write(table.names, vplayers_name_stride(), slot, body,
                   name_start, name_length)
    vt_iset(table.properties, slot, properties)
    vt_iset(table.game_mode, slot, game_mode)
    vt_iset(table.listed, slot, listed)
    return 1


public def vplayers_set_display(table: VPlayers*, body: int64[],
                                uuid_at: int64, source: int64[],
                                length: int64) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vplayers_write(table.displays, vplayers_display_stride(), slot, source,
                   0, length)
    return 1


public def vplayers_set_game_mode(table: VPlayers*, body: int64[],
                                  uuid_at: int64, game_mode: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.game_mode, slot, game_mode)
    return 1


public def vplayers_set_listed(table: VPlayers*, body: int64[],
                               uuid_at: int64, listed: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.listed, slot, listed)
    return 1


public def vplayers_set_latency(table: VPlayers*, body: int64[],
                                uuid_at: int64, latency: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.latency, slot, latency)
    return 1


public def vplayers_set_priority(table: VPlayers*, body: int64[],
                                 uuid_at: int64, priority: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.priority, slot, priority)
    return 1


public def vplayers_set_hat(table: VPlayers*, body: int64[], uuid_at: int64,
                            hat: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.hat, slot, hat)
    return 1


public def vplayers_set_chat(table: VPlayers*, body: int64[],
                             uuid_at: int64, present: int) -> int:
    int slot = vplayers_update_slot(table, body, uuid_at)
    if slot < 0:
        return 0
    vt_iset(table.chat_session, slot, present)
    return 1


def vplayers_copy_down(table: VPlayers*, slot: int) -> void:
    int byte = 0
    while byte < vplayers_uuid_stride():
        vt_put(table.uuids, slot * vplayers_uuid_stride() + byte,
               vt_at(table.uuids, (slot + 1) * vplayers_uuid_stride() + byte))
        byte = byte + 1
    byte = 0
    while byte < vplayers_name_stride():
        vt_put(table.names, slot * vplayers_name_stride() + byte,
               vt_at(table.names, (slot + 1) * vplayers_name_stride() + byte))
        byte = byte + 1
    byte = 0
    while byte < vplayers_display_stride():
        vt_put(table.displays, slot * vplayers_display_stride() + byte,
               vt_at(table.displays,
                     (slot + 1) * vplayers_display_stride() + byte))
        byte = byte + 1
    vt_iset(table.game_mode, slot, vt_iget(table.game_mode, slot + 1))
    vt_iset(table.latency, slot, vt_iget(table.latency, slot + 1))
    vt_iset(table.priority, slot, vt_iget(table.priority, slot + 1))
    vt_iset(table.hat, slot, vt_iget(table.hat, slot + 1))
    vt_iset(table.listed, slot, vt_iget(table.listed, slot + 1))
    vt_iset(table.properties, slot, vt_iget(table.properties, slot + 1))
    vt_iset(table.chat_session, slot, vt_iget(table.chat_session, slot + 1))


# Player Remove carries the uuids of everyone who left, and a stale row would
# keep showing a player in the tab list and let chat resolve a name nobody owns.
public def vplayers_remove(table: VPlayers*, body: int64[],
                           offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return 0
    int last = table.count - 1
    while slot < last:
        vplayers_copy_down(table, slot)
        slot = slot + 1
    table.count = last
    return 1


public def vplayers_active_count(table: VPlayers*) -> int:
    if table == null:
        return 0
    return table.count


public def vplayers_listed_count(table: VPlayers*) -> int:
    if table == null:
        return 0
    int found = 0
    int slot = 0
    while slot < table.count:
        if vt_iget(table.listed, slot) != 0:
            found = found + 1
        slot = slot + 1
    return found


public def vplayers_row_uuid(table: VPlayers*, slot: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return vplayers_absent()
    return (int)(vt_at(table.uuids, slot * vplayers_uuid_stride()) & 0xFF)


public def vplayers_row_name_byte(table: VPlayers*, slot: int,
                                  index: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return 0
    if index < 0 or index >= vplayers_name_stride():
        return 0
    return (int)(vt_at(table.names, slot * vplayers_name_stride() + index)
                 & 0xFF)


public def vplayers_row_display_byte(table: VPlayers*, slot: int,
                                     index: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return 0
    if index < 0 or index >= vplayers_display_stride():
        return 0
    return (int)(vt_at(table.displays, slot * vplayers_display_stride() + index)
                 & 0xFF)


public def vplayers_row_length(table: VPlayers*, slot: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return vplayers_absent()
    int index = 0
    while index < vplayers_name_stride():
        if vt_at(table.names, slot * vplayers_name_stride() + index) == 0:
            return index
        index = index + 1
    return index


public def vplayers_row_display_length(table: VPlayers*, slot: int) -> int:
    if table == null or slot < 0 or slot >= table.count:
        return vplayers_absent()
    int index = 0
    while index < vplayers_display_stride():
        if vt_at(table.displays,
                 slot * vplayers_display_stride() + index) == 0:
            return index
        index = index + 1
    return index


public def vplayers_game_mode(table: VPlayers*, body: int64[],
                              offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.game_mode, slot)


public def vplayers_latency(table: VPlayers*, body: int64[],
                            offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.latency, slot)


public def vplayers_priority(table: VPlayers*, body: int64[],
                             offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.priority, slot)


public def vplayers_hat(table: VPlayers*, body: int64[], offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.hat, slot)


public def vplayers_is_listed(table: VPlayers*, body: int64[],
                              offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.listed, slot)


public def vplayers_properties(table: VPlayers*, body: int64[],
                               offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.properties, slot)


public def vplayers_has_chat(table: VPlayers*, body: int64[],
                             offset: int64) -> int:
    int slot = vplayers_find(table, body, offset)
    if slot < 0:
        return vplayers_absent()
    return vt_iget(table.chat_session, slot)


# Lookup by name, for the paths that only have the chat sender's text: the name
# column is compared byte by byte so no copy is needed.
public def vplayers_slot_by_name(table: VPlayers*, text: str) -> int:
    if table == null:
        return vplayers_absent()
    int wanted = text_len(text)
    if wanted <= 0 or wanted >= vplayers_name_stride():
        return vplayers_absent()
    int slot = 0
    while slot < table.count:
        if vplayers_row_length(table, slot) == wanted:
            int index = 0
            int same = 1
            while index < wanted:
                int stored = vplayers_row_name_byte(table, slot, index)
                if stored != code_at(text, index):
                    same = 0
                    index = wanted
                index = index + 1
            if same == 1:
                return slot
        slot = slot + 1
    return vplayers_absent()


public def vplayers_name_at(table: VPlayers*, slot: int,
                            out: int64[]) -> int:
    int length = vplayers_row_length(table, slot)
    if length < 0:
        return 0
    int capacity = (int)len(out)
    if length > capacity:
        length = capacity
    int index = 0
    while index < length:
        out[index] = vplayers_row_name_byte(table, slot, index)
        index = index + 1
    return length


# The header and footer belong to the list rather than to a row, and the packet
# that carries them is allowed to clear either one by sending an absent
# component - which the caller represents as a zero length.
public def vplayers_set_header(table: VPlayers*, source: int64[],
                              length: int64) -> void:
    vplayers_write(table.header, vplayers_display_stride(), 0, source, 0,
                   length)


public def vplayers_set_footer(table: VPlayers*, source: int64[],
                              length: int64) -> void:
    vplayers_write(table.footer, vplayers_display_stride(), 0, source, 0,
                   length)


public def vplayers_header_length(table: VPlayers*) -> int:
    if table == null:
        return vplayers_absent()
    int index = 0
    while index < vplayers_display_stride():
        if vt_at(table.header, index) == 0:
            return index
        index = index + 1
    return index


public def vplayers_footer_length(table: VPlayers*) -> int:
    if table == null:
        return vplayers_absent()
    int index = 0
    while index < vplayers_display_stride():
        if vt_at(table.footer, index) == 0:
            return index
        index = index + 1
    return index


public def vplayers_header_byte(table: VPlayers*, index: int) -> int:
    if table == null or index < 0 or index >= vplayers_display_stride():
        return 0
    return (int)(vt_at(table.header, index) & 0xFF)


public def vplayers_footer_byte(table: VPlayers*, index: int) -> int:
    if table == null or index < 0 or index >= vplayers_display_stride():
        return 0
    return (int)(vt_at(table.footer, index) & 0xFF)

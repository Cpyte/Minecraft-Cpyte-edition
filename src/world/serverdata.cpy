# Vortex engine - server-pushed session metadata.
#
# Statistics, cooldowns, cookies, resource packs, links, report details, game
# rules, map contents, merchant offers and waypoints share one table because
# they share a shape: the server pushes a small named record set, the client
# keeps it for queries, and none of it drives world simulation. Names live in
# fixed-stride arenas; variable payloads live in pooled byte arrays.

public def vmeta_id_stride() -> int:
    return 128


public def vmeta_text_stride() -> int:
    return 512


public def vmeta_stat_max() -> int:
    return 2048


public def vmeta_named_max() -> int:
    return 256


public def vmeta_trade_max() -> int:
    return 64


public def vmeta_map_max() -> int:
    return 64


public def vmeta_map_pixels() -> int:
    return 16384


public def vmeta_waypoint_max() -> int:
    return 256


public def vmeta_pool_max() -> int:
    return 262144


public def vmeta_absent() -> int:
    return -1


struct VServerMeta:
    int* stat_category
    int* stat_id
    int* stat_value
    int stat_rows
    char* cooldown_names
    int* cooldown_ticks
    uint64* cooldown_started
    int cooldown_rows
    char* cookie_keys
    int* cookie_start
    int* cookie_length
    int cookie_rows
    char* text_pool
    int* text_used
    int* pack_uuid_high
    int* pack_uuid_low
    int* pack_url
    int* pack_hash
    int* pack_required
    int pack_rows
    int* link_type
    int* link_label
    int* link_url
    int link_rows
    char* rule_names
    char* rule_values
    int rule_rows
    char* report_names
    char* report_values
    int report_rows
    int* map_id
    int* map_scale
    int* map_locked
    int* map_pixels
    int map_rows
    int* decoration_map
    int* decoration_type
    int* decoration_x
    int* decoration_y
    int* decoration_rot
    int decoration_rows
    int trade_window
    int* trade_cost_a
    int* trade_cost_a_count
    int* trade_cost_b
    int* trade_cost_b_count
    int* trade_result
    int* trade_result_count
    int* trade_uses
    int* trade_max_uses
    int* trade_disabled
    int trade_rows
    int merchant_level
    int merchant_xp
    bool merchant_progress
    bool merchant_restock
    char* waypoint_names
    int* waypoint_uuid_high
    int* waypoint_uuid_low
    int* waypoint_kind
    int* waypoint_a
    int* waypoint_b
    int* waypoint_c
    int* waypoint_color
    int waypoint_rows
    char* payload_pool
    int payload_used


public def vmeta_new() -> VServerMeta*:
    VServerMeta* meta = new VServerMeta
    meta.stat_category = vt_calloc_int(vmeta_stat_max())
    meta.stat_id = vt_calloc_int(vmeta_stat_max())
    meta.stat_value = vt_calloc_int(vmeta_stat_max())
    meta.stat_rows = 0
    meta.cooldown_names = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.cooldown_ticks = vt_calloc_int(vmeta_named_max())
    meta.cooldown_started = vt_calloc_u64(vmeta_named_max())
    meta.cooldown_rows = 0
    meta.cookie_keys = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.cookie_start = vt_calloc_int(vmeta_named_max())
    meta.cookie_length = vt_calloc_int(vmeta_named_max())
    meta.cookie_rows = 0
    meta.text_pool = vt_calloc_char(vmeta_named_max() * vmeta_text_stride())
    meta.text_used = vt_calloc_int(1)
    meta.pack_uuid_high = vt_calloc_int(vmeta_named_max() * 2)
    meta.pack_uuid_low = vt_calloc_int(vmeta_named_max() * 2)
    meta.pack_url = vt_calloc_int(vmeta_named_max())
    meta.pack_hash = vt_calloc_int(vmeta_named_max())
    meta.pack_required = vt_calloc_int(vmeta_named_max())
    meta.pack_rows = 0
    meta.link_type = vt_calloc_int(vmeta_named_max())
    meta.link_label = vt_calloc_int(vmeta_named_max())
    meta.link_url = vt_calloc_int(vmeta_named_max())
    meta.link_rows = 0
    meta.rule_names = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.rule_values = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.rule_rows = 0
    meta.report_names = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.report_values = vt_calloc_char(vmeta_named_max() * vmeta_id_stride())
    meta.report_rows = 0
    meta.map_id = vt_calloc_int(vmeta_map_max())
    meta.map_scale = vt_calloc_int(vmeta_map_max())
    meta.map_locked = vt_calloc_int(vmeta_map_max())
    meta.map_pixels = vt_calloc_int(vmeta_map_max() * vmeta_map_pixels())
    meta.map_rows = 0
    meta.decoration_map = vt_calloc_int(vmeta_named_max())
    meta.decoration_type = vt_calloc_int(vmeta_named_max())
    meta.decoration_x = vt_calloc_int(vmeta_named_max())
    meta.decoration_y = vt_calloc_int(vmeta_named_max())
    meta.decoration_rot = vt_calloc_int(vmeta_named_max())
    meta.decoration_rows = 0
    meta.trade_window = vmeta_absent()
    meta.trade_cost_a = vt_calloc_int(vmeta_trade_max())
    meta.trade_cost_a_count = vt_calloc_int(vmeta_trade_max())
    meta.trade_cost_b = vt_calloc_int(vmeta_trade_max())
    meta.trade_cost_b_count = vt_calloc_int(vmeta_trade_max())
    meta.trade_result = vt_calloc_int(vmeta_trade_max())
    meta.trade_result_count = vt_calloc_int(vmeta_trade_max())
    meta.trade_uses = vt_calloc_int(vmeta_trade_max())
    meta.trade_max_uses = vt_calloc_int(vmeta_trade_max())
    meta.trade_disabled = vt_calloc_int(vmeta_trade_max())
    meta.trade_rows = 0
    meta.waypoint_names = vt_calloc_char(vmeta_waypoint_max() * vmeta_id_stride())
    meta.waypoint_uuid_high = vt_calloc_int(vmeta_waypoint_max() * 2)
    meta.waypoint_uuid_low = vt_calloc_int(vmeta_waypoint_max() * 2)
    meta.waypoint_kind = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_a = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_b = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_c = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_color = vt_calloc_int(vmeta_waypoint_max())
    meta.waypoint_rows = 0
    meta.payload_pool = vt_calloc_char(vmeta_pool_max())
    meta.payload_used = 0
    return meta


public def vmeta_free(meta: VServerMeta*) -> void:
    if meta == null:
        return
    vt_free(meta.stat_category)
    vt_free(meta.stat_id)
    vt_free(meta.stat_value)
    vt_free(meta.cooldown_names)
    vt_free(meta.cooldown_ticks)
    vt_free(meta.cooldown_started)
    vt_free(meta.cookie_keys)
    vt_free(meta.cookie_start)
    vt_free(meta.cookie_length)
    vt_free(meta.text_pool)
    vt_free(meta.text_used)
    vt_free(meta.pack_uuid_high)
    vt_free(meta.pack_uuid_low)
    vt_free(meta.pack_url)
    vt_free(meta.pack_hash)
    vt_free(meta.pack_required)
    vt_free(meta.link_type)
    vt_free(meta.link_label)
    vt_free(meta.link_url)
    vt_free(meta.rule_names)
    vt_free(meta.rule_values)
    vt_free(meta.report_names)
    vt_free(meta.report_values)
    vt_free(meta.map_id)
    vt_free(meta.map_scale)
    vt_free(meta.map_locked)
    vt_free(meta.map_pixels)
    vt_free(meta.decoration_map)
    vt_free(meta.decoration_type)
    vt_free(meta.decoration_x)
    vt_free(meta.decoration_y)
    vt_free(meta.decoration_rot)
    vt_free(meta.trade_cost_a)
    vt_free(meta.trade_cost_a_count)
    vt_free(meta.trade_cost_b)
    vt_free(meta.trade_cost_b_count)
    vt_free(meta.trade_result)
    vt_free(meta.trade_result_count)
    vt_free(meta.trade_uses)
    vt_free(meta.trade_max_uses)
    vt_free(meta.trade_disabled)
    vt_free(meta.waypoint_names)
    vt_free(meta.waypoint_uuid_high)
    vt_free(meta.waypoint_uuid_low)
    vt_free(meta.waypoint_kind)
    vt_free(meta.waypoint_a)
    vt_free(meta.waypoint_b)
    vt_free(meta.waypoint_c)
    vt_free(meta.waypoint_color)
    vt_free(meta.payload_pool)
    del meta


def vmeta_matches(arena: char*, base: int, body: int64[], offset: int64,
                  length: int64, stride: int) -> int:
    int64 limit = stride - 1
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


def vmeta_store(arena: char*, base: int, body: int64[], offset: int64,
                length: int64, stride: int) -> void:
    int64 limit = stride - 1
    if length > limit:
        length = limit
    if length < 0:
        length = 0
    int64 index = 0
    while index < length:
        vt_put(arena, base + (int)index, (int)(body[offset + index] & 0xFF))
        index = index + 1
    vt_put(arena, base + (int)index, 0)


# Text slots are append-only within a session: the count is small and the
# alternative is a second lifetime to manage for every pushed string.
def vmeta_text_slot(meta: VServerMeta*, body: int64[], offset: int64,
                    length: int64) -> int:
    int used = vt_iget(meta.text_used, 0)
    if used >= vmeta_named_max():
        return vmeta_absent()
    vmeta_store(meta.text_pool, used * vmeta_text_stride(),
                body, offset, length, vmeta_text_stride())
    vt_iset(meta.text_used, 0, used + 1)
    return used


public def vmeta_text_byte(meta: VServerMeta*, slot: int, index: int) -> int:
    if meta == null or slot < 0 or slot >= vt_iget(meta.text_used, 0):
        return 0
    if index < 0 or index >= vmeta_text_stride():
        return 0
    return vt_at(meta.text_pool, slot * vmeta_text_stride() + index)


# --- statistics ---------------------------------------------------------------


public def vmeta_set_stat(meta: VServerMeta*, category: int, id: int,
                          value: int) -> int:
    if meta == null or category < 0 or id < 0:
        return 1
    int row = 0
    while row < meta.stat_rows:
        if vt_iget(meta.stat_category, row) == category:
            if vt_iget(meta.stat_id, row) == id:
                vt_iset(meta.stat_value, row, value)
                return 0
        row = row + 1
    if meta.stat_rows >= vmeta_stat_max():
        return 1
    vt_iset(meta.stat_category, meta.stat_rows, category)
    vt_iset(meta.stat_id, meta.stat_rows, id)
    vt_iset(meta.stat_value, meta.stat_rows, value)
    meta.stat_rows = meta.stat_rows + 1
    return 0


public def vmeta_stat(meta: VServerMeta*, category: int, id: int) -> int:
    if meta == null:
        return 0
    int row = 0
    while row < meta.stat_rows:
        if vt_iget(meta.stat_category, row) == category:
            if vt_iget(meta.stat_id, row) == id:
                return vt_iget(meta.stat_value, row)
        row = row + 1
    return 0


public def vmeta_stat_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.stat_rows


# --- cooldowns ----------------------------------------------------------------


public def vmeta_set_cooldown(meta: VServerMeta*, body: int64[], offset: int64,
                              length: int64, ticks: int, now: int64) -> int:
    if meta == null or ticks < 0:
        return 1
    int row = 0
    while row < meta.cooldown_rows:
        if vmeta_matches(meta.cooldown_names, row * vmeta_id_stride(),
                         body, offset, length, vmeta_id_stride()) == 1:
            break
        row = row + 1
    if row >= vmeta_named_max():
        return 1
    if row == meta.cooldown_rows:
        vmeta_store(meta.cooldown_names, row * vmeta_id_stride(),
                    body, offset, length, vmeta_id_stride())
        meta.cooldown_rows = row + 1
    vt_iset(meta.cooldown_ticks, row, ticks)
    vt_uset(meta.cooldown_started, row, (uint64)now)
    return 0


public def vmeta_cooldown_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.cooldown_rows


public def vmeta_cooldown_ticks(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.cooldown_rows:
        return 0
    return vt_iget(meta.cooldown_ticks, row)


public def vmeta_cooldown_started(meta: VServerMeta*, row: int) -> int64:
    if meta == null or row < 0 or row >= meta.cooldown_rows:
        return (int64)0
    return (int64)vt_uget(meta.cooldown_started, row)


# --- cookies ------------------------------------------------------------------


public def vmeta_set_cookie(meta: VServerMeta*, body: int64[], offset: int64,
                            length: int64, payload: int64[],
                            payload_offset: int64, payload_length: int64) -> int:
    if meta == null or payload_length < 0:
        return 1
    int row = 0
    while row < meta.cookie_rows:
        if vmeta_matches(meta.cookie_keys, row * vmeta_id_stride(),
                         body, offset, length, vmeta_id_stride()) == 1:
            break
        row = row + 1
    if row >= vmeta_named_max():
        return 1
    if meta.payload_used + (int)payload_length > vmeta_pool_max():
        return 1
    if row == meta.cookie_rows:
        vmeta_store(meta.cookie_keys, row * vmeta_id_stride(),
                    body, offset, length, vmeta_id_stride())
        meta.cookie_rows = row + 1
    int64 index = 0
    while index < payload_length:
        vt_put(meta.payload_pool, meta.payload_used + (int)index,
               (int)(payload[payload_offset + index] & 0xFF))
        index = index + 1
    vt_iset(meta.cookie_start, row, meta.payload_used)
    vt_iset(meta.cookie_length, row, (int)payload_length)
    meta.payload_used = meta.payload_used + (int)payload_length
    return 0


public def vmeta_cookie_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.cookie_rows


public def vmeta_cookie_find(meta: VServerMeta*, body: int64[], offset: int64,
                             length: int64) -> int:
    if meta == null:
        return vmeta_absent()
    int row = 0
    while row < meta.cookie_rows:
        if vmeta_matches(meta.cookie_keys, row * vmeta_id_stride(),
                         body, offset, length, vmeta_id_stride()) == 1:
            return row
        row = row + 1
    return vmeta_absent()


public def vmeta_cookie_length(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.cookie_rows:
        return 0
    return vt_iget(meta.cookie_length, row)


public def vmeta_cookie_byte(meta: VServerMeta*, row: int, index: int) -> int:
    if meta == null or row < 0 or row >= meta.cookie_rows:
        return 0
    if index < 0 or index >= vt_iget(meta.cookie_length, row):
        return 0
    return vt_at(meta.payload_pool, vt_iget(meta.cookie_start, row) + index)


# --- resource packs -----------------------------------------------------------


public def vmeta_push_pack(meta: VServerMeta*, uuid_high: int64[],
                           uuid_low: int64[], url: int64[], url_offset: int64,
                           url_length: int64, hash: int64[], hash_offset: int64,
                           hash_length: int64, required: bool) -> int:
    if meta == null:
        return 1
    int row = 0
    while row < meta.pack_rows:
        if vt_iget(meta.pack_uuid_high, row * 2) == (int)uuid_high[0]:
            if vt_iget(meta.pack_uuid_low, row * 2) == (int)uuid_low[0]:
                break
        row = row + 1
    if row >= vmeta_named_max():
        return 1
    int url_slot = vmeta_text_slot(meta, url, url_offset, url_length)
    int hash_slot = vmeta_text_slot(meta, hash, hash_offset, hash_length)
    if url_slot == vmeta_absent() or hash_slot == vmeta_absent():
        return 1
    if row == meta.pack_rows:
        meta.pack_rows = row + 1
    vt_iset(meta.pack_uuid_high, row * 2, (int)uuid_high[0])
    vt_iset(meta.pack_uuid_high, row * 2 + 1, (int)uuid_high[1])
    vt_iset(meta.pack_uuid_low, row * 2, (int)uuid_low[0])
    vt_iset(meta.pack_uuid_low, row * 2 + 1, (int)uuid_low[1])
    vt_iset(meta.pack_url, row, url_slot)
    vt_iset(meta.pack_hash, row, hash_slot)
    int flag = 0
    if required:
        flag = 1
    vt_iset(meta.pack_required, row, flag)
    return row


# A zero UUID pops every pack; the arrays hold two 32-bit halves each.
public def vmeta_pop_pack(meta: VServerMeta*, uuid_high: int64[],
                          uuid_low: int64[], present: bool) -> int:
    if meta == null:
        return 1
    if not present:
        meta.pack_rows = 0
        return 0
    int row = 0
    while row < meta.pack_rows:
        if vt_iget(meta.pack_uuid_high, row * 2) == (int)uuid_high[0]:
            if vt_iget(meta.pack_uuid_low, row * 2) == (int)uuid_low[0]:
                int last = meta.pack_rows - 1
                while row < last:
                    vt_iset(meta.pack_uuid_high, row * 2,
                            vt_iget(meta.pack_uuid_high, (row + 1) * 2))
                    vt_iset(meta.pack_uuid_high, row * 2 + 1,
                            vt_iget(meta.pack_uuid_high, (row + 1) * 2 + 1))
                    vt_iset(meta.pack_uuid_low, row * 2,
                            vt_iget(meta.pack_uuid_low, (row + 1) * 2))
                    vt_iset(meta.pack_uuid_low, row * 2 + 1,
                            vt_iget(meta.pack_uuid_low, (row + 1) * 2 + 1))
                    vt_iset(meta.pack_url, row, vt_iget(meta.pack_url, row + 1))
                    vt_iset(meta.pack_hash, row, vt_iget(meta.pack_hash, row + 1))
                    vt_iset(meta.pack_required, row,
                            vt_iget(meta.pack_required, row + 1))
                    row = row + 1
                meta.pack_rows = last
                return 0
        row = row + 1
    return 0


public def vmeta_pack_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.pack_rows


public def vmeta_pack_required(meta: VServerMeta*, row: int) -> bool:
    if meta == null or row < 0 or row >= meta.pack_rows:
        return false
    return vt_iget(meta.pack_required, row) != 0


public def vmeta_pack_url_slot(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.pack_rows:
        return vmeta_absent()
    return vt_iget(meta.pack_url, row)


# --- links and report details -------------------------------------------------


public def vmeta_reset_links(meta: VServerMeta*) -> int:
    if meta == null:
        return 1
    meta.link_rows = 0
    return 0


public def vmeta_add_link(meta: VServerMeta*, known: int, label: int64[],
                          label_offset: int64, label_length: int64,
                          url: int64[], url_offset: int64,
                          url_length: int64) -> int:
    if meta == null or meta.link_rows >= vmeta_named_max():
        return 1
    int label_slot = 0
    if label_length >= 0:
        label_slot = vmeta_text_slot(meta, label, label_offset, label_length)
        if label_slot == vmeta_absent():
            return 1
    int url_slot = vmeta_text_slot(meta, url, url_offset, url_length)
    if url_slot == vmeta_absent():
        return 1
    vt_iset(meta.link_type, meta.link_rows, known)
    vt_iset(meta.link_label, meta.link_rows, label_slot)
    vt_iset(meta.link_url, meta.link_rows, url_slot)
    meta.link_rows = meta.link_rows + 1
    return 0


public def vmeta_link_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.link_rows


public def vmeta_link_type(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.link_rows:
        return vmeta_absent()
    return vt_iget(meta.link_type, row)


public def vmeta_link_url_slot(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.link_rows:
        return vmeta_absent()
    return vt_iget(meta.link_url, row)


public def vmeta_reset_report(meta: VServerMeta*) -> int:
    if meta == null:
        return 1
    meta.report_rows = 0
    return 0


# Game rules arrive as a partial map the client merges into its own rules, so
# there is no reset: a rule the server stops sending keeps its last value.
public def vmeta_set_pair(meta: VServerMeta*, name: int64[], name_offset: int64,
                          name_length: int64, value: int64[],
                          value_offset: int64, value_length: int64) -> int:
    if meta == null:
        return 1
    int row = 0
    while row < meta.rule_rows:
        if vmeta_matches(meta.rule_names, row * vmeta_id_stride(),
                         name, name_offset, name_length, vmeta_id_stride()) == 1:
            break
        row = row + 1
    if row >= vmeta_named_max():
        return 1
    if row == meta.rule_rows:
        vmeta_store(meta.rule_names, row * vmeta_id_stride(),
                    name, name_offset, name_length, vmeta_id_stride())
        meta.rule_rows = row + 1
    vmeta_store(meta.rule_values, row * vmeta_id_stride(),
                value, value_offset, value_length, vmeta_id_stride())
    return 0


public def vmeta_pair_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.rule_rows


public def vmeta_pair_value_byte(meta: VServerMeta*, row: int,
                                 index: int) -> int:
    if meta == null or row < 0 or row >= meta.rule_rows:
        return 0
    if index < 0 or index >= vmeta_id_stride():
        return 0
    return vt_at(meta.rule_values, row * vmeta_id_stride() + index)


# Report details are a whole-map replacement, unlike game rules, and a server
# sends both in one session, so they get their own arenas.
public def vmeta_set_report_pair(meta: VServerMeta*, name: int64[],
                                 name_offset: int64, name_length: int64,
                                 value: int64[], value_offset: int64,
                                 value_length: int64) -> int:
    if meta == null:
        return 1
    int row = meta.report_rows
    if row >= vmeta_named_max():
        return 1
    vmeta_store(meta.report_names, row * vmeta_id_stride(),
                name, name_offset, name_length, vmeta_id_stride())
    vmeta_store(meta.report_values, row * vmeta_id_stride(),
                value, value_offset, value_length, vmeta_id_stride())
    meta.report_rows = row + 1
    return 0


public def vmeta_report_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.report_rows


public def vmeta_report_value_byte(meta: VServerMeta*, row: int,
                                   index: int) -> int:
    if meta == null or row < 0 or row >= meta.report_rows:
        return 0
    if index < 0 or index >= vmeta_id_stride():
        return 0
    return vt_at(meta.report_values, row * vmeta_id_stride() + index)


# --- maps ---------------------------------------------------------------------


def vmeta_map_row(meta: VServerMeta*, id: int) -> int:
    int row = 0
    while row < meta.map_rows:
        if vt_iget(meta.map_id, row) == id:
            return row
        row = row + 1
    if meta.map_rows >= vmeta_map_max():
        return vmeta_absent()
    row = meta.map_rows
    meta.map_rows = row + 1
    vt_iset(meta.map_id, row, id)
    vt_iset(meta.map_scale, row, 0)
    vt_iset(meta.map_locked, row, 0)
    return row


public def vmeta_map_header(meta: VServerMeta*, id: int, scale: int,
                            locked: bool) -> int:
    if meta == null or id < 0:
        return vmeta_absent()
    int row = vmeta_map_row(meta, id)
    if row == vmeta_absent():
        return vmeta_absent()
    vt_iset(meta.map_scale, row, scale)
    int flag = 0
    if locked:
        flag = 1
    vt_iset(meta.map_locked, row, flag)
    return row


# A colour patch is width x height bytes laid down at (start_x, start_y) in the
# 128x128 map canvas.
public def vmeta_map_patch(meta: VServerMeta*, row: int, start_x: int,
                           start_y: int, width: int, height: int,
                           colors: int64[], offset: int64) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 1
    if start_x < 0 or (start_y < 0 or width < 0 or height < 0):
        return 1
    if start_x + width > 128 or start_y + height > 128:
        return 1
    int y = 0
    while y < height:
        int x = 0
        while x < width:
            int cell = (start_y + y) * 128 + start_x + x
            vt_iset(meta.map_pixels, row * vmeta_map_pixels() + cell,
                    (int)(colors[offset + (int64)y * (int64)width + (int64)x] & 0xFF))
            x = x + 1
        y = y + 1
    return 0


public def vmeta_map_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.map_rows


public def vmeta_map_pixel(meta: VServerMeta*, row: int, x: int, y: int) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 0
    if x < 0 or (x >= 128 or y < 0 or y >= 128):
        return 0
    return vt_iget(meta.map_pixels, row * vmeta_map_pixels() + y * 128 + x)


public def vmeta_map_scale(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 0
    return vt_iget(meta.map_scale, row)


public def vmeta_reset_decorations(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 1
    int kept = 0
    int scan = 0
    while scan < meta.decoration_rows:
        if vt_iget(meta.decoration_map, scan) != row:
            if kept != scan:
                vt_iset(meta.decoration_map, kept, vt_iget(meta.decoration_map, scan))
                vt_iset(meta.decoration_type, kept, vt_iget(meta.decoration_type, scan))
                vt_iset(meta.decoration_x, kept, vt_iget(meta.decoration_x, scan))
                vt_iset(meta.decoration_y, kept, vt_iget(meta.decoration_y, scan))
                vt_iset(meta.decoration_rot, kept, vt_iget(meta.decoration_rot, scan))
            kept = kept + 1
        scan = scan + 1
    meta.decoration_rows = kept
    return 0


public def vmeta_add_decoration(meta: VServerMeta*, row: int, kind: int,
                                x: int, y: int, rot: int) -> int:
    if meta == null or row < 0 or row >= meta.map_rows:
        return 1
    if meta.decoration_rows >= vmeta_named_max():
        return 1
    vt_iset(meta.decoration_map, meta.decoration_rows, row)
    vt_iset(meta.decoration_type, meta.decoration_rows, kind)
    vt_iset(meta.decoration_x, meta.decoration_rows, x)
    vt_iset(meta.decoration_y, meta.decoration_rows, y)
    vt_iset(meta.decoration_rot, meta.decoration_rows, rot)
    meta.decoration_rows = meta.decoration_rows + 1
    return 0


public def vmeta_decoration_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.decoration_rows


# --- merchant offers ----------------------------------------------------------


public def vmeta_reset_trades(meta: VServerMeta*, window: int) -> int:
    if meta == null:
        return 1
    meta.trade_window = window
    meta.trade_rows = 0
    return 0


public def vmeta_add_trade(meta: VServerMeta*, cost_a: int, cost_a_count: int,
                           cost_b: int, cost_b_count: int, result: int,
                           result_count: int, uses: int, max_uses: int,
                           disabled: bool) -> int:
    if meta == null or meta.trade_rows >= vmeta_trade_max():
        return 1
    int row = meta.trade_rows
    vt_iset(meta.trade_cost_a, row, cost_a)
    vt_iset(meta.trade_cost_a_count, row, cost_a_count)
    vt_iset(meta.trade_cost_b, row, cost_b)
    vt_iset(meta.trade_cost_b_count, row, cost_b_count)
    vt_iset(meta.trade_result, row, result)
    vt_iset(meta.trade_result_count, row, result_count)
    vt_iset(meta.trade_uses, row, uses)
    vt_iset(meta.trade_max_uses, row, max_uses)
    int flag = 0
    if disabled:
        flag = 1
    vt_iset(meta.trade_disabled, row, flag)
    meta.trade_rows = row + 1
    return 0


public def vmeta_set_merchant(meta: VServerMeta*, level: int, xp: int,
                              progress: bool, restock: bool) -> int:
    if meta == null:
        return 1
    meta.merchant_level = level
    meta.merchant_xp = xp
    meta.merchant_progress = progress
    meta.merchant_restock = restock
    return 0


public def vmeta_trade_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.trade_rows


public def vmeta_trade_result(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.trade_rows:
        return vmeta_absent()
    return vt_iget(meta.trade_result, row)


public def vmeta_trade_available(meta: VServerMeta*, row: int) -> bool:
    if meta == null or row < 0 or row >= meta.trade_rows:
        return false
    if vt_iget(meta.trade_disabled, row) != 0:
        return false
    return vt_iget(meta.trade_uses, row) < vt_iget(meta.trade_max_uses, row)


# --- waypoints ----------------------------------------------------------------


def vmeta_waypoint_find(meta: VServerMeta*, body: int64[], offset: int64,
                        length: int64) -> int:
    int row = 0
    while row < meta.waypoint_rows:
        if vmeta_matches(meta.waypoint_names, row * vmeta_id_stride(),
                         body, offset, length, vmeta_id_stride()) == 1:
            return row
        row = row + 1
    return vmeta_absent()


# `name_length` < 0 keys the waypoint by UUID instead of by name.
public def vmeta_track_waypoint(meta: VServerMeta*, body: int64[], offset: int64,
                                length: int64, uuid_high: int64[],
                                uuid_low: int64[], kind: int, a: int, b: int,
                                c: int, color: int) -> int:
    if meta == null or kind < 0 or kind > 3:
        return 1
    int row = vmeta_absent()
    if length >= 0:
        row = vmeta_waypoint_find(meta, body, offset, length)
    else:
        int scan = 0
        while scan < meta.waypoint_rows:
            if vt_iget(meta.waypoint_uuid_high, scan * 2) == (int)uuid_high[0]:
                if vt_iget(meta.waypoint_uuid_low, scan * 2) == (int)uuid_low[0]:
                    row = scan
                    break
            scan = scan + 1
    if row == vmeta_absent():
        if meta.waypoint_rows >= vmeta_waypoint_max():
            return 1
        row = meta.waypoint_rows
        meta.waypoint_rows = row + 1
        vmeta_store(meta.waypoint_names, row * vmeta_id_stride(),
                    body, offset, length, vmeta_id_stride())
    vt_iset(meta.waypoint_uuid_high, row * 2, (int)uuid_high[0])
    vt_iset(meta.waypoint_uuid_high, row * 2 + 1, (int)uuid_high[1])
    vt_iset(meta.waypoint_uuid_low, row * 2, (int)uuid_low[0])
    vt_iset(meta.waypoint_uuid_low, row * 2 + 1, (int)uuid_low[1])
    vt_iset(meta.waypoint_kind, row, kind)
    vt_iset(meta.waypoint_a, row, a)
    vt_iset(meta.waypoint_b, row, b)
    vt_iset(meta.waypoint_c, row, c)
    vt_iset(meta.waypoint_color, row, color)
    return row


public def vmeta_untrack_waypoint(meta: VServerMeta*, body: int64[],
                                  offset: int64, length: int64,
                                  uuid_high: int64[], uuid_low: int64[]) -> int:
    if meta == null:
        return 1
    int row = vmeta_absent()
    if length >= 0:
        row = vmeta_waypoint_find(meta, body, offset, length)
    else:
        int scan = 0
        while scan < meta.waypoint_rows:
            if vt_iget(meta.waypoint_uuid_high, scan * 2) == (int)uuid_high[0]:
                if vt_iget(meta.waypoint_uuid_low, scan * 2) == (int)uuid_low[0]:
                    row = scan
                    break
            scan = scan + 1
    if row == vmeta_absent():
        return 0
    int last = meta.waypoint_rows - 1
    while row < last:
        int index = 0
        while index < vmeta_id_stride():
            vt_put(meta.waypoint_names, row * vmeta_id_stride() + index,
                   vt_at(meta.waypoint_names, (row + 1) * vmeta_id_stride() + index))
            index = index + 1
        vt_iset(meta.waypoint_kind, row, vt_iget(meta.waypoint_kind, row + 1))
        vt_iset(meta.waypoint_a, row, vt_iget(meta.waypoint_a, row + 1))
        vt_iset(meta.waypoint_b, row, vt_iget(meta.waypoint_b, row + 1))
        vt_iset(meta.waypoint_c, row, vt_iget(meta.waypoint_c, row + 1))
        vt_iset(meta.waypoint_color, row, vt_iget(meta.waypoint_color, row + 1))
        index = 0
        while index < 2:
            vt_iset(meta.waypoint_uuid_high, row * 2 + index,
                    vt_iget(meta.waypoint_uuid_high, (row + 1) * 2 + index))
            vt_iset(meta.waypoint_uuid_low, row * 2 + index,
                    vt_iget(meta.waypoint_uuid_low, (row + 1) * 2 + index))
            index = index + 1
        row = row + 1
    meta.waypoint_rows = last
    return 0


public def vmeta_waypoint_rows(meta: VServerMeta*) -> int:
    if meta == null:
        return 0
    return meta.waypoint_rows


public def vmeta_waypoint_kind(meta: VServerMeta*, row: int) -> int:
    if meta == null or row < 0 or row >= meta.waypoint_rows:
        return vmeta_absent()
    return vt_iget(meta.waypoint_kind, row)


public def vmeta_waypoint_axis(meta: VServerMeta*, row: int, axis: int) -> int:
    if meta == null or row < 0 or row >= meta.waypoint_rows:
        return 0
    if axis == 0:
        return vt_iget(meta.waypoint_a, row)
    if axis == 1:
        return vt_iget(meta.waypoint_b, row)
    if axis == 2:
        return vt_iget(meta.waypoint_c, row)
    return 0
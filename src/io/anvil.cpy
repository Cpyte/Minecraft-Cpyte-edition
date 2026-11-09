# Vortex engine - Anvil region storage and the chunk NBT schema.
#
# Anvil is the layout every Java Edition world keeps chunks in, so saving a
# world here means producing a file the game can open. The rules:
#
#   offset  size    what
#   0       4096    location table: 1024 big endian entries, three bytes of
#                   sector offset plus one byte of sector count, indexed by
#                   (x & 31) + (z & 31) * 32
#   4096    4096    modification time table: 1024 big endian int32 seconds
#   8192    ...     4 KiB sectors, numbered from 0, chunk data starts at 2
#
#   record          int32 big endian payload length - counting the compression
#                   byte - then the compression byte, then the chunk's NBT
#
# Inside a record the chunk is a TAG_Compound with an empty name. This module
# writes the modern schema: DataVersion, sections of {Y, block_states, biomes,
# BlockLight, SkyLight}, Heightmaps, TileEntities, Entities, Status, Version,
# xPos, yPos, zPos. Reading also accepts the 1.13-1.17 `Level` wrapper, its
# `Palette`/`BlockData` containers and `Light` spelling, and the pre-1.13
# direct `Blocks`/`Add` byte arrays, so an older world still loads.
#
# Palette entries are where compatibility bites. The game writes a block
# palette as compounds of {Name, Properties} and a biome palette as
# namespaced id strings, while the engine's containers hold numeric ids. The
# mapping lives in an optional registry table (anvil_registry_load): one line
# per entry, produced from the vanilla data reports by the same auto-setup
# that builds the block database. Without it a palette is written as plain
# ids, which this engine round-trips but the game does not read, and the
# counter in anvil_lossy_palettes says so rather than hiding it.
#
# Everything this client cannot know - tile entity and entity payloads,
# structures, light population - is kept exactly as the file had it: a chunk
# being replaced starts from a copy of the compound it was stored in, so only
# the fields the engine really models are rewritten. A load, edit and save
# cycle therefore loses nothing it did not deliberately change.
#
# License boundary: no Mojang-derived code or data. See docs/PARITY_BOUNDARY.md.

import "region_io.c"
import stdlib


# ---- format constants --------------------------------------------------------

public def anvil_sector_bytes() -> int:
    return 4096


public def anvil_region_chunks() -> int:
    return 1024


public def anvil_header_bytes() -> int:
    return 8192


# Chunk sectors start after the two header sectors.
public def anvil_first_sector() -> int:
    return 2


# The location table gives one byte of sector count, and 0 means absent.
public def anvil_max_sectors() -> int:
    return 255


# The `Version` byte the game writes for a chunk it finished generating.
public def anvil_format_version() -> int:
    return 8


public def anvil_status_full() -> str:
    return "minecraft:full"


# Chunk record compression bytes.
public def anvil_comp_gzip() -> int:
    return 32


public def anvil_comp_zlib() -> int:
    return 33


public def anvil_comp_none() -> int:
    return 34


# The DataVersion written when the caller sets none. Chunk upgrades key off
# this number and the value for the 26.3 profile is not published, so it is
# data the caller owns rather than something invented here: 0 claims no
# upgrade history, which is what a client that only reads its own worlds needs.
public def anvil_default_data_version() -> int64:
    return (int64)0


public def anvil_palette_numeric() -> int:
    return 0


public def anvil_palette_named() -> int:
    return 1


public def anvil_palette_string() -> int:
    return 2


# Registry row kinds.
public def anvil_kind_state() -> int:
    return 0


public def anvil_kind_biome() -> int:
    return 1


# The five heightmap kinds, in the order the schema lists them.
public def anvil_hm_count() -> int:
    return 5


def anvil_hm_name(kind: int) -> str:
    if kind == 0:
        return "MOTION_BLOCKING"
    if kind == 1:
        return "MOTION_BLOCKING_NO_LEAVES"
    if kind == 2:
        return "OCEAN_FLOOR"
    if kind == 3:
        return "OCEAN_FLOOR_AGED"
    if kind == 4:
        return "WORLD_SURFACE"
    return ""


# Which heightmap kinds an engine column carries, or -1 for the ones it does
# not store and therefore has to recompute from the blocks.
def anvil_hm_engine_kind(kind: int) -> int:
    if kind == 0:
        return hm_motion_blocking()
    if kind == 4:
        return hm_world_surface()
    return -1


# Chunk record chunk: 4 length bytes, 1 compression byte, then the payload.
def anvil_record_overhead() -> int:
    return 5


# ---- the state and biome name table ------------------------------------------

struct VRegistry:
    int rows
    int state_count           # one past the highest block state id
    int biome_count
    str blob                  # names and property strings, concatenated
    int* kind
    int* id
    int* name_off
    int* name_len
    int* props_off
    int* props_len
    int* state_at             # state id -> row + 1
    int* biome_at             # biome id -> row + 1
    int* slots                # (name, properties) -> row + 1
    int slot_cap


def anvil_registry_stride() -> int:
    return 6


# The bracket codes: core.cpy has no constants for them.
def anvil_code_bracket_open() -> int:
    return 91


def anvil_code_bracket_close() -> int:
    return 93


# One parsed table line. `out` is the six fields anvil_registry_stride counts:
# kind (-1 when the line is not a row), id, name start, name end, properties
# start and properties end, the last four offsets inside `line`.
def anvil_parse_line(line: str, out: int*) -> void:
    int n = vt_strlen(line)
    vt_iset(out, 0, -1)
    vt_iset(out, 1, -1)
    if n < 4:
        return
    int first = vt_at(line, 0)
    int kind = -1
    if first == 66 or first == 98:
        kind = anvil_kind_state()
    if first == 73 or first == 105:
        kind = anvil_kind_biome()
    if kind < 0:
        return
    if vt_at(line, 1) != code_space():
        return
    int space = str_find_code(line, 2, code_space())
    if space < 0:
        return
    int ok = 0
    str id_text = str_slice(line, 2, space)
    int id = parse_int_or(id_text, -1, &ok)
    vt_free((void*)id_text)
    if ok == 0 or id < 0 or id > 1048576:
        return
    int rest = space + 1
    while rest < n and vt_at(line, rest) == code_space():
        rest = rest + 1
    int open = str_find_code(line, rest, anvil_code_bracket_open())
    int name_end = n
    int props_start = n
    int props_end = n
    if open >= 0:
        name_end = open
        props_start = open + 1
        int close = str_find_code(line, props_start, anvil_code_bracket_close())
        if close < 0:
            props_end = n
        else:
            props_end = close
    if rest >= name_end:
        return
    vt_iset(out, 0, kind)
    vt_iset(out, 1, (int)id)
    vt_iset(out, 2, rest)
    vt_iset(out, 3, name_end)
    vt_iset(out, 4, props_start)
    vt_iset(out, 5, props_end)


def anvil_pairs_sorted(pairs: str[]) -> void:
    int n = (int)len(pairs)
    int i = 1
    while i < n:
        str key = pairs[i]
        int j = i - 1
        while j >= 0 and str_compare(pairs[j], key) > 0:
            pairs[j + 1] = pairs[j]
            j = j - 1
        pairs[j + 1] = key
        i = i + 1


# Releases the heap strings a pair array holds. Both producers hand their
# entries over when they call anvil_props_sorted, so the sorted text is built
# and the originals dropped in one place.
def anvil_pairs_release(pairs: str[]) -> void:
    int i = 0
    int n = (int)len(pairs)
    while i < n:
        vt_free((void*)pairs[i])
        i = i + 1


# The canonical property text: every `key=value` pair in alphabetical order by
# key, comma separated. Sorting both sides means a compound written by another
# tool in another order still matches the table.
def anvil_props_sorted(pairs: str[]) -> str:
    int n = (int)len(pairs)
    VStr* sink = vstr_new(64)
    int i = 0
    while i < n:
        if i > 0:
            vstr_put(sink, code_comma())
        vstr_put_text(sink, pairs[i])
        i = i + 1
    str result = vstr_text(sink)
    vstr_free(sink)
    return result


def anvil_props_canonical(text: str, from: int, to: int) -> str:
    str[] pairs = new str[0]
    int at = from
    while at < to:
        int stop = str_find_code(text, at, code_comma())
        if stop < 0 or stop >= to:
            stop = to
        str source = str_slice(text, at, stop)
        str pair = str_trim(source)
        vt_free((void*)source)
        if vt_strlen(pair) > 0:
            append(pairs, pair)
        else:
            vt_free((void*)pair)
        at = stop + 1
    anvil_pairs_sorted(pairs)
    str sorted = anvil_props_sorted(pairs)
    anvil_pairs_release(pairs)
    return sorted


# A property value as text: the game writes strings, and older tools have been
# seen writing bytes or bools, so every scalar form is accepted.
def anvil_prop_text(t: VNbt*) -> str:
    if t == null:
        return ""
    if t.kind == nbt_string():
        return t.val_str
    if t.kind == nbt_byte():
        if t.val_int != 0:
            return "true"
        return "false"
    if t.kind == nbt_short() or t.kind == nbt_int():
        return str(t.val_int)
    if t.kind == nbt_long():
        return str(t.val_long)
    return ""


# The same, from a Properties compound.
def anvil_props_from_compound(t: VNbt*) -> str:
    str[] pairs = new str[0]
    if t == null or t.kind != nbt_compound():
        return ""
    int i = 0
    while i < t.items_len:
        VNbt* child = (VNbt*)vt_ptr_get(t.items, i)
        if child != null:
            str value = anvil_prop_text(child)
            VStr* pair = vstr_new(32)
            vstr_put_text(pair, child.name)
            vstr_put(pair, code_equals())
            vstr_put_text(pair, value)
            append(pairs, vstr_text(pair))
            vstr_free(pair)
        i = i + 1
    anvil_pairs_sorted(pairs)
    str sorted = anvil_props_sorted(pairs)
    anvil_pairs_release(pairs)
    return sorted


def anvil_blob_equals(blob: str, off: int, length: int, query: str) -> int:
    int n = vt_strlen(query)
    if n != length:
        return 0
    int i = 0
    while i < n:
        if vt_at(blob, off + i) != vt_at(query, i):
            return 0
        i = i + 1
    return 1


# -1 when the table has no row for this (name, properties) pair. The probe is a
# linear walk from an FNV slot over `name,properties`, the same text the table
# indexes, so both sides agree on what a row is called.
def anvil_registry_find(a: VAnvil*, kind: int, name: str, props: str) -> int:
    VRegistry* r = null
    if a != null:
        r = a.registry
    if r == null or r.rows <= 0:
        return -1
    int mask = r.slot_cap - 1
    # The probe key is the `name,properties` text the table indexes. Assembling
    # it in a sink that is freed here keeps a lookup from leaving a
    # concatenation behind for every palette entry decoded.
    VStr* key = vstr_new(64)
    vstr_put_text(key, name)
    vstr_put(key, code_comma())
    vstr_put_text(key, props)
    uint64 hash = vstr_hash(key) & (uint64)mask
    vstr_free(key)
    int slot = (int)hash
    int probe = 0
    while probe < r.slot_cap:
        int row = vt_iget(r.slots, slot) - 1
        if row < 0:
            return -1
        if vt_iget(r.kind, row) == kind:
            if anvil_blob_equals(r.blob, vt_iget(r.name_off, row),
                                 vt_iget(r.name_len, row), name) == 1:
                if anvil_blob_equals(r.blob, vt_iget(r.props_off, row),
                                     vt_iget(r.props_len, row), props) == 1:
                    return row
        slot = slot + 1
        if slot >= r.slot_cap:
            slot = 0
        probe = probe + 1
    return -1


def anvil_registry_row_id(r: VRegistry*, row: int) -> int:
    if r == null or row < 0 or row >= r.rows:
        return -1
    return vt_iget(r.id, row)


# The row for a numeric id, or -1.
def anvil_registry_row_of(a: VAnvil*, kind: int, id: int) -> int:
    VRegistry* r = null
    if a != null:
        r = a.registry
    if r == null or id < 0:
        return -1
    if kind == anvil_kind_state():
        if id >= r.state_count:
            return -1
        return vt_iget(r.state_at, id) - 1
    if id >= r.biome_count:
        return -1
    return vt_iget(r.biome_at, id) - 1


def anvil_registry_free(r: VRegistry*) -> void:
    if r == null:
        return
    vt_free((void*)r.kind)
    vt_free((void*)r.id)
    vt_free((void*)r.name_off)
    vt_free((void*)r.name_len)
    vt_free((void*)r.props_off)
    vt_free((void*)r.props_len)
    vt_free((void*)r.state_at)
    vt_free((void*)r.biome_at)
    vt_free((void*)r.slots)
    # vstr_text hands over a heap copy, so the blob belongs to this registry:
    # it holds every name and property string, and dropping the pointer would
    # keep all of them alive.
    vt_free((void*)r.blob)
    r.blob = ""
    r.rows = 0
    del r


# The table's default location, which is the folder the block database lives
# in: the auto-setup writes both files together.
public def anvil_registry_default_path() -> str:
    return vt_env_or("VORTEX_REGISTRY_TABLE", "generated/registry.txt")


# Counted rows, highest state id and highest biome id, so the arrays can be
# sized exactly before the fill pass parses every line a second time.
def anvil_registry_scan(text: str, out: int*) -> void:
    int n = vt_strlen(text)
    VStr* line = vstr_new(256)
    int* line_info = vt_calloc_int(anvil_registry_stride())
    int at = 0
    vt_iset(out, 0, 0)
    vt_iset(out, 1, 0)
    vt_iset(out, 2, 0)
    while at < n:
        int stop = at
        while stop < n and vt_at(text, stop) != code_newline():
            stop = stop + 1
        vstr_clear(line)
        vstr_put_trimmed_slice(line, text, at, stop)
        anvil_parse_line((str)line.data, line_info)
        if vt_iget(line_info, 0) >= 0:
            vt_iset(out, 0, vt_iget(out, 0) + 1)
            if vt_iget(line_info, 0) == anvil_kind_state():
                if vt_iget(line_info, 1) + 1 > vt_iget(out, 1):
                    vt_iset(out, 1, vt_iget(line_info, 1) + 1)
            else:
                if vt_iget(line_info, 1) + 1 > vt_iget(out, 2):
                    vt_iset(out, 2, vt_iget(line_info, 1) + 1)
        at = stop + 1
    vstr_free(line)
    vt_free((void*)line_info)


def anvil_registry_build(text: str) -> VRegistry*:
    int* counts = vt_calloc_int(3)
    anvil_registry_scan(text, counts)
    int rows = vt_iget(counts, 0)
    int state_count = vt_iget(counts, 1)
    int biome_count = vt_iget(counts, 2)
    vt_free((void*)counts)
    if rows <= 0:
        return null
    if state_count > 1048577:
        state_count = 1048577
    if biome_count > 1048577:
        biome_count = 1048577

    VRegistry* r = new VRegistry
    r.rows = 0
    r.state_count = state_count
    r.biome_count = biome_count
    r.kind = vt_calloc_int(rows)
    r.id = vt_calloc_int(rows)
    r.name_off = vt_calloc_int(rows)
    r.name_len = vt_calloc_int(rows)
    r.props_off = vt_calloc_int(rows)
    r.props_len = vt_calloc_int(rows)
    r.state_at = vt_calloc_int(state_count)
    r.biome_at = vt_calloc_int(biome_count)
    r.slot_cap = 64
    while r.slot_cap < rows * 4:
        r.slot_cap = r.slot_cap * 2
    r.slots = vt_calloc_int(r.slot_cap)

    # Names and property strings all live in one blob, so a row is four
    # integers rather than two owned allocations, and the name is copied
    # straight from the table line into it. One reused line buffer serves the
    # whole pass.
    VStr* blob = vstr_new(4096)
    int n = vt_strlen(text)
    int* line_info = vt_calloc_int(anvil_registry_stride())
    VStr* line = vstr_new(256)
    int at = 0
    while at < n:
        int stop = at
        while stop < n and vt_at(text, stop) != code_newline():
            stop = stop + 1
        vstr_clear(line)
        vstr_put_trimmed_slice(line, text, at, stop)
        anvil_parse_line((str)line.data, line_info)
        if vt_iget(line_info, 0) >= 0:
            int row = r.rows
            str props = anvil_props_canonical((str)line.data, vt_iget(line_info, 4),
                                              vt_iget(line_info, 5))
            vt_iset(r.kind, row, vt_iget(line_info, 0))
            vt_iset(r.id, row, vt_iget(line_info, 1))
            vt_iset(r.name_off, row, blob.len)
            vstr_put_slice(blob, (str)line.data, vt_iget(line_info, 2),
                           vt_iget(line_info, 3))
            vt_iset(r.name_len, row, blob.len - vt_iget(r.name_off, row))
            vt_iset(r.props_off, row, blob.len)
            vt_iset(r.props_len, row, vt_strlen(props))
            vstr_put_text(blob, props)
            vt_free((void*)props)
            if vt_iget(line_info, 0) == anvil_kind_state():
                if vt_iget(line_info, 1) < r.state_count:
                    vt_iset(r.state_at, vt_iget(line_info, 1), row + 1)
            else:
                if vt_iget(line_info, 1) < r.biome_count:
                    vt_iset(r.biome_at, vt_iget(line_info, 1), row + 1)
            r.rows = row + 1
        at = stop + 1
    vstr_free(line)
    vt_free((void*)line_info)
    r.blob = vstr_text(blob)
    vstr_free(blob)

    # Slots are indexed by the same `name,properties` text a lookup probes
    # with, assembled here in a sink that is reused for every row.
    int i = 0
    int mask = r.slot_cap - 1
    VStr* key = vstr_new(64)
    while i < r.rows:
        vstr_clear(key)
        vstr_put_slice(key, r.blob, vt_iget(r.name_off, i),
                       vt_iget(r.name_off, i) + vt_iget(r.name_len, i))
        vstr_put(key, code_comma())
        vstr_put_slice(key, r.blob, vt_iget(r.props_off, i),
                       vt_iget(r.props_off, i) + vt_iget(r.props_len, i))
        int slot = (int)(vstr_hash(key) & (uint64)mask)
        int probe = 0
        int placed = 0
        while probe < r.slot_cap and placed == 0:
            if vt_iget(r.slots, slot) == 0:
                vt_iset(r.slots, slot, i + 1)
                placed = 1
            else:
                slot = slot + 1
                if slot >= r.slot_cap:
                    slot = 0
            probe = probe + 1
        i = i + 1
    vstr_free(key)
    return r


# Reads the table from disk and installs it, replacing any previous one. A
# missing or empty file is a failure rather than a silent empty registry,
# because numeric palettes would then be written without anyone noticing.
public def anvil_registry_load(a: VAnvil*, path: str) -> int:
    if a == null:
        return -1
    if vt_file_slurp(path) != 0:
        return -1
    int n = (int)vt_file_buf_len()
    char* raw = vt_file_buf()
    if raw == null or n <= 0:
        vt_file_release()
        return -1
    # The file buffer is reused by every later read, so the table text is
    # copied before anything parses it.
    char* text = vt_calloc_char(n + 1)
    vt_copy_bytes(text, 0, raw, 0, n)
    vt_file_release()
    VRegistry* r = anvil_registry_build((str)text)
    vt_free((void*)text)
    if r == null:
        return -1
    if a.registry != null:
        anvil_registry_free(a.registry)
    a.registry = r
    return r.rows


# ---- the save context --------------------------------------------------------

struct VAnvil:
    VRegistry* registry
    int64 data_version
    str status                # owned heap copy; every writer dups before storing
    int compression
    int level
    int lossy_palettes       # named palettes that fell back to numeric ids
    int unknown_names        # names read that the table does not have


public def anvil_new() -> VAnvil*:
    VAnvil* a = new VAnvil
    a.registry = null
    a.data_version = anvil_default_data_version()
    a.status = vt_dup(anvil_status_full())
    a.compression = anvil_comp_gzip()
    a.level = 1
    a.lossy_palettes = 0
    a.unknown_names = 0
    return a


public def anvil_free(a: VAnvil*) -> void:
    if a == null:
        return
    if a.registry != null:
        anvil_registry_free(a.registry)
        a.registry = null
    vt_free((void*)a.status)
    a.status = ""
    del a


public def anvil_set_data_version(a: VAnvil*, value: int64) -> void:
    if a != null:
        a.data_version = value


public def anvil_set_status(a: VAnvil*, status: str) -> void:
    if a == null:
        return
    # The context owns its copy, so a caller may hand over a literal or a
    # string it releases right after and the Status field still writes out
    # correctly later in the session.
    str copy = vt_dup(status)
    vt_free((void*)a.status)
    a.status = copy


public def anvil_set_compression(a: VAnvil*, compression: int, level: int) -> int:
    if a == null:
        return 0
    if compression != anvil_comp_gzip() and compression != anvil_comp_zlib():
        if compression != anvil_comp_none():
            return 0
        a.compression = compression
        a.level = 0
        return 1
    a.compression = compression
    if level < 0:
        level = 0
    if level > 9:
        level = 9
    a.level = level
    return 1


# Cpyte resolves a field of a pointer struct only from a variable, not from
# `a.registry.field`, so each of these takes the registry into a local first.
public def anvil_registry_rows(a: VAnvil*) -> int:
    if a == null or a.registry == null:
        return 0
    VRegistry* r = a.registry
    return r.rows


public def anvil_lossy_palettes(a: VAnvil*) -> int:
    if a == null:
        return 0
    return a.lossy_palettes


public def anvil_unknown_names(a: VAnvil*) -> int:
    if a == null:
        return 0
    return a.unknown_names


public def anvil_state_name(a: VAnvil*, state: int) -> str:
    int row = anvil_registry_row_of(a, anvil_kind_state(), state)
    if row < 0:
        return ""
    VRegistry* r = a.registry
    int from = vt_iget(r.name_off, row)
    int to = from + vt_iget(r.name_len, row)
    return str_slice(r.blob, from, to)


public def anvil_state_props(a: VAnvil*, state: int) -> str:
    int row = anvil_registry_row_of(a, anvil_kind_state(), state)
    if row < 0:
        return ""
    VRegistry* r = a.registry
    int from = vt_iget(r.props_off, row)
    int to = from + vt_iget(r.props_len, row)
    return str_slice(r.blob, from, to)


public def anvil_biome_name(a: VAnvil*, biome: int) -> str:
    int row = anvil_registry_row_of(a, anvil_kind_biome(), biome)
    if row < 0:
        return ""
    VRegistry* r = a.registry
    int from = vt_iget(r.name_off, row)
    int to = from + vt_iget(r.name_len, row)
    return str_slice(r.blob, from, to)


# The state a saved palette entry names, or -1 when this table does not know
# it. `blocks` picks the compound form the game uses for states from the string
# form it uses for biomes.
def anvil_entry_state(a: VAnvil*, entry: VNbt*, blocks: bool) -> int:
    if entry == null:
        return -1
    if entry.kind == nbt_int() or entry.kind == nbt_short() or entry.kind == nbt_byte():
        return entry.val_int
    if entry.kind == nbt_long():
        return (int)entry.val_long
    if blocks:
        if entry.kind != nbt_compound():
            return -1
        str name = nbt_str_value(nbt_find(entry, "Name"), "")
        if vt_strlen(name) <= 0:
            return -1
        str props = anvil_props_from_compound(nbt_find(entry, "Properties"))
        int row = anvil_registry_find(a, anvil_kind_state(), name, props)
        if row < 0:
            if a != null:
                a.unknown_names = a.unknown_names + 1
            return -1
        VRegistry* states = a.registry
        return vt_iget(states.id, row)
    if entry.kind != nbt_string():
        return -1
    int biome_row = anvil_registry_find(a, anvil_kind_biome(), entry.val_str, "")
    if biome_row < 0:
        if a != null:
            a.unknown_names = a.unknown_names + 1
        return -1
    VRegistry* biomes = a.registry
    return vt_iget(biomes.id, biome_row)


# ---- NBT helpers -------------------------------------------------------------

# A deep copy under a new key. Nothing in the tree is shared with the source,
# so the clone and the original can be freed in any order.
def anvil_nbt_clone(t: VNbt*, name: str) -> VNbt*:
    if t == null:
        return null
    VNbt* c = nbt_new(t.kind, name)
    c.val_int = t.val_int
    c.val_long = t.val_long
    c.val_float = t.val_float
    c.val_double = t.val_double
    # A string payload is owned by the node that holds it, so the copy takes
    # its own rather than sharing the source's and freeing it twice.
    if t.kind == nbt_string():
        c.val_str = vt_dup(t.val_str)
    if t.bytes != null and t.bytes_len > 0:
        nbt_set_bytes(c, t.bytes, t.bytes_len)
    if t.ints != null and t.ints_len > 0:
        nbt_set_ints(c, t.ints_len)
        int i = 0
        while i < t.ints_len:
            nbt_set_int_at(c, i, vt_iget(t.ints, i))
            i = i + 1
    if t.longs != null and t.longs_len > 0:
        nbt_set_longs(c, t.longs_len)
        int j = 0
        while j < t.longs_len:
            nbt_set_long_at(c, j, (int64)vt_uget(t.longs, j))
            j = j + 1
    int k = 0
    while k < t.items_len:
        VNbt* child = (VNbt*)vt_ptr_get(t.items, k)
        if child != null:
            nbt_append(c, anvil_nbt_clone(child, child.name))
        k = k + 1
    return c


# Drops every child of `root` stored under `name`, freeing those subtrees.
# Returns how many went.
public def anvil_nbt_remove(root: VNbt*, name: str) -> int:
    if root == null or root.kind != nbt_compound():
        return 0
    int removed = 0
    VNbt* kept = nbt_compound_of("")
    int i = 0
    while i < root.items_len:
        VNbt* child = (VNbt*)vt_ptr_get(root.items, i)
        if child == null:
            i = i + 1
        else:
            if vt_eq(child.name, name) == 1:
                nbt_free(child)
                removed = removed + 1
            else:
                nbt_append(kept, child)
            i = i + 1
    root.items = kept.items
    root.items_len = kept.items_len
    root.items_cap = kept.items_cap
    kept.items = null
    kept.items_len = 0
    kept.items_cap = 0
    del kept
    return removed


# Replaces the value stored under `name`. A compound is a map, so the new
# entry goes at the end rather than keeping the old position.
def anvil_nbt_replace(root: VNbt*, name: str, value: VNbt*) -> void:
    if root == null or value == null:
        return
    anvil_nbt_remove(root, name)
    # The key is the caller's string; nbt_set_name keeps the node's own copy.
    nbt_set_name(value, name)
    nbt_append(root, value)


# Either spelling of a key: the schema renamed several fields along the way,
# and a world written by an older game still carries the old ones.
def anvil_nbt_find_any(t: VNbt*, first: str, second: str) -> VNbt*:
    if t == null:
        return null
    VNbt* found = nbt_find(t, first)
    if found != null:
        return found
    return nbt_find(t, second)


# ---- containers --------------------------------------------------------------

# 1 when every palette entry has a table row, which is what makes the named
# form the game writes available for the whole container.
def anvil_palette_named_ok(a: VAnvil*, c: VContainer*, blocks: bool) -> int:
    int slots = sec_palette_size(c)
    int i = 0
    int ok = 1
    while i < slots:
        int row = -1
        if blocks:
            row = anvil_registry_row_of(a, anvil_kind_state(), sec_palette_entry(c, i))
        else:
            row = anvil_registry_row_of(a, anvil_kind_biome(), sec_palette_entry(c, i))
        if row < 0:
            ok = 0
        i = i + 1
    return ok


def anvil_container_style(a: VAnvil*, c: VContainer*, blocks: bool) -> int:
    if a == null:
        return anvil_palette_numeric()
    if anvil_registry_rows(a) <= 0:
        return anvil_palette_numeric()
    if anvil_palette_named_ok(a, c, blocks) == 0:
        a.lossy_palettes = a.lossy_palettes + 1
        return anvil_palette_numeric()
    if blocks:
        return anvil_palette_named()
    return anvil_palette_string()


def anvil_props_compound(props: str) -> VNbt*:
    int n = vt_strlen(props)
    if n <= 0:
        return null
    VNbt* root = nbt_compound_of("Properties")
    int at = 0
    while at < n:
        int stop = str_find_code(props, at, code_comma())
        if stop < 0:
            stop = n
        str source = str_slice(props, at, stop)
        str pair = str_trim(source)
        vt_free((void*)source)
        int split = str_find_code(pair, 0, code_equals())
        if split > 0:
            str key_text = str_slice(pair, 0, split)
            str key = str_trim(key_text)
            vt_free((void*)key_text)
            str value_text = str_slice(pair, split + 1, vt_strlen(pair))
            str value = str_trim(value_text)
            vt_free((void*)value_text)
            if vt_strlen(key) > 0:
                # nbt_string_of takes its own copies, so both halves are
                # released here.
                nbt_append(root, nbt_string_of(key, value))
            vt_free((void*)key)
            vt_free((void*)value)
        vt_free((void*)pair)
        at = stop + 1
    if root.items_len <= 0:
        nbt_free(root)
        return null
    return root


# `{Name: "minecraft:stone", Properties: {axis: "y"}}`. The table holds the
# property text already sorted, which is the order this writes them in; the
# reader sorts too, so a compound from another tool matches either way.
def anvil_state_entry(a: VAnvil*, state: int) -> VNbt*:
    VNbt* entry = nbt_compound_of("")
    # The table hands out fresh copies of a row's text; the node keeps its own,
    # so these are released as soon as they are written.
    str name = anvil_state_name(a, state)
    nbt_append(entry, nbt_string_of("Name", name))
    vt_free((void*)name)
    str text = anvil_state_props(a, state)
    VNbt* props = anvil_props_compound(text)
    vt_free((void*)text)
    if props != null:
        nbt_append(entry, props)
    return entry


# The saved form of one container, named `block_states` or `biomes`:
# `{palette: [...], data: [long...]}`. A uniform container writes its single
# entry and no data array, and a container in direct mode is re-packed into
# palette form first, which is what the game does with both.
def anvil_container_to_nbt(a: VAnvil*, c: VContainer*, blocks: bool,
                           name: str) -> VNbt*:
    VContainer* encoded = c
    VContainer* temporary = c
    if vcont_mode(c) == vcont_direct_mode():
        temporary = vcont_new(vcont_count(c), c.min_bits, 30, c.direct_bits)
        int at = 0
        while at < vcont_count(c):
            vcont_set(temporary, at, vcont_at(c, at))
            at = at + 1
        vcont_compact(temporary)
        encoded = temporary

    int style = anvil_container_style(a, encoded, blocks)
    int slots = sec_palette_size(encoded)
    int element = nbt_int()
    if style == anvil_palette_named():
        element = nbt_compound()
    if style == anvil_palette_string():
        element = nbt_string()
    VNbt* root = nbt_compound_of(name)
    VNbt* palette = nbt_list_of("palette", element)
    int i = 0
    while i < slots:
        int value = sec_palette_entry(encoded, i)
        if style == anvil_palette_numeric():
            nbt_append(palette, nbt_int_of("", value))
        else:
            if style == anvil_palette_string():
                str biome = anvil_biome_name(a, value)
                nbt_append(palette, nbt_string_of("", biome))
                vt_free((void*)biome)
            else:
                nbt_append(palette, anvil_state_entry(a, value))
        i = i + 1
    nbt_append(root, palette)

    int bits = vcont_save_bits_for(encoded)
    if bits > 0:
        VNbt* data = nbt_new(nbt_long_array(), "data")
        int words = vcont_save_words_for(encoded, bits)
        nbt_set_longs(data, words)
        int w = 0
        while w < words:
            nbt_set_long_at(data, w, (int64)vcont_save_word(encoded, w))
            w = w + 1
        nbt_append(root, data)
    if temporary != c:
        vcont_free(temporary)
    return root


# Fills one container from the two nodes a saved form uses. Returns 1 for a
# container that decoded, 0 for a malformed one and -1 for a name the table
# does not know, which must not decode into a wrong block.
def anvil_container_from_nbt(a: VAnvil*, palette: VNbt*, data: VNbt*,
                             c: VContainer*, blocks: bool) -> int:
    if palette == null:
        return 0
    int entries = 0
    int element = nbt_end()
    if palette.kind == nbt_list():
        entries = nbt_child_count(palette)
        element = nbt_list_element_kind(palette)
        if element == nbt_end() and entries > 0:
            VNbt* first = nbt_child_at(palette, 0)
            if first != null:
                element = first.kind
    else:
        if palette.kind == nbt_int_array():
            entries = nbt_int_len(palette)
            element = nbt_int()
        else:
            if palette.kind == nbt_byte_array():
                entries = nbt_byte_len(palette)
                element = nbt_byte()
            else:
                return 0
    if entries <= 0:
        return 0

    # The palette resolves before any word is read, so an unknown name fails
    # the whole container instead of half filling it.
    int[] values = new int[entries]
    int i = 0
    int bad = 0
    int unknown = 0
    while i < entries:
        int value = -1
        if palette.kind == nbt_int_array():
            value = nbt_int_at(palette, i)
        else:
            if palette.kind == nbt_byte_array():
                value = nbt_byte_at(palette, i)
            else:
                value = anvil_entry_state(a, nbt_child_at(palette, i), blocks)
                if value < 0:
                    unknown = 1
        if value < 0:
            bad = 1
        values[i] = value
        i = i + 1
    if bad == 1:
        if unknown == 1:
            return -1
        return 0

    # A file wider than this container can index is decoded in a temporary and
    # copied across, which re-encodes it at the engine's own width.
    int bits = vcont_bits_for(entries, c.min_bits)
    vcont_reset(c, values[0])
    VContainer* decoded = c
    VContainer* temp = null
    if bits > c.max_bits:
        temp = vcont_new(vcont_count(c), c.min_bits, 30, c.direct_bits)
        decoded = temp
    i = 0
    while i < entries:
        vcont_palette_add(decoded, values[i])
        i = i + 1
    if data == null:
        # No data means the section holds the one palette entry.
        if entries == 1:
            vcont_free(temp)
            return 1
        vcont_free(temp)
        return 0
    if data.kind != nbt_long_array():
        vcont_free(temp)
        return 0
    vcont_alloc(decoded, bits)
    int words = nbt_long_len(data)
    int want = vcont_save_words_for(decoded, bits)
    if words > want:
        words = want
    int w = 0
    while w < words:
        vcont_set_word(decoded, w, (uint64)nbt_long_at(data, w))
        w = w + 1
    if temp != null:
        int at = 0
        while at < vcont_count(c):
            vcont_set(c, at, vcont_at(temp, at))
            at = at + 1
        vcont_free(temp)
    return 1


# The pre-1.13 form: one byte per block, with the ninth state bit in `Add`.
def anvil_direct_from_tag(t: VNbt*, add: VNbt*, c: VContainer*) -> int:
    if t == null:
        return 0
    int n = 0
    if t.kind == nbt_byte_array():
        n = nbt_byte_len(t)
    else:
        if t.kind == nbt_int_array():
            n = nbt_int_len(t)
        else:
            return 0
    if n != vcont_count(c):
        return 0
    int i = 0
    while i < n:
        int value = 0
        if t.kind == nbt_byte_array():
            value = nbt_byte_at(t, i)
        else:
            value = nbt_int_at(t, i)
        if add != null and add.kind == nbt_byte_array():
            if nbt_byte_len(add) * 2 >= n:
                int high = nbt_byte_at(add, i / 2)
                if (i % 2) == 0:
                    value = value | ((high & 15) << 8)
                else:
                    value = value | (((high >> 4) & 15) << 8)
        vcont_set(c, i, value & 65535)
        i = i + 1
    return 1


# ---- light -------------------------------------------------------------------

# The saved form is one byte per two blocks, exactly the section's own array.
def anvil_light_tag(light: char*, name: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_byte_array(), name)
    nbt_set_bytes(t, light, sec_light_bytes())
    return t


def anvil_light_read(t: VNbt*, light: char*) -> void:
    if light == null:
        return
    if t == null:
        return
    if t.kind == nbt_byte_array():
        int n = nbt_byte_len(t)
        if n > sec_light_bytes():
            n = sec_light_bytes()
        vt_copy_bytes(light, 0, t.bytes, 0, n)
        int i = n
        while i < sec_light_bytes():
            vt_put(light, i, 0)
            i = i + 1
        return
    # The network spelling - 256 longs, eight bytes little endian each - shows
    # up in files written by tools that round-tripped packets.
    if t.kind == nbt_long_array():
        int w = 0
        int words = nbt_long_len(t)
        if words > sec_light_words():
            words = sec_light_words()
        while w < sec_light_words():
            int64 value = (int64)0
            if w < words:
                value = nbt_long_at(t, w)
            int b = 0
            while b < 8:
                vt_put(light, w * 8 + b, (int)((value >> ((int64)b * (int64)8)) & (int64)255))
                b = b + 1
            w = w + 1
    return


# ---- heightmaps --------------------------------------------------------------

# 256 heights at `base` become the nine big endian longs the format uses. The
# packing straddles word boundaries, which is vt_bits_set's job.
def anvil_hm_tag(values: int*, base: int, name: str) -> VNbt*:
    VNbt* t = nbt_new(nbt_long_array(), name)
    uint64* words = vt_calloc_u64(hm_long_count())
    nbt_set_longs(t, hm_long_count())
    int i = 0
    while i < hm_cells():
        vt_bits_set(words, i, hm_bits(), (uint64)vt_iget(values, base + i))
        i = i + 1
    int w = 0
    while w < hm_long_count():
        nbt_set_long_at(t, w, (int64)vt_uget(words, w))
        w = w + 1
    vt_free((void*)words)
    return t


def anvil_hm_read(t: VNbt*, values: int*, base: int) -> int:
    if t == null or values == null or t.kind != nbt_long_array():
        return 0
    if nbt_long_len(t) < hm_long_count():
        return 0
    uint64* words = vt_calloc_u64(hm_long_count())
    int w = 0
    while w < hm_long_count():
        vt_uset(words, w, (uint64)nbt_long_at(t, w))
        w = w + 1
    int i = 0
    while i < hm_cells():
        int64 raw = vt_bits_get(words, i, hm_bits())
        vt_iset(values, base + i, (int)(raw & (int64)511))
        i = i + 1
    vt_free((void*)words)
    return 1


# Whether a state counts for a heightmap kind. The five kinds differ only in
# what they skip: leaves for MOTION_BLOCKING_NO_LEAVES, fluids for the two
# ocean floors.
def anvil_hm_counts(state: int, kind: int) -> int:
    if state == 0:
        return 0
    if blockdb_loaded() == 0:
        return 1
    if blockdb_is_air(state) == 1:
        return 0
    if kind == 1:
        if blockdb_is_leaves(state) == 1:
            return 0
    if kind == 2 or kind == 3:
        if blockdb_is_fluid(state) == 1:
            return 0
    return 1


# One pass over the column fills all five kinds: the scan stops at the highest
# block each kind still needs. Heights are absolute, as on the wire.
def anvil_hm_compute(world: VWorld*, chunk_x: int, chunk_z: int,
                     values: int*) -> void:
    int x = 0
    while x < 16:
        int z = 0
        while z < 16:
            int pending = 0
            int kind = 0
            while kind < anvil_hm_count():
                if vt_iget(values, kind * 256 + z * 16 + x) == -1:
                    pending = pending + 1
                kind = kind + 1
            int found = 0
            int sy = world.min_section + world.section_count - 1
            while sy >= world.min_section and found < pending:
                VSection* s = vworld_section(world, chunk_x, chunk_z, sy)
                if s != null:
                    int y = 15
                    while y >= 0 and found < pending:
                        int state = sec_block_at_index(s, sec_block_index(x, y, z))
                        kind = 0
                        while kind < anvil_hm_count():
                            if vt_iget(values, kind * 256 + z * 16 + x) == -1:
                                if anvil_hm_counts(state, kind) == 1:
                                    vt_iset(values, kind * 256 + z * 16 + x,
                                           sy * 16 + y)
                                    found = found + 1
                            kind = kind + 1
                        y = y - 1
                sy = sy - 1
            # A column with nothing to count gets height 0: the nine bit field
            # cannot hold the negative `min_y - 1` a below-zero dimension would
            # like, and 0 is what the field reads back as empty.
            kind = 0
            while kind < anvil_hm_count():
                if vt_iget(values, kind * 256 + z * 16 + x) == -1:
                    vt_iset(values, kind * 256 + z * 16 + x, 0)
                kind = kind + 1
            z = z + 1
        x = x + 1


# The engine's stored heightmap column, or null when the chunk is not loaded.
def anvil_world_heightmaps(world: VWorld*, chunk_x: int, chunk_z: int) -> int*:
    if world == null:
        return null
    int index = vworld_find(world, chunk_x, chunk_z)
    if index < 0:
        return null
    return (int*)vt_ptr_get(world.heightmaps, index)


def anvil_hm_copy(source: int*, engine_kind: int, values: int*, kind: int) -> void:
    int base = hm_kind_offset(engine_kind)
    int i = 0
    while i < hm_cells():
        int value = vt_iget(source, base + i)
        if value < 0:
            value = 0
        vt_iset(values, kind * hm_cells() + i, value)
        i = i + 1


# The Heightmaps compound for a column: the two kinds the engine keeps come
# from its own table, the rest are recomputed so a saved chunk is complete.
def anvil_heightmaps_to_nbt(world: VWorld*, chunk_x: int, chunk_z: int) -> VNbt*:
    VNbt* root = nbt_compound_of("Heightmaps")
    int* values = vt_calloc_int(anvil_hm_count() * hm_cells())
    int kind = 0
    while kind < anvil_hm_count():
        int i = 0
        while i < hm_cells():
            vt_iset(values, kind * hm_cells() + i, -1)
            i = i + 1
        kind = kind + 1
    int* column = anvil_world_heightmaps(world, chunk_x, chunk_z)
    if column != null:
        anvil_hm_copy(column, hm_motion_blocking(), values, 0)
        anvil_hm_copy(column, hm_world_surface(), values, 4)
    anvil_hm_compute(world, chunk_x, chunk_z, values)
    kind = 0
    while kind < anvil_hm_count():
        nbt_append(root, anvil_hm_tag(values, kind * hm_cells(), anvil_hm_name(kind)))
        kind = kind + 1
    vt_free((void*)values)
    return root


# ---- sections and chunks -----------------------------------------------------

def anvil_section_to_nbt(a: VAnvil*, s: VSection*) -> VNbt*:
    sec_compact(s)
    VNbt* root = nbt_compound_of("")
    nbt_append(root, anvil_container_to_nbt(a, s.blocks, true, "block_states"))
    nbt_append(root, anvil_container_to_nbt(a, s.biomes, false, "biomes"))
    nbt_append(root, nbt_byte_of("Y", s.y))
    nbt_append(root, anvil_light_tag(s.block_light, "BlockLight"))
    nbt_append(root, anvil_light_tag(s.sky_light, "SkyLight"))
    return root


def anvil_sections_to_nbt(a: VAnvil*, world: VWorld*, chunk_x: int,
                          chunk_z: int) -> VNbt*:
    VNbt* list = nbt_list_of("sections", nbt_compound())
    int sy = world.min_section
    while sy < world.min_section + world.section_count:
        VSection* s = vworld_section(world, chunk_x, chunk_z, sy)
        if s != null:
            nbt_append(list, anvil_section_to_nbt(a, s))
        sy = sy + 1
    return list


# A block or biome half, in whichever of the three schema generations the
# compound is written. 1 decoded, 0 malformed, -1 an unknown registry name.
def anvil_side_from_section(a: VAnvil*, t: VNbt*, c: VContainer*, blocks: bool) -> int:
    VNbt* container = null
    if blocks:
        container = anvil_nbt_find_any(t, "block_states", "States")
    else:
        container = nbt_find(t, "biomes")
        if container == null:
            container = nbt_find(t, "Biomes")
    if container != null and container.kind == nbt_compound():
        VNbt* palette = anvil_nbt_find_any(container, "palette", "Palette")
        VNbt* data = anvil_nbt_find_any(container, "data", "BlockData")
        if data == null:
            data = nbt_find(container, "Data")
        int from_container = anvil_container_from_nbt(a, palette, data, c, blocks)
        if from_container != 0:
            return from_container
    if blocks:
        VNbt* palette = nbt_find(t, "Palette")
        if palette != null:
            VNbt* data = anvil_nbt_find_any(t, "BlockData", "Data")
            int legacy = anvil_container_from_nbt(a, palette, data, c, blocks)
            if legacy != 0:
                return legacy
        return anvil_direct_from_tag(nbt_find(t, "Blocks"), nbt_find(t, "Add"), c)
    return anvil_direct_from_tag(container, null, c)


# The two kinds an engine column keeps.
def anvil_hm_engine_read(heightmaps: VNbt*, values: int*) -> void:
    if heightmaps == null or heightmaps.kind != nbt_compound():
        return
    anvil_hm_read(nbt_find(heightmaps, "MOTION_BLOCKING"), values,
                  hm_kind_offset(hm_motion_blocking()))
    anvil_hm_read(nbt_find(heightmaps, "WORLD_SURFACE"), values,
                  hm_kind_offset(hm_world_surface()))


# Pre-1.18 worlds keep one biome per block column, not one per section cell:
# the same 16x16 value fills every cell of every section in the column.
def anvil_column_biomes(t: VNbt*) -> int*:
    int* values = vt_calloc_int(hm_cells())
    int i = 0
    while i < hm_cells():
        vt_iset(values, i, nbt_int_at(t, i))
        i = i + 1
    return values


def anvil_fill_column_biomes(s: VSection*, values: int*, min_section: int) -> void:
    int x = 0
    while x < 4:
        int z = 0
        while z < 4:
            int biome = vt_iget(values, z * 16 + x)
            int y = 0
            while y < 4:
                vcont_set(s.biomes, sec_biome_index(x, y, z), biome)
                y = y + 1
            z = z + 1
        x = x + 1


# One saved section compound, in the world's own layout. The Y byte is signed,
# which is what the format means for sections below the origin.
def anvil_section_from_nbt(a: VAnvil*, t: VNbt*, world: VWorld*, y: int,
                           status: int*) -> VSection*:
    *status = 0
    if t == null or t.kind != nbt_compound():
        return null
    VSection* s = sec_new_for_wire(y, world.block_global_bits, world.biome_global_bits)
    int blocks = anvil_side_from_section(a, t, s.blocks, true)
    int biomes = anvil_side_from_section(a, t, s.biomes, false)
    if blocks < 1 or biomes < 1:
        sec_free(s)
        if blocks < 0 or biomes < 0:
            *status = -1
        return null
    *status = 1
    s.y = nbt_get_int(t, "Y", y)
    anvil_light_read(anvil_nbt_find_any(t, "BlockLight", "Light"), s.block_light)
    anvil_light_read(nbt_find(t, "SkyLight"), s.sky_light)
    return s


# The chunk compound the game reads: modern schema, with every field the
# engine does not model copied out of the record it is replacing.
public def anvil_chunk_to_nbt(a: VAnvil*, world: VWorld*, chunk_x: int,
                              chunk_z: int, keep: VNbt*) -> VNbt*:
    VNbt* root = null
    if keep != null and keep.kind == nbt_compound():
        root = anvil_nbt_clone(keep, "")
    else:
        root = nbt_compound_of("")
    int64 version = anvil_default_data_version()
    str status = anvil_status_full()
    if a != null:
        version = a.data_version
        status = a.status

    anvil_nbt_replace(root, "DataVersion", nbt_long_of("DataVersion", version))
    anvil_nbt_replace(root, "sections", anvil_sections_to_nbt(a, world, chunk_x, chunk_z))
    anvil_nbt_replace(root, "Heightmaps", anvil_heightmaps_to_nbt(world, chunk_x, chunk_z))
    anvil_nbt_replace(root, "Status", nbt_string_of("Status", status))
    anvil_nbt_replace(root, "Version", nbt_byte_of("Version", anvil_format_version()))
    anvil_nbt_replace(root, "xPos", nbt_int_of("xPos", chunk_x))
    anvil_nbt_replace(root, "yPos", nbt_int_of("yPos", world.min_section))
    anvil_nbt_replace(root, "zPos", nbt_int_of("zPos", chunk_z))
    # The superseded spellings, and the pre-1.18 wrapper whose contents this
    # chunk now replaces, go: leaving them would give a reader two answers.
    anvil_nbt_remove(root, "Sections")
    anvil_nbt_remove(root, "Level")
    anvil_nbt_remove(root, "yAxis")
    if nbt_find(root, "TileEntities") == null and nbt_find(root, "Tiles") == null:
        nbt_append(root, nbt_list_of("TileEntities", nbt_end()))
    if nbt_find(root, "Entities") == null:
        nbt_append(root, nbt_list_of("Entities", nbt_end()))
    return root


# Installs a saved chunk into `world`. 1 loaded, 0 malformed, -1 unsupported
# (a name the table does not know, or a column the world cannot hold).
public def anvil_chunk_from_nbt(a: VAnvil*, root: VNbt*, world: VWorld*,
                                chunk_x: int, chunk_z: int) -> int:
    if root == null or root.kind != nbt_compound() or world == null:
        return 0
    VNbt* body = root
    VNbt* level = nbt_find(root, "Level")
    if level != null and level.kind == nbt_compound():
        body = level
    int min_section = nbt_get_int(body, "yPos", world.min_section)
    if min_section < world.min_section:
        return -1
    char* sections = vt_calloc_ptrs(world.section_count)
    int result = 1
    VNbt* list = anvil_nbt_find_any(body, "sections", "Sections")
    if list != null and list.kind == nbt_list():
        int column_biomes = 0
        int* column_values = null
        VNbt* biomes = nbt_find(body, "Biomes")
        if biomes != null and biomes.kind == nbt_int_array():
            if nbt_int_len(biomes) == hm_cells():
                column_values = anvil_column_biomes(biomes)
                column_biomes = 1
        int i = 0
        int side = 0
        while i < nbt_child_count(list) and result == 1:
            VNbt* t = nbt_child_at(list, i)
            int y = nbt_get_int(t, "Y", min_section)
            if y >= world.min_section and y < world.min_section + world.section_count:
                VSection* s = anvil_section_from_nbt(a, t, world, y, &side)
                if s == null:
                    if side < 0:
                        result = -1
                    else:
                        result = 0
                else:
                    if column_biomes == 1:
                        anvil_fill_column_biomes(s, column_values, min_section)
                    vt_ptr_set(sections, y - world.min_section, (void*)s)
            i = i + 1
        if column_values != null:
            vt_free((void*)column_values)
    if result == 1:
        VNbt* heightmaps = nbt_find(body, "Heightmaps")
        int* values = hm_new()
        anvil_hm_engine_read(heightmaps, values)
        if vworld_replace_sections(world, chunk_x, chunk_z, sections) == 0:
            result = 0
            hm_free(values)
        else:
            # The world owns the column from here; a full store cannot fail
            # twice, since the slot the sections call just made is still free.
            if vworld_set_heightmaps(world, chunk_x, chunk_z, values) == 0:
                hm_free(values)
    if result != 1:
        vworld_free_column(sections, world.section_count)
    return result


# ---- the region image --------------------------------------------------------

struct VRegion:
    int region_x
    int region_z
    int present
    int* length             # compressed payload bytes, 0 when absent
    int* compression        # the record's compression byte
    int* sector             # sector it was read from, for reporting
    int* sectors            # how many it took
    int* mtime
    char* payloads          # one malloc'd blob per present slot


public def vregion_new(region_x: int, region_z: int) -> VRegion*:
    VRegion* r = new VRegion
    r.region_x = region_x
    r.region_z = region_z
    r.present = 0
    r.length = vt_calloc_int(anvil_region_chunks())
    r.compression = vt_calloc_int(anvil_region_chunks())
    r.sector = vt_calloc_int(anvil_region_chunks())
    r.sectors = vt_calloc_int(anvil_region_chunks())
    r.mtime = vt_calloc_int(anvil_region_chunks())
    r.payloads = vt_calloc_ptrs(anvil_region_chunks())
    return r


public def vregion_free(r: VRegion*) -> void:
    if r == null:
        return
    int i = 0
    while i < anvil_region_chunks():
        char* blob = (char*)vt_ptr_get(r.payloads, i)
        if blob != null:
            vt_free((void*)blob)
            vt_ptr_set(r.payloads, i, null)
        vt_iset(r.length, i, 0)
        i = i + 1
    vt_free((void*)r.length)
    vt_free((void*)r.compression)
    vt_free((void*)r.sector)
    vt_free((void*)r.sectors)
    vt_free((void*)r.mtime)
    vt_free((void*)r.payloads)
    del r


public def anvil_region_of(coordinate: int) -> int:
    int region = coordinate / 32
    # Integer division in the language truncates, and the format wants floor
    # semantics so that a chunk west of the origin lands in the region whose
    # local index is still 0..31.
    if region * 32 > coordinate:
        region = region - 1
    return region


public def anvil_local_of(coordinate: int) -> int:
    return coordinate - anvil_region_of(coordinate) * 32


public def anvil_chunk_of(region: int, local: int) -> int:
    return region * 32 + local


public def anvil_region_path(base: str, dimension: str, region_x: int,
                             region_z: int) -> str:
    return vt_region_path(base, dimension, (int64)region_x, (int64)region_z)


def vregion_index(local_x: int, local_z: int) -> int:
    if local_x < 0 or local_x >= 32 or local_z < 0 or local_z >= 32:
        return -1
    return local_x + local_z * 32


public def vregion_present(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    if vt_iget(r.length, slot) <= 0:
        return 0
    return 1


public def vregion_chunk_count(r: VRegion*) -> int:
    if r == null:
        return 0
    return r.present


public def vregion_sectors(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.sectors, slot)


public def vregion_sector(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.sector, slot)


public def vregion_time(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.mtime, slot)


public def vregion_payload(r: VRegion*, local_x: int, local_z: int) -> char*:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return null
    if vt_iget(r.length, slot) <= 0:
        return null
    return (char*)vt_ptr_get(r.payloads, slot)


# The compressed payload's length, not counting the compression byte.
public def vregion_payload_length(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.length, slot)


public def vregion_compression(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    return vt_iget(r.compression, slot)


def vregion_drop(r: VRegion*, slot: int) -> void:
    char* blob = (char*)vt_ptr_get(r.payloads, slot)
    if blob != null:
        vt_free((void*)blob)
        vt_ptr_set(r.payloads, slot, null)
    if vt_iget(r.length, slot) > 0:
        r.present = r.present - 1
    vt_iset(r.length, slot, 0)
    vt_iset(r.compression, slot, 0)
    vt_iset(r.sector, slot, 0)
    vt_iset(r.sectors, slot, 0)


public def vregion_forget(r: VRegion*, local_x: int, local_z: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0:
        return 0
    vregion_drop(r, slot)
    return 1


# Records one chunk in the image: the bytes it holds, where they came from and
# when they were written. `slot` is the table index, so a loader reading the
# location table does not have to split it back into local coordinates.
def vregion_store(r: VRegion*, slot: int, data: char*, from: int, length: int,
                  compression: int, offset: int, count: int, mtime: int) -> void:
    char* blob = vt_calloc_char(length + 1)
    if length > 0:
        vt_copy_bytes(blob, 0, data, from, length)
    char* previous = (char*)vt_ptr_get(r.payloads, slot)
    if previous != null:
        vt_free((void*)previous)
    vt_ptr_set(r.payloads, slot, (void*)blob)
    if vt_iget(r.length, slot) <= 0:
        r.present = r.present + 1
    vt_iset(r.length, slot, length)
    vt_iset(r.compression, slot, compression)
    vt_iset(r.sector, slot, offset)
    vt_iset(r.sectors, slot, count)
    vt_iset(r.mtime, slot, mtime)


# Stores a compressed payload, taking a copy: the codec buffer is reused by
# the next call. The sector fields go blank because the image no longer
# reflects the file on disk until vregion_save has run.
def vregion_set_payload(r: VRegion*, local_x: int, local_z: int, data: char*,
                        length: int, compression: int) -> int:
    int slot = vregion_index(local_x, local_z)
    if r == null or slot < 0 or length < 0:
        return 0
    if length == 0:
        vregion_drop(r, slot)
        return 1
    vregion_store(r, slot, data, 0, length, compression, 0, 0,
                  (int)vt_file_now())
    return 1


def anvil_comp_format(compression: int) -> int:
    if compression == anvil_comp_zlib():
        return 1
    if compression == anvil_comp_none():
        return 2
    return 0


public def vregion_codec_format(compression: int) -> int:
    return anvil_comp_format(compression)


# Serialises, compresses and stores one chunk compound.
public def vregion_set_chunk_nbt(r: VRegion*, a: VAnvil*, local_x: int,
                                 local_z: int, nbt: VNbt*) -> int:
    if r == null or nbt == null:
        return 0
    int compression = anvil_comp_gzip()
    int level = 1
    if a != null:
        compression = a.compression
        level = a.level
    VBuf* b = vbuf_new(4096)
    nbt_write(b, nbt)
    int format = anvil_comp_format(compression)
    int result = 0
    if vt_gz_compress(b.data, (int64)0, (int64)b.len, (int64)format, (int64)level) == 0:
        int length = (int)vt_gz_buf_len()
        if length >= 1 and length <= anvil_max_sectors() * anvil_sector_bytes():
            if vregion_set_payload(r, local_x, local_z, vt_gz_buf(), length,
                                   compression) == 1:
                result = 1
    vbuf_free(b)
    return result


# Reads and decompresses a stored chunk. The caller frees the tree.
public def vregion_chunk_nbt(r: VRegion*, local_x: int, local_z: int) -> VNbt*:
    char* payload = vregion_payload(r, local_x, local_z)
    int length = vregion_payload_length(r, local_x, local_z)
    if payload == null or length <= 0:
        return null
    int format = anvil_comp_format(vregion_compression(r, local_x, local_z))
    if vt_gz_decompress(payload, (int64)0, (int64)length, (int64)format) != 0:
        return null
    int n = (int)vt_gz_buf_len()
    if n <= 0:
        return null
    # nbt_read copies every payload it keeps, but the strings it returns are
    # its own allocations, so the codec buffer can go once the tree is built.
    VBuf* b = vbuf_new(n + 16)
    vbuf_put_bytes(b, vt_gz_buf(), n)
    VNbt* root = nbt_read(b)
    vbuf_free(b)
    if root == null:
        return null
    return root


# Parses the two tables and copies every record the location table names.
# An absent file is an empty image, which is what a new region is; a file that
# is there but does not parse is an error, never a silent empty region.
public def vregion_load(r: VRegion*, path: str) -> int:
    if r == null:
        return 0
    int i = 0
    while i < anvil_region_chunks():
        vregion_drop(r, i)
        i = i + 1
    if vt_file_exists(path) == 0:
        return 0
    if vt_file_slurp(path) != 0:
        return -1
    char* data = vt_file_buf()
    int n = (int)vt_file_buf_len()
    if data == null or n < anvil_header_bytes():
        vt_file_release()
        return -1
    int sectors = n / anvil_sector_bytes()
    int failed = 0
    int i = 0
    while i < anvil_region_chunks() and failed == 0:
        int at = i * 4
        int o0 = vt_at(data, at)
        int o1 = vt_at(data, at + 1)
        int o2 = vt_at(data, at + 2)
        int offset = (o0 << 16) | (o1 << 8) | o2
        int count = vt_at(data, at + 3)
        int time_at = anvil_sector_bytes() + i * 4
        int m0 = vt_at(data, time_at)
        int m1 = vt_at(data, time_at + 1)
        int m2 = vt_at(data, time_at + 2)
        int m3 = vt_at(data, time_at + 3)
        int mtime = (m0 << 24) | (m1 << 16) | (m2 << 8) | m3
        if count > 0:
            if offset < anvil_first_sector() or offset + count > sectors:
                failed = 1
            else:
                int record = offset * anvil_sector_bytes()
                int l0 = vt_at(data, record)
                int l1 = vt_at(data, record + 1)
                int l2 = vt_at(data, record + 2)
                int l3 = vt_at(data, record + 3)
                int length = (l0 << 24) | (l1 << 16) | (l2 << 8) | l3
                int compression = vt_at(data, record + 4)
                int capacity = count * anvil_sector_bytes() - anvil_record_overhead()
                if record + anvil_record_overhead() > n:
                    failed = 1
                else:
                    if length < 2 or length - 1 > capacity:
                        failed = 1
                    else:
                        if record + anvil_record_overhead() + length - 1 > n:
                            failed = 1
                        else:
                            int from = record + anvil_record_overhead()
                            vregion_store(r, i, data, from, length - 1,
                                          compression, offset, count, mtime)
        else:
            vt_iset(r.mtime, i, mtime)
        i = i + 1
    vt_file_release()
    if failed == 1:
        i = 0
        while i < anvil_region_chunks():
            vregion_drop(r, i)
            i = i + 1
        return -1
    return 0


# The copy above is a placeholder: payloads are stored with their real length,
# so this walks the table a second time and keeps the bytes.
# Writes the image out: header first, then each record at its own sector, with
# zero padding so every record starts on a sector boundary.
public def vregion_save(r: VRegion*, path: str) -> int:
    if r == null:
        return 0
    int* offsets = vt_calloc_int(anvil_region_chunks())
    int* sectors = vt_calloc_int(anvil_region_chunks())
    int cursor = anvil_first_sector()
    int i = 0
    int bad = 0
    while i < anvil_region_chunks():
        int length = vt_iget(r.length, i)
        if length > 0:
            int record = length + anvil_record_overhead()
            int needed = (record + anvil_sector_bytes() - 1) / anvil_sector_bytes()
            if needed > anvil_max_sectors():
                bad = 1
            else:
                vt_iset(offsets, i, cursor)
                vt_iset(sectors, i, needed)
                cursor = cursor + needed
        i = i + 1
    if bad == 1:
        vt_free((void*)offsets)
        vt_free((void*)sectors)
        return -1

    VBuf* out = vbuf_new(cursor * anvil_sector_bytes() + anvil_sector_bytes())
    char* padding = vt_calloc_char(anvil_sector_bytes())
    i = 0
    while i < anvil_region_chunks():
        int offset = vt_iget(offsets, i)
        int count = vt_iget(sectors, i)
        int value = 0
        if count > 0:
            value = (int)(((int64)offset << 8) | (int64)count)
        vbuf_put_u32_be(out, (uint64)value)
        i = i + 1
    i = 0
    while i < anvil_region_chunks():
        vbuf_put_i32_be(out, vt_iget(r.mtime, i))
        i = i + 1
    i = 0
    int written = anvil_first_sector()
    while i < anvil_region_chunks():
        int count = vt_iget(sectors, i)
        if count > 0:
            int offset = vt_iget(offsets, i)
            while written < offset:
                vbuf_put_bytes(out, padding, anvil_sector_bytes())
                written = written + 1
            char* payload = (char*)vt_ptr_get(r.payloads, i)
            int length = vt_iget(r.length, i)
            vbuf_put_i32_be(out, length + 1)
            vbuf_put_u8(out, (uint64)vt_iget(r.compression, i))
            vbuf_put_bytes(out, payload, length)
            int record = length + anvil_record_overhead()
            int pad = count * anvil_sector_bytes() - record
            if pad > 0:
                vbuf_put_bytes(out, padding, pad)
            written = written + count
            vt_iset(r.sector, i, offset)
            vt_iset(r.sectors, i, count)
        i = i + 1
    vt_free((void*)padding)
    vt_file_mkdirs(path)
    int result = 0
    if vt_file_spit(path, out.data, (int64)out.len) != 0:
        result = -1
    vbuf_free(out)
    vt_free((void*)offsets)
    vt_free((void*)sectors)
    return result


# ---- the world and the region file -------------------------------------------

public def vregion_save_chunk(a: VAnvil*, r: VRegion*, world: VWorld*,
                              chunk_x: int, chunk_z: int) -> int:
    if r == null or world == null:
        return 0
    if r.region_x != anvil_region_of(chunk_x) or r.region_z != anvil_region_of(chunk_z):
        return 0
    int local_x = anvil_local_of(chunk_x)
    int local_z = anvil_local_of(chunk_z)
    VNbt* keep = vregion_chunk_nbt(r, local_x, local_z)
    VNbt* root = anvil_chunk_to_nbt(a, world, chunk_x, chunk_z, keep)
    int stored = vregion_set_chunk_nbt(r, a, local_x, local_z, root)
    if keep != null:
        nbt_free(keep)
    nbt_free(root)
    if stored == 0:
        return 0
    return 1


public def vregion_load_chunk(a: VAnvil*, r: VRegion*, world: VWorld*,
                              chunk_x: int, chunk_z: int) -> int:
    if r == null or world == null:
        return 0
    if r.region_x != anvil_region_of(chunk_x) or r.region_z != anvil_region_of(chunk_z):
        return 0
    VNbt* root = vregion_chunk_nbt(r, anvil_local_of(chunk_x),
                                   anvil_local_of(chunk_z))
    if root == null:
        return 0
    int result = anvil_chunk_from_nbt(a, root, world, chunk_x, chunk_z)
    nbt_free(root)
    return result


# Loads every chunk a region holds. Returns the count installed, or -1 when
# the file did not parse.
public def anvil_load_region(a: VAnvil*, world: VWorld*, base: str,
                             dimension: str, region_x: int,
                             region_z: int) -> int:
    if world == null:
        return 0
    VRegion* r = vregion_new(region_x, region_z)
    str path = anvil_region_path(base, dimension, region_x, region_z)
    int loaded = 0
    int parsed = vregion_load(r, path)
    if parsed == 0:
        int local_z = 0
        while local_z < 32:
            int local_x = 0
            while local_x < 32:
                if vregion_present(r, local_x, local_z) == 1:
                    int chunk_x = anvil_chunk_of(region_x, local_x)
                    int chunk_z = anvil_chunk_of(region_z, local_z)
                    if vregion_load_chunk(a, r, world, chunk_x, chunk_z) == 1:
                        loaded = loaded + 1
                local_x = local_x + 1
            local_z = local_z + 1
    vregion_free(r)
    if parsed != 0:
        return -1
    return loaded


# Saves every loaded column, one region image per region it touches. Columns
# sharing a region go in one image so the file is rewritten once, which is what
# keeps the sector allocation simple: every record gets fresh sectors.
# Returns the count written, or -1 when a region file could not be written.
public def anvil_save_world(a: VAnvil*, world: VWorld*, base: str,
                            dimension: str) -> int:
    if world == null:
        return 0
    int count = world.count
    if count <= 0:
        return 0
    int* done = vt_calloc_int(count)
    int written = 0
    int failed = 0
    int i = 0
    while i < count and failed == 0:
        if vt_iget(done, i) == 0:
            int chunk_x = vt_iget(world.chunk_x, i)
            int chunk_z = vt_iget(world.chunk_z, i)
            int region_x = anvil_region_of(chunk_x)
            int region_z = anvil_region_of(chunk_z)
            VRegion* r = vregion_new(region_x, region_z)
            str path = anvil_region_path(base, dimension, region_x, region_z)
            if vregion_load(r, path) == 0:
                int j = i
                while j < count:
                    int other_x = vt_iget(world.chunk_x, j)
                    int other_z = vt_iget(world.chunk_z, j)
                    int same = 0
                    if anvil_region_of(other_x) == region_x:
                        if anvil_region_of(other_z) == region_z:
                            same = 1
                    if same == 1:
                        vt_iset(done, j, 1)
                        if vregion_save_chunk(a, r, world, other_x, other_z) == 1:
                            written = written + 1
                        else:
                            failed = 1
                    j = j + 1
                if failed == 0:
                    if vregion_save(r, path) != 0:
                        failed = 1
            else:
                failed = 1
            vregion_free(r)
        i = i + 1
    vt_free((void*)done)
    if failed == 1:
        return -1
    return written


# ---- one-call save/load, with the name table already handled -----------------

# Loads one region file's chunks into `world`, with the same name table. The
# count returned is how many chunks decoded; -1 means the file is there but
# cannot be parsed.
public def anvil_session_load(world: VWorld*, base: str, dimension: str,
                              region_x: int, region_z: int) -> int:
    VAnvil* a = anvil_new()
    anvil_registry_load(a, anvil_registry_default_path())
    int loaded = anvil_load_region(a, world, base, dimension, region_x, region_z)
    anvil_free(a)
    return loaded


# Where a session's recording goes: `saves/vortex` unless told otherwise. The
# overworld is that folder directly and every other dimension gets its own, so
# each one is a complete Anvil world root on its own.
public def anvil_save_base() -> str:
    return vt_env_or("VORTEX_WORLD_SAVE", "saves/vortex")


# Saves the loaded world and reports what the name table could and could not
# name: `named` rows loaded, `numeric` palettes that fell back to ids, and
# `unknown` saved names this table does not have.
public def anvil_world_save(world: VWorld*, named: int*, numeric: int*,
                            unknown: int*) -> int:
    str base = anvil_save_base()
    str folder = base
    int index = vworld_dimension_id(world)
    if index != 0:
        folder = base + ("/dimension" + str(index))
    VAnvil* a = anvil_new()
    int rows = anvil_registry_load(a, anvil_registry_default_path())
    if rows < 0:
        rows = 0
    int written = anvil_save_world(a, world, folder, "")
    int fell_back = anvil_lossy_palettes(a)
    int missed = anvil_unknown_names(a)
    anvil_free(a)
    if named != null:
        *named = rows
    if numeric != null:
        *numeric = fell_back
    if unknown != null:
        *unknown = missed
    return written

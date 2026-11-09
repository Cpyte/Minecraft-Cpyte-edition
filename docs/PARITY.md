# Chunk parity notes

The protocol section decoder was checked against Horizon's public chunk
implementation at commit
[`83ad384`](https://github.com/horizon-rust/horizon/commit/83ad384f48d0742746d518737511882680aab5b7):

- [`chunk.rs`](https://github.com/horizon-rust/horizon/blob/83ad384f48d0742746d518737511882680aab5b7/crates/horizon-protocol/src/chunk.rs)
  defines the 4096 block and 64 biome entries, section header, palette strategy,
  and padded `SimpleBitStorage` long packing.
- [`remote_chunks.rs`](https://github.com/horizon-rust/horizon/blob/83ad384f48d0742746d518737511882680aab5b7/crates/horizon-client/src/game/remote_chunks.rs)
  shows how decoded wire palettes depend on dimension layout and server
  registries.

For the supported wire section containers, the implementation follows these
rules:

| Container | Local palette | Global palette | Packed values |
|---|---|---|---|
| Blocks | wire widths 1-4 use 4 bits; 5-8 keep their width | widths above 8 use `max(server global bits, wire bits)` | `floor(64 / bits)` values per big-endian long; values do not straddle longs |
| Biomes | widths 1-3 keep their width | widths above 3 use `max(server global bits, wire bits)` | same padded long packing |

Width zero reads one VarInt palette value and no data words. Nonzero local
palettes read a VarInt palette followed by the fixed number of long words;
global containers have no palette. The section header's non-empty count and
block/biome values are retained in the in-memory column.

This is a behavior comparison against the cited protocol implementation, not a
port of Horizon source. It does **not** establish full engine parity: this
client reads dimension `min_y` and `height` from the configuration dimension
registry and selects the active type from Play login. The global biome width is
derived from the configured biome registry size. Block-state global width
uses the target protocol profile's 15-bit minimum and expands when a wire
palette declares a larger width. Custom or modded block-state registries are
not parsed. Missing dimension or biome registry data is rejected rather than
silently interpreting chunks as Overworld.

Chunk packets now validate and skip block-entity NBT records and decode the
sky/block light masks and arrays, applying in-range section light bytes to the
loaded column. Chunk heightmaps are decoded from the varint-counted list of
heightmap type ids and packed long arrays: the types the engine stores
(MOTION_BLOCKING and WORLD_SURFACE) are unpacked from 9-bit longs into
per-block absolute heights kept with the chunk column, a type it does not
store is walked and dropped, a stored type the server leaves out reads as
zero, and a stored type whose long count is not 36 rejects the chunk because
the packing width would be unknown. Heightmaps are not used to derive block
presence, so `vworld_height_at` reports only what the server sent. Block
entities are not retained or rendered, and
registry values are not mapped to renderable block/biome definitions. The
standalone NBT section serializer is a Vortex representation, not a complete
Minecraft chunk-save serializer. The packet IDs and framing remain tied to the
client's configured protocol profile; this chunk-tail layout has not been
independently verified against the claimed 26.3 / protocol 777 profile.

## Play packet handling

`tests/protocol_play.txt` exercises the Play wire formats that are implemented,
byte by byte: every serverbound encoder round-trips through the shared frame and
varint decoder, and the clientbound handlers are fed hand-built packets that
must either parse or reject them.

Covered: movement (`move_player_pos`, `pos_rot`, `rot`, `status_only`), use and
attack, `interact`, `player_action` with the canonical packed block position,
`player_command`, `set_carried_item`, `use_item`, `chat_ack`,
`player_abilities`, client command settings; and on the inbound side health,
experience, abilities, held slot, time, simulation distance, respawn, game
events, player info, default spawn, item stacks with structurally skipped NBT
components, container slots and content, player inventory, open screen and
player chat.

Covered on the stateful side too: `src/world/entities.cpy` is the client-side
entity registry (id -> type, position, motion, the three angle bytes, per-field
metadata values, name and flags) that every entity packet now merges into
instead of discarding, `src/world/bossbars.cpy` keeps the boss bars a server has
added, keyed by their uuid, `src/world/scoreboard.cpy` holds objectives, scores,
display slots and teams for the five scoreboard packets, and
`src/world/commands.cpy` stores the Brigadier node tree from `commands` so
literal names, parsers, redirects and the chain limit survive the packet.

Not covered, so still partial: signed chat rendering, block-entity NBT payloads,
particle and sound parameters, and mob effect durations, icons and colours.
`pl_decode_entity_metadata` uses the 1.20.2+ packing -
field id in the low seven bits of the header varint, serializer ordinal above
them, and a varint 255 terminator - and reads ordinals 0..40, 42 and 43
structurally. The ordering and the shapes are the ones the 26.3 jar registers
(`javap` on `net/minecraft/network/syncher/EntityDataSerializers`), which put
`boolean` at 8, `block position` at 10 and `rotation` at 9 rather than the
1.20.2 order many clients assume. Ordinal 41 (`resolvable profile`) is the one
gap: it is an either-discriminated profile with a property list and a skin patch
inside it, and none of those are decoded anywhere else in the client, so the
walk stops and names itself instead of guessing a size, because one wrong size
desynchronises every field after it. The movement packet flag/delta layout, the
client command settings field order and the `commands` node flag bits (documented
at the top of `src/world/commands.cpy`) are the three places most likely to
differ from a real 26.3 server. A tree that does not end exactly on the chain
limit byte is rejected rather than partially stored, so a disagreement shows up
as one clear "Malformed command tree" line instead of silently wrong
completions.

## Voxel engine wiring

The native parallel mesher (`src/engine/mesher.c`, a persistent pthreads/Win32
worker pool) is driven by the Play loop through `mesh_chunk_native` and
`remesh_section_native` in `src/protocol.cpy`:

- `level_chunk_with_light` meshes the freshly decoded column.
- `block_update` and `section_blocks_update` re-mesh the edited section plus its
  six face-adjacent sections so boundary faces stay correct.
- `light_update` re-meshes the affected column.

Each call builds a batch, runs the pool, reports quad/vertex counts and frees the
batch on the main thread; workers only read decoded sections through the
C-callable accessors (`sec_block_at_index`, `sec_light_packed_index`,
`vt_blockdb_render`) and write malloc'd buffers, so the GC never sees a worker
stack. The former `mesh_loaded_chunk` proof-of-concept is removed. Block states
are classified by the optional block database (every non-air state is an opaque
cube without it).

## Renderer

Finished batches are handed to the Vulkan renderer instead of stopping as
buffers. The boundary is two C-side channels in `src/engine/native.c`, so a
Play session and a window communicate without the protocol bundle calling
Vulkan directly:

- `vt_mesh_batch_publish` / `vt_mesh_batch_take` — a ring of finished vertex and
  index batches.
- `vt_publish_view` — a 14-slot mailbox holding the player's position, looking
  direction, day time, health, food, saturation, experience, held slot, game
  mode and view distance. It returns whether the window has been closed.
- `vt_set_view_pump` — the renderer installs its own frame function as an
  integer address; Cpyte cannot pass a function pointer through a C parameter.
- `vt_chat_begin` / `vt_chat_byte` / `vt_chat_end` — a 12-line ring of the chat
  text the session prints, each line stamped with a serial the renderer uses for
  fade-out.

`src/protocol.cpy` publishes a view after every processed packet
(`pl_publish_view`) and tees chat text through `pl_chat_text`; `main` mode 5
(`play_with_renderer` in `src/client_main.cpy`) attaches the pump, runs the same
`offline_login` and detaches on exit. If Vulkan is unavailable the mode falls
back to the headless session.

What the window draws for a live session: terrain in an opaque and a translucent
pass, culled per chunk section against a six-plane frustum, with the GPU store
keyed by `(chunk_x, chunk_z, section_y, pass)` so a server that re-sends the same
section replaces it instead of duplicating geometry. Sky colour, sky brightness,
fog colour and the fog start/end come from the day time and view distance the
server reported; the sun, moon and a star field are drawn from the same model.
The HUD shows the crosshair, hearts, hunger, saturation, experience level and
progress, the nine held-item slots with the server's selection, the game mode, a
session debug block and the chat lines. The menu screens (`src/render/gui.c`,
`src/render/menus.c`) are drawn whenever a session has not published a view, and
as an overlay when it has.

This is not Minecraft's renderer. Not drawn: player and other entities, block
entities, items in hand, the tab list, the target-block outline and breaking
progress, clouds, weather, particles, screen overlays such as damage or the
underwater haze, and mipmapped or animated atlas frames. Translucent sections are
drawn in store order rather than sorted back to front, and distant terrain has no
LOD. Nothing has been verified on a real server or on a display: the integrated
window path compiles and self-tests headless, and its visual result is untested.

## Menu GUI

`src/render/gui.c` is the widget set: an immediate-mode layer in logical GUI
pixels (the classic auto scale from the window height, or the factor chosen in
the options screen), drawing buttons, toggles, cycles, sliders, a single-line
editor, a scrolling list and text through two entry points the renderer
implements against its GUI vertex buffer. It holds no Vulkan or SDL knowledge.
`src/render/menus.c` is the screen stack built from those widgets: title, world
list, create-world form, server list, add/edit server, direct connect, the
options pages (video, sound, controls, chat, accessibility, language, resource
packs), the connecting screen, the pause menu in two 98-unit columns and the
death screen. Going back returns to the screen recorded on entry, so Options
reached from Pause goes back to Pause. `src/render/menudata.c` owns the files
behind them: `$VORTEX_HOME`/`%APPDATA%\.minecraft`/XDG discovery, a `saves/`
listing, `options.txt` both ways, `servers.dat` read and written as NBT, pack
selection, and deleting a save folder.

What each click does is one action code per frame (`mc_menu_action`), which
`apply_menu_action` in `src/client_main.cpy` turns into a join, a save or a
reload. During a session the window's own actions (chat, disconnect, quit to
title) are handed back through the input queue the Play loop already reads
(`mc_stdin_inject_line`), so the GUI gets the same verbs the terminal has.

This is not Minecraft's GUI. Not implemented: keyboard traversal between
widgets (Tab is accepted but does not move focus), textured widgets from the
pack - the GUI pass still samples the terrain atlas, so every control is drawn
from quads; there is no dedicated GUI texture, no panorama or `widgets.png`, and
no item sprites in an inventory or creative screen. There is no account or skin
screen: the offline name is asked once in the terminal, and no player directory,
`servers.dat` icons, advancements, statistics, Realms, chat signing, LAN scan,
server ping or subtitle rendering exist. The death screen's Respawn button
closes the overlay but cannot send a respawn, because the 26.3 serverbound
client-command respawn variant has not been read from the jar. A world chosen
from the list starts from a seed derived from its folder name: the anvil reader
is not pointed at the embedded server's data path, so saved buildings are not
loaded yet.

`main` mode 3 (`run_local_self_test` in `src/client_main.cpy`) exercises the chat
decoder, block/sky light and the native mesher on a locally built column without
a server connection.

## Server address resolution

`resolve_address` (`src/protocol.cpy`) follows the Minecraft client convention:
an explicit `host:port` suffix wins; otherwise `mc_resolve_srv` (`src/network.c`)
queries the SRV record `_minecraft._tcp.<host>` and uses its lowest-priority
target and port; with no usable record the default port 25565 is used. The
resolver uses `DnsQuery` on Windows and `res_query` on macOS/Linux, so the build
links `dnsapi` on Windows and `resolv` elsewhere.

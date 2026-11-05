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
loaded column. Heightmap NBT is validated and skipped, not retained or decoded
into per-block height values. Block entities are not retained or rendered, and
registry values are not mapped to renderable block/biome definitions. The
standalone NBT section serializer is a Vortex representation, not a complete
Minecraft chunk-save serializer. Play packet handling is partial; the
implementation is not a complete protocol packet set or a full Minecraft
client. The packet IDs and framing remain tied to the client's configured
protocol profile; this chunk-tail layout has not been independently verified
against the claimed 26.3 / protocol 777 profile.

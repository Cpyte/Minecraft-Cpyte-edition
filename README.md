# Minecraft: Cpyte Edition

The final client bundle combines the protocol client with the Vortex voxel
section engine. Build it with `./build.sh src/backend.txt`; add `--run` to run
the result. Run `./test.sh` for focused headless protocol smoke tests and a
backend build without launching the client or renderer. The bundle preserves
the platform-specific C transport import, so the existing POSIX and Winsock
implementations are included in the executable. Builds use Cpyte optimization
level 1 to avoid an LLVM loop-pass assertion in the current compiler; the
compiler itself is unchanged.

Play-state chunk packets decode sections using the dimension bounds and biome
registry size received during Configuration. The active dimension type is
selected from the Play login packet rather than assuming the Overworld. Chunk
lighting is decoded into section data. Heightmaps arrive as a varint count of
heightmap type ids each followed by a packed long array; type 4
(MOTION_BLOCKING) and type 1 (WORLD_SURFACE) are unpacked into per-column
absolute heights and queried through `vworld_height_at`, an unstored type is
walked but dropped, and a stored type whose long count is not the expected 36
rejects the chunk. Block entities are validated but not retained. The block-state global
width remains fixed to the target protocol profile; custom or modded block
registries are not parsed. Most Play packets are still only partially handled,
and there is no client-side world simulation.

Meshed terrain is drawn. The same session that decodes a server's world can open
a Vulkan window that renders it: `./build.sh src/renderer.txt` builds the
standalone window, and backend `main` mode 5 runs a login with the window
attached. The client publishes the finished mesh batches, the player's state and
the chat text it prints to the renderer through C-side channels, so the protocol
code never calls Vulkan itself. What the window does not yet draw — entities,
block entities, the tab list, the target outline, particles, clouds and weather
— is listed in [`docs/PARITY.md`](docs/PARITY.md), along with the fact that the
integrated window has not been run against a real server.

The wire palette rules and current parity scope are recorded in
[`docs/PARITY.md`](docs/PARITY.md). This is a protocol/world-data client, not a
full Minecraft client.

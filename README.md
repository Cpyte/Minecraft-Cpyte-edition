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
lighting is decoded into section data; heightmaps are validated and skipped,
and block entities are validated but not retained. The block-state global
width remains fixed to the target protocol profile; custom or modded block
registries are not parsed. Rendering and world simulation are not connected,
and most Play packets are not implemented.

The wire palette rules and current parity scope are recorded in
[`docs/PARITY.md`](docs/PARITY.md). This is a protocol/world-data client, not a
full Minecraft client.

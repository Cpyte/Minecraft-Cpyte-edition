# Agent guide

## Project purpose and boundaries

This repository is an original Cpyte implementation of a Minecraft-like
Java-protocol client and voxel data backend. It is not a translation or
decompilation of Minecraft. The goal is to interoperate with Java servers where
the selected protocol profile permits it; local/offline accounts do not bypass
online-mode authentication. Do not promise parity with a normal Minecraft
client: rendering and world simulation are not connected, and much of Play
packet handling is partial or absent.

The Cpyte compiler/specification lives in a separate project at
`/Users/main/PycharmProjects/WEW/`. **Do not modify the compiler project.**
Make client changes only in this repository. Do not add Minecraft-derived
source or claim that a protocol catalog means its packets are implemented.

## Build and test

- `./build.sh src/backend.txt` bundles and builds the backend without launching
  the client.
- `./build.sh --run tests/<suite>.txt` builds and runs one headless suite.
- `./test.sh` runs all suites, then builds the backend. Run Cpyte builds
  sequentially: concurrent invocations can race on generated files and build
  artifacts.
- Tests cover `buf`, `nbt`, `palette`, `section`, `wire_chunk`, `heightmap`,
  `registry`, `chunk_light`, `mesher`, `protocol_ids`, `entities`, and
  `protocol_play`.
- `git diff --check` checks whitespace; run it separately from builds that
  rewrite or remove generated files.

The current environment has Cpyte 4.6.7 and Python 3.14. `build.sh` uses
optimization level 1 to avoid a compiler LLVM loop-pass assertion and includes
a compatibility wrapper for the compiler's AOT linker-library API. Preserve
these workarounds unless their necessity is verified; do not fix them by
changing the compiler.

## Architecture and important files

- `src/backend.txt` is the production bundle manifest; `src/engine.txt` is the
  engine manifest. `tests/*.txt` bundle the engine, shared test harness, and a
  test module. `tools/bundle.py` resolves manifests into one Cpyte translation
  unit.
- `src/protocol.cpy` contains packet IDs, frame/VarInt/compression logic,
  configuration and Play flows, packet handlers, and client interaction.
- `src/network.c` and `src/engine/native.c` provide native transport and
  platform helpers; `src/engine/native.cpy` declares the Cpyte bindings.
- `src/world/` contains voxel storage and related state, including entities,
  boss bars, scoreboards, and commands.
- `src/engine/blockdb.c` and `src/engine/blockdb_setup.c` implement and populate
  the validated block database.
- `tests/test_protocol_play.cpy` is the focused Play wire/handler regression
  suite; `tests/test_entities.cpy` covers entity storage and validation.
- `README.md`, `docs/BUILD.md`, and `docs/PARITY.md` describe use, toolchain
  constraints, and known protocol/world parity limits. Keep these accurate when
  behavior changes.

## Horizon reference

`docs/PARITY.md` records a prior behavior comparison against Horizon Rust at
commit [`83ad384`](https://github.com/horizon-rust/horizon/commit/83ad384f48d0742746d518737511882680aab5b7).
Use these upstream files as references when investigating chunk decoding and
the boundary between decoded world data and rendering:

- [`chunk.rs`](https://github.com/horizon-rust/horizon/blob/83ad384f48d0742746d518737511882680aab5b7/crates/horizon-protocol/src/chunk.rs)
  documents the section shape, palette strategy, and padded bit-storage
  packing.
- [`remote_chunks.rs`](https://github.com/horizon-rust/horizon/blob/83ad384f48d0742746d518737511882680aab5b7/crates/horizon-client/src/game/remote_chunks.rs)
  shows how the client uses dimension layout and server registries for decoded
  chunks.
- [`horizon-client-render/src/chunk.rs`](https://github.com/horizon-rust/horizon/blob/83ad384f48d0742746d518737511882680aab5b7/crates/horizon-client-render/src/chunk.rs)
  is a renderer-side chunk/section reference.
- [`horizon-client-render/src/mesher.rs`](https://github.com/horizon-rust/horizon/blob/83ad384f48d0742746d518737511882680aab5b7/crates/horizon-client-render/src/mesher.rs)
  is a renderer-side terrain meshing reference. These are behavioral and
  architectural references only; do not copy source or assets.

Treat Horizon as a behavioral comparison, not code to port or evidence of
complete parity. Verify any protocol-profile assumptions independently and
update `docs/PARITY.md` if the comparison or implementation scope changes.

## Voxel engine and rendering references

The in-repository voxel/world implementation is under `src/world/`:
`world.cpy` owns bounded loaded chunks, `section.cpy` and `palette.cpy` hold
decoded section data, `protocol_chunk.cpy` decodes wire palettes, and
`heightmap.cpy`/`chunk_light.cpy` retain per-column heights and lighting.
`src/world/mesher.cpy` is the readable Cpyte greedy mesher; `src/engine/mesher.c`
is the production parallel worker-pool mesher and mesh-batch API. Their output
contract and algorithm notes are at the top of those files. `tests/mesher.txt`
and `tests/test_mesher.cpy` provide focused coverage.

There is currently no integrated renderer in this repository. Meshing produces
opaque and translucent vertex/index streams, but they are not uploaded or drawn
by a graphics backend; `mesh_loaded_chunk` in `src/protocol.cpy` is not wired
into the session loop. Horizon's renderer links above are useful for
understanding a larger client architecture, not proof that this project's
voxel engine or renderer is equivalent. Do not describe the current backend as
rendering a playable world.

## Protocol and engine status

The client uses a configured protocol profile identified in the project as
Java 26.3 / protocol 777. This profile and real-server interoperability have
not been independently verified. The packet-ID table is a catalog, not proof
of behavioral support. `docs/PARITY.md` is the best current inventory of
implemented packet paths and known gaps; check it before claiming coverage.

Implemented work includes status/login/configuration flow, packet framing and
compression with size limits, registry/dimension handling, chunk section
decoding and light/heightmap storage, block database loading, and partial Play
handlers. The Vortex engine can hold world data and build greedy meshes, but
there is no renderer connected and the session loop does not submit loaded
chunks to rendering. Block entities are validated/skipped rather than retained;
custom or modded block registries are not mapped to renderable definitions.
Many Play handlers remain log-only or structurally partial; signed chat and
some sound, particle, effect, metadata, equipment, and other packet semantics
are incomplete. Do not describe this as a complete Minecraft backend.

## Cpyte implementation constraints

These are compiler-specific behaviors already encountered here. Follow the
patterns in nearby code and `docs/BUILD.md`:

- Definitions must precede use in the bundled translation unit, including
  helpers called by a function. Keep helper ordering bottom-up.
- A bare `return -1` from an `int64` function can widen incorrectly; return
  `(int64)-1` or a typed local.
- Locals only used in f-string interpolation may still trigger unused-variable
  warnings; underscore-prefix intentional such locals.
- Use `(char*)0`, not `null`, for a null pointer.
- Avoid reassigning heap array locals; return from branches instead of
  discarding their allocations.
- `del` is a move. Do not use values after passing them to a `del` parameter.
- Use C helpers in `src/engine/native.c` for text input/bytes. Engine-only
  bundles must not call protocol/network-only helpers; use portable
  `text_len`/`code_at` from `src/util/strings.cpy` where appropriate.
- Parenthesize bitwise comparisons, e.g. `(flags & bit) == 0`.
- Cast wide integer expressions explicitly when assigning to `int`.
- Keep `print(...)` calls on one source line; implicit line continuation in
  calls is not accepted.
- A local passed by address may read stale afterward; where possible, use the
  returned array/value from helpers rather than relying on an out parameter.
- An `-> int` function cannot directly return a boolean comparison; use
  explicit integer branches.
- Declare arrays as `int64[]`, not `int64`, even when initialized with
  `new int64[...]`.
- Prefer explicit bounds checks before indexing/parsing. Preserve existing
  error reporting rather than silently accepting malformed packets.

## Continuing work safely

The worktree has been heavily modified across prior tasks and contains staged,
unstaged, and untracked project changes. Build/test commands also regenerate
tracked files under `build/` and `dist/`. Before editing, inspect `git status
--short` and the relevant diff. Preserve changes you did not make: do not reset,
checkout, clean, or broadly revert generated files. Do not stage or commit
unless explicitly requested.

Recent hardening added strict block database file/record validation,
entity-capacity and setter checks, a POSIX/Windows send-length type, Play
dispatcher checks for handler failures, and malformed block-event/entity and
teleport bounds checks with regression tests. During that work, a duplicate
`pl_team_members` definition that appeared after its caller was removed and the
single helper was placed before `pl_handle_set_player_team`, because Cpyte
requires definition-before-use.

Most recent verification: `./test.sh` passed all 12 headless suites and built
the backend; `git diff --check` passed. The test run rewrote tracked build and
distribution outputs, so review their status but do not assume those diffs are
source changes. Continue production hardening surgically: inspect handler
field boundaries and trailing bytes, add focused malformed-input tests, and
update `docs/PARITY.md` for material behavior changes. Do not infer the
behavior of the entire protocol from tests of individual handlers.

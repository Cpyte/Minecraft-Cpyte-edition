# Build and Cpyte toolchain notes

The engine is written in Cpyte and compiled ahead of time; there is no
interpreter or Python at run time. `tools/bundle.py <manifest> build/<name>.cpy`
concatenates the modules listed in a manifest into a single translation unit,
and `build.sh` then runs
`python3 -m cpyte build --opt 1 --output dist/<name>.exe build/<name>.cpy`.
One unit is required because Cpyte resolves names within a file, so a module
cannot call a sibling module that the manifest placed after it.

Manifests list modules in dependency order and `use <manifest>` splices in
another list. `src/engine.txt` is the engine; `src/backend.txt` adds the
protocol client; `src/renderer.txt` adds the Vulkan renderer and its own entry
point; `tests/*.txt` add `harness.cpy` and one test module.

The renderer needs Vulkan headers, SDL2, libpng and zlib at link time, and its
shaders are committed as `src/render/shaders_spv.h` so a build never needs a
GLSL compiler. Regenerate that header with `glslangValidator -V` over the
`.vert`/`.frag` files in `src/render/shaders/` after editing a shader; `build.sh`
does not do it.

## The embedded single-player server

Single player and multiplayer are the same executable. The world is a Rust
library (`server/`: a C ABI over Pumpkin) that the client opens at run time, so
no cargo build is part of the normal client and a client without the library
only reports that mode 6 is unavailable.

```
./tools/pumpkin_host.sh          # fetch the pinned revision, build the library
./build.sh --run src/backend.txt # then choose mode 6
```

`tools/pumpkin_host.sh` clones Pumpkin into `vendor/pumpkin` at the revision the
shim is written against and builds `libpumpkin_host.{dylib,so,dll}`, copying it
beside `dist/backend.exe`. `src/engine/host.c` finds it through
`VORTEX_SERVER_LIB`, next to the executable, in the working directory, or in
`server/target/release`, resolves the `pk_host_*` and `pk_pipe_*` entry points,
and installs the in-memory pipe as an alternate transport in `src/network.c` for
the negative handle the connection returns. `offline_login` takes that handle
instead of opening a TCP connection. The bytes never reach a network stack.

Licensing, and it is not a detail: Pumpkin is GPL-3.0, so distributing this
client together with the library it loads means distributing a GPL-3.0 work with
source available. Pumpkin's game data additionally derives from Mojang's server
jar and is governed by the Minecraft EULA. This repository is MIT and ships no
part of Pumpkin: `vendor/`, `server/target/` and the copied library are
gitignored, and the fetch happens only when you run the script.

## Rules that come from the compiler itself

These are observed behaviours of Cpyte 4.6.7, not style preferences.

- **Definitions must precede use** in the bundled unit, including inside struct
  method call chains. `src/protocol.cpy` is ordered bottom-up for this reason.
- **`return -1` from an `int64` function yields `4294967295`.** The negative
  literal is widened unsigned on the return path, so a caller's `value < 0`
  test silently passes. Write `return (int64)-1`, or assign to an `int64` local
  first. Parameters and array slots convert correctly, so only bare negative
  return literals are affected.
- **`W1001 assigned but never used` ignores f-string interpolation.** A local
  that only appears in `print(f"{value}")` is still reported. Either print it
  with a real use or prefix the name with `_`, which the linter accepts.
- **`char* p = null` triggers `W0001 implicit int-to-pointer conversion`.**
  Use `char* p = (char*)0`.
- **Reassigning a heap `int64[]` local** reports
  `W0001 unmanaged memory: ... discards its previous heap allocation`. Return
  from each branch instead of rebinding the variable.
- **`del` is a move**, so a value cannot be read after it is passed to a `del`
  parameter, and a struct pointer must not be freed while a branch still uses
  it.
- There is no `pass` statement, and text handling goes through the C helpers in
  `src/engine/native.c` rather than string indexing or slicing.
- **`unsigned long long` only appears in `native.c` signatures.** Cpyte maps it
  to its own `uint64`: a struct field must be declared `uint64*`, a cast must be
  written `(uint64)`, and `unsigned long long* x = vt_calloc_u64(n)` is a parse
  error. Assign the result straight to a `uint64*` field.
- **Bitwise operators bind looser than comparison.** `flags & bit == 0` parses
  as `flags & (bit == 0)` and reports that `&` got a `bool`; write
  `(flags & bit) == 0`.
- **An integer literal wider than int32 makes the expression int64**, so
  `int slot = (id * 2654435761) & mask` is a narrowing-conversion error; cast
  the product with `(int)`.
- **Implicit line continuation is not accepted inside `print(...)`** - a second
  f-string on the next line is a parse error. Keep the whole message on one
  line.
- **An address-taken local reads back stale in the next expression.** Passing
  `&value` to a function that writes through the pointer does not invalidate the
  register Cpyte allocated for `value`, so `int size = 0; fill(&size); return
  cursor + size;` silently adds zero. The array results every `decode_*` helper
  returns exist for this reason: reading `result[1]` is a memory read.
- **A `return` of a comparison from a `-> int` function is `E0001`** ("wrong
  return type `bool`"); spell the two branches out with `return 0` and
  `return 1`.
- **Array locals must be declared with the array type.** `int64 result = new
  int64[3]` compiles but then reports `cannot index value of type int64` at
  every `result[i]`; write `int64[] result = new int64[3]`.
- **Only modules in the bundle exist.** `mc_string_length` and `mc_string_byte`
  live in the network client's C imports, so an engine module that uses them
  breaks every suite that omits `src/protocol.cpy`; `text_len` and `code_at` in
  `src/util/strings.cpy` are the portable equivalents.

## The menu GUI

`src/render/gui.c` (widgets), `src/render/menus.c` (the screens) and
`src/render/menudata.c` (the files behind them: `saves/`, `options.txt`,
`servers.dat`) are imported by `src/render/renderer.cpy`, so they join every
bundle that contains the renderer, including the test bundles. Each compiles on
its own with `cc -Wall -Wextra -O1 -I src/render -c <file>`; that is the fastest
way to check a change there without linking Vulkan.

`main` mode 7 runs the whole client through the window: the title screen, both
lists, the options pages, the game and the pause menu. It needs the same
libraries as the renderer plus a discovered pack, and it reads one line from the
terminal first - the offline name - because the account screen does not exist
yet. `./tools/pumpkin_host.sh` must have run for mode 7 to offer single player;
without the library the rest of the menus still work and the embedded mode
reports itself unavailable.

## Verifying a change

`./test.sh` runs every headless suite and then builds the client backend. Build
and run one suite with `./build.sh --run tests/<name>.txt`. The suites are
`buf`, `nbt`, `palette`, `section`, `wire_chunk`, `heightmap`, `registry`,
`chunk_light`, `mesher`, `protocol_ids`, `entities` and `protocol_play`.

`DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib` traps out-of-bounds heap
writes at the first offense, but every binary in this project, including ones
that pass, dies under guard malloc because the Cpyte runtime is incompatible
with it. Use it to locate a suspect access, not as a pass or fail gate.

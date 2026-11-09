#!/usr/bin/env bash
# Build a Vortex target with the Cpyte compiler.
#
#   ./build.sh --run src/backend.txt  # protocol client + voxel section engine
#   ./build.sh tests/buf.txt          # bundle the test manifest -> dist/buf.exe
#   ./build.sh hello.cpy              # single file           -> dist/hello.exe
#   ./build.sh --run tests/buf.txt    # build, then execute it
#
# A .txt argument is a tools/bundle.py manifest: the engine modules are
# concatenated into build/<name>.cpy first, because the Cpyte back end cannot
# resolve another file's struct fields or module constants. See README.md.
set -euo pipefail

RUN=0
if [ "${1:-}" = "--run" ]; then
  RUN=1
  shift
fi

TARGET="${1:?usage: build.sh [--run] <target.cpy|target.txt>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPYTE_HOME="${CPYTE_HOME:-/c/Users/Son ha/cpyte}"
PREFIX="${MSYS2_MINGW64:-/c/msys64v/msys64/mingw64}"
PYTHON="${PYTHON:-python}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  PYTHON=python3
fi

cd "$HERE"
mkdir -p build dist

NAME="$(basename "$TARGET")"
NAME="${NAME%.*}"

case "$TARGET" in
  *.txt)
    SOURCE="build/$NAME.cpy"
    "$PYTHON" tools/bundle.py "$TARGET" "$SOURCE"
    ;;
  *)
    SOURCE="$TARGET"
    ;;
esac
if [ ! -f "$SOURCE" ]; then
  echo "build.sh: no such source: $SOURCE" >&2
  exit 1
fi

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    # Cpyte's numeric runtime needs the MSYS2 GMP/MPFR development headers.
    export CPYTE_GMP_INCLUDE="$(cygpath -w "$PREFIX/include")"
    export CPYTE_MPFR_INCLUDE="$(cygpath -w "$PREFIX/include")"
    # src/network.c needs Winsock, the DNS resolver and zlib import libraries on
    # Windows.
    export CPYTE_EXTRA_LIBS="${CPYTE_EXTRA_LIBS:+$CPYTE_EXTRA_LIBS }ws2_32 dnsapi z"
    ;;
  Darwin)
    export CPATH="/opt/homebrew/include${CPATH:+:$CPATH}"
    export LIBRARY_PATH="/opt/homebrew/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
    ;;
esac

if [ -d "$CPYTE_HOME/source" ]; then
  export PYTHONPATH="$CPYTE_HOME/source${PYTHONPATH:+:$PYTHONPATH}"
fi

# Cpyte's C step cannot overwrite an existing object file: the second build of
# a target fails with "can't create <name>.runpy.o: Invalid argument", so the
# per-target objects from the previous build go first.
case "$SOURCE" in
  */*) SOURCE_DIR="${SOURCE%/*}" ;;
  *) SOURCE_DIR="." ;;
esac
rm -f "$SOURCE_DIR/$NAME.o" "$SOURCE_DIR/$NAME.gc.o" \
     "$SOURCE_DIR/$NAME.runpy.o" "$SOURCE_DIR/$NAME.runtime.o"

# Build and link.
#
# compiling.aot_link_executable() tries the first link with ['-lm'] only and
# bails out unless the linker complains about a GMP/MPFR symbol, so the zlib
# symbols our C imports need are never resolved. Patching
# compiling.aot_link_libraries() does not help: that list is only consulted on
# the GMP retry. Inject the extra libraries into every link attempt instead.
"$PYTHON" -c "
import sys
from cpyte import compiling, mainpie

extra = ['z']
if sys.platform == 'win32':
    extra.append('ws2_32')
    extra.append('dnsapi')
else:
    extra.append('resolv')
    extra.append('vulkan')
    extra.append('SDL2')
    extra.append('png')
    # src/engine/host.c opens the embedded server library at run time. glibc
    # only folded dl*() into libc from 2.34, so link it explicitly.
    if sys.platform.startswith('linux'):
        extra.append('dl')

def link_with_extra(linker, objects, output, **kwargs):
    original = linker.link
    def link(objs, out, libraries=None, library_paths=None, **kw):
        libs = list(libraries or [])
        lib_paths = list(library_paths or [])
        for name in extra:
            if name not in libs:
                libs.append(name)
        if sys.platform == 'darwin' and '/opt/homebrew/lib' not in lib_paths:
            lib_paths.append('/opt/homebrew/lib')
        return original(objs, out, libraries=libs, library_paths=lib_paths, **kw)
    linker.link = link
    try:
        return compiling.aot_link_executable(linker, objects, output, **kwargs)
    finally:
        linker.link = original

mainpie.aot_link_executable = link_with_extra
mainpie.main()
" build \
  --opt 1 --output "dist/$NAME.exe" "$SOURCE"

echo "built: dist/$NAME.exe"
if [ "$RUN" = "1" ]; then
  # The AOT executable links against the mingw runtime (libmpfr, libgomp).
  PATH="$PREFIX/bin:$PATH" "./dist/$NAME.exe"
fi

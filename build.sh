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
    # src/network.c needs Winsock and zlib import libraries on Windows.
    export CPYTE_EXTRA_LIBS="${CPYTE_EXTRA_LIBS:+$CPYTE_EXTRA_LIBS }ws2_32 z"
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

# Avoid the current compiler's LLVM loop-pass assertion, including on macOS's
# default Bash 3.2 where expanding an empty array under `set -u` fails.
"$PYTHON" -m cpyte build \
  --opt 1 --output "dist/$NAME.exe" "$SOURCE"

echo "built: dist/$NAME.exe"
if [ "$RUN" = "1" ]; then
  # The AOT executable links against the mingw runtime (libmpfr, libgomp).
  PATH="$PREFIX/bin:$PATH" "./dist/$NAME.exe"
fi

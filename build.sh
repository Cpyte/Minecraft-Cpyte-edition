#!/usr/bin/env bash
# Build a Vortex engine target with the Cpyte compiler.
#
#   ./build.sh tests/buf.txt          # bundle the test manifest -> dist/buf.exe
#   ./build.sh hello.cpy              # single file           -> dist/hello.exe
#   ./build.sh --run tests/buf.txt    # build, then execute it
#
# A .txt argument is a tools/bundle.py manifest: the engine modules are
# concatenated into build/<name>.cpy first, because the Cpyte back end cannot
# resolve another file's struct fields or module constants. See docs/BUILD.md.
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

cd "$HERE"
mkdir -p build dist

NAME="$(basename "$TARGET")"
NAME="${NAME%.*}"

case "$TARGET" in
  *.txt)
    SOURCE="build/$NAME.cpy"
    python tools/bundle.py "$TARGET" "$SOURCE"
    ;;
  *.cpy)
    SOURCE="$TARGET"
    ;;
  *)
    SOURCE="$TARGET.cpy"
    ;;
esac
if [ ! -f "$SOURCE" ]; then
  echo "build.sh: no such source: $SOURCE" >&2
  exit 1
fi

# Cpyte compiles its bignum/float runtime from C at build time, which needs the
# GMP and MPFR development headers and link libraries.
export CPYTE_GMP_INCLUDE="$(cygpath -w "$PREFIX/include")"
export CPYTE_MPFR_INCLUDE="$(cygpath -w "$PREFIX/include")"

# src/network.c talks to Winsock and zlib. On POSIX both come from libc and the
# dynamically loaded libz, but a Windows link has to name the import libraries,
# and CPYTE_EXTRA_LIBS is the only hook a .cpy program has for that.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    export CPYTE_EXTRA_LIBS="${CPYTE_EXTRA_LIBS:+$CPYTE_EXTRA_LIBS }ws2_32 z"
    ;;
esac

PYTHONPATH="$CPYTE_HOME/source" python -m cpyte build \
  --output "dist/$NAME.exe" "$SOURCE"

echo "built: dist/$NAME.exe"
if [ "$RUN" = "1" ]; then
  # The AOT executable links against the mingw runtime (libmpfr, libgomp).
  PATH="$PREFIX/bin:$PATH" "./dist/$NAME.exe"
fi

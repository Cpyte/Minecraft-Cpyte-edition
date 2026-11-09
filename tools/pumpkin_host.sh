#!/usr/bin/env bash
# Build the embedded single-player server library.
#
#   ./tools/pumpkin_host.sh
#   CARGO_TARGET_DIR=/path/to/target ./tools/pumpkin_host.sh   # reuse a tree
#
# The result is server/target/release/libpumpkin_host.{dylib,so,dll}: a C ABI
# over Pumpkin that boots a Java 26.3 server on its own threads and talks to the
# client through an in-memory pipe. The client opens it at run time, so nothing
# else in the build depends on Rust and one executable still does both
# multiplayer and single player. It is copied next to dist/backend.exe, and
# otherwise found by VORTEX_SERVER_LIB or in ./server/target/release.
#
# Licensing, and it is not a detail: Pumpkin is GPL-3.0, so an executable that
# loads it and ships it as its own module must be distributed under GPL-3.0 with
# source available. Its extracted game data additionally derives from Mojang's
# server jar and is governed by the Minecraft EULA. This repository is MIT and
# ships no part of Pumpkin - vendor/ and the build output are gitignored, and the
# fetch happens only when you run this script.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The revision this shim is written against. Pumpkin's internals move, so the
# pin is what makes a rebuilt library still compile here.
REVISION="ac235ed7793db5cbdf455a14e641ed05fea0bc52"
REMOTE="${PUMPKIN_REMOTE:-https://github.com/Pumpkin-MC/Pumpkin}"

cd "$HERE"
if ! command -v cargo >/dev/null 2>&1; then
  echo "pumpkin_host.sh: cargo (Rust 1.90 or newer) is required" >&2
  exit 1
fi

SOURCE="$HERE/vendor/pumpkin"
if [ ! -d "$SOURCE" ]; then
  mkdir -p vendor
  echo "fetching Pumpkin into vendor/pumpkin ..."
  git clone --quiet "$REMOTE" vendor/pumpkin
fi

if [ -e "$SOURCE/.git" ]; then
  CURRENT="$(git -C "$SOURCE" rev-parse HEAD)"
  if [ "$CURRENT" != "$REVISION" ]; then
    if [ -n "$(git -C "$SOURCE" status --porcelain)" ]; then
      echo "pumpkin_host.sh: $SOURCE has local changes and is not at $REVISION" >&2
      echo "pumpkin_host.sh: check it out yourself, or replace the clone" >&2
      exit 1
    fi
    git -C "$SOURCE" fetch --quiet origin "$REVISION" 2>/dev/null || true
    git -C "$SOURCE" checkout --quiet "$REVISION"
  fi
fi

echo "building the host library against $SOURCE ..."
TARGET="${CARGO_TARGET_DIR:-$HERE/server/target}"
(cd "$HERE/server" && CARGO_TARGET_DIR="$TARGET" cargo build --release)

case "$(uname -s)" in
  Darwin) LIBNAME=libpumpkin_host.dylib ;;
  MINGW*|MSYS*|CYGWIN*) LIBNAME=pumpkin_host.dll ;;
  *) LIBNAME=libpumpkin_host.so ;;
esac
if [ ! -f "$TARGET/release/$LIBNAME" ]; then
  echo "pumpkin_host.sh: $TARGET/release/$LIBNAME was not produced" >&2
  exit 1
fi

# Beside the client, where src/engine/host.c looks first.
if [ -d dist ]; then
  cp "$TARGET/release/$LIBNAME" "dist/$LIBNAME"
  echo "copied to dist/$LIBNAME"
fi
echo "built: $TARGET/release/$LIBNAME"

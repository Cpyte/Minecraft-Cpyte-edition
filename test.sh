#!/usr/bin/env bash
# Run focused headless engine/protocol smoke tests and build without launching.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

SMOKE_TESTS=(
  tests/buf.txt
  tests/wire_chunk.txt
  tests/registry.txt
  tests/chunk_light.txt
)

if [ "$#" -ne 0 ]; then
  echo "usage: ./test.sh" >&2
  exit 2
fi

TESTS=("${SMOKE_TESTS[@]}")

for manifest in "${TESTS[@]}"; do
  printf '\n==> %s\n' "$manifest"
  ./build.sh --run "$manifest"
done

printf '\n==> Building client backend (not launching renderer/client)\n'
./build.sh src/backend.txt
printf '\nHeadless tests passed; backend build succeeded.\n'

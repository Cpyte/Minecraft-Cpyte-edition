#!/usr/bin/env python3
"""Assemble Vortex engine sources into one Cpyte translation unit.

Why bundling rather than `import "..."`: the Cpyte 4.6.7 back end resolves a
struct declaration across imported files but not its *fields* - touching
`ptr.member` on a struct owned by another file aborts codegen with
"Unknown field". Module-level constants are likewise only visible inside
`main()` when imported. Both rules make a conventional multi-file split
unworkable for an engine that passes chunk and registry state around, so each
module lives in its own file for clarity and is concatenated into a single
compilation unit here, in dependency order.

Usage:
    python tools/bundle.py src/engine.txt build/vortex.cpy
"""
import os
import pathlib
import re
import sys

HEADER = """# Vortex engine - generated bundle. Do not edit: this file is assembled from
# the modules listed below by tools/bundle.py.
#
#   {sources}

import stdlib
{imports}
"""


def read_manifest(manifest: pathlib.Path) -> list[pathlib.Path]:
    """Manifest entries are read in order, resolved against the directory the
    manifest lives in. A `use <other manifest>` line splices in another list."""
    sources: list[pathlib.Path] = []
    for line in manifest.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("use "):
            nested = (manifest.parent / line[4:].strip()).resolve()
            sources.extend(read_manifest(nested))
        else:
            sources.append((manifest.parent / line).resolve())
    return sources


def strip_module_headers(text: str) -> str:
    """Drop per-module `import` lines; the bundle is one flat scope."""
    return re.sub(r"(?m)^import\s+\S+\s*$", "", text)


def c_imports(sources: list[pathlib.Path], output_dir: pathlib.Path) -> str:
    """Keep C imports and rewrite them relative to the generated bundle."""
    imports: set[str] = set()
    for source in sources:
        for match in re.finditer(r'(?m)^import\s+"([^"]+\.c)"\s*$', source.read_text(encoding="utf-8")):
            target = (source.parent / match.group(1)).resolve()
            relative = os.path.relpath(target, output_dir)
            imports.add(f'import "{relative}"')
    return "\n".join(sorted(imports))


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    manifest = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    sources = read_manifest(manifest)
    for src in sources:
        if not src.is_file():
            print(f"bundle.py: missing module {src}", file=sys.stderr)
            return 1
    chunks = [HEADER.format(
        sources=", ".join(p.name for p in sources),
        imports=c_imports(sources, out.parent.resolve()),
    )]
    for src in sources:
        body = strip_module_headers(src.read_text(encoding="utf-8"))
        chunks.append(f"# ===== {src.name} =====\n{body}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n\n".join(chunks), encoding="utf-8")
    print(f"bundled {len(sources)} modules -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

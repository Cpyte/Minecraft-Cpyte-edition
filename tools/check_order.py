#!/usr/bin/env python3
"""Report Cpyte call-order violations: a call to a function defined later.

Cpyte resolves a call target only against definitions already parsed, so a
bundle must list callees before callers. Self-recursive calls are legal.

    python tools/check_order.py build/protocol_ids.cpy
"""
import io
import re
import sys

DEF = re.compile(r"^(?:public )?def (\w+)\(")
CALL = re.compile(r"\b(\w+)\(")
BUILTINS = {
    "def", "if", "elif", "while", "for", "return", "else", "print", "len",
    "append", "del", "struct", "import", "use", "new", "and", "or", "not",
}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    lines = io.open(sys.argv[1], encoding="utf-8").read().split("\n")
    order = {}
    for i, line in enumerate(lines):
        m = DEF.match(line)
        if m and m.group(1) not in order:
            order[m.group(1)] = i + 1
    current = None
    bad = []
    for i, line in enumerate(lines):
        m = DEF.match(line)
        if m:
            current = m.group(1)
            continue
        if line.lstrip().startswith("#") or current is None:
            continue
        code = line.split("#", 1)[0]
        for name in CALL.findall(code):
            where = order.get(name)
            if where is None or name == current or name in BUILTINS:
                continue
            if where > i + 1:
                bad.append((i + 1, current, name, where))
    for line_no, caller, callee, defined in bad:
        print(f"L{line_no} {caller} -> {callee} defined later at L{defined}")
    print(f"found: {len(bad)} forward calls")
    return 0


if __name__ == "__main__":
    sys.exit(main())

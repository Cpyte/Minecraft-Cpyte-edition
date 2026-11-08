"""Expand Cpyte's rejected one-line `head: stmt` bodies onto two lines.

Cpyte 4.6.9 parses `if cond: return x` and `def f() -> int: return 0` as a
syntax error (a colon must end its line). The split point is the first colon
at bracket depth zero and outside a string, which is exactly the colon that
ends an if/elif/while condition or a signature, so annotations inside a
parameter list and text containing ": " are left alone.
"""

import io
import re
import sys

HEAD = re.compile(r"^(?:(?:el)?if|while|public def|def)\b")
OPEN = {"(": ")", "[": "]", "{": "}"}


def split_point(line):
    depth = 0
    quote = ""
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch in OPEN:
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == ":" and depth == 0:
            return i
        i += 1
    return -1


def expand(text):
    out = []
    changed = 0
    for line in text.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("#") or not HEAD.match(stripped):
            out.append(line)
            continue
        cut = split_point(line)
        rest = line[cut + 1:].strip() if cut >= 0 else ""
        if cut < 0 or not rest:
            out.append(line)
            continue
        indent = " " * (len(line) - len(stripped))
        out.append(line[:cut + 1])
        out.append(indent + "    " + rest)
        changed += 1
    return "\n".join(out), changed


def main(paths):
    for path in paths:
        text = io.open(path, encoding="utf-8").read()
        grown, changed = expand(text)
        if changed:
            io.open(path, "w", encoding="utf-8", newline="\n").write(grown)
        print("%s: expanded %d one-line bodies" % (path, changed))


if __name__ == "__main__":
    main(sys.argv[1:])

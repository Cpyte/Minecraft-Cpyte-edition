import io

PATH = "src/proto/wire.cpy"
lines = io.open(PATH, encoding="utf-8").read().split("\n")


def find(prefix):
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            return i
    raise SystemExit("not found: " + prefix)


def block(start):
    i = start + 1
    while i < len(lines):
        if lines[i].startswith("def ") or lines[i].startswith("public def "):
            break
        i += 1
    while i > start + 1 and lines[i - 1].strip() == "":
        i -= 1
    return lines[start:i]


def move(prefix, before_prefix):
    start = find(prefix)
    body = block(start)
    del lines[start:start + len(body)]
    target = find(before_prefix)
    lines[target:target] = body + ["", ""]


move("def pw_gate_cut(", "def pw_gate_field(")
move("def pw_metadata_token(", "def pw_measure_token(")

old = """    elif kind == pw_k_metadata():
        pw_read_metadata(w, &unused)"""
new = """    elif kind == pw_k_metadata():
        int md_entries = 0
        while true:
            if vbuf_avail(w.b) < 2:
                w.error = pw_err_truncated()
                return 0
            int md_index = (int)vbuf_take_u8(w.b)
            if md_index == 255:
                break
            int md_kind = (int)pw_read_varint(w)
            if w.error != pw_err_none():
                return 0
            str md_shape = pw_metadata_token(md_kind)
            if vt_strlen(md_shape) == 0:
                w.error = pw_err_shape()
                return 0
            int md_n = pw_token_count(md_shape)
            int md_i = 0
            while md_i < md_n:
                if pw_measure_token(w, pw_plain(pw_token(md_shape, md_i)), depth + 1) == 0:
                    return 0
                md_i += 1
            md_entries += 1
            if md_entries > pw_array_max():
                w.error = pw_err_range()
                return 0
        return 1"""

text = "\n".join(lines)
assert old in text
text = text.replace(old, new, 1)
io.open(PATH, "w", encoding="utf-8", newline="\n").write(text)
print("ok")

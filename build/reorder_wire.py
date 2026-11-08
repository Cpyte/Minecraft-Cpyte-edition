import io

PATH = "src/proto/wire.cpy"
lines = io.open(PATH, encoding="utf-8").read().split("\n")


def sl(a, b):
    # 1-based inclusive
    return lines[a - 1:b]


measure_token = "\n".join(sl(664, 716))
nested_loops = """
        str inner_shape = pw_inner(plain)
        int in = pw_token_count(inner_shape)
        int ii = 0
        while ii < in:
            str itoken = pw_token(inner_shape, ii)
            if pw_gate_open(w, itoken, 0) == 0:
                if w.error != pw_err_none():
                    return 0
            elif pw_measure_token(w, pw_plain(itoken), depth) == 0:
                return 0
            ii += 1
        return 1"""

old_option = """        return pw_measure(w, pw_inner(plain), depth)"""
assert old_option in measure_token
measure_token = measure_token.replace(old_option, nested_loops.strip())

nested_array = """
        str sub = pw_sub_shape(pw_sub_name(plain))
        if vt_strlen(sub) == 0:
            w.error = pw_err_shape()
            return 0
        int64 sub_count = pw_read_varint(w)
        if w.error != pw_err_none():
            return 0
        if sub_count < (int64)0 or sub_count > (int64)pw_array_max():
            w.error = pw_err_range()
            return 0
        int sn = pw_token_count(sub)
        int e = 0
        while e < (int)sub_count:
            int sk = 0
            while sk < sn:
                str stoken = pw_token(sub, sk)
                if pw_gate_open(w, stoken, 0) == 0:
                    if w.error != pw_err_none():
                        return 0
                elif pw_measure_token(w, pw_plain(stoken), depth + 1) == 0:
                    return 0
                sk += 1
            e += 1
        return 1"""

old_array = """        return pw_measure_array(w, plain, depth)"""
assert old_array in measure_token
measure_token = measure_token.replace(old_array, nested_array.strip())

# pw_measure_tokens is a self-contained composite walk used by pw_measure_token
# (self-recursion is legal; a forward call to pw_measure is not).
measure_tokens_helper = """def pw_measure_tokens(w: VWire*, shape: str, depth: int) -> int:
    if vt_strlen(shape) == 0:
        w.error = pw_err_shape()
        return 0
    if depth > pw_depth_max():
        w.error = pw_err_shape()
        return 0
    int count = pw_token_count(shape)
    int i = 0
    while i < count:
        str token = pw_token(shape, i)
        if pw_gate_open(w, token, 0) == 0:
            if w.error != pw_err_none():
                return 0
        elif pw_measure_token(w, pw_plain(token), depth) == 0:
            return 0
        i += 1
    return 1"""

# Depth guard at entry: the walkers below are self-recursive, so the only
# recursion limit is the one checked here.
guard = """def pw_measure_token(w: VWire*, plain: str, depth: int) -> int:
    if depth > pw_depth_max():
        w.error = pw_err_shape()
        return 0"""
measure_token = measure_token.replace(
    "def pw_measure_token(w: VWire*, plain: str, depth: int) -> int:", guard, 1)

gates_comment = "\n".join(sl(756, 757))
gate_value = "\n".join(sl(758, 773))
gate_open = "\n".join(sl(775, 797))
gate_open_sub = "\n".join(sl(983, 1007))
flat_slots = "\n".join(sl(1065, 1087))
meas_header = "\n".join(sl(658, 663))
measure = "\n".join(sl(737, 754))
measure_array = "\n".join(sl(718, 735))
rec_header = "\n".join(sl(799, 800))
records = "\n".join(sl(801, 831))
record_flat = "\n".join(sl(1010, 1015))
read_flat_token = "\n".join(sl(1018, 1063))
read_flat = "\n".join(sl(961, 981))
array_sub = "\n".join(sl(910, 912))
read_array = "\n".join(sl(914, 958))
read_field = "\n".join(sl(833, 908))
walk = "\n".join(sl(1090, 1118))

# pw_read_field must not forward-call pw_read_array; reorder already fixes it,
# but the option branch calls pw_read_field recursively (legal).
region = "\n\n".join([
    gates_comment,
    gate_value,
    "\n\n".join([gate_open, gate_open_sub]),
    flat_slots,
    meas_header,
    measure_token,
    measure,
    measure_array,
    rec_header,
    records,
    "\n\n".join([record_flat, read_flat_token, read_flat]),
    "\n\n".join([array_sub, read_array]),
    read_field,
    walk,
])

out = "\n".join(sl(1, 657)) + "\n" + region + "\n" + "\n".join(sl(1119, len(lines)))
io.open(PATH, "w", encoding="utf-8", newline="\n").write(out)
print("region lines:", region.count("\n") + 1, "total:", out.count("\n") + 1)

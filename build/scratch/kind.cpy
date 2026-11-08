def f() -> int:
    int kind = 5
    int64 v = (int64)12
    if (v >> (int64)1) & (int64)1 != (int64)0:
        return kind
    return 0


def main() -> int:
    print_int(f.f())
    return 0

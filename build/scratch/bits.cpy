def g(v: uint64, bit: int) -> int:
    if (v >> (uint64)bit) & (uint64)1 != (uint64)0:
        return 1
    return 0


def h(v: int64) -> int:
    uint64 u = (uint64)v
    if (u >> (uint64)2) & (uint64)1 != (uint64)0:
        return 1
    return 0


def k(v: int64) -> int:
    if ((uint64)v >> (uint64)2) & (uint64)1 != (uint64)0:
        return 1
    return 0


def main() -> int:
    return g.g((uint64)5, 1) + h.h((int64)5) + k.k((int64)5)

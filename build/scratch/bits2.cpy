def g(v: uint64, bit: int) -> int:
    uint64 shifted = v >> (uint64)bit
    uint64 masked = shifted & (uint64)1
    if (int)masked != 0:
        return 1
    return 0


def h(v: int64, bit: int) -> int:
    uint64 u = (uint64)v
    uint64 masked = (u >> (uint64)bit) & (uint64)1
    if masked != (uint64)0:
        return 1
    return 0


def k(v: int64, mask: int) -> int:
    uint64 masked = (uint64)v & (uint64)mask
    if masked != (uint64)0:
        return 1
    return 0


def main() -> int:
    return g.g((uint64)5, 1) + h.h((int64)6, 1) + k.k((int64)6, 4)

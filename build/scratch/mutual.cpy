def a(n: int) -> int:
    if n <= 0:
        return 0
    return b(n - 1)


def b(n: int) -> int:
    if n <= 0:
        return 0
    return a(n - 1)


def main() -> int:
    print_int(a(5))
    return 0

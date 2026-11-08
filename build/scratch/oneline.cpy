def f(x: int) -> str:
    if x == 1: return "a"
    return "b"


def main() -> int:
    print(f.f(1))
    return 0

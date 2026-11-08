struct Inner:
    int len
    int pos


struct Outer:
    Inner* i
    int fields


public def outer_len(o: Outer*) -> int:
    Inner* local = o.i
    return local.len


def main() -> int:
    Inner* value = new Inner
    value.len = 7
    value.pos = 1
    Outer* o = new Outer
    o.i = value
    o.fields = 3
    return outer_len(o)

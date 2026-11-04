# Vortex engine - the shared assertion harness for the test bundles.
#
# A test target's manifest lists the engine, this file, and the test itself;
# failures count up through an `int*` out parameter because Cpyte module-level
# variables are only reachable from `main()`.

import stdlib


def check(label: str, cond: bool, fails: int*) -> void:
    if cond:
        print("  ok   " + label)
    else:
        print("  FAIL " + label)
        *fails = *fails + 1


def check_int(label: str, got: int, want: int, fails: int*) -> void:
    if got == want:
        print("  ok   " + label)
    else:
        print("  FAIL " + label + ": got " + str(got) + " want " + str(want))
        *fails = *fails + 1


def check_str(label: str, got: str, want: str, fails: int*) -> void:
    if str_equals(got, want):
        print("  ok   " + label)
    else:
        print("  FAIL " + label + ": got '" + got + "' want '" + want + "'")
        *fails = *fails + 1


# Runs the suite and returns the process exit code.
public def report(title: str, fails: int) -> int:
    if fails == 0:
        print(title + ": all passed")
        return 0
    print(title + ": " + str(fails) + " failure(s)")
    return 1

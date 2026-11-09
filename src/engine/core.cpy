# Vortex engine - shared scalar constants.
#
# Cpyte only resolves a module-level `int NAME = value` inside `main()`: any
# other function that reads one aborts codegen with "Undefined variable", even
# within a single flat translation unit. Engine-wide values are therefore plain
# accessor functions.
#
# Delimiters have to be integers as well: a Cpyte character literal compiles to
# a string pointer, so `code_at(text, i) == '|'` is never true.

import stdlib


# ---- character codes used by the text formats --------------------------------

public def code_nul() -> int:
    return 0


public def code_tab() -> int:
    return 9


public def code_newline() -> int:
    return 10


public def code_cr() -> int:
    return 13


public def code_space() -> int:
    return 32


public def code_hash() -> int:
    return 35


public def code_plus() -> int:
    return 43


public def code_comma() -> int:
    return 44


public def code_minus() -> int:
    return 45


public def code_dot() -> int:
    return 46


public def code_zero() -> int:
    return 48


public def code_nine() -> int:
    return 57


public def code_colon() -> int:
    return 58


public def code_semicolon() -> int:
    return 59


public def code_equals() -> int:
    return 61


public def code_underscore() -> int:
    return 95


public def code_pipe() -> int:
    return 124


# ---- the usual limits --------------------------------------------------------

public def i8_min() -> int:
    return -128


public def i8_max() -> int:
    return 127


public def i16_min() -> int:
    return -32768


public def i16_max() -> int:
    return 32767


public def i32_min() -> int:
    return -2147483648


public def i32_max() -> int:
    return 2147483647


# A negative literal written straight into the `return` of a `-> int64` def is
# folded into the unsigned constant 4294967295, so the caller sees a huge
# positive number and every `result < 0` test silently misses. Building the same
# value in a local keeps the sign, which is what the byte walkers need.
public def i64_failed() -> int64:
    int64 failure = 0
    failure = failure - 1
    return failure

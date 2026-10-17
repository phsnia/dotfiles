---
name: c-generic
user-invocable: false
description: >
  Write type-generic C code with void* containers, C11 _Generic dispatch, and
  macro/include-file templates. Covers byte-based memory, alignment, ownership,
  comparator callbacks, preprocessor token pasting, and compile-time type safety.
allow-tools:
  - bash
  - read
  - edit
  - write
---

# C Generic Code

## Overview

Use for C code that must work over many element types: generic containers
(vector, stack, map, queue), type-dispatching helpers (min, max, print, free),
and compile-time per-type instantiation. Check project conventions first; prefer
the simplest technique that meets the type-safety and performance needs.

## Choose the Technique

| Need | Technique | Trade-off |
|------|-----------|-----------|
| One container, many runtime types | `void*` type-erased | No compile-time type check, alignment care |
| Same-named function that varies by type | `_Generic` (C11) | Compile-time dispatch, macro pitfalls |
| Fixed set of typed instantiations, max safety/speed | Macro/include templates | Code bloat, harder to debug |
| Compile-time overload with full type checking | `_Generic` + `static inline` | Recommended default for helpers |

## 1. `void*` Type-Erased Containers

One implementation, bytes in one buffer, arithmetic in bytes through `char*`.
Never do arithmetic on `void*` (GCC/Clang extension, not portable).

### State to track

```text
data
length
capacity
element_size
```

### Byte pointers

```c
char *base = container->data;
char *slot = base + index * container->element_size;
```

### `realloc` safe growth

```c
static bool grow(struct Vector *v)
{
    if (v->length == SIZE_MAX / v->element_size) {
        return false;
    }
    size_t capacity = v->capacity == 0 ? 4 : v->capacity * 2;
    if (capacity > SIZE_MAX / v->element_size) {
        return false;
    }
    void *next = realloc(v->data, capacity * v->element_size);
    if (next == NULL) {
        return false;
    }
    v->data = next;
    v->capacity = capacity;
    return true;
}
```

### Insert and remove

Use `memcpy` for non-overlapping copy-in of the new element. Use `memmove`
when shifting existing elements (source and destination overlap).

```c
memcpy(v->data + v->length * v->element_size, element, v->element_size);
v->length += 1;
```

```c
char *base = v->data;
memmove(base + index * v->element_size,
        base + (index + 1) * v->element_size,
        (v->length - index - 1) * v->element_size);
v->length -= 1;
```

### Comparator callback

Match the `qsort`/`bsearch` signature for reuse:

```c
int compare_int(const void *left, const void *right)
{
    int a = *(const int *)left;
    int b = *(const int *)right;
    return (a > b) - (a < b);
}
```

Return negative/zero/positive. Do not return `a - b` for integers: signed
overflow is undefined behavior.

### Get element as typed value

Return a byte copy through a typed out-parameter, or return a `void*`
pointer into storage (lifetime tied to container, invalided by `realloc`).

### Invariants

```text
0 <= length <= capacity
element_size > 0
data non-NULL when capacity > 0
caller owns pointed-to objects; container owns bytes only
```

## 2. `_Generic` Compile-Time Dispatch

C11 `_Generic` picks an expression by the type of a controlling expression.
Controlling expression is unevaluated; only the selected branch runs.

### Minimal example

```c
#include <stdint.h>

static int32_t min_i32(int32_t a, int32_t b) { return a < b ? a : b; }
static double  min_dbl(double a, double b)    { return a < b ? a : b; }

#define min(a, b) _Generic((a),          \
    int32_t: min_i32,                    \
    double:  min_dbl)((a), (b))
```

Arguments appear once in the selected call, but beware macro hazards at the
call site (see Pitfalls).

### Prefer `_Generic` over bare macros

Extra arguments are caught by the underlying static function (`-Wconversion`,
prototype checks work). Bare `#define min(a,b) ((a)<(b)?(a):(b))` has no
prototype and re-evaluates arguments. Wrap in `static inline` functions and
dispatch with `_Generic`:

```c
#define min(a, b) _Generic((a), int: min_int, long: min_long)((a), (b))
```

### Type identity notes

- Controlled expression undergoes default argument promotions only at function
  calls, not in `_Generic`. `char` and `signed char` are distinct types; both
  must be listed to cover both.
- Array expressions decay to pointers in the controlling position.
- String literals are `char[N]` → decays to `char *`. Use `char *:`. To cover
  `const char *`, add an association. A robust pattern dispatches on the
  decayed type and handles `const` via a helper macro.
- `default:` covers any unlisted type. Decide whether missing types should
  compile-error (omitted) or fall back (listed).

## 3. Macro and Include-File Templates

Generate a full typed struct plus functions per instantiation. The `.inc` file
holds one parameterized body; `#define` the parameters, include it, then
`#undef` them. Works in any compiler because it is pure preprocessing.

### `vector.inc` (included multiple times)

```c
#ifndef VEC_T
#error "VEC_T: element type required"
#endif
#ifndef VEC_NAME
#error "VEC_NAME: tag prefix required"
#endif

#define CAT2(a, b) a##b
#define CAT(a, b)  CAT2(a, b)
#define VEC(t, s)  CAT(CAT(t, _), s)

struct VEC(VEC_NAME, vector) {
    VEC_T *data;
    size_t length;
    size_t capacity;
};

static inline bool VEC(VEC_NAME, push)(struct VEC(VEC_NAME, vector) *v, VEC_T e)
{
    if (v->length == v->capacity) {
        size_t cap = v->capacity == 0 ? 4 : v->capacity * 2;
        if (cap > SIZE_MAX / sizeof(VEC_T)) {
            return false;
        }
        VEC_T *next = realloc(v->data, cap * sizeof(VEC_T));
        if (next == NULL) {
            return false;
        }
        v->data = next;
        v->capacity = cap;
    }
    v->data[v->length++] = e;
    return true;
}

static inline void VEC(VEC_NAME, free)(struct VEC(VEC_NAME, vector) *v)
{
    free(v->data);
    v->data = NULL;
    v->length = v->capacity = 0;
}

#undef VEC_T
#undef VEC_NAME
#undef VEC
#undef CAT2
#undef CAT
```

### Instantiation in the public header

```c
#define VEC_T   int
#define VEC_NAME intvec
#include "vector.inc"

#define VEC_T   double
#define VEC_NAME dblvec
#include "vector.inc"
```

Two-level token pasting (`CAT2` → `CAT`) is required: with a single
`#define VEC(t,s) t##s`, the parameters expand before paste only if you
double-wrap. Without it, names like `intvec_push` fail or produce
`VEC_NAME_push`.

### X-macros: generate lists of fields and code together

```c
#define ATTRIBUTES(X) \
    X(int, count)     \
    X(double, ratio)

#define DECL_FIELD(type, name) type name;
struct stats { ATTRIBUTES(DECL_FIELD) };
#undef DECL_FIELD

#define CLEAR_FIELD(type, name) stats.name = 0;
static void clear_stats(struct stats *stats)
{
    ATTRIBUTES(CLEAR_FIELD)
}
#undef CLEAR_FIELD
```

Adding an attribute updates struct and all generated code at once. Two hazards:
the table macro must keep one-line-per-`X(...)` continuation (no trailing
content), and every generation must `#undef` its helper.

## 4. Alignment and Ownership

### Alignment

`malloc` returns storage aligned for `max_align_t`. A `void*` container that
stores `element_size` bytes per slot keeps that alignment only if every
element type the caller stores has alignment less than or equal to
`alignof(max_align_t)`. That holds for scalars, pointers, and most ordinary
structs. For exotic types (long double, `_Alignas` over-aligned types, SIMD
vectors), store `_Alignof` too and align slot starts explicitly, or reject
those types in the contract.

Document the alignment contract in the header comment.

### Ownership

- Container owns its byte buffer. Caller owns pointed-to dynamic objects.
- Default copy is shallow `memcpy`. If the element type owns nested dynamic
  memory, provide a `destroy`/`clone` callback or document that shallow copy
  is caller-controlled.
- After a failed `realloc`, the original pointer is still valid and owned.
  Assign only after success.

## 5. Helpers That Work on `void*`

`bsearch`, `qsort` already generic in the standard library. For custom ordered
lookup, reuse the same comparator signature:

```c
void *vector_find(const void *container, const void *key,
                  int (*compare)(const void *, const void *))
```

Keep generic callbacks `const void*` only. Do not cast away `const` from
caller-owned objects.

## Practices

- Track `length`, `capacity`, `element_size` for every type-erased container.
- Do byte arithmetic on `char *`, never on `void *`.
- Check `count * element_size` against `SIZE_MAX` before allocating.
- Assign `realloc` result to a temporary, then to the real pointer on success.
- Use `memcpy` for non-overlapping copy, `memmove` for overlapping shifts.
- Give comparators the `int (*)(const void *, const void *)` signature.
- Compare integers as `(a > b) - (a < b)`, never `a - b`.
- Prefer `_Generic` over dispatch macros without prototypes.
- Double-wrap token-pasting macros (`CAT2` then `CAT`).
- `#undef` every parameter and helper after each `.inc` include.
- Put `_Generic` and templates behind public `static inline` functions.
- Document alignment and ownership in the header.

## Common Pitfalls

- Arithmetic on `void*` (extension; fails on strict/portable builds).
- `a - b` integer comparator underflow → undefined behavior.
- Counting overflow in `count * element_size`.
- Losing the original pointer after failed `realloc`.
- `memcpy` for overlapping shift (must be `memmove`).
- Comparator mismatch with `qsort` expectation (wrong element width).
- Macro argument evaluated twice (side-effect duplication).
- Unparenthesized macro parameters breaking precedence.
- Single-level `a##b` pasting that expands before pasting.
- Stale `#undef` leak: parameters from one instantiation leak into another.
- Missing `#undef` of X-macro helpers after use.
- `_Generic` association missing `char`/`signed char`/`const T *` variants.
- Dependency on `typeof` (GNU extension) in portable C17 code.
- Forgetting string literals decay to `char *` in `_Generic`.

## When to Use This Skill

Use for generic containers, type-dispatching utilities, compile-time
templates, and review of `void*`/macro-heavy C. For raw low-level memory
debugging, POSIX processes, threads, or sockets, use c-system-programming.

## Compile and Test

```sh
cc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g test.c -o test
./test
```

Test every instantiation: empty input, single element, growth across
capacities, remove from head/middle/tail, duplicate values, and `SIZE_MAX`
overflow guards. Test with both GCC and Clang; macros and `_Generic` quirks
differ between compilers.

## Resources

### Standard and References

- [C standard (C11 `_Generic`)](https://en.cppreference.com/w/c/language/generic)
- [cppreference: Preprocessor](https://en.cppreference.com/w/c/preprocessor)
- [cppreference: C language reference](https://en.cppreference.com/w/c)
- [GCC C dialect options](https://gcc.gnu.org/onlinedocs/gcc/C-Dialect-Options.html)
- [Clang diagnostics](https://clang.llvm.org/docs/DiagnosticsReference.html)

### Guided Articles

- [SEI CERT C](https://wiki.sei.cmu.edu/confluence/display/c)
- [X-macros](https://en.wikipedia.org/wiki/X_macro)
- [Linux kernel container_of](https://www.kernel.org/doc/html/latest/core-api/kernel-api.html)
- [P99 macros (generic helpers)](https://p99.gforge.inria.fr/)

### Tools

- [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
- [Compiler Explorer](https://godbolt.org/)
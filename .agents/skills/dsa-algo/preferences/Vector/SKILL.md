---
name: dsa-vector
user-invocable: false
description: >
  Generic dynamic array (Vector) over a void* buffer with stored
  element_size. All operations return a VectorError enum instead of
  bool success codes. Language-agnostic C-style pseudocode.
allow-tools:
  - bash
  - read
  - edit
  - write
  - gcc
---

# Vector

## Table of Contents
- [Overview](#overview)
  - [What is a Vector](#what-is-a-vector)
  - [How It Works](#how-it-works)
  - [When to Use It](#when-to-use-it)
- [Implementation Context](#implementation-context)
  - [Standard Library](#standard-library)
  - [Memory Allocation](#memory-allocation)
  - [Generic Data](#generic-data)
- [Rules](#rules)
- [Vector Structure](#vector-structure)
  - [Data Fields](#data-fields)
  - [Size and Capacity](#size-and-capacity)
  - [Invariants](#invariants)
- [Memory Management](#memory-management)
  - [Allocation](#allocation)
  - [Reallocation](#reallocation)
  - [Growth Strategy](#growth-strategy)
  - [Shrink Strategy](#shrink-strategy)
- [Helpers](#helpers)
  - [Index Validation](#index-validation)
  - [State Validation](#state-validation)
  - [Capacity Checks](#capacity-checks)
- [Operations](#operations)
  - [Initialize](#initialize)
  - [Is Empty](#is-empty)
  - [Push Back](#push-back)
  - [Access](#access)
  - [Front and Back](#front-and-back)
  - [Insert](#insert)
  - [Erase](#erase)
  - [Pop Back](#pop-back)
  - [Destroy](#destroy)
- [Complexity](#complexity)
- [Pitfalls](#pitfalls)
- [Validation](#validation)
- [Resources](#resources)

## Overview

### What is a Vector

A Vector is a dynamic array: one contiguous element buffer plus a live
element count (`size`) and an allocated slot count (`capacity`). In
other languages this is `std::vector` (C++), `Vec` (Rust), or
`ArrayList` (Java). In C you assemble it by hand from raw memory.

```text
structure Vector:
  data: void*             # raw element buffer, null when capacity == 0
  element_size: size_t    # bytes per element, fixed at init
  size: size_t            # live elements
  capacity: size_t        # allocated slots
```

### How It Works

The Vector owns one contiguous buffer. `size` counts readable elements;
`capacity` counts allocated slots. When `size == capacity`, the next
`push_back` allocates a larger buffer, copies the live elements, and
frees the old one. Reads/writes go through the buffer only after the
index passes validation. All operations return a `VectorError` code and
leave the vector in its last valid state on failure.

### When to Use It

Use a Vector for ordered data with frequent append and random access by
index. `at` is O(1), `push_back` is amortized O(1). Avoid it when you
need cheap middle insertion/removal (a linked list wins), or when
elements must keep stable addresses while the collection grows
(reallocation moves them).

## Implementation Context

### Standard Library

ISO C ships no dynamic-array container — unlike C++'s `std::vector` or
other languages' built-in list types, C gives you only `malloc`/`realloc`
and you build the container yourself.

### Memory Allocation

- `malloc`, `realloc`, `free` — from `<stdlib.h>`, for buffer allocation,
  growth, and shrink.
- `memcpy`, `memmove` — from `<string.h>`, for element moves (memmove is
  overlap-safe, required by insert/erase).
- `SIZE_MAX` — from `<stdint.h>`, for overflow checks when sizing the
  element buffer.

### Generic Data

Generality comes from a `void *` buffer plus a stored `element_size`:
one implementation serves every element type, with all element access
done via `memcpy`/`memmove` at byte offsets. Non-standard alternatives
(C++ `std::vector`, GLib `GArray`, `stb_ds.h`) exist but are not ISO C.

## Rules

Store pointer, element size, element count, and capacity together. Keep
`size <= capacity`. One object owns storage; every successful allocation
has one matching `free`. Never read or write through `data` unless the
vector is valid and the index has been validated first. Every operation
returns a `VectorError`; a failed call mutates nothing.

### Error type

```text
enum VectorError:
  OK = 0
  ERR_NULL          # vector is null / corrupted
  ERR_OOB           # index >= size on read/erase
  ERR_BAD_INDEX     # index > size on insert, or vector empty
  ERR_ALLOC         # malloc/realloc failed
  ERR_INVALID_ARG   # bad element_size, null value pointer, etc.
```

## Vector Structure

### Data Fields

```text
structure Vector:
  data: void*             # element buffer; null when capacity == 0
  element_size: size_t    # bytes per element, fixed at init
  size: size_t            # elements currently in use
  capacity: size_t        # allocated slots
```

### Size and Capacity

`size` measures logical length; `capacity` measures storage. They differ
after growth reserves spare slots and before shrink releases them.
Capacity describes what the buffer holds, not what the caller can read.

### Invariants

- `0 <= size <= capacity`.
- Only indexes below `size` contain active elements.
- `data == null` iff `capacity == 0` (and then `size == 0`).
- `element_size > 0` always.
- Every buffer allocation has exactly one matching `free`.

## Memory Management

### Allocation

Start with a small initial capacity so the first several appends cost
one allocation.

```text
INITIAL_CAPACITY = 8

function grow(v):
  require(is_valid(v))
  if is_full(v):
    next = (v.capacity == 0) ? INITIAL_CAPACITY : v.capacity * 2
    if next < v.capacity or next > SIZE_MAX / v.element_size:
      return ERR_ALLOC                        # overflow guard
    tmp = reallocate(v.data, next * v.element_size)
    if tmp == null: return ERR_ALLOC          # v.data untouched
    v.data = tmp
    v.capacity = next
  return OK
```

### Reallocation

`realloc` may move the buffer. Copy the result to a temporary first so a
failed call keeps the old pointer alive — never assign the result
directly to `v.data` before the null check.

### Growth Strategy

Double capacity for amortized O(1) `push_back`: each element moves only
a constant number of times across all doublings.

### Shrink Strategy

Shrink only after a deliberate hysteresis threshold (`size <= capacity /
4`) to avoid repeated grow-shrink cycles. Ignore shrink failure — `size`
is already updated and the larger buffer stays valid.

```text
SHRINK_THRESHOLD = 4

function shrink(v, target):
  require(is_valid(v))
  require(target >= v.size)                 # never drop live elements

  if target == 0:
    free(v.data)
    v.data = null; v.capacity = 0
    return OK

  tmp = reallocate(v.data, target * v.element_size)
  if tmp == null: return ERR_ALLOC          # keep larger storage on failure
  v.data = tmp
  v.capacity = target
  return OK
```

## Helpers

Every check is its own named predicate; public operations call the
helpers before touching memory.

### Index Validation

```text
function valid_index(v, index):
  # read/update/erase: index must reference an existing element
  return index < v.size

function valid_insert_index(v, index):
  # insert: index may equal size (append-at-end is allowed)
  return index <= v.size
```

### State Validation

```text
function is_valid(v):
  # catches a corrupted/uninitialized vector
  return v != null and v.element_size > 0

function is_empty(v):
  return v.size == 0

function is_full(v):
  return v.size == v.capacity
```

### Capacity Checks

```text
function needs_grow(v):
  return v.size == v.capacity

function needs_shrink(v):
  return v.capacity > 0 and v.size <= v.capacity / SHRINK_THRESHOLD
```

## Operations

Every operation validates state and index first, returns a `VectorError`,
and mutates nothing on an invalid call. `at` is the only way callers read
an element; it always bounds-checks first.

### Initialize

```text
function init(v, element_size):
  if v == null or element_size == 0: return ERR_INVALID_ARG
  v.data = null; v.element_size = element_size
  v.size = 0; v.capacity = 0
  return OK
```

### Is Empty

```text
function is_empty_op(v):
  if not is_valid(v): return ERR_NULL
  return v.size == 0 ? OK : ERR_BAD_INDEX     # or expose a bool out-param
```

### Push Back

```text
function push_back(v, value):          # value: const void*, one element
  if not is_valid(v) or value == null: return ERR_INVALID_ARG
  err = grow(v)
  if err != OK: return err                # leave vector in last valid state
  memcpy(v.data + v.size * v.element_size, value, v.element_size)
  v.size += 1
  return OK
```

### Access

```text
function at(v, index, out):            # out: void*, receives one element
  if not is_valid(v): return ERR_NULL
  if out == null: return ERR_INVALID_ARG
  if not valid_index(v, index): return ERR_OOB
  memcpy(out, v.data + index * v.element_size, v.element_size)
  return OK
```

### Front and Back

```text
function front(v, out):
  if not is_valid(v): return ERR_NULL
  if is_empty(v): return ERR_BAD_INDEX
  return at(v, 0, out)

function back(v, out):
  if not is_valid(v): return ERR_NULL
  if is_empty(v): return ERR_BAD_INDEX
  return at(v, v.size - 1, out)
```

### Insert

Shift elements right with an overlap-safe block move, back to front,
before writing the new value. `index == size` appends.

```text
function insert(v, index, value):
  if not is_valid(v) or value == null: return ERR_INVALID_ARG
  if not valid_insert_index(v, index): return ERR_BAD_INDEX
  err = grow(v)
  if err != OK: return err

  dst = v.data + (index + 1) * v.element_size
  src = v.data + index * v.element_size
  memmove(dst, src, (v.size - index) * v.element_size)
  memcpy(src, value, v.element_size)
  v.size += 1
  return OK
```

### Erase

Shift elements left, front to back. Shrink only when the hysteresis
threshold triggers; ignore shrink failure.

```text
function erase(v, index, out):         # out may be null
  if not is_valid(v): return ERR_NULL
  if not valid_index(v, index): return ERR_OOB

  slot = v.data + index * v.element_size
  if out != null: memcpy(out, slot, v.element_size)
  memmove(slot, slot + v.element_size, (v.size - index - 1) * v.element_size)
  v.size -= 1

  if needs_shrink(v):
    shrink(v, v.capacity / 2)             # ignore failure, size already updated
  return OK
```

### Pop Back

```text
function pop_back(v, out):
  if not is_valid(v): return ERR_NULL
  if is_empty(v): return ERR_BAD_INDEX
  return erase(v, v.size - 1, out)
```

### Destroy

Free the buffer and reset every field. Safe to call repeatedly.

```text
function destroy(v):
  if not is_valid(v): return ERR_NULL
  free(v.data)
  v.data = null; v.size = 0; v.capacity = 0
  return OK
```

## Complexity

- `at`, `front`, `back`: O(1).
- `push_back`, `pop_back`: O(1) amortized, O(n) during growth.
- `insert`, `erase` at arbitrary index: O(n) — elements shift.
- Storage: O(capacity).

## Pitfalls

- Assigning the `realloc` result directly and losing the old pointer on failure.
- Multiplying `capacity * element_size` without an overflow check (`> SIZE_MAX / element_size`).
- Reading past `size` because `capacity` is larger (uninitialized slots).
- Skipping `is_valid` on a vector that was never `init`ialized.
- `ERR_OOB` vs `ERR_BAD_INDEX` confusion — insert allows `index == size`, everything else does not.
- Calling `front`, `back`, or `pop_back` without an `is_empty` check first.
- Shrinking on every `erase` instead of using a hysteresis threshold.
- Freeing or growing the buffer while callers still hold pointers into elements — they dangle immediately.
- Treating `grow`/`shrink` failure as fatal instead of leaving the vector in its last valid state.

## Validation

Test: null/uninitialized vector, empty vector, one item, growth
boundaries, shrink boundaries, duplicate values, index zero, last index,
`index == size` on insert, out-of-range indexes on read/insert/erase,
allocation failure paths, `front`/`back`/`pop_back` on empty, and
repeated `destroy`.

Compile and run with sanitizers enabled:

```sh
gcc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g vector.c -o vector
./vector
```

## Resources

### Documentation

- [C `malloc` and `realloc` reference](https://en.cppreference.com/w/c/memory)
- [C `memmove` reference](https://en.cppreference.com/w/c/string/byte/memmove)
- [C `SIZE_MAX` reference](https://en.cppreference.com/w/c/types/integer)

### Online Resources

- [C dynamic array / vector overview](https://en.wikipedia.org/wiki/Dynamic_array)
- [SEI CERT C memory rules](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/)
- [NIST Data Structures and Algorithms](https://www.nist.gov/dads/)

### Tools

- [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
- [Valgrind](https://valgrind.org/docs/manual/manual.html)
- [GDB](https://sourceware.org/gdb/documentation/)

---
name: dsa-hash-table
user-invocable: false
description: >
  Implement a generic hash table (map) with explicit buckets, hashing,
  collision handling, ownership, resizing, deletion, and load-factor
  control, expressed as language-agnostic pseudocode over generic key K
  and value V types.
allow-tools:
  - bash
  - read
  - edit
  - write
  - gcc
---

# Hash Table

## Table of Contents
- [Overview](#overview)
  - [What Is a Hash Table](#what-is-a-hash-table)
  - [How It Works](#how-it-works)
  - [When to Use It](#when-to-use-it)
- [Implementation Context](#implementation-context)
  - [Standard Library](#standard-library)
  - [Memory Allocation](#memory-allocation)
  - [Generic Data](#generic-data)
- [Rules](#rules)
- [Hash Table Structure](#hash-table-structure)
  - [Buckets](#buckets)
  - [Entries](#entries)
  - [Hash Function](#hash-function)
  - [Collision Handling](#collision-handling)
  - [Invariants](#invariants)
- [Ownership](#ownership)
- [Helpers](#helpers)
  - [Key Comparison](#key-comparison)
  - [Index Calculation](#index-calculation)
  - [Capacity Checks](#capacity-checks)
- [Operations](#operations)
  - [Initialize](#initialize)
  - [Insert or Update](#insert-or-update)
  - [Get](#get)
  - [Contains](#contains)
  - [Delete](#delete)
  - [Resize](#resize)
  - [Destroy](#destroy)
- [Load Factor](#load-factor)
- [Complexity](#complexity)
- [Pitfalls](#pitfalls)
- [Validation](#validation)
- [Resources](#resources)

## Overview

### What Is a Hash Table

A hash table is a map: it stores key-value pairs and answers "what
value belongs to this key" in expected $O(1)$ time. It computes an
index from the key instead of scanning every stored pair.

The core idea is a function that turns a key into a bucket index. Store
the pair in that bucket. Lookup re-runs the function on the key, jumps
straight to the bucket, and compares keys there.

### How It Works

A hash table has three components that must work together: a bucket
array, a hash function, and a collision strategy.

1. Hash the key to a fixed-width integer.
2. Map that integer to a bucket index, usually `hash % bucket_count`.
3. Store the entry in that bucket.
4. When two keys map to the same bucket, resolve the collision
   (see [Collision Handling](#collision-handling)).
5. When the table gets full enough, grow the bucket array and rehash
   every entry (see [Resize](#resize)).

Lookup and deletion follow the same path: hash, index, then search only
that bucket.

### When to Use It

Use a hash table when the workload is keyed lookup, insertion, or
deletion and order does not matter. It beats a linear array or list for
any structure with thousands of entries.

Do not use a hash table when you need:

- Ordered iteration by key `k`, `k+1`, `k+2` — use a balanced tree.
- A predecessor/successor query — use a tree.
- Stable addressing of elements regardless of insertion — a growing
  table moves entries during rehash; pointers into it do not survive.
- Tiny collections. Below roughly a few hundred entries a sorted array
  with binary search is often faster and memory-cheaper.

## Implementation Context

### Standard Library

ISO C has no map type, so you assemble one. The pieces you need:

- `malloc`, `calloc`, `realloc`, `free` — from `<stdlib.h>`, for the
  bucket array and entries.
- `memcpy`, `memcmp`, `strcmp` — from `<string.h>`, for copying values,
  comparing keys, and copying string keys.
- `strlen` — from `<string.h>`, when keys are NUL-terminated strings.
- `SIZE_MAX`, `size_t`, and exact-width types from `<stdint.h>` —
  for overflow checks and index arithmetic.
- `UINT64_MAX` from `<stdint.h>` — to cap `size` before wrap-around.

There is no portable standard hash function. Write your own or vendor
one; see [Hash Function](#hash-function).

### Memory Allocation

The table allocates three kinds of storage:

- The bucket array: fixed block, allocated at init/resize, freed at
  destroy.
- Entry nodes: one allocation per distinct key at insert, freed at
  delete/destroy.
- Copied keys: one allocation per string key at insert, freed with its
  entry.

All allocation failure must fail the operation cleanly and leave the
table usable — never a half-inserted entry. Check every allocation
return before dereferencing it.

### Generic Data

Make the table generic over key type K and value type V. Two viable
mechanisms:

- **Pseudocode/generic (shown here)**: the operations are written
  against abstract K and V. The caller supplies the hash function, the
  equals predicate, and (if K/V own dynamic memory) the free function.
- **C macro instantiation**: `DECLARE(Name, K, V)` declares a struct and
  API; `DEFINE(Name, K, V)` emits the bodies tuned for one K/V pair.
  String keys and integer-valued keys get specialized helpers.

The table stores values by copy. If V holds heap pointers, the caller
owns that memory and supplies a per-entry cleanup callback for
destroy/overwrite. The table never guesses how to free a value.

## Rules

- Pick K and V before writing a single operation.
- Every key must be hashable and comparable. Enforce a `hash(K)` and an
  `equals(K,K)` at the API boundary.
- Every operation preserves the invariants in
  [Invariants](#invariants); failure leaves the table unchanged.
- Check overflow before capacity arithmetic. `bucket_count * 2` and
  `size + 1` can both overflow `UINT64_MAX`.
- Resize grows, never shrinks on delete. Shrinking on delete invites
  resize thrash.
- Never return an internal pointer to the user; always copy the value
  out through an output parameter.
- Never let an entry lease persist across a resize. Rehash moves
  entries; a stored `Entry*` is stale after growth.

## Hash Table Structure

### Buckets

A bucket is one slot in the primary array. Each bucket anchors its own
collision chain.

```text
structure HashTable<K, V>:
  buckets: array of pointer to Entry<K, V>   # bucket_count slots
  bucket_count: unsigned integer             # current number of slots
  size: unsigned integer                     # number of live entries
```

The bucket array is allocated as one block and indexed by
`hash(K) % bucket_count`. Unused buckets hold a null pointer.

### Entries

An entry is one live key-value pair. It links to the rest of its
collision chain through `next`.

```text
structure Entry<K, V>:
  key: K                  # table copies and owns the key
  value: V                # table copies the value; caller owns deep data
  next: pointer to Entry<K, V>   # null when this is the chain tail
```

The entry carries the key because the hash alone does not identify it:
the bucket must re-check keys on lookup (`equals`) to reject different
keys that hash to the same index.

### Hash Function

The hash function maps an arbitrary key to a fixed-width integer. Two
properties matter:

- **Uniformity**: keys spread evenly across buckets so chains stay
  short.
- **Determinism**: the same key always yields the same hash, or lookup
  breaks.

For string keys a good portable baseline is FNV-1a:

```c
uint64_t hash_string(const unsigned char *key)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    while (*key != '\0') {
        hash ^= (uint8_t)*key++;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}
```

For integer keys, mix so equal simple patterns land in different
buckets; a bare identity hash on power-of-two bucket counts shares all
multiples of the bucket count into one bucket:

```text
function hash_integer(k, bucket_count):
  # splitmix-style stage, then index map
  hash = k
  hash = hash xor (hash >> 33); hash = hash * const_a
  hash = hash xor (hash >> 33); hash = hash * const_b
  hash = hash xor (hash >> 33)
  return hash mod bucket_count
```

Prefer a power of two `bucket_count` with a mixer so the index
fold is `hash & (bucket_count - 1)`, which is cheapest.

### Collision Handling

Two common strategies, both anchored on a bucket:

- **Separate chaining (this skill)**: each bucket owns a singly linked
  list of entries. Colliding keys simply extend the chain. Simple,
  safe under any load factor within reason, and deletion is direct.
- **Open addressing**: entries live inside the bucket array itself;
  a collision probes the next free slot (`linear`, `quadratic`, or
  `double` probing). Fewer pointer hops, but deletion requires
  tombstone marking and load factor must stay well below 1, or probe
  runs explode.

This skill uses separate chaining: expected $O(1)$ lookup with no probe
run, trivial delete, and a load factor up to about $1.0$ stays fast.

### Invariants

Every table, at every moment:

- `size` equals the number of live entry nodes reachable from
  `buckets`.
- `buckets` has exactly `bucket_count` slots; null buckets hold null.
- Every non-null slot is the head of a chain of entries, all distinct.
- No two entries in the table have equal keys.
- Every entry's key was copied by the table and will be freed by the
  same table.
- Entries are only reachable through the chain structure; there are no
  orphan or duplicated nodes.
- `bucket_count` is a power of two, or the index fold is compatible
  with `mod` semantics; pick one and stick to it.

## Ownership

The table owns the bucket array, every entry node, and every copied
key. The caller owns the values' deep data.

- Insert copies the key into freshly allocated storage. If the caller
  keeps a reference to the original key string, both remain valid; the
  table does not alias it.
- Insert copies the value by assignment (`entry->value = value`). If V
  is `char*` or holds pointers of its own, both the caller and the
  table now reference the same underlying memory. This shallow copy is
  caller-visible behavior, not a bug.
- Delete and destroy free the key and the entry, never the value's deep
  data. If V needs freeing, call a `destroy_value(V)` callback before
  the entry is freed.
- Overwrite (`insert` on an existing key) must first run
  `destroy_value` on the old value if such a callback exists, then
  assign the new value, or the old deep data leaks.

## Helpers

### Key Comparison

Comparing keys is the one place a hash table cannot be generic without
a callback. Provide an `equals` predicate:

```text
function equals(a: K, b: K) -> bool   # supplied by caller
```

The default for string keys is `strcmp(a, b) == 0`. The default for
integer keys is `a == b`. The lookup path uses `equals`, never the
hash value, to decide a hit.

```text
function find(table, key):
  require(key is not null)
  index = bucket_index(key)
  entry = table.buckets[index]
  while entry is not null:
    if equals(entry.key, key):
      return entry            # hit
    entry = entry.next
  return not_found            # key absent
```

### Index Calculation

Index calculation must never index out of bounds, so the hash is always
reduced mod `bucket_count`:

```text
function bucket_index(key, bucket_count):
  if bucket_count is a power of two:
    return hash(key) and (bucket_count - 1)
  else:
    return hash(key) mod bucket_count
```

### Capacity Checks

Wrapping the table stats in readable helpers keeps the operations clean:

```text
function is_null(table):  return table == null
function is_valid(table):
  return table != null and
         (table.buckets == null) implies (table.bucket_count == 0) and
         count_reachable(table) == table.size
function is_empty(table):  return is_valid(table) and table.size == 0
function is_full(table):
  return table.size >= table.bucket_count * LOAD_FACTOR_LIMIT
```

The overflow-safe full test is:

```text
function should_resize(table):
  # load limit such as 3/4 of bucket_count
  return table.size >= table.bucket_count - table.bucket_count / 4
```

Written this way, the right side never overflows and stays at
`3/4 * bucket_count`.

## Operations

### Initialize

An initialized table is empty with zero buckets; the first insert
allocates the bucket array lazily.

```text
function init(table):
  require not is_null(table)
  table.buckets = null
  table.bucket_count = 0
  table.size = 0
```

The caller may pass `init` with a size hint instead; then the bucket
array is allocated immediately so the first inserts avoid a resize.

### Insert or Update

Insertion is upsert: an absent key inserts, a present key updates the
value in place.

```text
function set(table, key, value):
  require not is_null(table)
  require key is not null
  entry = find(table, key)
  if entry is a hit:
    destroy_value(entry.value)      # free old deep data if any
    entry.value = value
    return success

  if table.size == UINT64_MAX:
    return overflow                  # size cannot grow

  if table.bucket_count == 0:
    resize(table, INITIAL_BUCKET_COUNT)   # e.g. 8
  elif should_resize(table):
    resize(table, table.bucket_count * 2)

  entry = allocate Entry
  entry.key = copy_key(key)          # fresh allocation
  index = bucket_index(key, table.bucket_count)
  entry.value = value
  entry.next = table.buckets[index]
  table.buckets[index] = entry
  table.size = table.size + 1
  return success
```

Read the resize failure path twice: if `resize` cannot allocate, the
table must not attempt the insert. Return failure with the original
state intact.

### Get

Lookup hashes, indexes, and walks the chain. Values come out through an
output pointer; never return an internal reference.

```text
function get(table, key, out_value):
  require key is not null
  entry = find(table, key)
  if entry is not_found:
    return failure
  *out_value = entry.value
  return success

function contains(table, key) -> bool:
  return find(table, key) is a hit
```

### Contains

`contains` is the bool form of lookup. It must only test existence and
must not copy anything out:

```text
function contains(table, key) -> bool:
  return find(table, key) != not_found
```

### Delete

Deletion unlinks the entry from its chain before freeing anything.
Keep the predecessor link while walking, or delete via the "pointer to
the next pointer" pattern so the unlink is a single store.

```text
function remove(table, key, out_removed):
  require not is_null(table)
  require key is not null
  if table.bucket_count == 0:
    return failure                       # empty table

  link = address of table.buckets[bucket_index(key)]
  while *link != null:
    entry = *link
    if equals(entry.key, key):
      *link = entry.next                 # unlink first
      if out_removed is provided:
        *out_removed = entry.value
      destroy_value(entry.value)         # free deep value data if any
      free key_copy(entry.key)
      free entry
      table.size = table.size - 1
      return success
    link = address of entry.next
  return failure                         # key absent
```

### Resize

Resize allocates a new bucket array, rehashes every entry into it, and
frees the old array. Entries and keys are reused, never reallocated.

```text
function resize(table, new_bucket_count):
  require new_bucket_count > 0
  if new_bucket_count overflows SIZE_MAX / pointer size:
    return failure
  new_buckets = calloc(new_bucket_count, size of pointer)
  if new_buckets == null:
    return failure                        # table unchanged

  for each old_index:
    entry = table.buckets[old_index]
    while entry != null:
      next_entry = entry.next
      index = bucket_index(entry.key, new_bucket_count)
      entry.next = new_buckets[index]     # head-insert into new chain
      new_buckets[index] = entry
      entry = next_entry

  free(table.buckets)
  table.buckets = new_buckets
  table.bucket_count = new_bucket_count
  return success
```

Resize is all-or-nothing. Allocate and fill the new array completely
before freeing the old one; on any early failure the old array is
untouched.

### Destroy

Destroy frees every entry, every copied key, then the bucket array, and
returns the table to the initialized empty state so `destroy` is
idempotent and a destroyed table can be re-initialized.

```text
function destroy(table):
  if is_null(table):
    return
  for each index:
    entry = table.buckets[index]
    while entry != null:
      next_entry = entry.next
      destroy_value(entry.value)          # free deep value data if any
      free key_copy(entry.key)
      free entry
      entry = next_entry
  free(table.buckets)
  table.buckets = null
  table.bucket_count = 0
  table.size = 0
```

## Load Factor

Load factor is `size / bucket_count`. It decides when the table grows:

- At load factor near $1.0$ with separate chaining, chains average one
  entry and lookup stays $O(1)$.
- Keep the growth threshold at $3/4$ to $1.0$. Below that you waste
  memory; above it chains get long and lookup degrades toward linear.
- Grow by doubling `bucket_count` so rehashing is $O(n)$ on the
  existing entries and amortized cost per insert stays $O(1)$.
- Never shrink on delete. Deletion only decreases `size`; growth
  happens on the next insert if the threshold passes.

## Complexity

| Operation | Average | Worst | Notes |
|-----------|---------|-------|-------|
| `init` / `destroy` | $O(n)$ | $O(n)$ | `destroy` walks every entry |
| `set` insert | $O(1)$ | $O(n)$ | amortized $O(1)$ over resizes; worst is one long chain |
| `set` update | $O(1)$ | $O(n)$ | find then assign, no resize |
| `get` / `contains` | $O(1)$ | $O(n)$ | one bucket walk |
| `remove` | $O(1)$ | $O(n)$ | one bucket walk + unlink |
| `resize` | $O(n)$ | $O(n)$ | rehash every live entry |

- Auxiliary space: $O(n)$ for entries plus $O(\text{bucket\_count})$ for
  the bucket array.
- The $O(n)$ worst cases require a deliberately adversarial key set
  that collapses onto one bucket; a uniform hash keeps chains short.
- Amortized insert stays $O(1)$ because doubling makes the resize cost
  chargeable to the prior insertions.

## Pitfalls

- Returning an internal `Entry*` or `&entry->value` from `get`. A later
  insert that triggers `resize` or `set` on the same key invalidates it.
- Freeing the old bucket array before rehashing all entries into the
  new one. Unreachable entries then leak and the resize is not
  all-or-nothing.
- Copying the key shallowly (`entry.key = key`) instead of allocating a
  copy. The caller can free or modify the string and corrupt the table.
- Comparing hash values instead of keys on lookup. Hash collisions are
  expected; `equals` alone decides a hit.
- Forgetting the `size == UINT64_MAX` guard before `size + 1`.
- Resize arithmetic overflow: `bucket_count * 2` and
  `bucket_count * LOAD_FACTOR` must be checked against `UINT64_MAX`
  and `SIZE_MAX / sizeof(pointer)`.
- Reuse of the load-factor test in a form like
  `size >= bucket_count * 3 / 4` where `bucket_count * 3` overflows.
  Use `bucket_count - bucket_count / 4` instead.
- Deleting without unlinking first, leaking the rest of the chain.
- Missing the resize failure branch in `set`: allocating the entry
  after a failed `resize` inserts into a table whose array never grew,
  or worse, into a stale pointer.
- Not freeing a value's deep data on overwrite (`set` on existing key)
  or on destroy, leaking one allocation per lost value.
- Table that is not `null`-safe: every operation must reject a null
  table pointer the same way at the top of the function.
- Shrinking on delete; churn can cause resize oscillation.

## Validation

Test: empty table, single insert, missing-key lookups, overwrite of an
existing key, distinct keys hashing to the same bucket (collision),
many inserts forcing several resizes, delete head/middle/tail of a
chain, delete of a missing key, capacity arithmetic near overflow,
allocation failure on first insert, and mid-resize, repeated `destroy`,
and a re-`init` after `destroy`.

```sh
gcc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g hash_table.c -o hash_table
./hash_table
```

Run the same test under Valgrind once to confirm no leaks on the
alive-at-exit code path.

## Resources

### Documentation

- [C `malloc`, `calloc`, `realloc`, `free` reference](https://en.cppreference.com/w/c/memory)
- [C `stdint.h` exact-width types](https://en.cppreference.com/w/c/types/integer)

### Online Resources

- [Hash table overview](https://en.wikipedia.org/wiki/Hash_table)
- [Separate chaining description](https://en.wikipedia.org/wiki/Hash_table#Separate_chaining)
- [Open addressing description](https://en.wikipedia.org/wiki/Open_addressing)
- [FNV-1a hash reference](https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function)
- [The Art of Computer Programming, vol. 3, hashing chapter](https://en.wikipedia.org/wiki/The_Art_of_Computer_Programming)
- [SEI CERT C memory rules](https://wiki.sei.cmu.edu/confluence/display/c/MEM)

### Tools

- [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
- [Valgrind](https://valgrind.org/docs/manual/manual.html)

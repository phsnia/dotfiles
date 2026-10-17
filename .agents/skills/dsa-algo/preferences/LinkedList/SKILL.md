---
name: dsa-linked-list
user-invocable: false
description: >
  Implement singly and doubly linked lists in two ownership models —
  non-intrusive lists that own heap nodes, and intrusive lists that embed
  a link member inside the payload — with explicit traversal, insertion,
  removal, and cleanup invariants.
---

# Linked List (Non-Intrusive and Intrusive)

## Table of Contents
- [Overview](#overview)
  - [What is a Linked List](#what-is-a-linked-list)
  - [How It Works](#how-it-works)
  - [When to Use It](#when-to-use-it)
- [Implementation Context](#implementation-context)
  - [Standard Library](#standard-library)
  - [Memory Allocation](#memory-allocation)
  - [Generic Data](#generic-data)
- [Rules](#rules)
- [List Structure](#list-structure)
  - [Data Fields](#data-fields)
  - [Links and Counts](#links-and-counts)
  - [Invariants](#invariants)
  - [Doubly Linked List Variant](#doubly-linked-list-variant)
- [Memory Management](#memory-management)
  - [Allocation](#allocation)
  - [Deallocation](#deallocation)
  - [Ownership Models](#ownership-models)
- [Helpers](#helpers)
  - [Index Validation](#index-validation)
  - [State Validation](#state-validation)
  - [Node Management](#node-management)
- [Operations](#operations)
  - [Initialize](#initialize)
  - [Is Empty](#is-empty)
  - [Push Back](#push-back)
  - [Push Front](#push-front)
  - [Access](#access)
  - [Front and Back](#front-and-back)
  - [Find](#find)
  - [Insert](#insert)
  - [Erase](#erase)
  - [Pop Back](#pop-back)
  - [Pop Front](#pop-front)
  - [Destroy](#destroy)
- [Complexity](#complexity)
- [Pitfalls](#pitfalls)
- [Validation](#validation)
- [Resources](#resources)

## Overview

### What is a Linked List

A Linked List is a sequence of nodes, each carrying a payload and a link
to the next node. The list grows and shrinks one node at a time — no
contiguous buffer to maintain. In other languages this is `std::list`
or `std::forward_list` (C++). In C you assemble it by hand from raw
nodes and pointers.

This skill covers two ownership models:

- **Non-intrusive**: each node points to a list-owned heap copy of one
  element. The list stores the element size and copies payloads through
  it; the list owns every node and every payload copy.
- **Intrusive**: the link member lives inside the payload struct. The
  list never allocates payloads; the caller constructs and owns each one.

```text
structure Node:
  data: void*             # heap copy of one element; list owns this
  next: pointer to Node   # null when this is the tail

structure IntrusiveNode:
  next: pointer to IntrusiveNode   # embedded in the payload; no data field
```

### How It Works

The list owns a `head` pointer to its first node and a `tail` pointer to
its last node. Each node points to its successor; the tail's link is
null. Traversals walk `next` from `head`. Non-intrusive nodes reference a
list-owned heap copy of each element; intrusive nodes are the caller's
payloads themselves. Insertion and removal rewire links at a known
position in O(1); reaching that position by index is a O(n) `next` walk.
Append is O(1) because the `tail` link is kept.

### When to Use It

Use a Linked List when you need ordered data with cheap insertion and
removal at known positions (often in the middle), or when an element must
live in several collections at once (intrusive model). Avoid it when you
need random access by index (a Vector wins, O(1) vs O(n)), when cache
locality matters (nodes scatter across the heap), or when elements must
sit in contiguous memory.

## Implementation Context

### Standard Library

ISO C ships no linked-list container — unlike C++'s `std::list` or
`std::forward_list`, C gives you only the raw pieces and you build the
structure yourself. If a project can take a dependency, common
non-standard options exist (Linux kernel `list_head`, BSD `TAILQ`,
GLib `GList`), but this skill's hand-rolled structures are the
standard-library-only approach.

### Memory Allocation

- `malloc`, `calloc`, `realloc`, `free` — from `<stdlib.h>`, used for
  nodes and, in the non-intrusive model, for each element's payload
  copy.
- `memcpy` — from `<string.h>`, used to copy payloads in and out at
  `element_size` byte offsets.
- `offsetof` — from `<stddef.h>`, used for intrusive links to convert
  between a link pointer and its containing payload.
- `SIZE_MAX` — from `<stdint.h>`, used for overflow checks when counting
  nodes.

### Generic Data

Generality comes from a `void *` payload pointer per node plus a stored
`element_size` on the list: one implementation serves every element
type, and the list moves elements byte-wise with `memcpy`. The
non-intrusive model owns these copies; the intrusive model instead
embeds the link inside the caller's typed payload and reaches the
payload through `offsetof`, never through an assumed value layout:

```c
#include <stddef.h>

#define CONTAINER_OF(ptr, type, member) \
    ((type *)((char *)(ptr) - offsetof(type, member)))
```

## Rules

Store head, tail, count, and `element_size` together. One object owns
storage: in the non-intrusive model the list owns every node and each
payload copy; in the intrusive model the caller owns every payload.
Every successful allocation has exactly one matching `free`. Never read
or write through a node pointer or its `data` unless the list is valid
and the position has been located first. Every operation returns a
`ListError`; a failed call mutates nothing.

### Error type

```text
enum ListError:
  OK = 0
  ERR_NULL          # list is null / corrupted
  ERR_OOB           # index >= count on access/remove
  ERR_BAD_INDEX     # index > count on insert
  ERR_EMPTY         # pop/front/back on an empty list
  ERR_NOT_FOUND     # find missed
  ERR_ALLOC         # malloc failed
  ERR_INVALID_ARG   # null value pointer, unreachable node, etc.
```

## List Structure

### Data Fields

```text
structure Node:
  data: void*             # list-owned heap copy of one element
  next: pointer to Node   # null when this is the tail

structure List:
  head: pointer to Node   # null when empty
  tail: pointer to Node   # null when empty; kept for O(1) append
  count: unsigned integer # number of nodes
  element_size: size_t    # bytes per element, fixed at init
```

### Links and Counts

`head` addresses the first node, `tail` the last; `count` measures
logical length. `element_size` is fixed at `init` and drives every
payload copy. `head` and `tail` differ only when two nodes or more are
linked. `count` counts nodes, not slots — there is no reserved capacity.
For an intrusive list the links are the fields the caller embedded in
each payload and `element_size` is unused.

### Invariants

- `head == null` iff `tail == null` iff `count == 0`.
- `count` counts nodes, not slots.
- `tail->next == null` always; only the tail has a null link.
- Non-intrusive: `element_size > 0`, and every `node.data` and node was
  allocated by the list and freed by the same list.
- Intrusive: the list holds no ownership; the caller removes a payload
  before freeing it, never while its link is still on a list.

### Doubly Linked List Variant

Add a `prev` pointer to each node for O(1) `remove_node` and reverse
traversal. Doubling the link cost buys symmetric insertion and removal
at either end.

```text
structure Node:
  data: void*             # list-owned heap copy of one element
  next: pointer to Node
  prev: pointer to Node   # null when this is the head
```

When `remove_node` has a `prev` link, the predecessor is `node.prev` and
no walk is needed. Keep `head.prev == null` and `tail.next == null`.

## Memory Management

### Allocation

Allocation happens inside `make_node`, and only there. The node and its
payload copy are separate allocations, each checked. Capture the pointer
before touching the list: a failed allocation leaves the list in its
last valid state.

```text
function make_node(data, element_size):
  node = allocate Node
  if node == null:
    return null
  node.data = allocate element_size
  if node.data == null:
    free node
    return null
  memcpy(node.data, data, element_size)
  node.next = null
  node.prev = null            # only in the doubly linked variant
  return node
```

### Deallocation

`pop`, `remove`, and `destroy` free a node through `free_node`, which
releases the payload copy first and only when the list owns its nodes.
An intrusive list must never free a payload — the caller does that after
unlinking it.

```text
function free_node(list, node):
  if list owns nodes:         # non-intrusive only
    free(node.data)
    free(node)
```

### Ownership Models

Pick the model before writing code. They differ only in where the link
lives and who owns the payload.

- **Non-intrusive list**: the node holds a `void *` pointer to a
  list-owned heap copy of one element plus a `next` pointer. The list
  allocates every node and payload copy and owns them. Use when the list
  is the only owner of the elements and you want the smallest API.
- **Intrusive list**: the link member lives inside the payload struct.
  The list never allocates payloads. Use when an element can live in
  several lists at once, or when allocating a wrapper node is too costly.

## Helpers

Keep traversal and state checks as named helpers. Every operation walks
the list through `next` only and never assumes a sentinel.

### Index Validation

```text
function valid_index(list, index):
  # read/remove: index must reference an existing node
  return index < list.count

function valid_insert_index(list, index):
  # insert: index may equal count (append-at-end is allowed)
  return index <= list.count

function node_at(list, index):
  # O(n) walk to the node at index; caller checks valid_index first
  node = list.head
  while index > 0:
    node = node.next
    index -= 1
  return node
```

### State Validation

```text
function is_null(list):
  return list == null

function is_empty(list):
  return is_null(list) or list.head == null

function is_valid(list):
  # checks the invariants; O(n) walk, use for debugging not hot paths
  return (not is_null(list)) and
         list.count == count_nodes(list) and
         (list.count == 0 or list.tail.next == null)
```

### Node Management

```text
function container_of(link, type, member):
  return (type *)((char *)link - offsetof(type, member))
```

## Operations

Every operation validates state and index first, returns a `ListError`,
and mutates nothing on an invalid call. Node allocation is funneled
through `make_node`, freeing through `free_node`, and payload copies go
through the list's stored `element_size`.

### Initialize

```text
function init(list, element_size):
  if is_null(list): return ERR_NULL
  list.head = null; list.tail = null; list.count = 0
  list.element_size = element_size
  return OK
```

### Is Empty

```text
function is_empty_op(list):
  # or expose a bool out-param
  if is_null(list): return ERR_NULL
  return is_empty(list) ? OK : ERR_BAD_INDEX
```

### Push Back

```text
function push_back(list, value):      # value: const void*, one element
  if is_null(list): return ERR_NULL
  node = make_node(value, list.element_size)
  if node == null:
    return ERR_ALLOC                 # list untouched
  if list.head == null:
    list.head = node
    list.tail = node
  else:
    list.tail.next = node
    list.tail = node
  list.count += 1
  return OK
```

### Push Front

```text
function push_front(list, value):     # value: const void*, one element
  if is_null(list): return ERR_NULL
  node = make_node(value, list.element_size)
  if node == null:
    return ERR_ALLOC
  node.next = list.head
  list.head = node
  if list.tail == null:
    list.tail = node
  list.count += 1
  return OK
```

### Access

```text
function at(list, index, out):       # out: void*, receives one element
  if is_null(list): return ERR_NULL
  if out == null: return ERR_INVALID_ARG
  if not valid_index(list, index): return ERR_OOB
  node = node_at(list, index)        # O(n) walk
  memcpy(out, node.data, list.element_size)
  return OK
```

### Front and Back

```text
function front(list, out):           # out: void*, receives one element
  if is_null(list): return ERR_NULL
  if is_empty(list): return ERR_EMPTY
  memcpy(out, list.head.data, list.element_size)
  return OK

function back(list, out):            # out: void*, receives one element
  if is_null(list): return ERR_NULL
  if is_empty(list): return ERR_EMPTY
  memcpy(out, list.tail.data, list.element_size)
  return OK
```

### Find

```text
function find(list, key, equal):     # equal compares void* payloads
  if is_null(list): return ERR_NULL
  node = list.head
  while node is not null:
    if equal(node.data, key):
      return OK                     # optionally out-param the node
    node = node.next
  return ERR_NOT_FOUND
```

### Insert

Insert at arbitrary index walks O(n) to the predecessor. Track the
previous node so a removal can repair the chain.

```text
function insert_at(list, index, value):
  if is_null(list): return ERR_NULL
  if not valid_insert_index(list, index): return ERR_BAD_INDEX
  if index == 0:
    return push_front(list, value)
  if index == list.count:
    return push_back(list, value)
  predecessor = node_at(list, index - 1)    # O(n) walk
  node = make_node(value, list.element_size)
  if node == null:
    return ERR_ALLOC
  node.next = predecessor.next
  predecessor.next = node
  list.count += 1
  return OK
```

### Erase

Removal must know the predecessor. A doubly linked list removes in O(1)
with a `prev` link; a singly linked list removes by index or by walking
to the predecessor.

```text
function remove_at(list, index, out):       # out may be null
  if is_null(list): return ERR_NULL
  if not valid_index(list, index): return ERR_OOB
  if index == 0:
    return pop_front(list, out)
  predecessor = node_at(list, index - 1)
  node = predecessor.next
  predecessor.next = node.next
  if node == list.tail:
    list.tail = predecessor
  if out != null:
    memcpy(out, node.data, list.element_size)
  list.count -= 1
  free_node(list, node)
  return OK

function remove_node(list, node, out):
  # O(1) with a prev link; O(n) singly linked walks to the predecessor
  if is_null(list): return ERR_NULL
  if node is not reachable from list.head:
    return ERR_INVALID_ARG           # O(n) trust check
  predecessor = node.prev if node.prev exists else find predecessor
  if predecessor is null:
    list.head = node.next
  else:
    predecessor.next = node.next
  if node == list.tail:
    list.tail = predecessor
  if out != null:
    memcpy(out, node.data, list.element_size)
  list.count -= 1
  free_node(list, node)
  return OK
```

### Pop Back

```text
function pop_back(list, out):
  # O(n) without a prev link; O(1) with one
  if is_null(list): return ERR_NULL
  if is_empty(list): return ERR_EMPTY
  return remove_node(list, list.tail, out)
```

### Pop Front

```text
function pop_front(list, out):
  if is_null(list): return ERR_NULL
  if is_empty(list): return ERR_EMPTY
  node = list.head
  if out != null:
    memcpy(out, node.data, list.element_size)
  list.head = node.next
  if list.head == null:
    list.tail = null
  list.count -= 1
  free_node(list, node)
  return OK
```

### Destroy

Free all nodes and reset every field. Safe to call repeatedly.

```text
function destroy(list):
  if is_null(list): return ERR_NULL
  node = list.head
  while node is not null:
    next_node = node.next
    free_node(list, node)            # never frees intrusive payloads
    node = next_node
  list.head = null; list.tail = null; list.count = 0
  return OK
```

## Complexity

- `front`, `back`, `push_back`, `push_front`, `pop_front`: O(1) with a
  `tail` link.
- `pop_back`: O(n) singly linked, O(1) with a `prev` link.
- `at`, `insert_at`, `remove_at`: O(n) because of the `next` walk.
- `remove_node` (singly linked): O(n). `remove_node` (doubly linked): O(1).
- `find`: O(n).
- `destroy`: O(n).
- Storage: O(n) non-intrusive — one node plus one payload copy per
  element. Intrusive lists add no storage beyond the embedded links.

## Pitfalls

- Keeping a `tail` but forgetting to update it on `pop_front` or
  `remove_at`.
- Freeing list-owned nodes in `destroy` for a non-intrusive list, but
  freeing caller-owned payloads for an intrusive list.
- Freeing a payload while its intrusive link still sits on a list.
- Missing the `node == list.tail` case, leaving `tail` pointing to freed
  memory.
- Freeing a node without freeing its `data` copy first, or dereferencing
  `node.data` after the node is gone.
- Breaking the chain: overwriting `predecessor.next` before reading the
  next node during a walk.
- Copying payloads with a caller-sized type instead of the stored
  `element_size`.
- Using `CONTAINER_OF` on a link that does not belong to the payload type.
- Counting nodes during `destroy` but not resetting `count` after.
- Assuming the tail has a sentinel; check `next == null` instead.

## Validation

Test: empty list, one node, append/insert/remove at head, tail, and
middle, `remove_node` on the only node, duplicate values, invalid
indexes, `element_size` mismatch on copy, allocation failure on first
and later nodes, intrusive payload removed before free, and repeated
`destroy`.

```sh
gcc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g linked_list.c -o linked_list
./linked_list
```

## Resources

### Documentation

- [C `malloc` and `free` reference](https://en.cppreference.com/w/c/memory)
- [C `memcpy` reference](https://en.cppreference.com/w/c/string/byte/memcpy)
- [C `offsetof` reference](https://en.cppreference.com/w/c/types/offsetof)

### Online Resources

- [Linked list overview](https://en.wikipedia.org/wiki/Linked_list)
- [Linux kernel `list_head` documentation](https://www.kernel.org/doc/html/latest/core-api/kernel-api.html)
- [SEI CERT C memory rules](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/)

### Tools

- [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
- [Valgrind](https://valgrind.org/docs/manual/manual.html)

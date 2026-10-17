---
name: dsa-algo
user-invocable: false
description: >
  Design and implement data structures and algorithms in C with explicit memory,
  ownership, invariants, complexity analysis, and manual implementations.
allow-tools:
  - bash
  - read
  - edit
  - write
  - gcc
---

# C Data Structures and Algorithms

## Overview

Use this skill for manual C implementations of arrays, lists, stacks, queues,
hash tables, trees, graphs, sorting, searching, and algorithm analysis.

Prefer C structs, pointers, explicit allocation, and clear invariants. Do not
replace requested manual logic with C++ containers or opaque libraries.

Organize each DSA preference as:

1. Structure Data
2. Helpers
3. Operations

## Workflow

1. Define input, output, ownership, invariants, and failure behavior.
2. Choose data structure and algorithm from constraints.
3. State time and space complexity.
4. Implement small helpers with checked indexes and allocation.
5. Test empty, one-item, duplicate, sorted, reverse-sorted, and large inputs.
6. Compile with warnings and sanitizers.

## Preference Map

Read matching preference file:

1. [Sort](preferences/Sort/SKILL.md)
2. [Vector](preferences/Vector/SKILL.md)
3. [Linked list](preferences/LinkedList/SKILL.md)
4. [Hash table](preferences/HashTable/SKILL.md)
5. [Tree](preferences/Tree/SKILL.md)
6. [Graph](preferences/Graph/SKILL.md)

## Complexity Rules

- State best, average, and worst case when they differ.
- State auxiliary space separately from input storage.
- Prefer stable sorting when equal-key order matters.
- Prefer iterative code when recursion can overflow the stack.
- Check integer overflow before index or capacity arithmetic.

## Validation

```sh
gcc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g algorithm.c -o algorithm
./algorithm
```

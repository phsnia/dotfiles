---
name: dsa-tree
user-invocable: false
description: Implement C trees with explicit nodes, ownership, traversal helpers, invariants, recursion limits, balancing, and cleanup.
allow-tools:
  - bash
  - read
  - edit
  - write
  - gcc
---

# Tree

## Table of Contents
- [Overview](#overview)
  - [What is a Tree](#what-is-a-tree)
  - [Tree Terminology](#tree-terminology)
  - [Tree Properties](#tree-properties)
  - [When to Use Trees](#when-to-use-trees)
- [Implementation Context](#implementation-context)
  - [Standard Library](#standard-library)
  - [Memory Allocation](#memory-allocation)
  - [Generic Data](#generic-data)
- [Rules](#rules)
- [Tree Structure](#tree-structure)
  - [Node](#node)
  - [Root](#root)
  - [Edges](#edges)
  - [Parent and Child](#parent-and-child)
  - [Leaf Nodes](#leaf-nodes)
  - [Height and Depth](#height-and-depth)
- [Tree Types](#tree-types)
  - [Binary Tree](#binary-tree)
  - [Binary Search Tree](#binary-search-tree)
  - [Balanced Tree](#balanced-tree)
  - [Heap](#heap)
- [Operations](#operations)
  - [Create](#create)
  - [Insert](#insert)
  - [Search](#search)
  - [Delete](#delete)
  - [Traversal](#traversal)
    - [Preorder](#preorder)
    - [Inorder](#inorder)
    - [Postorder](#postorder)
    - [Level Order](#level-order)
- [Complexity](#complexity)
- [Pitfalls](#pitfalls)
- [Validation](#validation)
- [Resources](#resources)
  - [Documentation](#documentation)
  - [Online Resources](#online-resources)
  - [Tools](#tools)

## Overview

### What is a Tree

A tree is a hierarchical structure of nodes connected by edges. Every node
except the root has exactly one parent. The structure has no cycles. A tree
generalizes a linked list from one child to many children.

### Tree Terminology

- Node: one element and its child links.
- Root: the single top node with no parent.
- Edge: a link from a parent to a child.
- Leaf: a node with no children.
- Internal node: a node with at least one child.
- Subtree: a node and all nodes reachable from it.

### Tree Properties

- One root exists when the tree is non-empty.
- Every node is reachable from the root by exactly one path.
- Height is the longest edge count from a node to a leaf.
- Depth is the edge count from the root to a node.
- Size is the total node count.

### When to Use Trees

Use a tree for hierarchical data (file systems, expression parsing) or for
ordered data when you need search, insert, and delete faster than a sorted
array. Use a binary search tree when ordered search matters. Use a balanced
tree when worst-case guarantees matter. Use a heap when you need the
minimum or maximum quickly. Use a hash table instead when you need average
$O(1)$ lookup and do not need ordering.

## Implementation Context

### Standard Library

ISO C has no built-in tree — unlike C++'s `std::map` or Java's
`TreeMap`, C gives you only the raw pieces and you assemble the container
yourself, as this skill does.

### Memory Allocation

- `malloc`, `calloc`, `free` — from `<stdlib.h>`, used for node
  allocation and for `create` and `delete`.
- `SIZE_MAX` — from `<stdint.h>`, used for overflow checks when counting
  nodes.

No standard tree container exists. If a project can take a dependency,
common non-standard options exist (GLib `GNode`, `uthash`), but this
hand-rolled `Tree<T>` is the standard-library-only approach.

### Generic Data

Parameterize the tree over a generic element type `T`. Instantiate the
pseudocode for a concrete `T` (for example, `int`) before compiling. In C,
use a code-generation macro (`Tree_DECLARE`/`Tree_DEFINE`) or a
`void *` payload plus a comparator callback. The comparator defines total
order for ordered trees.

```c
typedef int (*TreeCompare)(const void *left, const void *right);
```

## Rules

Every node has one owner. Every successful allocation has one matching free.
Never dereference a null child. Validate the tree and the key before any
operation. Keep the ordering invariant valid after every mutation. Prefer
iterative traversal when recursion can overflow the stack. Limit recursion
depth explicitly for unbalanced input.

## Tree Structure

### Node

```text
structure Node<T>:
  value: T
  left: pointer to Node<T>   # null when no left child
  right: pointer to Node<T>  # null when no right child
  # for general trees: children: array or list of child pointers

structure Tree<T>:
  root: pointer to Node<T>   # null when empty
  count: unsigned integer    # number of nodes
  compare: TreeCompare       # defines order for ordered trees; null for unordered
```

### Root

The root is the entry point. An empty tree has `root == null` and
`count == 0`. All operations start at the root.

### Edges

An edge is a parent-to-child pointer. No edge points to a parent. No
cycles exist. A binary node holds at most two edges; a general node holds
a variable number.

### Parent and Child

A node with a child is the parent; the child has exactly one parent. For
simple binary trees the parent link is optional. Store a `parent` pointer
only when the algorithm needs upward traversal or iterative deletion:

```text
structure Node<T>:
  value: T
  left: pointer to Node<T>
  right: pointer to Node<T>
  parent: pointer to Node<T>   # null for root; optional
```

### Leaf Nodes

A leaf has no children: `left == null` and `right == null`. Leaf checks
drive base cases in recursion and cleanup.

```text
function is_leaf(node):
  return node != null and node.left == null and node.right == null
```

### Height and Depth

```text
function height(node):
  if node == null:
    return -1                  # empty subtree; leaf has height 0
  return 1 + max(height(node.left), height(node.right))

function depth(tree, target):
  # edge count from root to target; undefined when target not in tree
  walk from root following parent links or search path and count edges
```

Height measures the longest downward path. Depth measures distance from the
root. An empty tree has height -1. A single node has height 0.

## Tree Types

### Binary Tree

Each node has at most two children, conventionally `left` and `right`.
A binary tree imposes no ordering. Use it for expression trees, decision
trees, and as the base for ordered variants.

### Binary Search Tree

A binary search tree enforces the ordering invariant:

```text
invariant BST(node):
  every value in node.left subtree < node.value
  every value in node.right subtree > node.value
  # duplicates: pick one side consistently (common: right) or reject
  both subtrees are BSTs
```

Lookup, insert, and delete walk from the root and choose left or right by
comparison. Average $O(\log n)$ when reasonably balanced; worst $O(n)$ when
skewed.

### Balanced Tree

A balanced tree keeps height $O(\log n)$ after every mutation. Common
choices:

- AVL tree: `|height(left) - height(right)| <= 1`; rotate on violation.
- Red-black tree: color invariant plus black-height; fewer rotations.
- B-tree: many keys per node; preferred for disk-backed storage.

Balance trades extra rotation logic for guaranteed logarithmic height.
Implement only when worst-case bounds matter; otherwise document that the
unbalanced BST degrades on sorted input.

### Heap

A heap enforces heap order, not search order:

- Min-heap: `parent.value <= child.value` for every edge.
- Max-heap: `parent.value >= child.value`.

A heap gives $O(1)$ access to the minimum or maximum and $O(\log n)$
insert and extract. It does not support efficient search for arbitrary
keys. Represent a binary heap as an array (`parent at (i-1)/2`, children at
`2*i+1` and `2*i+2`) for cache locality, or as a tree when pointer
stability matters.

## Operations

Validate the tree and the key before any operation. Return failure on
allocation failure or invalid input and leave the tree in its last valid
state.

### Create

```text
function init(tree, compare):
  tree.root = null
  tree.count = 0
  tree.compare = compare

function make_node(value):
  node = allocate Node<T>
  if node == null:
    return failure
  node.value = value
  node.left = null
  node.right = null
  return node
```

### Insert

BST insert without balancing. Reject duplicates or handle them on the
chosen side consistently.

```text
function insert(tree, value):
  require(tree != null)
  if tree.root == null:
    tree.root = make_node(value)
    if tree.root == null:
      return failure
    tree.count = tree.count + 1
    return success

  current = tree.root
  loop:
    cmp = tree.compare(value, current.value)
    if cmp == 0:
      return duplicate   # or update current.value = value
    if cmp < 0:
      if current.left == null:
        current.left = make_node(value)
        if current.left == null:
          return failure
        tree.count = tree.count + 1
        return success
      current = current.left
    else:
      if current.right == null:
        current.right = make_node(value)
        if current.right == null:
          return failure
        tree.count = tree.count + 1
        return success
```

For balanced trees, walk back from the insertion point and rotate to
restore the balance invariant after the leaf insert.

### Search

```text
function search(tree, key, out_value):
  require(tree != null)
  current = tree.root
  while current != null:
    cmp = tree.compare(key, current.value)
    if cmp == 0:
      if out_value is provided:
        out_value = current.value
      return found
    if cmp < 0:
      current = current.left
    else:
      current = current.right
  return not_found

function contains(tree, key):
  return search(tree, key, null) == found
```

### Delete

Handle three cases: leaf, one child, two children. For two children,
replace with the inorder successor (minimum of the right subtree) or the
predecessor, then delete the successor node which has at most one child.

```text
function delete(tree, key, out_removed):
  require(tree != null)
  parent = null
  current = tree.root
  # find node and its parent
  while current != null and tree.compare(key, current.value) != 0:
    parent = current
    if tree.compare(key, current.value) < 0:
      current = current.left
    else:
      current = current.right
  if current == null:
    return not_found
  if out_removed is provided:
    out_removed = current.value

  # case 1 and 2: zero or one child
  if current.left == null or current.right == null:
    child = current.left != null ? current.left : current.right
    if parent == null:
      tree.root = child
    else if parent.left == current:
      parent.left = child
    else:
      parent.right = child
    free current
  else:
    # case 3: two children — replace with successor
    succ_parent = current
    succ = current.right
    while succ.left != null:
      succ_parent = succ
      succ = succ.left
    current.value = succ.value
    # succ has at most a right child
    if succ_parent.left == succ:
      succ_parent.left = succ.right
    else:
      succ_parent.right = succ.right
    free succ

  tree.count = tree.count - 1
  # for balanced trees: rebalance from parent upward
  return success
```

### Traversal

Traversal visits every node exactly once. Use recursion only when depth is
bounded; otherwise use an explicit stack or queue.

#### Preorder

Visit root before children. Use for copying or prefix notation.

```text
function preorder(node, visit):
  if node == null:
    return
  visit(node.value)
  preorder(node.left, visit)
  preorder(node.right, visit)
```

#### Inorder

Visit left, root, right. For a BST, inorder yields sorted order.

```text
function inorder(node, visit):
  if node == null:
    return
  inorder(node.left, visit)
  visit(node.value)
  inorder(node.right, visit)
```

#### Postorder

Visit children before root. Use for cleanup and postfix notation.

```text
function postorder(node, visit):
  if node == null:
    return
  postorder(node.left, visit)
  postorder(node.right, visit)
  visit(node.value)

function destroy(tree):
  postorder(tree.root, free_node)
  tree.root = null
  tree.count = 0
```

#### Level Order

Visit level by level with a queue. Use for breadth-first search and
level-aware processing.

```text
function level_order(tree, visit):
  if tree.root == null:
    return
  queue = empty queue
  enqueue(queue, tree.root)
  while queue not empty:
    node = dequeue(queue)
    visit(node.value)
    if node.left != null:
      enqueue(queue, node.left)
    if node.right != null:
      enqueue(queue, node.right)
```

Iterative inorder with an explicit stack avoids recursion limits:

```text
function inorder_iterative(tree, visit):
  stack = empty stack
  current = tree.root
  while stack not empty or current != null:
    while current != null:
      push(stack, current)
      current = current.left
    current = pop(stack)
    visit(current.value)
    current = current.right
```

## Complexity

- BST `search`, `insert`, `delete`: $O(h)$ where $h$ is height.
  Average $O(\log n)$ for random data; worst $O(n)$ when skewed.
- Balanced tree `search`, `insert`, `delete`: $O(\log n)$ worst case.
- Heap `insert`, `extract_min`/`extract_max`: $O(\log n)$; `peek`: $O(1)$.
- Traversal (`preorder`, `inorder`, `postorder`, `level_order`): $O(n)$
  time, $O(h)$ auxiliary space for recursion or stack and $O(n)$ for the
  queue in level order.
- Storage: $O(n)$ nodes. Balanced trees add at most one color or height
  field per node.

## Pitfalls

- Dereferencing a null child; always check `left` and `right` before use.
- Forgetting to update `parent` links when the node stores a parent pointer.
- Double-free or use-after-free during `delete` and `destroy`; null the
  root after destroy and free each node exactly once.
- Losing the original child pointer after a failed allocation on `insert`.
- Violating the BST ordering invariant on duplicate handling; pick one side
  consistently.
- Using recursion with no depth bound on skewed or attacker-controlled
  input; prefer an explicit stack or iterative traversal.
- Rebalancing incorrectly after `insert` and `delete` in balanced trees;
  test rotation cases exhaustively.
- Holding a pointer to a node value after the node has been deleted; that
  pointer is dangling.
- Counting `count` incorrectly after a failed insert or a duplicate return.
- Freeing caller-owned payloads when the tree stores borrowed references.

## Validation

Test: empty tree, single node, left-skewed, right-skewed, balanced, random
insert order, duplicate keys, missing keys, delete leaf, delete node with
one child, delete node with two children, delete root, repeated `destroy`,
traversal order checks (`inorder` yields sorted order for a BST), and
allocation failure on `create` and `insert`.

Instantiate the pseudocode for a concrete `T` (for example, `int`) before
running; in C, compile and run with sanitizers enabled:

```sh
gcc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g tree.c -o tree
./tree
```

Verify height stays logarithmic for balanced variants under sorted input.

## Resources

### Documentation

- [C `malloc` and `free` reference](https://en.cppreference.com/w/c/memory)
- [C `SIZE_MAX` reference](https://en.cppreference.com/w/c/types/integer)

### Online Resources

- [Binary tree overview](https://en.wikipedia.org/wiki/Binary_tree)
- [Binary search tree](https://en.wikipedia.org/wiki/Binary_search_tree)
- [Tree traversal](https://en.wikipedia.org/wiki/Tree_traversal)
- [Self-balancing binary search tree](https://en.wikipedia.org/wiki/Self-balancing_binary_search_tree)
- [Heap (data structure)](https://en.wikipedia.org/wiki/Heap_(data_structure))
- [SEI CERT C memory rules](https://wiki.sei.cmu.edu/confluence/display/c/MEM)
- [NIST Data Structures and Algorithms](https://www.nist.gov/dads/)

### Tools

- [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
- [Valgrind](https://valgrind.org/docs/manual/manual.html)
- [GDB](https://sourceware.org/gdb/documentation/)

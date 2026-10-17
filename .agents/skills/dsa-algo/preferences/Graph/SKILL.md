---
name: dsa-graph
user-invocable: false
description: >
  Design and implement C graphs with explicit vertex and edge ownership,
  adjacency-list operations, traversal, and checked allocation.
allow-tools:
  - bash
  - read
  - edit
  - write
  - gcc
---

# Graph

## Table of Contents
- [Overview](#overview)
  - [What Is a Graph](#what-is-a-graph)
  - [Graph Terminology](#graph-terminology)
  - [Graph Properties](#graph-properties)
  - [When to Use Graphs](#when-to-use-graphs)
- [Implementation Context](#implementation-context)
  - [Standard Library](#standard-library)
  - [Memory Allocation](#memory-allocation)
  - [Generic Data](#generic-data)
- [Rules](#rules)
- [Graph Structure](#graph-structure)
  - [Vertices](#vertices)
  - [Edges](#edges)
  - [Adjacency Lists](#adjacency-lists)
  - [Directed and Undirected Graphs](#directed-and-undirected-graphs)
  - [Weighted Graphs](#weighted-graphs)
  - [Invariants](#invariants)
- [Ownership](#ownership)
- [Helpers](#helpers)
  - [Vertex Lookup](#vertex-lookup)
  - [Edge Lookup](#edge-lookup)
  - [Unlink Edge](#unlink-edge)
  - [Renumber Vertex Ids](#renumber-vertex-ids)
  - [Allocation Checks](#allocation-checks)
- [Operations](#operations)
  - [Create](#create)
  - [Add Vertex](#add-vertex)
  - [Add Edge](#add-edge)
  - [Remove Edge](#remove-edge)
  - [Remove Vertex](#remove-vertex)
  - [Traversal](#traversal)
    - [Depth-First Search (DFS)](#depth-first-search-dfs)
      - [Recursive DFS](#recursive-dfs)
      - [Iterative DFS (Explicit Stack)](#iterative-dfs-explicit-stack)
    - [Breadth-First Search (BFS)](#breadth-first-search-bfs)
      - [Recursive BFS](#recursive-bfs)
      - [Iterative BFS (Queue)](#iterative-bfs-queue)
    - [Check Connectivity](#check-connectivity)
    - [Cycle Detection](#cycle-detection)
      - [Directed Graph Cycle Detection](#directed-graph-cycle-detection)
      - [Undirected Graph Cycle Detection](#undirected-graph-cycle-detection)
  - [Destroy](#destroy)
- [Complexity](#complexity)
- [Pitfalls](#pitfalls)
- [Validation](#validation)
- [Resources](#resources)

## Overview

### What Is a Graph

A graph is a set of vertices connected by edges. It models relationships,
routes, dependencies, and networks. This skill uses adjacency lists because
they store sparse graphs efficiently.

### Graph Terminology

- Vertex: one graph item.
- Edge: a connection between two vertices.
- Neighbor: a vertex connected by an edge.
- Degree: number of incident edges.
- Path: an ordered sequence of connected vertices.
- Cycle: a path that returns to its starting vertex.
- Connected component: a maximal set of mutually reachable vertices.

### Graph Properties

- Directed graph edges have a source and a destination.
- Undirected graph edges have no direction.
- Weighted graph edges store a numeric cost.
- A simple graph has no self-loops or duplicate edges.
- A graph can be empty, disconnected, cyclic, or acyclic.

### When to Use Graphs

Use a graph for many-to-many relationships, dependency networks, maps, or
state transitions. Use adjacency lists for sparse graphs. Use an adjacency
matrix only when the graph is dense or constant-time edge checks matter more
than memory use.

## Implementation Context

### Standard Library

ISO C provides no graph container. Use `<stdbool.h>`, `<stddef.h>`,
`<stdint.h>`, `<stdlib.h>`, and `<string.h>` as needed. A queue or stack may
use a project vector, but graph ownership rules remain explicit.

### Memory Allocation

Allocate each vertex and edge with `malloc` or `calloc`. Check every
allocation before writing through the returned pointer. On partial failure,
free all objects created by the current operation.

Use `SIZE_MAX` checks before multiplying counts by element sizes. `realloc`
may move storage and leaves the original allocation valid on failure.

### Generic Data

Parameterize vertex data with a payload type `T`, or store a `void *payload`
with a destructor callback. Vertex identifiers need a comparison function.

```c
typedef int (*GraphCompare)(const void *left, const void *right);
typedef void (*GraphDestroy)(void *payload);
```

Keep identity separate from payload. A comparator must define a consistent
equality relation. Never compare arbitrary payload bytes with `memcmp` unless
the payload representation explicitly permits it.

## Rules

Validate graph pointers, identifiers, and callback requirements before each
operation. Keep vertex identifiers unique. Keep every edge attached to valid
vertices. Keep `vertex_count` and `edge_count` accurate after every mutation.

For undirected graphs, store each edge in both endpoint adjacency lists and
count one logical edge. For directed graphs, store one outgoing adjacency
entry and count one directed edge.

Every successful allocation has one matching free. Do not expose internal
links to callers who can invalidate graph invariants.

## Graph Structure

### Vertices

```text
structure Vertex<T>:
  key: K
  id: integer
  payload: T
  edges: pointer to Edge
  next: pointer to Vertex<T>
```

`next` links vertices owned by the graph. `edges` points to the first
adjacency entry. Use stable keys for lookup; do not use a mutable payload as
identity unless the graph updates its indexes when payload changes.

### Edges

```text
structure Edge:
  target: pointer to Vertex<T>
  weight: W
  next: pointer to Edge
```

An adjacency entry points to its target vertex. In an undirected graph,
`add_edge(A, B)` creates entries `A -> B` and `B -> A`. Each entry is freed
when its owning adjacency list is destroyed or when the edge is removed.

### Adjacency Lists

Adjacency lists give $O(V + E)$ storage for a graph with $V$ vertices and
$E$ logical edges. Each vertex owns its outgoing adjacency list. Lookup of a
neighbor is linear in that vertex's degree unless an additional index exists.

### Directed and Undirected Graphs

Store a `directed` flag in graph state, or use separate constructors that fix
the mode. Do not mix modes during one graph lifetime. For undirected graphs,
mutations must update both adjacency lists or reject the operation unchanged.

### Weighted Graphs

Store weight in each adjacency entry. Define whether negative weights are
valid. Traversal ignores weights; shortest-path algorithms must enforce their
own weight requirements. Reject non-finite weights when the graph contract
requires finite values.

### Invariants

- `vertex_count` equals the number of owned vertices.
- Every edge target belongs to the same graph.
- Every adjacency entry appears in exactly one owner's list.
- Undirected edges have symmetric adjacency entries.
- `edge_count` counts logical edges, not undirected adjacency entries.
- No duplicate key exists.
- Every vertex `id` equals its 0-based position in the owner list; `renumber_ids` rebuilds this after `remove_vertex`.
- A failed mutation leaves graph state unchanged.

## Ownership

The graph owns every vertex and adjacency entry created through graph
operations. The graph owns payloads only when a destructor callback says so.
Document payload ownership at the API boundary.

Destroy edges before their vertices. For undirected graphs, remove both
adjacency entries before freeing either entry. Invoke a payload destructor
exactly once for each owned payload.

## Helpers

### Vertex Lookup

```text
function find_vertex(graph, key):
  current = graph.vertices
  while current != null:
    if compare(current.key, key) == 0:
      return current
    current = current.next
  return null
```

Return a borrowed pointer. Callers must not free it or retain it after vertex
removal. Return an error when `graph`, `key`, or `compare` is invalid.

### Edge Lookup

Search only the source vertex adjacency list. Compare target identity, not
payload address. Reject duplicate edges when the graph is simple.

```text
function find_edge(source, target):
  edge = source.edges
  while edge != null:
    if edge.target == target:
      return edge
    edge = edge.next
  return null
```

### Unlink Edge

```text
function unlink_edge(source, edge):
  prev = null
  current = source.edges
  while current != null:
    if current == edge:
      if prev != null:
        prev.next = current.next
      else:
        source.edges = current.next
      return OK
    prev = current
    current = current.next
  return NOT_FOUND
```

Detaches a located adjacency entry from its owner list by pointer identity.
The caller stays responsible for freeing the entry. Every adjacency entry must
remain owned by exactly one vertex list.

### Renumber Vertex Ids

```text
function renumber_ids(graph):
  id = 0
  current = graph.vertices
  while current != null:
    current.id = id
    id = id + 1
    current = current.next
```

Rebuilds the dense `id == position` invariant after `remove_vertex`. Call it
after any mutation of the owner list so visited arrays indexed by `vertex.id`
stay in range `[0, vertex_count)`.

### Allocation Checks

Before allocation, check `count > SIZE_MAX / element_size`. Allocate the
object, check for null, initialize every field, then link it into the graph.
Link only after all operation-specific allocations succeed.

## Operations

### Create

Initialize an empty graph with mode, comparator, payload destructor, and zero
counts. Reject a null comparator when keys require comparison.

```text
function create(directed, compare, destroy_payload):
  graph = allocate Graph
  if graph == null:
    return OUT_OF_MEMORY
  graph.vertices = null
  graph.vertex_count = 0
  graph.edge_count = 0
  graph.directed = directed
  graph.compare = compare
  graph.destroy_payload = destroy_payload
  return graph
```

### Add Vertex

Reject duplicate keys. Allocate and initialize the vertex with a position id
equal to `vertex_count`, append it to the owner list, and only then increment
`vertex_count`. On allocation failure or duplicate key, leave the graph
unchanged.

```text
function add_vertex(graph, key, payload):
  if graph == null or key == null or graph.compare == null:
    return INVALID_ARGUMENT
  if find_vertex(graph, key) != null:
    return DUPLICATE_KEY

  vertex = allocate Vertex
  if vertex == null:
    return OUT_OF_MEMORY
  vertex.key = key
  vertex.id = graph.vertex_count
  vertex.payload = payload
  vertex.edges = null
  vertex.next = null

  if graph.vertices == null:
    graph.vertices = vertex
  else:
    tail = graph.vertices
    while tail.next != null:
      tail = tail.next
    tail.next = vertex

  graph.vertex_count = graph.vertex_count + 1
  return OK
```

`vertex.id` is the 0-based position of the vertex in the owner list. It indexes
visited arrays during traversal, so it must stay dense and
`remove_vertex` renumbers surviving vertices after unlinking one.

### Add Edge

Find both endpoint vertices first. Reject missing endpoints, invalid weights,
duplicate edges, and self-loops on a simple graph. Allocate every required
adjacency entry before linking any, so a failed allocation leaves the graph
unchanged. For an undirected graph, allocate two entries and count one logical
edge; for a directed graph, one entry and one edge.

```text
function add_edge(graph, src_key, dst_key, weight):
  if graph == null or src_key == null or dst_key == null:
    return INVALID_ARGUMENT
  if graph.weighted and not finite(weight):
    return INVALID_WEIGHT
  if graph.simple and src_key == dst_key:
    return INVALID_SELF_LOOP

  src = find_vertex(graph, src_key)
  dst = find_vertex(graph, dst_key)
  if src == null or dst == null:
    return VERTEX_NOT_FOUND
  if find_edge(src, dst) != null:
    return DUPLICATE_EDGE

  entry = allocate Edge
  if entry == null:
    return OUT_OF_MEMORY
  entry.target = dst
  entry.weight = weight
  entry.next = null

  reverse = null
  if not graph.directed:
    reverse = allocate Edge
    if reverse == null:
      free(entry)
      return OUT_OF_MEMORY
    reverse.target = src
    reverse.weight = weight
    reverse.next = null

  // link into adjacency lists only after every allocation succeeded
  insert_head(src.edges, entry)
  if reverse != null:
    insert_head(dst.edges, reverse)
  graph.edge_count = graph.edge_count + 1
  return OK
```

`insert_head(list, node)` prepends a node to an adjacency list. Adjacency
entry order is not part of the graph contract.

### Remove Edge

Locate both endpoint vertices and both adjacency entries without mutating
anything. Only when the full entry pair (or the single directed entry) is
found, unlink and free the entries, then decrement `edge_count`. If any entry
is missing, leave graph state unchanged.

```text
function remove_edge(graph, src_key, dst_key):
  if graph == null or src_key == null or dst_key == null:
    return INVALID_ARGUMENT
  src = find_vertex(graph, src_key)
  dst = find_vertex(graph, dst_key)
  if src == null or dst == null:
    return VERTEX_NOT_FOUND

  entry = find_edge(src, dst)
  if entry == null:
    return EDGE_NOT_FOUND

  reverse = null
  if not graph.directed:
    reverse = find_edge(dst, src)
    if reverse == null:
      return GRAPH_CORRUPT  // undirected adjacency must stay symmetric

  unlink_edge(src, entry)
  if reverse != null:
    unlink_edge(dst, reverse)

  free(entry)
  if reverse != null:
    free(reverse)
  graph.edge_count = graph.edge_count - 1
  return OK
```

Both entries are located before either is unlinked. If the graph is corrupt
(asymmetric undirected adjacency), the operation fails without changing state.

### Remove Vertex

Remove every edge incident to the vertex, then unlink the vertex itself.
Never free a vertex while another adjacency entry still targets it. Free every
adjacency entry owned by the vertex, then scan the other vertices and free the
entries that target it. Destroy the payload exactly once (if owned), free the
vertex, decrement counts, and renumber ids.

```text
function remove_vertex(graph, key):
  if graph == null or key == null:
    return INVALID_ARGUMENT
  target = find_vertex(graph, key)
  if target == null:
    return VERTEX_NOT_FOUND

  freed_entries = 0

  // free every adjacency entry owned by the target
  edge = target.edges
  while edge != null:
    next = edge.next
    free(edge)
    freed_entries = freed_entries + 1
    edge = next
  target.edges = null

  // free every entry on other vertices that targets this vertex
  current = graph.vertices
  while current != null:
    if current != target:
      prev = null
      edge = current.edges
      while edge != null:
        next = edge.next
        if edge.target == target:
          if prev != null:
            prev.next = edge.next
          else:
            current.edges = edge.next
          free(edge)
          freed_entries = freed_entries + 1
        else:
          prev = edge
        edge = next
    current = current.next

  // unlink the vertex from the owner list
  prev = null
  current = graph.vertices
  while current != null:
    if current == target:
      if prev != null:
        prev.next = target.next
      else:
        graph.vertices = target.next
      break
    prev = current
    current = current.next

  if graph.directed:
    graph.edge_count = graph.edge_count - freed_entries
  else:
    graph.edge_count = graph.edge_count - (freed_entries / 2)

  if graph.destroy_payload != null:
    graph.destroy_payload(target.payload)
  free(target)
  graph.vertex_count = graph.vertex_count - 1
  renumber_ids(graph)
  return OK
```

For an undirected graph every logical edge owns exactly two adjacency entries,
so halving the freed entry count yields the removed logical edges. Each entry
is freed exactly once: outgoing entries on the target, incoming entries on
other vertices.

### Traversal

Traversal marks vertices by stable identity. Allocate a visited array indexed
by `vertex.id` and never use payload values as visited state. Neighbors are
reached directly through adjacency entries, so edge scanning costs
$O(V + E)$ total with no per-neighbor key lookup.

#### Depth-First Search (DFS)

Depth-first search explores as far as possible along each branch before
backtracking. It uses a stack: the call stack in the recursive variant, an
explicit stack in the iterative variant. Both visit each vertex exactly once
in pre-order.

##### Recursive DFS

```text
function dfs_recursive(graph, start_key, visit):
  if graph == null or start_key == null:
    return INVALID_ARGUMENT
  start = find_vertex(graph, start_key)
  if start == null:
    return NOT_FOUND

  visited = allocate boolean[graph.vertex_count] initialized to false
  if visited == null:
    return OUT_OF_MEMORY

  dfs_step(start, visited, visit)
  free(visited)
  return OK

function dfs_step(vertex, visited, visit):
  visited[vertex.id] = true
  visit(vertex)
  edge = vertex.edges
  while edge != null:
    if not visited[edge.target.id]:
      dfs_step(edge.target, visited, visit)
    edge = edge.next
```

**Time Complexity:** $O(V + E)$  
**Space Complexity:** $O(V)$ visited array plus recursion stack (worst case is
a line graph with depth $V$)

Recursion depth equals the longest DFS path and can reach $V$. Reject
recursive DFS when graph depth can exceed the process stack limit; use the
iterative variant for untrusted or large graphs.

##### Iterative DFS (Explicit Stack)

```text
function dfs_stack(graph, start_key, visit):
  if graph == null or start_key == null:
    return INVALID_ARGUMENT
  start = find_vertex(graph, start_key)
  if start == null:
    return NOT_FOUND

  visited = allocate boolean[graph.vertex_count] initialized to false
  if visited == null:
    return OUT_OF_MEMORY

  push(stack, start)
  visited[start.id] = true
  while stack is not empty:
    vertex = pop(stack)
    visit(vertex)
    edge = vertex.edges
    while edge != null:
      if not visited[edge.target.id]:
        visited[edge.target.id] = true
        push(stack, edge.target)
      edge = edge.next

  free(visited)
  return OK
```

**Time Complexity:** $O(V + E)$  
**Space Complexity:** $O(V)$ visited array plus explicit stack

Marking a vertex visited at push time prevents duplicate stack entries in
cyclic graphs. Explicit stack DFS keeps auxiliary storage predictable at
$O(V)$ and avoids recursion depth limits. Neighbor push order affects the
visit sequence; push reverse adjacency order for the recursive pre-order.

#### Breadth-First Search (BFS)

Breadth-first search explores layer by layer, visiting every neighbor before
moving to the next layer. Both variants visit vertices in BFS order: the
iterative form uses an explicit FIFO queue, the recursive form processes one
level per recursion step.

##### Recursive BFS

```text
function bfs_recursive(graph, start_key, visit):
  if graph == null or start_key == null:
    return INVALID_ARGUMENT
  start = find_vertex(graph, start_key)
  if start == null:
    return NOT_FOUND

  visited = allocate boolean[graph.vertex_count] initialized to false
  level = allocate array of Vertex of size graph.vertex_count
  next_level = allocate array of Vertex of size graph.vertex_count
  if visited == null or level == null or next_level == null:
    free(visited)
    free(level)
    free(next_level)
    return OUT_OF_MEMORY

  level[0] = start
  visited[start.id] = true
  bfs_level(level, 1, next_level, visited, visit)

  free(visited)
  free(level)
  free(next_level)
  return OK

function bfs_level(level, level_count, next_level, visited, visit):
  next_count = 0
  for i from 0 to level_count - 1:
    vertex = level[i]
    visit(vertex)
    edge = vertex.edges
    while edge != null:
      if not visited[edge.target.id]:
        visited[edge.target.id] = true
        next_level[next_count] = edge.target
        next_count = next_count + 1
      edge = edge.next
  if next_count > 0:
    swap(level, next_level)
    bfs_level(level, next_count, next_level, visited, visit)
```

**Time Complexity:** $O(V + E)$  
**Space Complexity:** $O(V)$ visited array plus two level buffers plus
recursion stack

Recursive BFS postpones the explicit FIFO and instead buffers each next level
in a vertex array. Recursion depth equals the graph diameter (the longest
shortest path), not the vertex count, but can still reach $V$ on a path graph.
Prefer the iterative queue variant for large or untrusted graphs.

##### Iterative BFS (Queue)

```text
function bfs_iterative(graph, start_key, visit):
  if graph == null or start_key == null:
    return INVALID_ARGUMENT
  start = find_vertex(graph, start_key)
  if start == null:
    return NOT_FOUND

  visited = allocate boolean[graph.vertex_count] initialized to false
  if visited == null:
    return OUT_OF_MEMORY

  enqueue(queue, start)
  visited[start.id] = true
  while queue is not empty:
    vertex = dequeue(queue)
    visit(vertex)
    edge = vertex.edges
    while edge != null:
      if not visited[edge.target.id]:
        visited[edge.target.id] = true
        enqueue(queue, edge.target)
      edge = edge.next

  free(visited)
  return OK
```

**Time Complexity:** $O(V + E)$  
**Space Complexity:** $O(V)$ visited array plus queue

Marking a vertex visited at enqueue time prevents duplicate queue entries when
the graph contains cycles. Implement the queue over a growable buffer with
head/tail indices: dequeue from `head` without shifting the buffer, check
capacity before enqueue, and reuse consumed slots with a ring buffer for
amortized $O(1)$ operations.

#### Check Connectivity

For an undirected graph, run DFS or BFS from the first vertex and count the
visited vertices. The graph is connected when the count equals
`vertex_count`. An empty graph is connected only if the API explicitly
defines it so; document the choice.

```text
function is_connected(graph):
  if graph == null:
    return INVALID_ARGUMENT
  if graph.vertex_count == 0:
    return CONNECTED  // empty-graph policy is an API decision

  start = graph.vertices
  visited = allocate boolean[graph.vertex_count] initialized to false
  if visited == null:
    return OUT_OF_MEMORY

  dfs_step(start, visited, count_visitor)  // or bfs_iterative
  visit_count = count_marked(visited)
  free(visited)

  if visit_count == graph.vertex_count:
    return CONNECTED
  return DISCONNECTED
```

**Time Complexity:** $O(V + E)$  
**Space Complexity:** $O(V)$

`count_visitor` is a callback that increments a counter and
`count_marked(visited)` counts the `true` entries. For a directed graph, this
check reports reachability from one chosen start vertex, not strong
connectivity; strong connectivity needs additional reachability checks or a
component algorithm.

#### Cycle Detection

Cycle detection identifies paths that return to previously visited vertices.
The algorithm depends on graph directionality: directed graphs track a
per-vertex state, undirected graphs track the DFS parent.

##### Directed Graph Cycle Detection

```text
function has_cycle_directed(graph):
  if graph == null:
    return INVALID_ARGUMENT

  state = allocate integer[graph.vertex_count] initialized to 0
  // 0 = unseen, 1 = active in the current DFS path, 2 = completed
  if state == null:
    return OUT_OF_MEMORY

  vertex = graph.vertices
  while vertex != null:
    if state[vertex.id] == 0:
      if dfs_cycle_directed(vertex, state) == true:
        free(state)
        return true
    vertex = vertex.next

  free(state)
  return false

function dfs_cycle_directed(vertex, state):
  state[vertex.id] = 1
  edge = vertex.edges
  while edge != null:
    next_vertex = edge.target
    if state[next_vertex.id] == 1:
      return true  // back-edge into the active DFS path
    if state[next_vertex.id] == 0:
      if dfs_cycle_directed(next_vertex, state) == true:
        return true
    edge = edge.next
  state[vertex.id] = 2  // completed; safe to leave the DFS path
  return false
```

**Time Complexity:** $O(V + E)$  
**Space Complexity:** $O(V)$ state array plus recursion stack

An edge into a vertex that is active (state 1) is a back-edge and proves a
cycle. A vertex marked completed (state 2) never re-enters the traversal
because all its outgoing paths were already explored.

##### Undirected Graph Cycle Detection

```text
function has_cycle_undirected(graph):
  if graph == null:
    return INVALID_ARGUMENT
  if graph.vertex_count == 0:
    return false

  visited = allocate boolean[graph.vertex_count] initialized to false
  if visited == null:
    return OUT_OF_MEMORY

  result = false
  vertex = graph.vertices
  while vertex != null and not result:
    if not visited[vertex.id]:
      result = dfs_cycle_undirected(vertex, null, visited)
    vertex = vertex.next

  free(visited)
  return result

function dfs_cycle_undirected(vertex, parent, visited):
  visited[vertex.id] = true
  edge = vertex.edges
  while edge != null:
    next_vertex = edge.target
    if next_vertex == parent:
      edge = edge.next
      continue  // skip only the edge back to the DFS parent
    if visited[next_vertex.id]:
      return true  // visited neighbor that is not the parent
    if dfs_cycle_undirected(next_vertex, vertex, visited) == true:
      return true
    edge = edge.next
  return false
```

**Time Complexity:** $O(V + E)$  
**Space Complexity:** $O(V)$ visited array plus recursion stack

Skip only the single `Edge` back to the parent, not every edge to the parent
vertex, so parallel edges between the same two vertices still report a cycle.
A visited neighbor that is not the parent indicates a back-edge or cross-edge
and therefore a cycle. Starting from every vertex detects a cycle in a
disconnected graph that has one cyclic component.

### Destroy

Free every adjacency entry, invoke the payload destructor exactly once for
each owned payload, free every vertex, and finally free the graph. Clearing
counts and the vertex pointer after the loop leaves the graph in a safe,
reusable state after any partial cleanup failure.

```text
function destroy(graph):
  if graph == null:
    return INVALID_ARGUMENT

  vertex = graph.vertices
  while vertex != null:
    next = vertex.next
    edge = vertex.edges
    while edge != null:
      edge_next = edge.next
      free(edge)
      edge = edge_next
    if graph.destroy_payload != null:
      graph.destroy_payload(vertex.payload)
    free(vertex)
    vertex = next

  graph.vertices = null
  graph.vertex_count = 0
  graph.edge_count = 0
  free(graph)
  return OK
```

**Time Complexity:** $O(V + E)$  
**Space Complexity:** $O(1)$

Each undirected logical edge contributes two adjacency entries, one on each
endpoint list, so iterating every list frees each entry exactly once. The
graph owns payloads only when a destructor callback is provided; call it once
per vertex and never after the vertex is freed. Set local pointers to null
after freeing when a callback may resume cleanup after an error.

## Complexity

With adjacency lists and linear vertex lookup:

- Create: $O(1)$ time, $O(1)$ space.
- Add vertex: $O(V)$ time for duplicate detection, $O(1)$ new space.
- Add edge: $O(V + d)$ time, where $d$ is source degree.
- Remove edge: $O(V + d)$ time.
- Remove vertex: $O(V + E)$ time.
- DFS, BFS, connectivity check, or cycle detection: $O(V + E)$ time and
  $O(V)$ auxiliary space.
- Destroy: $O(V + E)$ time.

An external key index can reduce vertex lookup, but it adds ownership and
consistency work. State index space separately from adjacency storage.

## Pitfalls

- Counting both undirected adjacency entries as two logical edges.
- Freeing a vertex while incoming edges still target it.
- Linking the first allocation before a second allocation succeeds.
- Using recursive DFS on attacker-controlled depth.
- Forgetting visited state and revisiting cycles forever.
- Treating directed reachability as strong connectivity.
- Comparing payload addresses instead of vertex keys.
- Calling a payload destructor more than once.
- Using signed indexes that underflow during list removal.
- Leaving stale `id` values after `remove_vertex`, so visited arrays index
  out of range.
- Mutating graph state after allocation failure.

## Validation

Test empty, one-vertex, disconnected, duplicate-key, duplicate-edge, self-loop,
cycle, tree-shaped, directed, undirected, weighted, and large sparse graphs.
Test removing missing vertices and edges. Test allocation failure when the
allocator can inject failures.

Check invariants after every mutation. Compile with warnings and sanitizers:

```sh
gcc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g graph.c -o graph
./graph
```

## Resources

Use project-local vector, queue, or list implementations when their ownership
contracts match this skill. Keep graph-specific invariants in graph tests.

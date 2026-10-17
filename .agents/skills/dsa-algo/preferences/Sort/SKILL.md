---
name: dsa-sort
user-invocable: false
description: >
  Choose, explain, and implement C sorting algorithms with pseudocode, explicit
  complexity, stability, memory limits, and standard-library alternatives.
allow-tools:
  - bash
  - read
  - edit
  - write
  - gcc
---

# Sorting Algorithms in C

## Rules

Define sorted order, duplicate behavior, stability, ownership, and memory limit
before choosing an algorithm. Every sort must return a permutation in order.

Use pseudocode to reason first. Translate pseudocode to C only after invariants
and complexity are clear.

## Structure Data

Represent sortable data as a contiguous array plus an element count. Define a
total comparator before implementing an algorithm.

```c
typedef int (*SortCompare)(const void *left, const void *right);
```

## Helpers

Common helpers include swap, compare, partition, merge, heapify, and digit or
bucket indexing. Helpers must preserve array bounds and comparator ordering.

```text
function swap(array, left, right):
	temporary = array[left]
	array[left] = array[right]
	array[right] = temporary

function is_sorted(array, n):
	for i = 1 to n - 1:
		if array[i - 1] > array[i]:
			return false
	return true
```

## Operations

### Complexity Map

| Algorithm | Best | Average | Worst | Extra space | Stable |
|---|---:|---:|---:|---:|---|
| Bubble | $O(n)$ | $O(n^2)$ | $O(n^2)$ | $O(1)$ | Yes |
| Selection | $O(n^2)$ | $O(n^2)$ | $O(n^2)$ | $O(1)$ | No |
| Insertion | $O(n)$ | $O(n^2)$ | $O(n^2)$ | $O(1)$ | Yes |
| Shell | depends | depends | depends | $O(1)$ | No |
| Merge | $O(n\log n)$ | $O(n\log n)$ | $O(n\log n)$ | $O(n)$ | Yes |
| Quick | $O(n\log n)$ | $O(n\log n)$ | $O(n^2)$ | $O(\log n)$ stack average | No |
| Heap | $O(n\log n)$ | $O(n\log n)$ | $O(n\log n)$ | $O(1)$ | No |
| Counting | $O(n+k)$ | $O(n+k)$ | $O(n+k)$ | $O(k)$ | Optional |
| Radix | $O(d(n+k))$ | $O(d(n+k))$ | $O(d(n+k))$ | $O(n+k)$ | Usually |
| Bucket | $O(n+k)$ expected | depends | $O(n^2)$ | $O(n+k)$ | Depends |

`n` is item count. `k` is key range or bucket count. `d` is digit count.

## Basic Comparison Sorts

### Bubble sort

Use for teaching or tiny, nearly sorted input. Stop when a pass makes no swap.

```text
function bubble_sort(array, n):
	repeat until no_swap:
		no_swap = true
		for i = 1 to n - 1:
			if array[i - 1] > array[i]:
				swap(array[i - 1], array[i])
				no_swap = false
		n = n - 1
```

### Selection sort

Use when writes are expensive and input is small. Find minimum for each position.

```text
function selection_sort(array, n):
	for start = 0 to n - 2:
		minimum = start
		for i = start + 1 to n - 1:
			if array[i] < array[minimum]:
				minimum = i
		swap(array[start], array[minimum])
```

### Insertion sort

Use for small or nearly sorted input. Keep the sorted prefix invariant.

```text
function insertion_sort(array, n):
	for i = 1 to n - 1:
		value = array[i]
		position = i
		while position > 0 and array[position - 1] > value:
			array[position] = array[position - 1]
			position = position - 1
		array[position] = value
```

## Intermediate Comparison Sorts

### Shell sort

Use when in-place sorting matters and exact worst-case bounds are less important.

```text
function shell_sort(array, n):
	gap = n / 2
	while gap > 0:
		for i = gap to n - 1:
			value = array[i]
			position = i
			while position >= gap and array[position - gap] > value:
				array[position] = array[position - gap]
				position = position - gap
			array[position] = value
		gap = gap / 2
```

### Merge sort

Use for stable, predictable $O(n\log n)$ sorting. Allocate one scratch array.

```text
function merge_sort(array, scratch, left, right):
	if right - left < 2:
		return
	middle = left + (right - left) / 2
	merge_sort(array, scratch, left, middle)
	merge_sort(array, scratch, middle, right)
	merge two sorted ranges into scratch
	copy scratch[left..right) back into array
```

### Quick sort

Use for fast average performance. Choose a safe pivot and control recursion.

```text
function quick_sort(array, low, high):
	while low < high:
		pivot_index = partition(array, low, high)
		if pivot_index - low < high - pivot_index:
			quick_sort(array, low, pivot_index - 1)
			low = pivot_index + 1
		else:
			quick_sort(array, pivot_index + 1, high)
			high = pivot_index - 1
```

## Advanced Comparison Sorts

### Heap sort

Use for guaranteed $O(n\log n)$ time and $O(1)$ extra space. It is not stable.

```text
function heap_sort(array, n):
	build max_heap(array, n)
	for end = n - 1 down to 1:
		swap(array[0], array[end])
		sift_down(array, root = 0, limit = end)
```

### Introsort

Use as a production hybrid when implementing a general-purpose sort manually.
Start with quick sort, use insertion sort for small ranges, and use heap sort
when recursion depth becomes unsafe.

```text
function introsort(array, depth_limit):
	if range_size <= insertion_threshold:
		insertion_sort(array)
	else if depth_limit == 0:
		heap_sort(array)
	else:
		pivot = partition(array)
		introsort(left_range, depth_limit - 1)
		introsort(right_range, depth_limit - 1)
```

### Tim sort

Use for data with existing ordered runs. It combines insertion sort and stable
merge operations. Implement only when run detection and extra memory are needed.

```text
function tim_sort(array, n):
	find ascending or descending runs
	extend short runs with insertion_sort
	push runs onto stack
	while run invariants require merging:
		merge adjacent runs
	merge remaining runs
```

## Distribution Sorts

Use only when key constraints make the extra memory and assumptions acceptable.

### Counting sort

Use for small non-negative integer ranges. Check `max - min` overflow.

```text
function counting_sort(array, n, minimum, maximum):
	counts = zeroed array of size maximum - minimum + 1
	for value in array:
		counts[value - minimum] += 1
	output_index = 0
	for offset = 0 to count(counts) - 1:
		repeat counts[offset] times:
			array[output_index] = offset + minimum
			output_index += 1
```

### Radix sort

Use for fixed-width integers or strings. Each digit pass must be stable.

```text
function radix_sort(array, n):
	for digit = least_significant to most_significant:
		stable_counting_sort_by_digit(array, digit)
```

### Bucket sort

Use when values are evenly distributed over a known range.

```text
function bucket_sort(array, n, bucket_count):
	buckets = empty bucket array
	for value in array:
		index = bucket_index(value, bucket_count)
		append value to buckets[index]
	for bucket in buckets:
		insertion_sort(bucket)
	concatenate buckets into array
```

## Standard C Library Sort

Use standard `qsort` when manual implementation is not required. C defines the
comparator contract, but does not guarantee algorithm, stability, or complexity.

```c
#include <stdlib.h>

static int compare_ints(const void *left, const void *right)
{
	int first = *(const int *)left;
	int second = *(const int *)right;

	return (first > second) - (first < second);
}

qsort(values, count, sizeof *values, compare_ints);
```

Do not return `first - second`; integer overflow can break comparator ordering.
Use `bsearch` only on an already sorted array with the same comparator.

## Selection Guide

- Tiny or nearly sorted: insertion sort.
- Teaching: bubble or selection sort.
- Stable general sort: merge sort.
- In-place guaranteed bound: heap sort.
- General manual production sort: introsort.
- Fixed small integer range: counting sort.
- Fixed-width integer keys: radix sort.
- Existing C code, no manual constraint: `qsort`.

## Testing

Test empty, one-item, duplicate, sorted, reverse-sorted, negative, extreme,
large, and already-nearly-sorted inputs. Verify sorted order and permutation.

```sh
gcc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g sort.c -o sort
./sort
```

## Resources

- [C `qsort` reference](https://en.cppreference.com/w/c/algorithm/qsort)
- [C searching and sorting utilities](https://en.cppreference.com/w/c/algorithm)
- [Sorting algorithm overview](https://en.wikipedia.org/wiki/Sorting_algorithm)

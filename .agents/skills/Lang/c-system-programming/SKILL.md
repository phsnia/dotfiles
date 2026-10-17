---
name: c-system-programming
user-invocable: false
description: >
  Write and debug portable C system software with explicit ownership, checked
  errors, safe memory access, POSIX APIs, file I/O, processes, threads, and sockets.
allow-tools:
  - bash
  - read
  - edit
  - write
---

# Table of Contents

- [Portable C System Software](#portable-c-system-software)
  - [Goals and Design Principles](#goals-and-design-principles)
    - [Portability](#portability)
    - [Explicit Ownership](#explicit-ownership)
    - [Checked Errors](#checked-errors)
    - [Safe Memory Access](#safe-memory-access)
    - [Resource Lifetime](#resource-lifetime)
    - [Fail-Fast Design](#fail-fast-design)
  - [Project Structure](#project-structure)
    - [Source Layout](#source-layout)
    - [Header Files](#header-files)
    - [Translation Units](#translation-units)
    - [Public vs Private APIs](#public-vs-private-apis)
    - [Build Configuration](#build-configuration)
  - [Portable C Fundamentals](#portable-c-fundamentals)
    - [C Standard and Implementation Extensions](#c-standard-and-implementation-extensions)
    - [Integer Types](#integer-types)
    - [Fixed-Width Integers](#fixed-width-integers)
    - [Signed vs Unsigned Integers](#signed-vs-unsigned-integers)
    - [Integer Overflow](#integer-overflow)
    - [Size Types](#size-types)
    - [Pointers](#pointers)
    - [Pointer Arithmetic](#pointer-arithmetic)
    - [Arrays and Buffers](#arrays-and-buffers)
    - [Structures and Unions](#structures-and-unions)
    - [Enums](#enums)
    - [Function Pointers](#function-pointers)
    - [Const Correctness](#const-correctness)
    - [Opaque Types](#opaque-types)
  - [Memory Management](#memory-management)
    - [Stack vs Heap](#stack-vs-heap)
    - [malloc](#malloc)
    - [calloc](#calloc)
    - [realloc](#realloc)
    - [free](#free)
    - [Allocation Failure](#allocation-failure)
    - [Allocation Size Overflow](#allocation-size-overflow)
    - [Initialization](#initialization)
    - [Zero-Length Allocations](#zero-length-allocations)
    - [Use-After-Free](#use-after-free)
    - [Double Free](#double-free)
    - [Memory Leaks](#memory-leaks)
    - [Dangling Pointers](#dangling-pointers)
    - [Invalid Pointers](#invalid-pointers)
    - [Buffer Overflows](#buffer-overflows)
    - [Aliasing](#aliasing)
    - [Lifetime and Scope](#lifetime-and-scope)
  - [Ownership and Resource Management](#ownership-and-resource-management)
    - [Ownership Model](#ownership-model)
    - [Borrowed References](#borrowed-references)
    - [Owned References](#owned-references)
    - [Transfer of Ownership](#transfer-of-ownership)
    - [Resource Cleanup](#resource-cleanup)
    - [Single Owner Rule](#single-owner-rule)
    - [Cleanup Paths](#cleanup-paths)
    - [Partial Initialization](#partial-initialization)
    - [Error Cleanup](#error-cleanup)
    - [RAII-Style Patterns in C](#raii-style-patterns-in-c)
  - [Error Handling](#error-handling)
    - [Return Codes](#return-codes)
    - [errno](#errno)
    - [perror](#perror)
    - [strerror](#strerror)
    - [Error Propagation](#error-propagation)
    - [Error Translation](#error-translation)
    - [Recoverable vs Fatal Errors](#recoverable-vs-fatal-errors)
    - [Partial Failure](#partial-failure)
    - [Cleanup After Failure](#cleanup-after-failure)
    - [Error Context](#error-context)
  - [Safe Memory and Buffer Operations](#safe-memory-and-buffer-operations)
    - [memcpy](#memcpy)
    - [memmove](#memmove)
    - [memset](#memset)
    - [memcmp](#memcmp)
    - [String Buffers](#string-buffers)
    - [Buffer Length Validation](#buffer-length-validation)
    - [Null-Termination](#null-termination)
    - [Overlapping Buffers](#overlapping-buffers)
    - [Integer-to-Size Conversion](#integer-to-size-conversion)
  - [Strings](#strings)
    - [C String Representation](#c-string-representation)
    - [String Length](#string-length)
    - [String Copying](#string-copying)
    - [String Concatenation](#string-concatenation)
    - [String Comparison](#string-comparison)
    - [String Parsing](#string-parsing)
    - [String-to-Integer Conversion](#string-to-integer-conversion)
    - [UTF-8 and Byte Strings](#utf-8-and-byte-strings)
    - [String Ownership](#string-ownership)
  - [File I/O](#file-io)
    - [File Descriptors](#file-descriptors)
    - [open](#open)
    - [close](#close)
    - [read](#read)
    - [write](#write)
    - [pread](#pread)
    - [pwrite](#pwrite)
    - [lseek](#lseek)
    - [File Metadata](#file-metadata)
    - [stat](#stat)
    - [File Permissions](#file-permissions)
    - [Directories](#directories)
    - [Directory Iteration](#directory-iteration)
    - [Path Handling](#path-handling)
    - [Partial Reads](#partial-reads)
    - [Partial Writes](#partial-writes)
    - [EINTR](#eintr)
    - [EOF Handling](#eof-handling)
    - [Atomic File Updates](#atomic-file-updates)
  - [POSIX APIs](#posix-apis)
    - [POSIX vs ISO C](#posix-vs-iso-c)
    - [Feature Test Macros](#feature-test-macros)
    - [System Calls](#system-calls)
    - [File Descriptors](#file-descriptors-1)
    - [Signals](#signals)
    - [Environment Variables](#environment-variables)
    - [Process APIs](#process-apis)
    - [Thread APIs](#thread-apis)
    - [Socket APIs](#socket-apis)
    - [Portability Boundaries](#portability-boundaries)
  - [Processes](#processes)
    - [Process Model](#process-model)
    - [Process IDs](#process-ids)
    - [getpid](#getpid)
    - [getppid](#getppid)
    - [fork](#fork)
    - [Parent and Child Execution](#parent-and-child-execution)
    - [Copy-on-Write](#copy-on-write)
    - [exec](#exec)
    - [execve](#execve)
    - [Environment Passing](#environment-passing)
    - [wait](#wait)
    - [waitpid](#waitpid)
    - [Exit Status](#exit-status)
    - [Zombie Processes](#zombie-processes)
    - [Orphan Processes](#orphan-processes)
    - [Process Cleanup](#process-cleanup)
    - [Pipes](#pipes)
    - [Process Communication](#process-communication)
  - [Signals](#signals-1)
    - [Signal Model](#signal-model)
    - [signal](#signal)
    - [sigaction](#sigaction)
    - [Signal Masks](#signal-masks)
    - [Blocking Signals](#blocking-signals)
    - [Handling SIGINT](#handling-sigint)
    - [Handling SIGTERM](#handling-sigterm)
    - [SIGCHLD](#sigchld)
    - [Async-Signal-Safe Functions](#async-signal-safe-functions)
    - [Signal-Safe Cleanup](#signal-safe-cleanup)
  - [Threads](#threads)
    - [Process vs Thread](#process-vs-thread)
    - [pthread_create](#pthread_create)
    - [pthread_join](#pthread_join)
    - [pthread_detach](#pthread_detach)
    - [Thread Arguments](#thread-arguments)
    - [Thread Lifetime](#thread-lifetime)
    - [Shared Memory](#shared-memory)
    - [Thread-Local Storage](#thread-local-storage)
  - [Synchronization](#synchronization)
    - [Race Conditions](#race-conditions)
    - [Data Races](#data-races)
    - [Mutexes](#mutexes)
    - [pthread_mutex_init](#pthread_mutex_init)
    - [pthread_mutex_lock](#pthread_mutex_lock)
    - [pthread_mutex_unlock](#pthread_mutex_unlock)
    - [Condition Variables](#condition-variables)
    - [pthread_cond_wait](#pthread_cond_wait)
    - [pthread_cond_signal](#pthread_cond_signal)
    - [pthread_cond_broadcast](#pthread_cond_broadcast)
    - [Read-Write Locks](#read-write-locks)
    - [Deadlocks](#deadlocks)
    - [Lock Ordering](#lock-ordering)
    - [Thread-Safe Resource Ownership](#thread-safe-resource-ownership)
  - [Sockets and Networking](#sockets-and-networking)
    - [Network Programming Model](#network-programming-model)
    - [Socket Creation](#socket-creation)
    - [socket](#socket)
    - [bind](#bind)
    - [listen](#listen)
    - [accept](#accept)
    - [connect](#connect)
    - [send](#send)
    - [recv](#recv)
    - [shutdown](#shutdown)
    - [close](#close-1)
    - [IPv4](#ipv4)
    - [IPv6](#ipv6)
    - [sockaddr](#sockaddr)
    - [getaddrinfo](#getaddrinfo)
    - [Client Architecture](#client-architecture)
    - [Server Architecture](#server-architecture)
    - [TCP](#tcp)
    - [UDP](#udp)
    - [Partial Sends](#partial-sends)
    - [Partial Receives](#partial-receives)
    - [Connection Errors](#connection-errors)
    - [Socket Ownership](#socket-ownership)
  - [Blocking and Non-Blocking I/O](#blocking-and-non-blocking-io)
    - [Blocking File Descriptors](#blocking-file-descriptors)
    - [O_NONBLOCK](#ononblock)
    - [EAGAIN and EWOULDBLOCK](#eagain-and-ewouldblock)
    - [select](#select)
    - [poll](#poll)
    - [Event-Driven I/O](#event-driven-io)
    - [I/O Multiplexing](#io-multiplexing)
    - [Timeouts](#timeouts)
  - [Portable Build System](#portable-build-system)
    - [Compiler Flags](#compiler-flags)
    - [Strict Warnings](#strict-warnings)
    - [C Standard Selection](#c-standard-selection)
    - [POSIX Feature Macros](#posix-feature-macros)
    - [Debug vs Release Builds](#debug-vs-release-builds)
    - [Static Linking Considerations](#static-linking-considerations)
    - [Makefiles](#makefiles)
    - [Cross-Platform Builds](#cross-platform-builds)
  - [Debugging](#debugging)
    - [Assertions](#assertions)
    - [Debug Logging](#debug-logging)
    - [GDB](#gdb)
    - [Breakpoints](#breakpoints)
    - [Watchpoints](#watchpoints)
    - [Backtraces](#backtraces)
    - [Core Dumps](#core-dumps)
    - [strace](#strace)
    - [System Call Debugging](#system-call-debugging)
  - [Testing](#testing)
    - [Unit Tests](#unit-tests)
    - [Integration Tests](#integration-tests)
    - [Error-Path Testing](#error-path-testing)
    - [Memory-Safety Testing](#memory-safety-testing)
    - [AddressSanitizer](#addresssanitizer)
    - [UndefinedBehaviorSanitizer](#undefinedbehaviorsanitizer)
    - [ThreadSanitizer](#threadsanitizer)
    - [Valgrind](#valgrind)
    - [Stress Testing](#stress-testing)
    - [Concurrency Testing](#concurrency-testing)
    - [Network Testing](#network-testing)
  - [Undefined Behavior and Common Bugs](#undefined-behavior-and-common-bugs)
    - [Uninitialized Variables](#uninitialized-variables)
    - [Out-of-Bounds Access](#out-of-bounds-access)
    - [Use-After-Free](#use-after-free-1)
    - [Double Free](#double-free-1)
    - [Null Dereference](#null-dereference)
    - [Signed Integer Overflow](#signed-integer-overflow)
    - [Invalid Pointer Arithmetic](#invalid-pointer-arithmetic)
    - [Strict Aliasing](#strict-aliasing)
    - [Data Races](#data-races-1)
    - [Deadlocks](#deadlocks-1)
    - [Resource Leaks](#resource-leaks)
  - [Security](#security)
    - [Input Validation](#input-validation)
    - [Buffer Overflow Prevention](#buffer-overflow-prevention)
    - [Path Traversal](#path-traversal)
    - [File Permission Safety](#file-permission-safety)
    - [TOCTOU](#toctou)
    - [Resource Exhaustion](#resource-exhaustion)
    - [Safe Temporary Files](#safe-temporary-files)
    - [Defensive Parsing](#defensive-parsing)
  - [Design Patterns](#design-patterns)
    - [Opaque Resource Handles](#opaque-resource-handles)
    - [Init / Destroy Pattern](#init--destroy-pattern)
    - [Create / Close Pattern](#create--close-pattern)
    - [Result-Based APIs](#result-based-apis)
    - [Cleanup Stack](#cleanup-stack)
    - [State Machines](#state-machines)
    - [Producer / Consumer](#producer--consumer)
    - [Worker Pool](#worker-pool)
    - [Client / Server](#client--server)
  - [Performance](#performance)
    - [System Call Cost](#system-call-cost)
    - [Buffering](#buffering)
    - [Memory Allocation Cost](#memory-allocation-cost)
    - [Cache Locality](#cache-locality)
    - [Lock Contention](#lock-contention)
    - [Batching I/O](#batching-io)
    - [Zero-Copy Techniques](#zero-copy-techniques)
    - [Profiling](#profiling)
  - [Complete Examples](#complete-examples)
    - [Safe File Copier](#safe-file-copier)
    - [Command Runner](#command-runner)
    - [Parent-Child Process Example](#parent-child-process-example)
    - [Thread Pool](#thread-pool)
    - [Producer-Consumer Queue](#producer-consumer-queue)
    - [TCP Echo Client](#tcp-echo-client)
    - [TCP Echo Server](#tcp-echo-server)
    - [Concurrent TCP Server](#concurrent-tcp-server)
    - [Graceful Shutdown](#graceful-shutdown)
  - [Validation Checklist](#validation-checklist)
    - [Memory Ownership](#memory-ownership)
    - [Error Handling](#error-handling-1)
    - [File Descriptors](#file-descriptors-2)
    - [Processes](#processes-1)
    - [Threads](#threads-1)
    - [Synchronization](#synchronization-1)
    - [Sockets](#sockets-1)
    - [Portability](#portability-1)
    - [Testing](#testing-1)
  - [Resources](#resources)
    - [ISO C Documentation](#iso-c-documentation)
    - [POSIX Documentation](#posix-documentation)
    - [Memory Management](#memory-management-1)
    - [File I/O](#file-io-1)
    - [Processes](#processes-2)
    - [Threads](#threads-2)
    - [Sockets](#sockets-2)
    - [Debugging Tools](#debugging-tools)
    - [Security Resources](#security-resources)

# Portable C System Software

## Goals and Design Principles

### Portability

Write once, run on ISO C, POSIX, and Windows targets. Keep platform code
behind small adapter functions.

### Explicit Ownership

Every allocation and descriptor has exactly one owner. Naming reflects
ownership: `_Init`, `_Destroy`, `_Create`, `_Close`.

### Checked Errors

Check every return value. A system call return is data, not ceremony.

### Safe Memory Access

Validate indexes and lengths before access. Never trust caller-supplied
sizes.

### Resource Lifetime

Free or close every resource exactly once. Never free what you do not own.

### Fail-Fast Design

Detect invalid state early and return failure. Do not continue with
corrupted data.

## Project Structure

### Source Layout

Separate public headers, private implementation files, and test sources.
Match repository layout before inventing a new one.

### Header Files

Headers declare interface; source files define behavior. Include guard in
every header.

```c
#ifndef MODULE_H
#define MODULE_H
/* declarations */
#endif
```

### Translation Units

One `.c` file is one translation unit. Static functions and `static`
storage stay private to a unit.

### Public vs Private APIs

Export minimal public surface. Keep implementation details out of public
headers, or place them in a private `_internal.h`.

### Build Configuration

Keep build configuration explicit and repeatable. Define flags, targets,
and sanitizer modes in build files, not shell history.

## Portable C Fundamentals

### C Standard and Implementation Extensions

Target a named ISO C standard. Guard extensions behind `#if` so a conforming
compiler still builds.

### Integer Types

ISO C guarantees `char`, `short`, `int`, `long` minimum widths, not exact
widths. Use fixed-width types when the layout must be exact.

### Fixed-Width Integers

```c
#include <stdint.h>

uint32_t message_type = 1;
uint64_t message_length = 0;
```

### Signed vs Unsigned Integers

Signed and unsigned mix promotes to unsigned. Compare loop counters of the
same type as the lengths they bound.

### Integer Overflow

Signed overflow is undefined behavior. Check before arithmetic.

### Size Types

Use `size_t` for sizes and indexes. Print with `%zu`.

### Pointers

A null pointer is valid state; use it to mean "no object". Freeing a null
pointer is a no-op.

### Pointer Arithmetic

Pointer arithmetic must stay inside one array object. `p + n` past one
past the end is valid only as a comparison value.

### Arrays and Buffers

An array decays to a pointer. Preserve the bound separately; never infer a
buffer length from a pointer alone.

### Structures and Unions

Structures group differently typed data; unions overlay storage. `union`
interpretation is only as valid as the active member written last.

### Enums

Enums are implementation-defined integer types. Use them for named
constants, not for exact widths.

### Function Pointers

```c
typedef int (*CompareFn)(const void *left, const void *right);
```

Function pointers must match the exact signature stored and called.

### Const Correctness

Preserve `const` for read-only data. Casting away `const` to write is
undefined if the object was originally constant.

### Opaque Types

Declare the struct in the header, define it in the source. Callers hold a
pointer and cannot depend on layout.

```c
struct Resource;   /* opaque */
struct Resource *resource_open(const char *path);
void resource_close(struct Resource *resource);
```

## Memory Management

### Stack vs Heap

Stack storage is automatic and fast but dies at scope end. Heap storage
survives until `free`. Pick heap when lifetime outlives the function.

### malloc

```c
int *value = malloc(sizeof *value);
if (value == NULL) {
    return 0;
}
*value = 42;
```

Allocated memory is uninitialized. Initialize before use.

### calloc

```c
int *values = calloc(4, sizeof *values);
if (values == NULL) {
    return 1;
}
```

`calloc(n, size)` zero-fills and takes its two sizes as arguments. Check
the result.

### realloc

```c
int *next = realloc(value, 2 * sizeof *value);
if (next == NULL) {
    free(value);
    return 0;
}
value = next;
```

Assign the result to a temporary. On failure, the original pointer is
still valid.

### free

```c
free(value);
value = NULL;
```

Free each allocation exactly once. Nulling the pointer after free turns a
double free into a no-op.

### Allocation Failure

Every allocation can fail. Check and return an error; do not dereference.

### Allocation Size Overflow

Check `count * size` before allocation.

```c
if (count > SIZE_MAX / sizeof *array) {
    return 0;
}
```

### Initialization

Initialize every field before use. Prefer `calloc` for tables of structs
when zero is a valid initial state.

### Zero-Length Allocations

`malloc(0)` may return non-null yet point to zero usable bytes. Do not
rely on it; handle a zero length before allocation.

### Use-After-Free

Reading or writing freed memory is undefined behavior. Clear the pointer
after `free`.

### Double Free

Freeing the same pointer twice corrupts the heap. One owner frees once.

### Memory Leaks

Every path that allocates must release. Sanitizers and Valgrind detect
leaks; a leak check in CI catches regressions.

### Dangling Pointers

A pointer to freed or out-of-scope storage. Reusing it is use-after-free
or stack-use-after-scope. Null after free.

### Invalid Pointers

A pointer that never named a real object. Validate before dereference.

### Buffer Overflows

Writing past a buffer corrupts adjacent memory. Bound every write by
capacity, not by assumption.

### Aliasing

Two pointers may name the same object. `restrict` promises they do not;
violating that promise is undefined.

### Lifetime and Scope

An object is alive from construction to destruction. Passing a pointer to
a dead object outlives its lifetime.

## Ownership and Resource Management

### Ownership Model

One resource, one owner. Ownership transfers only at documented boundaries.

### Borrowed References

A function that does not allocate nor free a resource borrows it. Borrowed
pointers must stay alive for the call.

### Owned References

Ownership means the current holder frees on all later paths.

### Transfer of Ownership

State in comments or naming when cleanup moves:

```c
/* Caller owns the returned struct. */
struct Item *item_create(void);
```

### Resource Cleanup

Cleanup belongs to the owner. Free allocations in reverse order of
acquisition.

### Single Owner Rule

If two code paths both free the same resource, pick one and drop the other.

### Cleanup Paths

Use one cleanup label so failure paths release everything:

```c
int *a = NULL;
int *b = NULL;

a = malloc(sizeof *a);
if (a == NULL) {
    goto cleanup;
}
b = malloc(sizeof *b);
if (b == NULL) {
    goto cleanup;
}

/* success path */
free(b);
free(a);
return 0;

cleanup:
free(b);
free(a);
return 1;
```

### Partial Initialization

If step 3 of 5 fails, release steps 1 and 2 before returning.

### Error Cleanup

```c
char **items = calloc(3, sizeof *items);
if (items == NULL) {
    return 0;
}

for (size_t index = 0; index < 3; ++index) {
    items[index] = strdup("item");
    if (items[index] == NULL) {
        while (index != 0) {
            free(items[--index]);
        }
        free(items);
        return 0;
    }
}

for (size_t index = 0; index < 3; ++index) {
    free(items[index]);
}
free(items);
```

### RAII-Style Patterns in C

C has no destructors. Emulate with `goto cleanup`, wrapper functions, or
owner structs that own and free their children in `destroy`.

## Error Handling

### Return Codes

Return an explicit status. Define a consistent convention: `0` for success,
non-zero for failure, or a bool/int status enum.

### errno

`errno` reports libc errors after a failing system call. Do not read
`errno` after pthread calls; those report through the return value.

### perror

`perror("open")` prints the message plus the system error text. Use at a
decision point, not for logging internals.

### strerror

```c
fprintf(stderr, "open failed: %s\n", strerror(errno));
```

`strerror` returns a writable-or-static string; copy it if you keep it.

### Error Propagation

Translate low-level failures into the caller's error vocabulary. Wrap a
short, fixed message with context, not a stack trace.

### Error Translation

Map `errno` to a project enum at module boundaries so callers never match
against raw `errno` values.

### Recoverable vs Fatal Errors

Recoverable: retry, skip, or degrade. Fatal: abort or return immediately.
Classify per resource before writing the handler.

### Partial Failure

A loop that fails at item 42 must decide the contract: keep the prefix,
roll back all, or report the partial range.

### Cleanup After Failure

Run identical cleanup on success and failure. The only difference is the
return value.

### Error Context

Report which operation failed and on what object. `open failed: path
permission denied` beats bare `-1`.

## Safe Memory and Buffer Operations

### memcpy

```c
memcpy(destination, source, byte_count);
```

Requires non-overlapping ranges. Undefined if they overlap.

### memmove

```c
memmove(destination, source, byte_count);
```

Safe for overlapping ranges. Prefer when overlap is possible.

### memset

```c
memset(buffer, 0, sizeof buffer);
```

Fills byte by byte. Do not use on non-object byte representations
that require more than zeroing.

### memcmp

`memcmp(a, b, n)` compares bytes lexicographically. Do not use it to
compare floating-point or struct equality with padding.

### String Buffers

String operations need capacity. Write helpers that take `(buffer,
capacity)` and enforce the terminator.

### Buffer Length Validation

Validate before copying:

```c
if (source_length >= destination_capacity) {
    return 0;
}
memcpy(destination, source, source_length + 1);
```

### Null-Termination

Always reserve one byte for `'\0'`. Use `snprintf` truncation checks and
bounded copy helpers.

### Overlapping Buffers

Detect or document overlap before `memcpy`; use `memmove` when uncertain.

### Integer-to-Size Conversion

Convert integer lengths to `size_t` only after range validation. A
negative user length must fail before the cast.

## Strings

### C String Representation

A C string is a `char *` to bytes terminated by `'\0'`. The length is not
stored; compute or pass it explicitly.

### String Length

`strlen` is O(n). Cache lengths when they survive across loops.

### String Copying

Use bounded copy, never raw `strcpy`, on untrusted input.

```c
strncpy(destination, source, capacity - 1);
destination[capacity - 1] = '\0';
```

### String Concatenation

Use `snprintf` and check truncation:

```c
int written = snprintf(buffer, buffer_size, "%s/%s", dir, file);
if (written < 0 || (size_t)written >= buffer_size) {
    return 1;
}
```

### String Comparison

`strcmp` compares byte values. `strncmp` takes a limit for prefixes.

### String Parsing

Use `strtok_r` (reentrant), `sscanf` with bounds, or manual scanners.
Avoid non-reentrant `strtok`.

### String-to-Integer Conversion

Use `strtol` with `endptr`:

```c
char *end = NULL;
errno = 0;
long value = strtol(text, &end, 10);
if (errno != 0 || end == text || *end != '\0') {
    return 0;
}
```

### UTF-8 and Byte Strings

Treat UTF-8 as bytes for storage and transport. Validate sequences with a
decoder before indexing by code point.

### String Ownership

`strdup` returns owned memory:

```c
char *copy = strdup("hello");
if (copy == NULL) {
    return 0;
}
free(copy);
```

Know which buffers are owned and which are borrowed.

## File I/O

### File Descriptors

A descriptor is an index into the process table. Open, use, close on every
path.

### open

```c
#include <fcntl.h>
#include <unistd.h>

int fd = open("input.txt", O_RDONLY | O_CLOEXEC);
if (fd < 0) {
    return 1;
}
```

### close

```c
(void)close(fd);
```

Closing an unknown or double-closed descriptor is a bug. Track open state.

### read

```c
char buffer[128];
ssize_t count = read(fd, buffer, sizeof buffer);
if (count < 0) {
    return 1;
}
```

`read` returns bytes read, 0 at EOF, or -1 on error.

### write

```c
ssize_t count = write(fd, buffer, sizeof buffer);
```

`write` may write fewer bytes than requested. Continue until complete.

### pread

`pread(fd, buf, n, off)` reads without moving the file offset. Safe for
concurrent readers of one descriptor.

### pwrite

`pwrite(fd, buf, n, off)` writes at an explicit offset without touching
the file offset.

### lseek

`lseek(fd, offset, whence)` repositions the offset. Return -1 on error;
check before assuming a position.

### File Metadata

Metadata lives on the file, not the descriptor. Query with `fstat` for an
open descriptor.

### stat

```c
struct stat info;
if (stat(path, &info) < 0) {
    return 1;
}
```

### File Permissions

Open with least privilege. Do not create world-writable files without a
reason.

### Directories

Use `mkdir`, `opendir`, and descriptor-safe directory operations behind
an adapter per platform.

### Directory Iteration

```c
DIR *dir = opendir(path);
if (dir == NULL) {
    return 1;
}
struct dirent *entry;
while ((entry = readdir(dir)) != NULL) {
    process(entry->d_name);
}
closedir(dir);
```

### Path Handling

Build paths with size-checked concatenation. Never splice raw user input
into a path.

### Partial Reads

A read loop must continue until the needed bytes or EOF arrive.

### Partial Writes

```c
static int write_all(int fd, const void *data, size_t length)
{
    const char *bytes = data;

    while (length != 0) {
        ssize_t count = write(fd, bytes, length);

        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            return 0;
        }

        bytes += count;
        length -= (size_t)count;
    }

    return 1;
}
```

### EINTR

```c
do {
    count = read(fd, buffer, sizeof buffer);
} while (count < 0 && errno == EINTR);
```

### EOF Handling

Read until `read` returns 0. Treat a zero-length receive as peer close.

### Atomic File Updates

Write a temp file in the target directory, `fsync`, then `rename`. The
rename replaces the old file atomically.

## POSIX APIs

### POSIX vs ISO C

ISO C provides language and a small library. POSIX adds files, processes,
signals, threads, sockets, and time beyond the C standard.

### Feature Test Macros

Define feature macros before system headers:

```c
#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
```

### System Calls

System calls cross user-kernel boundary and cost more than a function call.
Batch and buffer their use.

### File Descriptors

Use `O_CLOEXEC` where supported. Reap children with `waitpid`. Check every
descriptor result.

### Signals

Install handlers with `sigaction`. Keep handlers to async-signal-safe
calls only.

### Environment Variables

Treat environment values as untrusted input. Read with `getenv`, validate
ranges, never trust format.

### Process APIs

`fork`, `exec`, `waitpid` compose process control. Check each return.

### Thread APIs

POSIX threads report errors through the return value, not `errno`.

### Socket APIs

Sockets are descriptors with connect, bind, listen, accept semantics.
Handle partial send and receive.

### Portability Boundaries

Isolate POSIX calls behind adapters so the core logic compiles where the
API differs.

## Processes

### Process Model

A process is an isolated address space plus one or more threads. Processes
share only what the kernel explicitly shares.

### Process IDs

`pid_t` names a process. Store it, do not guess it.

### getpid

```c
#include <unistd.h>
pid_t me = getpid();
```

### getppid

`getppid` returns the parent pid. It changes to 1 (or the reaper) if the
original parent died.

### fork

```c
#include <sys/wait.h>
#include <unistd.h>

pid_t child = fork();

if (child == 0) {
    execlp("echo", "echo", "hello", (char *)NULL);
    _exit(127);
}
if (child < 0) {
    return 1;
}

return waitpid(child, NULL, 0) < 0 ? 1 : 0;
```

`fork` returns 0 in the child and the child pid in the parent.

### Parent and Child Execution

Both branches run after `fork`. Branch on the return value before any
shared-state operation.

### Copy-on-Write

The child shares pages with the parent until either writes. Memory is
copied lazily.

### exec

`exec*` replaces the current image. On success it never returns; on failure
it returns -1. Check and `_exit` in the child.

### execve

`execve` is the base form. The `exec*` family wraps path search and
argument building.

### Environment Passing

`execle` and `execve` take an explicit environment array. Pass a
controlled environment, never the inherited one, for privilege-sensitive
work.

### wait

`wait(&status)` reaps any child. Use it only when a specific child is not
required.

### waitpid

```c
int status = 0;
if (waitpid(child, &status, 0) < 0) {
    return 1;
}
```

### Exit Status

```c
if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    return 1;
}
```

### Zombie Processes

An unreaped child stays a zombie in the table. `waitpid` reaps it; a
`SIGCHLD` handler with `waitpid` reaps without blocking.

### Orphan Processes

An orphan is adopted by the nearest reaper. Design around reparenting, do
not rely on the original parent.

### Process Cleanup

Close inherited descriptors in the child. `_exit` skips `atexit` handlers;
`exit` runs them. Pick deliberately after `fork`.

### Pipes

```c
int pipe_fds[2];
if (pipe(pipe_fds) < 0) {
    return 1;
}

pid_t child = fork();
if (child == 0) {
    close(pipe_fds[0]);
    write(pipe_fds[1], "ok", 2);
    close(pipe_fds[1]);
    _exit(0);
}

close(pipe_fds[1]);
read(pipe_fds[0], buffer, sizeof buffer);
close(pipe_fds[0]);
waitpid(child, NULL, 0);
```

### Process Communication

Pipes, FIFOs, sockets, shared memory, and signals compose IPC. Choose by
lifetime, bandwidth, and trust boundary.

## Signals

### Signal Model

A signal is an asynchronous kernel notification. Delivery can interrupt a
running instruction.

### signal

Prefer `sigaction` over `signal`. Legacy `signal` semantics vary per
platform.

### sigaction

```c
#include <signal.h>
#include <stddef.h>

static void handle_signal(int signal_number)
{
    (void)signal_number;
    stop_requested = 1;
}

struct sigaction action = { .sa_handler = handle_signal };
sigemptyset(&action.sa_mask);
action.sa_flags = 0;
if (sigaction(SIGTERM, &action, NULL) < 0) {
    return 1;
}
```

### Signal Masks

`sigemptyset`, `sigaddset`, `sigprocmask` control which signals a thread
accepts.

### Blocking Signals

Block signals around sections that must not be interrupted. Restore the
previous mask after.

### Handling SIGINT

```c
static volatile sig_atomic_t stop_requested;

static void handle_signal(int signal_number)
{
    (void)signal_number;
    stop_requested = 1;
}

int main(void)
{
    struct sigaction action = { .sa_handler = handle_signal };
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);

    while (!stop_requested) {
        /* Do short units of work. */
    }
    return 0;
}
```

### Handling SIGTERM

Install a handler for `SIGTERM` to flush and shut down cleanly. Set a flag
and let normal flow finish the work.

### SIGCHLD

Reap children on `SIGCHLD` with `waitpid(..., WNOHANG)` in a loop until no
child remains.

### Async-Signal-Safe Functions

Only async-signal-safe calls belong in a handler: `write`, `_exit`,
`sig_atomic_t` stores. No `malloc`, `free`, `printf`, or locking.

### Signal-Safe Cleanup

Tell the main flow to clean up via a flag or by writing one byte to a
self-pipe. Never allocate or free inside the handler.

```c
int signal_pipe[2];
if (pipe(signal_pipe) < 0) {
    return 1;
}
/* Handler writes one byte. Event loop reads signal_pipe[0]. */
```

## Threads

### Process vs Thread

Threads share the address space of one process. A fault in one thread can
take the process down.

### pthread_create

```c
#include <pthread.h>

if (pthread_create(&thread, NULL, worker, &value) != 0) {
    return 1;
}
```

### pthread_join

```c
if (pthread_join(thread, NULL) != 0) {
    return 1;
}
```

Join reaps thread resources and receives the return value.

### pthread_detach

```c
pthread_detach(thread);
```

A detached thread releases its resources on exit. Never join a detached
thread.

### Thread Arguments

Pass one owned argument pointer. The thread owns the argument for its
lifetime and frees it before returning.

### Thread Lifetime

Join or detach every thread exactly once. Leaked joinable threads are a
resource leak.

### Shared Memory

Threads share process memory. Shared state needs synchronization (see
Synchronization).

### Thread-Local Storage

Use `_Thread_local` (C11) or `__thread` for per-thread state that does
not need a lock.

## Synchronization

### Race Conditions

A race is incorrect behavior caused by interleaving. Define the ordering
you need before writing synchronization.

### Data Races

Two threads touching the same object where at least one writes and neither
is synchronized is undefined behavior.

### Mutexes

A mutex makes a critical section exclusive. Keep sections short.

### pthread_mutex_init

```c
pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
```

Or init at runtime and check the result.

### pthread_mutex_lock

```c
if (pthread_mutex_lock(&mutex) != 0) {
    return 1;
}
```

### pthread_mutex_unlock

```c
pthread_mutex_unlock(&mutex);
```

Unlock on every path out of the critical section, including errors.

### Condition Variables

```c
pthread_mutex_lock(&mutex);
while (!ready) {
    pthread_cond_wait(&condition, &mutex);
}
pthread_mutex_unlock(&mutex);
```

Wait in a while loop. Spurious wakeups are allowed.

### pthread_cond_wait

`pthread_cond_wait` atomically unlocks, waits, and relocks. The predicate
must be re-checked after return.

### pthread_cond_signal

```c
pthread_cond_signal(&condition);
```

Wakes one waiter. Use when one unit of work is available.

### pthread_cond_broadcast

```c
pthread_cond_broadcast(&condition);
```

Wakes all waiters. Use when the state change affects everyone.

### Read-Write Locks

`pthread_rwlock` lets readers run together and writers exclusively. Use
only when reads dominate and profiling justifies the complexity.

### Deadlocks

A deadlock starves every holder. Two locks in opposite order deadlock;
pick one global order.

### Lock Ordering

Acquire locks in a fixed order across the program. Document the order at
the first use site.

### Thread-Safe Resource Ownership

If a resource is reachable from two threads, the mutex that guards it is
part of the resource contract. Document which lock guards which field.

## Sockets and Networking

### Network Programming Model

Sockets are endpoints of a connection between two network applications.
The model: create, address, connect or listen, exchange, close.

### Socket Creation

```c
#include <sys/socket.h>
#include <unistd.h>

int sockets[2];

if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) < 0) {
    return 1;
}
```

### socket

`socket(domain, type, protocol)` creates one endpoint. Check the
descriptor result.

### bind

`bind` assigns a local address. Check the result; the port is in use or
privileged on failure.

### listen

`listen(fd, backlog)` marks a socket as passive. Start before `accept`.

### accept

```c
int client = accept(listen_fd, NULL, NULL);
if (client < 0) {
    return 1;
}
```

`accept` returns a new descriptor for one connection. Manage each.

### connect

`connect` establishes the connection. Handle `EINPROGRESS` on
non-blocking sockets.

### send

```c
ssize_t sent = send(fd, data + offset, length - offset, 0);
if (sent <= 0) {
    return 0;
}
offset += (size_t)sent;
```

### recv

```c
ssize_t count = recv(fd, buffer, sizeof buffer, 0);
if (count == 0) {
    /* peer closed */
}
```

### shutdown

`shutdown(fd, how)` stops one or both directions without closing the
descriptor.

### close

Closing the socket releases the endpoint. Close the accept-returned
descriptor too; `close` of a listening socket does not close accepted
connections.

### IPv4

`AF_INET` plus a `struct sockaddr_in` with a 32-bit address. Prefer
`getaddrinfo` over hand-packed addresses.

### IPv6

`AF_INET6` plus a `struct sockaddr_in6`. Use `getaddrinfo` with `AI_V4MAPPED`
when both families must work.

### sockaddr

Addresses use a generic `struct sockaddr` with a family tag. Always size
the call with the concrete address type.

### getaddrinfo

```c
struct addrinfo hints = { .ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM };
struct addrinfo *result = NULL;

if (getaddrinfo(host, port, &hints, &result) != 0) {
    return 1;
}
freeaddrinfo(result);
```

Never hard-code addresses when a hostname may be supplied.

### Client Architecture

Resolve, create, connect, exchange, close. Retry connect only with an
explicit policy and bounded count.

### Server Architecture

Create, bind, listen, accept loop, handle, close each client descriptor.
Choose per-connection threads or an event loop.

### TCP

Stream semantics, no message boundaries. You must frame messages yourself;
a read can return any prefix of the stream.

### UDP

Datagram semantics, no delivery guarantees, message boundaries kept.
Check truncation on receive.

### Partial Sends

```c
size_t offset = 0;
while (offset < length) {
    ssize_t sent = send(fd, data + offset, length - offset, 0);
    if (sent <= 0) {
        return 0;
    }
    offset += (size_t)sent;
}
```

### Partial Receives

A receive returns at most the requested bytes and any prefix thereof.
Frame data and keep partial state across calls.

### Connection Errors

A send or receive can fail because the peer closed or reset. Treat
`ECONNRESET`, `EPIPE`, and zero-length receive as the connection end.

### Socket Ownership

The accepting side owns each client descriptor until it closes it. Do not
share one socket across threads without a defined protocol.

## Blocking and Non-Blocking I/O

### Blocking File Descriptors

Blocking calls wait for readiness. A blocked thread pauses until data
arrives or an error occurs.

### O_NONBLOCK

```c
#include <fcntl.h>

int flags = fcntl(fd, F_GETFL, 0);
fcntl(fd, F_SETFL, flags | O_NONBLOCK);
```

### EAGAIN and EWOULDBLOCK

```c
if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
    /* Wait for readiness, then retry. */
}
```

These report that the operation would block.

### select

`select` waits for readiness on a descriptor set with a timeout. Bounded by
`FD_SETSIZE`; prefer `poll` for larger sets.

### poll

`poll` waits on an array of `pollfd` up to any count. More scalable than
`select`.

### Event-Driven I/O

An event loop dispatches readiness events and keeps state per descriptor:
`epoll` on Linux, `kqueue` on BSD/macOS, `poll` as portable baseline.

### I/O Multiplexing

Multiplexing servers track many connections in one thread. Each connection
needs its own buffer and parse state.

### Timeouts

```c
struct timeval timeout = { .tv_sec = 5, .tv_usec = 0 };
if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO,
               &timeout, sizeof timeout) < 0) {
    return 0;
}
```

Timeout prevents one blocked descriptor from stalling the process.

## Portable Build System

### Compiler Flags

```sh
cc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g main.c -o main
```

### Strict Warnings

Treat warnings as input for fixes, not decoration. Add `-Werror` only when
the whole project is warning-clean.

### C Standard Selection

Pick one standard (`c11` or `c17`) and keep it stable. Extensions stay
guarded.

### POSIX Feature Macros

Pass `-D_POSIX_C_SOURCE=200809L` or define it first in a shared header so
portable code sees the same API surface.

### Debug vs Release Builds

Keep separate flags. Debug: `-g`, no optimization, sanitizers. Release:
optimization, assertions off unless required, no sanitizer overhead.

### Static Linking Considerations

Static builds need the same libraries on every target. Link order matters;
libraries must follow the objects that use them.

### Makefiles

```make
app: main.c
    $(CC) $(CFLAGS) $< -o $@

test: app
    ./app 42
```

### Cross-Platform Builds

Separate the build into a neutral core plus a per-platform component. Do
not fork the whole build per target.

## Debugging

### Assertions

```c
#include <assert.h>

assert(add(2, 3) == 5);
```

Assertions encode preconditions. They compile out under `NDEBUG`; do not
put side effects inside them.

### Debug Logging

Log with level and file:line so field errors carry location. Route logs
through one function to enable or disable silently.

### GDB

```sh
gdb --args ./main 42
(gdb) break main
(gdb) run
(gdb) backtrace
```

### Breakpoints

`break file.c:line` or `break function`. Break on a failure return to
inspect state exactly at the fault.

### Watchpoints

`watch expression` stops when a value changes. Useful for unsynchronized
writes.

### Backtraces

`backtrace` shows the call chain. Build with `-g` and no `-fomit-frame-pointer`
for readable frames.

### Core Dumps

Enable core files, reproduce, and inspect: `gdb ./main core`. Limit core
size in production.

### strace

`strace -f -e trace=network ./main` shows system calls and their results.
Use to confirm which calls fail and with which `errno`.

### System Call Debugging

Match a failing system call to its `errno`, then check the man page
documented causes. Fix the call, not the symptom.

## Testing

### Unit Tests

Test one function in isolation. Feed it boundary values and invalid inputs,
not only happy paths.

### Integration Tests

Test real interactions: file, process, socket, thread. Keep each test
independent and repeatable.

### Error-Path Testing

Inject allocation and system-call failure. A test that only passes on
success proves nothing about error handling.

### Memory-Safety Testing

Run every test under a memory checker once per change.

### AddressSanitizer

```sh
cc -std=c17 -Wall -Wextra -fsanitize=address,undefined -g test.c -o test
ASAN_OPTIONS=detect_leaks=1 ./test
```

### UndefinedBehaviorSanitizer

Compile with `-fsanitize=undefined` and the runtime fires on UB: overflow,
alignment, aliasing.

### ThreadSanitizer

`-fsanitize=thread` detects data races and lock-order misuse. Run
concurrency tests under TSan with `-O1` for stable backtraces.

### Valgrind

`valgrind --leak-check=full ./test` reports leaks and invalid accesses
where ASan does not run.

### Stress Testing

Run long, randomized workloads to surface rare interleavings and
resource-exhaustion paths.

### Concurrency Testing

Vary thread counts, repeat many times, and run under TSan. A race that
does not reproduce in one run still exists.

### Network Testing

Test against a local `socketpair` or loopback peer. Use timeouts so a
blocked test fails instead of hanging the suite.

## Undefined Behavior and Common Bugs

### Uninitialized Variables

Reading an uninitialized automatic variable is undefined. Initialize at
declaration when possible.

### Out-of-Bounds Access

Reading or writing past an array is undefined. Bound every index by the
known capacity.

### Use-After-Free

Freed memory must not be read, written, or freed again. Null the pointer
after `free`.

### Double Free

Two `free` calls on one pointer corrupt the heap. One owner, one free.

### Null Dereference

Dereferencing a null pointer crashes or is undefined. Check every pointer
that can be null.

### Signed Integer Overflow

Signed overflow is undefined, not wraparound. Check `INT_MAX`/`INT_MIN`
before adding, multiplying, or negating.

### Invalid Pointer Arithmetic

Pointer arithmetic outside one array, or on a freed object, is undefined.
Keep indexes inside `[0, n]`.

### Strict Aliasing

Accessing an object through an incompatible pointer type violates strict
aliasing. Use `memcpy` or a union for type re-interpretation.

### Data Races

Unsynchronized shared access is undefined. Lock or atomically store.

### Deadlocks

Threads waiting on locks in conflicting order stop forever. Use one lock
order.

### Resource Leaks

Unclosed descriptors and unfreed allocations exhaust the process. Every
acquire has a matching release path.

## Security

### Input Validation

Treat input, paths, environment values, and network data as untrusted.
Validate range and format before use.

### Buffer Overflow Prevention

Bound every write by capacity.

```c
int written = snprintf(buffer, buffer_size, "id=%d", identifier);
if (written < 0 || (size_t)written >= buffer_size) {
    return 1;
}
```

### Path Traversal

Reject paths with `..` segments or absolute paths when the input should
name a file inside one directory.

### File Permission Safety

Create files with restrictive modes. Never open a world-writable path
with elevate privileges.

### TOCTOU

Check-then-use races on paths. Use descriptor-based opens (`openat`,
`fstat`) instead of checking a path then opening it.

### Resource Exhaustion

Bound request counts, buffer sizes, and concurrent connections. Reject
oversized inputs before allocating.

### Safe Temporary Files

Use `mkstemp` (POSIX) or a per-process random directory. Never guess a
temp name and open it; attackers race the guess.

### Defensive Parsing

Assume every parser input is malformed. Check every length, return, and
terminator before copying or dereferencing.

## Design Patterns

### Opaque Resource Handles

```c
struct Resource;   /* opaque */
struct Resource *resource_open(const char *path);
void resource_close(struct Resource *resource);
```

Callers use handles; the source owns internals.

### Init / Destroy Pattern

`init` prepares a struct in place; `destroy` releases it. Pair each
`init` with exactly one `destroy`.

### Create / Close Pattern

`create` returns an owned handle; `close` releases it. The creator is the
owner until transfer.

### Result-Based APIs

Return a status enum plus `out` parameters. The caller checks status
before reading outputs.

### Cleanup Stack

Acquire resources, then `goto cleanup` frees them in reverse order on any
error path.

### State Machines

Encode connection or protocol behavior with explicit states. Illegal
transitions fail fast instead of misparsing.

### Producer / Consumer

Producers enqueue work; consumers dequeue. Use a mutex plus condition
variable, flushed at shutdown.

### Worker Pool

A fixed set of threads consumes a shared work queue. Bound the queue to
cap backpressure.

### Client / Server

One side listens and accepts; the other resolves and connects. Keep the
message protocol identical on both sides.

## Performance

### System Call Cost

System calls dominate micro-operations. Read and write in chunks, not
bytes.

### Buffering

Wrap descriptors in a userspace buffer to coalesce many small calls into
few large ones.

### Memory Allocation Cost

`realloc` in doubling sizes, never one element at a time. Reserve before
bulk insertion.

### Cache Locality

Contiguous structures and arrays beat scattered links. Reorder fields by
access frequency.

### Lock Contention

Short critical sections and coarse-grained less-used locks reduce
contention. Profile before adding fine-grained locks.

### Batching I/O

Describe many operations in one call: `readv`, `writev`, `sendmsg`,
`recvmmsg`.

### Zero-Copy Techniques

`sendfile`, `splice`, and `mmap` move data without userspace copies.
Use only after profiling shows copy cost matters.

### Profiling

Measure first: `perf`, gprof, or a minimal cycle counter. Optimize the
measured hotspot, not the guessed one.

## Complete Examples

### Safe File Copier

```c
#include <fcntl.h>
#include <unistd.h>

static int write_all(int fd, const void *data, size_t length)
{
    const char *bytes = data;
    while (length != 0) {
        ssize_t count = write(fd, bytes, length);
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            return 0;
        }
        bytes += count;
        length -= (size_t)count;
    }
    return 1;
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        return 1;
    }

    int in = open(argv[1], O_RDONLY | O_CLOEXEC);
    if (in < 0) {
        return 1;
    }
    int out = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (out < 0) {
        close(in);
        return 1;
    }

    char buffer[4096];
    ssize_t count;
    int ok = 1;

    while ((count = read(in, buffer, sizeof buffer)) > 0) {
        if (!write_all(out, buffer, (size_t)count)) {
            ok = 0;
            break;
        }
    }
    if (count < 0) {
        ok = 0;
    }

    close(in);
    close(out);
    return ok ? 0 : 1;
}
```

### Command Runner

```c
#include <sys/wait.h>
#include <unistd.h>

int run(const char *path, char *const argv[])
{
    pid_t child = fork();
    if (child == 0) {
        execv(path, argv);
        _exit(127);
    }
    if (child < 0) {
        return -1;
    }

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        return -1;
    }
    if (!WIFEXITED(status)) {
        return -2;
    }
    return WEXITSTATUS(status);
}
```

### Parent-Child Process Example

```c
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void)
{
    int pipe_fds[2];
    char buffer[8] = { 0 };

    if (pipe(pipe_fds) < 0) {
        return 1;
    }

    pid_t child = fork();
    if (child == 0) {
        close(pipe_fds[0]);
        write(pipe_fds[1], "ok", 2);
        close(pipe_fds[1]);
        _exit(0);
    }
    if (child < 0) {
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        return 1;
    }

    close(pipe_fds[1]);
    read(pipe_fds[0], buffer, sizeof buffer - 1);
    close(pipe_fds[0]);

    int status = 0;
    if (waitpid(child, &status, 0) < 0) return 1;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return 1;

    printf("%s\n", buffer);
    return 0;
}
```

### Thread Pool

```c
#include <pthread.h>
#include <stddef.h>

struct work_item {
    void (*run)(void *);
    void *argument;
};

struct pool_block {
    struct work_item *items;
    size_t capacity;
    size_t head;
    size_t tail;
    size_t waiting;
    int shutdown;
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
};
```

The pool owns the queue and the worker threads. Workers wait on
`not_empty`; `destroy` sets `shutdown`, broadcasts, and joins all.

### Producer-Consumer Queue

```c
pthread_mutex_lock(&mutex);
if (full) {
    pthread_cond_wait(&not_full, &mutex);
}
push(item);
pthread_cond_signal(&not_empty);
pthread_mutex_unlock(&mutex);
```

The consumer mirrors the pattern with `not_empty` and `not_full` swapped.

### TCP Echo Client

```c
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return 1;
    }

    struct sockaddr_in address = {
        .sin_family = AF_INET,
        .sin_port = htons(7000)
    };
    if (inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) != 1) {
        close(fd);
        return 1;
    }
    if (connect(fd, (struct sockaddr *)&address, sizeof address) < 0) {
        close(fd);
        return 1;
    }

    char buffer[128];
    send(fd, "ping", 4, 0);
    ssize_t count = recv(fd, buffer, sizeof buffer, 0);
    (void)count;
    close(fd);
    return 0;
}
```

### TCP Echo Server

```c
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return 1;
    }

    struct sockaddr_in address = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
        .sin_port = htons(7000)
    };
    if (bind(fd, (struct sockaddr *)&address, sizeof address) < 0) {
        close(fd);
        return 1;
    }
    if (listen(fd, 8) < 0) {
        close(fd);
        return 1;
    }

    for (;;) {
        int client = accept(fd, NULL, NULL);
        if (client < 0) {
            break;
        }
        char buffer[128];
        ssize_t count;
        while ((count = recv(client, buffer, sizeof buffer, 0)) > 0) {
            send(client, buffer, (size_t)count, 0);
        }
        close(client);
    }

    close(fd);
    return 0;
}
```

### Concurrent TCP Server

Accept on `SOCK_STREAM` with `SO_REUSEADDR`, then hand each client to a
thread:

```c
static void *handle_client(void *argument)
{
    int client = (int)(intptr_t)argument;
    char buffer[128];
    ssize_t count;
    while ((count = recv(client, buffer, sizeof buffer, 0)) > 0) {
        send(client, buffer, (size_t)count, 0);
    }
    close(client);
    return NULL;
}
```

Set `SO_REUSEADDR` before `bind` so restarts do not hit `EADDRINUSE`.

### Graceful Shutdown

Install a `SIGTERM`/`SIGINT` handler that sets a `sig_atomic_t` flag or
writes to a self-pipe. The accept loop stops when the flag is set, then
closes the listener and joins workers before `exit(0)`.

## Validation Checklist

### Memory Ownership

- [ ] Every `malloc`, `calloc`, `strdup`, `realloc` path has one matching free.
- [ ] `realloc` result stored in a temporary pointer.
- [ ] Arithmetic checked before allocation and pointer arithmetic.

### Error Handling

- [ ] Every system call result and pthread error code checked.
- [ ] `errno` not read after pthread calls.
- [ ] `EINTR` retry applied where permitted.
- [ ] `snprintf` truncation checked.

### File Descriptors

- [ ] Every descriptor and socket closes on success and error paths.
- [ ] `O_CLOEXEC` used where supported.

### Processes

- [ ] Every `fork` child has a matching `waitpid`.
- [ ] No zombie children left behind.
- [ ] Child uses `_exit`, not `exit`, after a failed `exec`.

### Threads

- [ ] Every thread joins or detaches exactly once.

### Synchronization

- [ ] Shared state protected by a mutex on every path.
- [ ] Condition wait in a while loop until the predicate holds.
- [ ] Lock ordering documented.

### Sockets

- [ ] Partial `send`/`recv` results handled.
- [ ] Zero-length receive treated as peer close.
- [ ] Accepted sockets closed on every path.

### Portability

- [ ] Feature macros defined before POSIX headers.
- [ ] Platform code isolated behind adapters.

### Testing

- [ ] Tested under ASan/UBSan with `detect_leaks=1`.
- [ ] Error paths and malformed input tested.
- [ ] Concurrency code run under TSan.

```sh
cc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
  -fsanitize=address,undefined -g main.c -o main
ASAN_OPTIONS=detect_leaks=1 ./main
```

## Resources

### ISO C Documentation

- [C reference](https://en.cppreference.com/w/c)

### POSIX Documentation

- [POSIX specification](https://pubs.opengroup.org/onlinepubs/9799919799/)
- [Linux man-pages](https://man7.org/linux/man-pages/)

### Memory Management

- [C `malloc` and `free`](https://en.cppreference.com/w/c/memory)
- [SEI CERT C memory rules](https://wiki.sei.cmu.edu/confluence/display/c/MEM)

### File I/O

- [Linux `open`(2)](https://man7.org/linux/man-pages/man2/open.2.html)
- [Linux `read`(2)](https://man7.org/linux/man-pages/man2/read.2.html)
- [Linux `write`(2)](https://man7.org/linux/man-pages/man2/write.2.html)

### Processes

- [Linux `fork`(2)](https://man7.org/linux/man-pages/man2/fork.2.html)
- [Linux `exec`(3)](https://man7.org/linux/man-pages/man3/exec.3.html)
- [Linux `wait`(2)](https://man7.org/linux/man-pages/man2/wait.2.html)

### Threads

- [Linux `pthread_create`(3)](https://man7.org/linux/man-pages/man3/pthread_create.3.html)
- [POSIX threads](https://man7.org/linux/man-pages/man7/pthreads.7.html)

### Sockets

- [Linux sockets](https://man7.org/linux/man-pages/man7/socket.7.html)
- [Beej's Network Guide](https://beej.us/guide/bgnet/)

### Debugging Tools

- [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
- [ThreadSanitizer](https://clang.llvm.org/docs/ThreadSanitizer.html)
- [GDB](https://sourceware.org/gdb/documentation/)
- [Valgrind](https://valgrind.org/docs/manual/manual.html)

### Security Resources

- [SEI CERT C](https://wiki.sei.cmu.edu/confluence/display/c)
- [Open Web Application Security Project](https://owasp.org/www-community/)
- [The Linux Programming Interface](https://man7.org/tlpi/)
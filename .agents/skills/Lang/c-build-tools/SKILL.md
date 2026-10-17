---
name: c-build-tools
user-invocable: false
description: >
  Choose and use the correct C build tool from the repository configuration.
  Available tools: GCC, Just, CMake, and Ninja.
allow-tools:
  - bash
  - read
  - edit
  - write
  - gcc
  - just
  - ninja
  - cmake
---

# C Build Tools

## Purpose

Select one available build tool for each build step. Do not run every tool by
default. Prefer repository configuration over personal preference.

## Available Tools

- `gcc`: direct C compilation, linking, warnings, and sanitizers.
- `just`: project task runner and recipe aliases.
- `cmake`: portable build configuration and generator selection.
- `ninja`: fast incremental build execution for generated build graphs.

## Tool Selection

Choose tool from repository files in this order:

1. `Justfile` or `justfile`: use `just` recipe requested by the task.
2. `CMakeLists.txt` or `CMakePresets.json`: use `cmake` to configure.
3. `build.ninja`: use `ninja` to build existing generated files.
4. No build configuration: use `gcc` for direct compilation.

Use one tool as main driver. A normal CMake workflow may call Ninja internally.
Do not replace a repository's Just recipe with raw GCC commands without reason.

## Decision Map

```text
Justfile?       yes -> just
CMake project?  yes -> cmake configure, then selected generator
build.ninja?    yes -> ninja
No config?      yes -> gcc
```

Before running a tool:

1. Inspect repository files and existing build output.
2. Read matching preference file.
3. Check required executable with `<tool> --version` when needed.
4. Run the narrowest build or test command.
5. Report command failure without switching tools silently.

## Preference Files

Read shared rules first, then selected tool rules:

0. [Shared preferences](preferences/shared.md)
1. [GCC preferences](preferences/gcc.md)
2. [Just preferences](preferences/just.md)
3. [CMake preferences](preferences/cmake.md)
4. [Ninja preferences](preferences/ninja.md)

## Common Rules

- Keep generated files under `build/`.
- Keep Debug and Release builds separate.
- Keep warnings enabled.
- Fail fast on build or test failure.
- Never edit generated CMake or Ninja files by hand.
- Rebuild after changing headers or compiler flags.
## Ninja Preferences

- Use Ninja for generated incremental builds.
- Let CMake or another generator create `build.ninja`.
- Never edit generated Ninja files by hand.
- Use separate build directories for Debug and Release.
- Inspect targets with Ninja tools before changing build configuration.

```sh
ninja -C build
ninja -C build test
ninja -C build -t targets
ninja -C build -d explain app
```

Ninja reads `build.ninja`, builds out-of-date targets, and runs commands in
parallel. A generator should create complex Ninja files.

Useful commands:

```sh
ninja -C build
ninja -C build app
ninja -C build -j 4
ninja -C build -v
ninja -C build -n
ninja -C build -t clean
```

## Resources

- [Ninja manual](https://ninja-build.org/manual.html)
- [Running Ninja](https://ninja-build.org/manual.html#_running_ninja)
- [Ninja extra tools](https://ninja-build.org/manual.html#_extra_tools)
- [Ninja file reference](https://ninja-build.org/manual.html#_ninja_file_reference)

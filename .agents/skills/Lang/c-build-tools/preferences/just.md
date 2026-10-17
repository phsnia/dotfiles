## Just Preferences

- Use Just for short, readable task aliases.
- Run `just --list` before using unfamiliar recipes.
- Reuse repository recipe names.
- Keep recipes repeatable and fail fast.
- Keep generated output under `build/`.

```sh
just --list
just build
just test
```

Example recipe:

```just
build:
	cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
	cmake --build build

test: build
	ctest --test-dir build --output-on-failure
```

Just is a command runner. It stores project recipes in `justfile` and does not
replace the project build system.

Useful commands:

```sh
just --list
just --summary
just --choose
just build
```

## Resources

- [Just Programmer's Manual](https://just.systems/man/en/)
- [Listing recipes](https://just.systems/man/en/listing-available-recipes.html)
- [Recipe parameters](https://just.systems/man/en/recipe-parameters.html)
- [Just repository](https://github.com/casey/just)

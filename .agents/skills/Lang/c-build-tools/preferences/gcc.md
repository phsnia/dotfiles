## GCC Preferences

- Use GCC for direct C compilation.
- Use `-std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow`.
- Include `-g` for debug builds.
- Pass sanitizer flags during compile and link.
- Use `-pthread` for threaded programs.
- Keep object files and binaries under `build/`.

```sh
mkdir -p build
gcc -std=c17 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
	-g src/main.c -o build/main
./build/main
```

Useful GCC command groups:

```sh
gcc -std=c17 src/main.c -o build/main
gcc -Wall -Wextra -Wpedantic src/main.c -o build/main
gcc -g src/main.c -o build/main
gcc -fsanitize=address,undefined src/main.c -o build/main
gcc -O2 src/main.c -o build/main
```

## Resources

- [GCC manual](https://gcc.gnu.org/onlinedocs/gcc/)
- [GCC command options](https://gcc.gnu.org/onlinedocs/gcc/Invoking-GCC.html)
- [Warning options](https://gcc.gnu.org/onlinedocs/gcc/Warning-Options.html)
- [Debugging options](https://gcc.gnu.org/onlinedocs/gcc/Debugging-Options.html)

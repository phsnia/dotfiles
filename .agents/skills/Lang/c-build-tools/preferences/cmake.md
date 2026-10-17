## CMake Preferences

- Use CMake for portable build configuration.
- Store project rules in `CMakeLists.txt`.
- Use separate build directories for Debug and Release.
- Use Ninja as generator when available.
- Never edit generated files under `build/`.
- Enable tests with CTest.

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure
```

Example configuration:

```cmake
cmake_minimum_required(VERSION 3.20)
project(example C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_executable(app src/main.c)
target_compile_options(app PRIVATE -Wall -Wextra -Wpedantic)

enable_testing()
add_test(NAME app_runs COMMAND app)
```

CMake separates configuration from building. Reconfigure after changing
`CMakeLists.txt` or toolchain settings.

Useful commands:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build --parallel
ctest --test-dir build --output-on-failure
cmake --build build --target clean
```

## Resources

- [CMake documentation](https://cmake.org/cmake/help/latest/)
- [CMake tutorial](https://cmake.org/cmake/help/latest/guide/tutorial/index.html)
- [CMake command-line manual](https://cmake.org/cmake/help/latest/manual/cmake.1.html)
- [CMake buildsystem manual](https://cmake.org/cmake/help/latest/manual/cmake-buildsystem.7.html)
- [CTest manual](https://cmake.org/cmake/help/latest/manual/ctest.1.html)

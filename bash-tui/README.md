# Bash TUI Manager

A small Bash + `stty` terminal menu for Linux and macOS. It uses ANSI terminal sequences and does not depend on `dialog` or `whiptail`.

## Run

```bash
chmod +x main.sh tests/check.sh tests/unit.sh
./tests/check.sh && ./tests/unit.sh
./main.sh
```

Run `./main.sh` directly in a real interactive terminal; piping input is intentionally rejected.

## Controls

- `↑` / `↓`: move selection
- `Enter`: select
- `Esc`: go back; exits from the top-level menu
- `q`: same as Esc

## Layout

- `kernel/core.sh`: shared colors, logger, command checks, terminal preflight, and system-check screen
- `plugins/input.sh`: keyboard and line input
- `plugins/ui.sh`: drawing and messages
- `plugins/menu.sh`: menu selection loop
- `plugins/utils.sh`: confirmation and safe argument-list command execution
- `modules/`: system, network, file, and settings screens

## Logging

Set `LOG_LEVEL=DEBUG` to enable debug messages. Set `LOG_FILE=/path/to/app.log` to append log records to a file. Logging is best-effort and will not crash the UI if the log file cannot be written.

## Safety notes

- Commands are invoked with `"$@"`; no `eval` or shell command-string parsing is used.
- File tools are read-only.
- Ping is limited to four packets; host input is validated and passed as one argument.
- The application checks for an interactive terminal and restores terminal settings on normal exit and handled signals.
- Real terminal behavior still needs manual verification on both Linux and macOS.

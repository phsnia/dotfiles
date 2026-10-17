#!/usr/bin/env bash
set -o nounset

APP_DIR=$(
    CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
) || exit 1

for file in \
    "$APP_DIR/plugins/enum.sh" \
    "$APP_DIR/kernel/core.sh" \
    "$APP_DIR/plugins/input.sh" \
    "$APP_DIR/plugins/ui.sh" \
    "$APP_DIR/plugins/utils.sh" \
    "$APP_DIR/plugins/menu.sh" \
    "$APP_DIR/modules/system.sh" \
    "$APP_DIR/modules/network.sh" \
    "$APP_DIR/modules/files.sh" \
    "$APP_DIR/modules/settings.sh"
do
    if [[ ! -r "$file" ]]; then
        printf 'Error: cannot read required file: %s\n' "$file" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$file"
done

if ! core_preflight; then
    exit 1
fi

TTY_STATE=$(stty -g) || {
    log_error "Cannot read terminal settings."
    exit 1
}
TERMINAL_CHANGED=0

terminal_restore() {
    if (( TERMINAL_CHANGED )); then
        stty "$TTY_STATE" 2>/dev/null || :
        TERMINAL_CHANGED=0
    fi
}

terminal_raw() {
    if stty -echo -icanon min 1 time 0 2>/dev/null; then
        TERMINAL_CHANGED=1
    else
        log_error "Cannot configure terminal input."
        exit 1
    fi
}

cleanup() {
    terminal_restore
    printf '%s\033[?25h' "$C_RESET"
}

on_interrupt() {
    cleanup
    printf '\nInterrupted.\n'
    exit 130
}

trap cleanup EXIT
trap on_interrupt INT TERM HUP

printf '\033[?25l'
terminal_raw

main_menu() {
    local choice
    while menu_select "BASH TUI MANAGER" \
        "System tools" \
        "Network tools" \
        "File tools" \
        "Settings" \
        "System checks" \
        "Exit"
    do
        choice=$MENU_SELECTION
        case "$choice" in
            0) system_menu ;;
            1) network_menu ;;
            2) files_menu ;;
            3) settings_menu ;;
            4) core_system_check_screen ;;
            5)
                if confirm "Exit the application?"; then
                    return 0
                fi
                ;;
        esac
    done
    return 0
}

main_menu

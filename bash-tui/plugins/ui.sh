#!/usr/bin/env bash

readonly UI_RESET=$'\033[0m'
readonly UI_BOLD=$'\033[1m'
readonly UI_CYAN=$'\033[36m'
readonly UI_GREEN=$'\033[32m'
readonly UI_YELLOW=$'\033[33m'
readonly UI_RED=$'\033[31m'
readonly UI_DIM=$'\033[2m'
readonly UI_SELECTED=$'\033[7m'

ui_clear() {
    printf '\033[2J\033[H'
}

ui_width() {
    local width
    width=$(tput cols 2>/dev/null) || width=80

    # Keep rendering usable in very narrow terminals.
    [[ "$width" =~ ^[0-9]+$ ]] || width=80
    (( width < 40 )) && width=40
    (( width > 100 )) && width=100

    printf '%s' "$width"
}

ui_header() {
    local title="$1"
    local width
    width=$(ui_width)

    ui_clear
    printf '%s%s' "$UI_CYAN" "$UI_BOLD"
    printf '%*s\n' "$width" '' | tr ' ' '='
    printf '  %s\n' "$title"
    printf '%*s\n' "$width" '' | tr ' ' '='
    printf '%s\n' "$UI_RESET"
}

ui_footer() {
    printf '\n%s↑/↓ Navigate  Enter Select  Esc Back  q Quit%s\n' \
        "$UI_DIM" "$UI_RESET"
}

ui_message() {
    printf '\n%s%s%s\n' "$UI_YELLOW" "$1" "$UI_RESET"
}

ui_error() {
    printf '\n%sError: %s%s\n' "$UI_RED" "$1" "$UI_RESET"
}

ui_pause() {
    printf '\nPress any key to continue...'
    read_key
    printf '\n'
}

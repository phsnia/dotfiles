#!/usr/bin/env bash
# command_exists is provided by kernel/core.sh (loaded first in main.sh).

confirm() {
    local answer

    printf '%s [y/N] ' "$1"
    read_line answer || return 1

    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

run_action() {
    # Arguments are passed directly; no eval or command-string parsing.
    if "$@"; then
        return 0
    else
        local status=$?
        ui_error "Command failed with exit status $status."
        return "$status"
    fi
}

show_output() {
    local title="$1"
    shift

    ui_header "$title"
    if ! run_action "$@"; then
        :
    fi
    ui_pause
}

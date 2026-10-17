#!/usr/bin/env bash
# Shared runtime: colors, logging, and portable system checks

# Keep color output readable when redirected or when NO_COLOR is set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_REVERSE=$'\033[7m'
else
    C_RESET='' C_BOLD='' C_DIM=''
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_REVERSE=''
fi
readonly C_RESET C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_CYAN C_REVERSE

LOG_LEVEL=${LOG_LEVEL:-INFO}
LOG_FILE=${LOG_FILE:-}

# Numeric level enum. Hand registry: values are numbers, so the generic
# word-definer does not fit; registry shape matches enum_is_valid.
readonly ENUM_LEVEL_DEBUG=10
readonly ENUM_LEVEL_INFO=20
readonly ENUM_LEVEL_WARN=30
readonly ENUM_LEVEL_WARNING=30
readonly ENUM_LEVEL_ERROR=40
readonly ENUM_LEVEL_ITEMS="DEBUG INFO WARN WARNING ERROR"

_log_level_value() {
    case "${1^^}" in
        DEBUG) printf '%s' "$ENUM_LEVEL_DEBUG" ;;
        INFO)  printf '%s' "$ENUM_LEVEL_INFO" ;;
        WARN|WARNING) printf '%s' "$ENUM_LEVEL_WARN" ;;
        ERROR) printf '%s' "$ENUM_LEVEL_ERROR" ;;
        *) printf '%s' "$ENUM_LEVEL_INFO" ;;
    esac
}

log_message() {
    local level="${1:-INFO}"
    shift || :
    local message="$*"
    local threshold current stamp line color
    threshold=$(_log_level_value "$LOG_LEVEL")
    current=$(_log_level_value "$level")
    (( current >= threshold )) || return 0
    stamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf 'time-unknown')
    line="[$stamp] [${level^^}] $message"
    case "${level^^}" in
        DEBUG) color=$C_DIM ;;
        INFO) color=$C_CYAN ;;
        WARN|WARNING) color=$C_YELLOW ;;
        ERROR) color=$C_RED ;;
        *) color='' ;;
    esac
    printf '%s%s%s\n' "$color" "$line" "$C_RESET" >&2
    if [[ -n "$LOG_FILE" ]]; then
        # Logging failure must not crash the interactive UI.
        printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || :
    fi
}

log_debug() { log_message DEBUG "$@"; }
log_info()  { log_message INFO "$@"; }
log_warn()  { log_message WARN "$@"; }
log_error() { log_message ERROR "$@"; }

command_exists() {
    [[ $# -eq 1 && -n "$1" ]] || return 2
    command -v "$1" >/dev/null 2>&1
}

core_require_command() {
    local name="${1:-}"
    if [[ -z "$name" ]] || ! command_exists "$name"; then
        log_error "Required command not found: ${name:-<empty>}"
        return 1
    fi
}

core_is_supported_shell() {
    [[ -n "${BASH_VERSION:-}" ]]
}

core_is_interactive_terminal() {
    [[ -t 0 && -t 1 ]]
}

core_os_name() {
    uname -s 2>/dev/null || printf 'unknown'
}

core_check_terminal() {
    if ! core_is_interactive_terminal; then
        log_error "Run this application directly in an interactive terminal (not through a pipe)."
        return 1
    fi
    core_require_command stty || return 1
    if ! stty -g >/dev/null 2>&1; then
        log_error "Terminal settings are unavailable."
        return 1
    fi
}

core_preflight() {
    if ! core_is_supported_shell; then
        printf 'Error: Bash is required.\n' >&2
        return 1
    fi
    if ! core_check_terminal; then
        return 1
    fi
    log_debug "Preflight passed; OS=$(core_os_name), Bash=$BASH_VERSION"
    return 0
}

core_system_check_screen() {
    ui_header "SYSTEM CHECKS"
    printf '%sBash:%s       %s\n' "$C_BOLD" "$C_RESET" "${BASH_VERSION:-unknown}"
    printf '%sOS:%s         %s\n' "$C_BOLD" "$C_RESET" "$(core_os_name)"
    printf '%sArchitecture:%s %s\n' "$C_BOLD" "$C_RESET" "$(uname -m 2>/dev/null || printf unknown)"
    printf '%sTerminal:%s   %s\n' "$C_BOLD" "$C_RESET" "${TERM:-unknown}"
    printf '%sTTY:%s        ' "$C_BOLD" "$C_RESET"
    if core_is_interactive_terminal; then printf 'interactive\n'; else printf 'not interactive\n'; fi
    printf '\n%sCommand availability%s\n' "$C_BOLD" "$C_RESET"
    local name
    for name in bash stty uname date tput df ls du ping; do
        if command_exists "$name"; then
            printf '  %s[OK]%s   %s\n' "$C_GREEN" "$C_RESET" "$name"
        else
            printf '  %s[MISSING]%s %s\n' "$C_YELLOW" "$C_RESET" "$name"
        fi
    done
    ui_pause
}
#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || exit 1

pass=0
fail=0

assert_eq() {
    local want="$1" got="$2" label="$3"
    if [[ "$want" == "$got" ]]; then
        ((pass++))
        printf '[PASS] %s\n' "$label"
    else
        ((fail++))
        printf '[FAIL] %s (want=%s got=%s)\n' "$label" "$want" "$got"
    fi
}

check_contains() {
    local out="$1" needle="$2" label="$3"
    if [[ "$out" == *"$needle"* ]]; then
        ((pass++))
        printf '[PASS] %s\n' "$label"
    else
        ((fail++))
        printf '[FAIL] %s (missing %s)\n' "$label" "$needle"
    fi
}

setup_input() {
    # shellcheck source=/dev/null
    source "$ROOT/plugins/enum.sh"
    # shellcheck source=/dev/null
    source "$ROOT/kernel/core.sh"
    # shellcheck source=/dev/null
    source "$ROOT/plugins/input.sh"
    # shellcheck source=/dev/null
    source "$ROOT/plugins/ui.sh"
    # shellcheck source=/dev/null
    source "$ROOT/plugins/menu.sh"
    # shellcheck source=/dev/null
    source "$ROOT/plugins/utils.sh"
    # shellcheck source=/dev/null
    source "$ROOT/modules/system.sh"
    # shellcheck source=/dev/null
    source "$ROOT/modules/network.sh"
    # shellcheck source=/dev/null
    source "$ROOT/modules/files.sh"
    # shellcheck source=/dev/null
    source "$ROOT/modules/settings.sh"
    # read_line shells out to terminal funcs (live in main.sh) — stub them.
    terminal_restore() { :; }
    terminal_raw() { :; }
}

key_case() {
    local label="$1" bytes="$2" want="$3"
    local got
    got=$(printf '%b' "$bytes" | { read_key; printf '%s' "$REPLY"; })
    assert_eq "$want" "$got" "key $label"
}

test_keys() {
    key_case "up" '\033[A' "UP"
    key_case "down" '\033[B' "DOWN"
    key_case "enter-lf" '\n' "ENTER"
    key_case "enter-cr" '\r' "ENTER"
    key_case "esc" '\033' "ESC"
    key_case "q" 'q' "QUIT"
    key_case "Q" 'Q' "QUIT"
    key_case "other" 'x' "OTHER"
    local got
    got=$(printf '' | { read_key; printf '%s' "$REPLY"; })
    assert_eq "EOF" "$got" "key eof"
}

test_read_line() {
    local out
    out=$(printf 'hello' | { read_line out_inner; printf '%s' "$out_inner"; })
    assert_eq "hello" "$out" "read_line passthrough"
    # empty stdin → read fails, status nonzero
    out=$(printf '' | { read_line out_inner || printf 'rc=%s' "$?"; })
    assert_eq "rc=1" "$out" "read_line eof-status"
}

test_ui() {
    local width out saved width_ok hdr_ok
    width=$(ui_width)
    width_ok=0
    [[ "$width" =~ ^[0-9]+$ ]] && (( width >= 40 && width <= 100 )) && width_ok=1
    assert_eq "1" "$width_ok" "ui_width range ($width)"
    out=$(ui_header "T")
    if [[ "$out" == *"T"* && "$out" == *"="* ]]; then hdr_ok=1; else hdr_ok=0; fi
    assert_eq "1" "$hdr_ok" "ui_header content"
    out=$(ui_footer)
    check_contains "$out" "Navigate" "ui_footer content"
    out=$(ui_error "boom")
    check_contains "$out" "Error:" "ui_error content"
    # ui_pause blocks on read_key — stub it, then restore.
    saved=$(declare -f read_key)
    read_key() { REPLY="ENTER"; }
    ui_pause >/dev/null
    assert_eq "ENTER" "$REPLY" "ui_pause returns"
    eval "$saved"
}

menu_case() {
    local label="$1" bytes="$2" want_rc="$3" want_sel="$4"
    local line rc sel
    line=$(printf '%b' "$bytes" | {
        menu_select "T" "a" "b" "c"
        rc=$?
        printf 'rc=%s sel=%s' "$rc" "$MENU_SELECTION"
    } | tail -1)
    rc=${line#rc=}; rc=${rc%% *}
    sel=${line#*sel=}
    if [[ "$rc" == "$want_rc" ]] && [[ -z "$want_sel" || "$sel" == "$want_sel" ]]; then
        ((pass++))
        printf '[PASS] menu %s (%s)\n' "$label" "$line"
    else
        ((fail++))
        printf '[FAIL] menu %s (want rc=%s sel=%s got %s)\n' "$label" "$want_rc" "$want_sel" "$line"
    fi
}

test_menu() {
    menu_case "down-down-enter" '\033[B\033[B\n' "0" "2"
    menu_case "up-top-stay" '\033[A\n' "0" "0"
    menu_case "down-bottom-stay" '\033[B\033[B\033[B\033[B\n' "0" "2"
    menu_case "esc" '\033' "1" ""
    menu_case "q" 'q' "1" ""
    local rc
    menu_select "T" >/dev/null 2>&1; rc=$?
    assert_eq "1" "$rc" "menu empty-opts"
}

confirm_case() {
    local label="$1" canned="$2" want_rc="$3"
    local rc
    read_line() { printf -v "$1" '%s' "$canned"; return 0; }
    confirm "Exit?" >/dev/null 2>&1; rc=$?
    assert_eq "$want_rc" "$rc" "confirm $label"
}

test_utils() {
    local saved rc out
    saved=$(declare -f read_line)
    confirm_case "y" "y" "0"
    confirm_case "n" "n" "1"
    confirm_case "YES" "YES" "0"
    confirm_case "empty" "" "1"
    eval "$saved"
    run_action true >/dev/null 2>&1; rc=$?
    assert_eq "0" "$rc" "run_action true"
    out=$(run_action false 2>&1); rc=$?
    if (( rc != 0 )); then
        check_contains "$out" "exit status" "run_action false err"
    else
        ((fail++)); printf '[FAIL] run_action false err (rc=0)\n'
    fi
    touch "/tmp/unit f o o"
    run_action ls "/tmp/unit f o o" >/dev/null 2>&1; rc=$?
    assert_eq "0" "$rc" "run_action spaced-arg"
    rm -f "/tmp/unit f o o"
    saved=$(declare -f ui_pause)
    ui_pause() { :; }
    show_output "T" true >/dev/null 2>&1; rc=$?
    assert_eq "0" "$rc" "show_output ok"
    eval "$saved"
}

test_core() {
    local rc out saved_level saved_file tmp
    command_exists bash; rc=$?
    assert_eq "0" "$rc" "command_exists bash"
    command_exists __nope_xyz__; rc=$?
    assert_eq "1" "$rc" "command_exists missing"
    command_exists ""; rc=$?
    assert_eq "2" "$rc" "command_exists empty"
    saved_level=$LOG_LEVEL
    LOG_LEVEL=WARN
    out=$(log_info "quiet" 2>&1)
    assert_eq "" "$out" "log level-filter hides INFO"
    out=$(log_error "loud" 2>&1)
    check_contains "$out" "loud" "log error shows"
    saved_file=$LOG_FILE
    tmp=$(mktemp)
    LOG_FILE=$tmp
    LOG_LEVEL=INFO
    log_info "tofile" 2>/dev/null
    out=$(cat "$tmp")
    check_contains "$out" "tofile" "log file-append"
    rm -f "$tmp"
    LOG_FILE="/nonexistent-dir-xyz/app.log"
    log_info "nocrash" 2>/dev/null; rc=$?
    assert_eq "0" "$rc" "log bad-path no-crash"
    LOG_LEVEL=$saved_level
    LOG_FILE=$saved_file
    core_require_command __nope_xyz__ >/dev/null 2>&1; rc=$?
    assert_eq "1" "$rc" "require-command missing"
    printf '' | core_preflight >/dev/null 2>&1; rc=$?
    assert_eq "1" "$rc" "preflight pipe-refuse"
}

module_back_case() {
    local label="$1" func="$2" bytes="$3"
    local rc
    rc=$(printf '%b' "$bytes" | { "$func" >/dev/null 2>&1; printf '%s' "$?"; })
    assert_eq "0" "$rc" "$label Back"
}

test_modules_back() {
    module_back_case "system" "system_menu" '\033[B\033[B\033[B\n'
    module_back_case "network" "network_menu" '\033[B\033[B\033[B\n'
    module_back_case "files" "files_menu" '\033[B\033[B\033[B\n'
    module_back_case "settings" "settings_menu" '\033[B\033[B\n'
    module_back_case "system-esc" "system_menu" '\033'
}

test_modules_fallback() {
    local saved_exists saved_pause saved_read out
    saved_exists=$(declare -f command_exists)
    saved_pause=$(declare -f ui_pause)
    ui_pause() { :; }
    # all commands missing → nice errors, then q exits
    command_exists() { return 1; }
    out=$(printf '\nq' | network_menu 2>&1)
    check_contains "$out" "Neither ip nor ifconfig" "fallback no-iface-msg"
    out=$(printf '\033[B\nq' | network_menu 2>&1)
    check_contains "$out" "No supported routing" "fallback no-route-msg"
    eval "$saved_exists"
    # files du with spaced dir, real du
    saved_read=$(declare -f read_line)
    mkdir -p "/tmp/unit dir"
    read_line() { printf -v "$1" '%s' "/tmp/unit dir"; return 0; }
    out=$(printf '\033[B\033[B\nq' | files_menu 2>&1)
    check_contains "$out" "unit dir" "fallback spaced-dir"
    rm -rf "/tmp/unit dir"
    eval "$saved_read"
    eval "$saved_pause"
}

test_enum() {
    local rc out
    enum_def KEYT UP DOWN ENTER || rc=$?
    assert_eq "UP" "${ENUM_KEYT_UP:-}" "enum const set"
    assert_eq "UP DOWN ENTER" "${ENUM_KEYT_ITEMS:-}" "enum registry"
    enum_is_valid KEYT UP; rc=$?
    assert_eq "0" "$rc" "enum valid word"
    enum_is_valid KEYT NOPE; rc=$?
    assert_eq "1" "$rc" "enum bad word"
    enum_is_valid NOSUCH UP; rc=$?
    assert_eq "2" "$rc" "enum unknown registry"
    enum_def; rc=$?
    assert_eq "2" "$rc" "enum empty-args"
    out=$(enum_name KEYT DOWN)
    assert_eq "DOWN" "$out" "enum name known"
    out=$(enum_name KEYT NOPE)
    assert_eq "UNKNOWN" "$out" "enum name unknown"
    rc=$( (ENUM_KEYT_UP=X) 2>/dev/null; printf '%s' "$?" )
    assert_eq "1" "$rc" "enum readonly"
}

test_enum_apply() {
    local rc out
    enum_is_valid KEY UP; rc=$?
    assert_eq "0" "$rc" "enum KEY valid word"
    enum_is_valid KEY NOPE; rc=$?
    assert_eq "1" "$rc" "enum KEY bad word"
    out=$(enum_name KEY DOWN)
    assert_eq "DOWN" "$out" "enum KEY reverse-name"
    assert_eq "0" "$MENU_OK" "enum MENU_OK const"
    assert_eq "1" "$MENU_BACK" "enum MENU_BACK const"
    assert_eq "20" "$ENUM_LEVEL_INFO" "enum LEVEL numeric"
    enum_is_valid LEVEL WARN; rc=$?
    assert_eq "0" "$rc" "enum LEVEL validator"
}

host_case() {
    local label="$1" host="$2" want="$3"
    local got
    if [[ "$host" =~ ^[a-zA-Z0-9._:-]+$ ]]; then got="valid"; else got="invalid"; fi
    assert_eq "$want" "$got" "host $label"
}

test_host_validation() {
    host_case "domain" "example.com" "valid"
    host_case "ipv4" "192.168.1.1" "valid"
    host_case "inject-semi" 'host;rm -rf' "invalid"
    host_case "space" 'a b' "invalid"
    host_case "empty" '' "invalid"
    host_case "dollar" '$(id)' "invalid"
}

TESTS=(
    test_keys test_read_line test_ui test_menu test_utils
    test_core test_modules_back test_modules_fallback test_host_validation
    test_enum test_enum_apply
)

main() {
    local t
    setup_input
    (( ${#TESTS[@]} > 0 )) || { printf 'no tests\n'; return 1; }
    for t in "${TESTS[@]}"; do
        if declare -F "$t" >/dev/null; then
            "$t"
        else
            ((fail++)); printf '[FAIL] missing test %s\n' "$t"
        fi
    done
    printf -- '---\nPASS %s, FAIL %s\n' "$pass" "$fail"
    (( fail == 0 ))
}

main

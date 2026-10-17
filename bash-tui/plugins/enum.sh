#!/usr/bin/env bash
# String-valued enums. Convention over type system:
#   enum_def KEY UP DOWN   ->  readonly ENUM_KEY_UP=UP ... + registry ENUM_KEY_ITEMS
# No assocs, no namerefs, no eval — works on macOS bash 3.2.

enum_def() {
    (( $# >= 2 )) || return 2
    local name="$1"
    shift
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
    local item var items=""
    for item in "$@"; do
        [[ "$item" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
        var="ENUM_${name}_${item}"
        # printf -v assigns globally (no local of that name here); then lock it.
        printf -v "$var" '%s' "$item" || return 1
        readonly "$var" || return 1
        items="${items}${items:+ }$item"
    done
    var="ENUM_${name}_ITEMS"
    printf -v "$var" '%s' "$items" || return 1
    readonly "$var" || return 1
}

enum_is_valid() {
    (( $# == 2 )) || return 2
    local regvar="ENUM_$1_ITEMS"
    [[ -n "${!regvar:-}" ]] || return 2
    local w
    # shellcheck disable=SC2086
    for w in ${!regvar}; do
        [[ "$w" == "$2" ]] && return 0
    done
    return 1
}

enum_name() {
    (( $# == 2 )) || return 2
    enum_is_valid "$1" "$2" && printf '%s' "$2" || printf 'UNKNOWN'
}

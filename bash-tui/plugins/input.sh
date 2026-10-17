#!/usr/bin/env bash
# Requires plugins/enum.sh (loaded first in main.sh). Keys are a string enum.

# Keys are a string enum. Values flow on REPLY; menu + tests match words.
enum_def KEY UP DOWN ENTER ESC QUIT OTHER EOF

# Sets REPLY to a KEY enum word.
read_key() {
    local key next

    IFS= read -r -s -n 1 key || {
        REPLY="$ENUM_KEY_EOF"
        return 0
    }

    case "$key" in
        "")
            REPLY="$ENUM_KEY_ENTER"
            ;;
        $'\n'|$'\r')
            REPLY="$ENUM_KEY_ENTER"
            ;;
        q|Q)
            REPLY="$ENUM_KEY_QUIT"
            ;;
        $'\x1b')
            # An Escape key may also begin an arrow-key sequence.
            if ! IFS= read -r -s -n 1 -t 0.08 next; then
                REPLY="$ENUM_KEY_ESC"
                return 0
            fi

            if [[ "$next" == "[" ]]; then
                if IFS= read -r -s -n 1 -t 0.08 next; then
                    case "$next" in
                        A) REPLY="$ENUM_KEY_UP" ;;
                        B) REPLY="$ENUM_KEY_DOWN" ;;
                        *) REPLY="$ENUM_KEY_OTHER" ;;
                    esac
                else
                    REPLY="$ENUM_KEY_OTHER"
                fi
            else
                REPLY="$ENUM_KEY_ESC"
            fi
            ;;
        *)
            REPLY="$ENUM_KEY_OTHER"
            ;;
    esac
}

read_line() {
    local destination="$1"
    local value
    local status=0

    terminal_restore

    IFS= read -r value || status=$?

    terminal_raw

    printf -v "$destination" '%s' "$value"
    return "$status"
}

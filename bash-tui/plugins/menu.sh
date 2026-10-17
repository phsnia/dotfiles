#!/usr/bin/env bash
# Requires plugins/enum.sh (loaded first in main.sh). Menu result codes.
readonly MENU_OK=0
readonly MENU_BACK=1

MENU_SELECTION=0

menu_select() {
    local title="$1"
    shift

    local -a options=("$@")
    local count=${#options[@]}
    local selected=0
    local i

    (( count > 0 )) || return "$MENU_BACK"

    while :; do
        ui_header "$title"

        for ((i = 0; i < count; i++)); do
            if (( i == selected )); then
                printf '  %s> %s%s\n' \
                    "$UI_SELECTED" "${options[i]}" "$UI_RESET"
            else
                printf '    %s\n' "${options[i]}"
            fi
        done

        ui_footer
        read_key

        case "$REPLY" in
            UP)
                (( selected > 0 )) && ((selected--))
                ;;
            DOWN)
                (( selected < count - 1 )) && ((selected++))
                ;;
            ENTER)
                MENU_SELECTION=$selected
                return "$MENU_OK"
                ;;
            ESC|QUIT|EOF)
                return "$MENU_BACK"
                ;;
            *)
                ;;
        esac
    done
}

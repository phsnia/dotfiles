#!/usr/bin/env bash

settings_menu() {
    local choice

    while menu_select "SETTINGS" \
        "Show application information" \
        "Show terminal information" \
        "Back"
    do
        choice=$MENU_SELECTION

        case "$choice" in
            0)
                ui_header "APPLICATION INFORMATION"
                printf 'Application: Bash TUI Manager\n'
                printf 'Version:     1.0.0\n'
                printf 'Bash:        %s\n' "$BASH_VERSION"
                printf 'Platform:    %s\n' "$(uname -s)"
                ui_pause
                ;;
            1)
                ui_header "TERMINAL INFORMATION"
                printf 'TERM:   %s\n' "${TERM:-unknown}"
                printf 'TTY:    '
                if [[ -t 0 ]]; then
                    printf 'interactive\n'
                else
                    printf 'not interactive\n'
                fi
                printf 'Width:  %s columns\n' "$(ui_width)"
                ui_pause
                ;;
            2) return 0 ;;
        esac
    done

    return 0
}

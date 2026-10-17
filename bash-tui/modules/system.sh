#!/usr/bin/env bash

system_menu() {
    local choice

    while menu_select "SYSTEM TOOLS" \
        "Operating system" \
        "Disk usage" \
        "Memory information" \
        "Back"
    do
        choice=$MENU_SELECTION

        case "$choice" in
            0)
                ui_header "OPERATING SYSTEM"
                printf 'OS:      %s\n' "$(uname -s)"
                printf 'Release: %s\n' "$(uname -r)"
                printf 'Machine: %s\n' "$(uname -m)"
                printf 'Shell:   %s\n' "${BASH_VERSION:-unknown}"
                ui_pause
                ;;
            1)
                show_output "DISK USAGE" df -h
                ;;
            2)
                ui_header "MEMORY INFORMATION"
                if command_exists free; then
                    free -h
                elif [[ -r /proc/meminfo ]]; then
                    # Linux fallback when free is unavailable.
                    sed -n '1,8p' /proc/meminfo
                else
                    printf 'Memory reporting is unavailable on this system.\n'
                fi
                ui_pause
                ;;
            3) return 0 ;;
        esac
    done

    return 0
}

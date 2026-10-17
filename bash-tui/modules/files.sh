#!/usr/bin/env bash

files_menu() {
    local choice path

    while menu_select "FILE TOOLS" \
        "Show current directory" \
        "List files" \
        "Show directory size" \
        "Back"
    do
        choice=$MENU_SELECTION

        case "$choice" in
            0)
                ui_header "CURRENT DIRECTORY"
                pwd
                ui_pause
                ;;
            1)
                ui_header "FILE LIST"
                ls -la
                ui_pause
                ;;
            2)
                ui_header "DIRECTORY SIZE"
                printf 'Directory path (blank for current): '
                read_line path || continue
                [[ -n "$path" ]] || path=.

                if [[ ! -d "$path" ]]; then
                    ui_error "Directory does not exist."
                elif command_exists du; then
                    du -sh "$path"
                else
                    ui_error "du is unavailable."
                fi
                ui_pause
                ;;
            3) return 0 ;;
        esac
    done

    return 0
}

#!/usr/bin/env bash

network_menu() {
    local choice host

    while menu_select "NETWORK TOOLS" \
        "Show network interfaces" \
        "Show routing table" \
        "Ping a host" \
        "Back"
    do
        choice=$MENU_SELECTION

        case "$choice" in
            0)
                ui_header "NETWORK INTERFACES"
                if command_exists ip; then
                    ip addr
                elif command_exists ifconfig; then
                    ifconfig
                else
                    ui_error "Neither ip nor ifconfig is available."
                fi
                ui_pause
                ;;
            1)
                ui_header "ROUTING TABLE"
                if command_exists ip; then
                    ip route
                elif command_exists netstat; then
                    netstat -rn
                else
                    ui_error "No supported routing command was found."
                fi
                ui_pause
                ;;
            2)
                ui_header "PING A HOST"
                printf 'Hostname or IP address: '
                read_line host || continue

                # Basic validation; the value is passed as one argument.
                if [[ ! "$host" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
                    ui_error "Invalid hostname or address format."
                    ui_pause
                    continue
                fi

                if command_exists ping; then
                    # Limit the number of packets. Options differ by OS.
                    if [[ "$(uname -s)" == "Darwin" ]]; then
                        show_output "PING RESULTS" ping -c 4 "$host"
                    else
                        show_output "PING RESULTS" ping -c 4 -W 2 "$host"
                    fi
                else
                    ui_error "ping is not installed."
                    ui_pause
                fi
                ;;
            3) return 0 ;;
        esac
    done

    return 0
}

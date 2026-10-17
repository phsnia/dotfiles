#!/usr/bin/env bash

volume=$(pamixer --get-volume)
muted=$(pamixer --get-mute)

case "$1" in
  up)
    pamixer -i 5             
    ;;
  down)
    pamixer -d 5             
    ;;
  toggle)
    pamixer --toggle-mute   
    ;;
#   *)
#     echo "Usage: $0 {up|down|toggle}"
#     exit 1
#     ;;
esac

if [ "$muted" = "true" ]; then
  echo "Muted"
else
  echo "$volume%"
fi

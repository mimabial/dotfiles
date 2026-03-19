#!/usr/bin/env bash
# Cycle monitor scaling: 1 → 1.6 → 2 → 3 → 1

MONITOR_INFO=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true)')
ACTIVE_MONITOR=$(jq -r '.name' <<<"$MONITOR_INFO")
CURRENT_SCALE=$(jq -r '.scale' <<<"$MONITOR_INFO")
WIDTH=$(jq -r '.width' <<<"$MONITOR_INFO")
HEIGHT=$(jq -r '.height' <<<"$MONITOR_INFO")
REFRESH_RATE=$(jq -r '.refreshRate' <<<"$MONITOR_INFO")

CURRENT_INT=$(awk -v s="$CURRENT_SCALE" 'BEGIN { printf "%.0f", s * 10 }')

case "$CURRENT_INT" in
  10) NEW_SCALE=1.6 ;;
  16) NEW_SCALE=2 ;;
  20) NEW_SCALE=3 ;;
  *) NEW_SCALE=1 ;;
esac

hyprctl keyword misc:disable_scale_notification true
hyprctl keyword monitor "$ACTIVE_MONITOR,${WIDTH}x${HEIGHT}@${REFRESH_RATE},auto,$NEW_SCALE"
hyprctl keyword misc:disable_scale_notification false
dunstify -a "Hyprland" -t 3000 -i "preferences-desktop-display" -h "string:x-dunst-stack-tag:scale" "Display scaling: ${NEW_SCALE}x"

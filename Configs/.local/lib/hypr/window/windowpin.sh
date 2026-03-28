#!/bin/bash

# Toggle to pop-out a tile to stay fixed on a display basis.

normalize_uint() {
  local value="${1:-}"
  local default_value="${2:-0}"

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

active=$(hyprctl activewindow -j)
pinned=$(echo "$active" | jq .pinned)
addr=$(echo "$active" | jq -r ".address")
[ -z "$addr" ] && {
  echo "No active window"
  exit 0
}

if [ "$pinned" = "true" ]; then
  hyprctl -q --batch \
    "dispatch pin address:$addr;" \
    "dispatch togglefloating address:$addr;" \
    "dispatch tagwindow -pop address:$addr;"
else
  # Get monitor resolution (already in logical pixels, accounts for scale)
  monitor_info=$(hyprctl -j monitors | jq -r '.[] | select(.focused==true)')
  monitor_width=$(normalize_uint "$(echo "$monitor_info" | jq -r '.width')" 0)
  monitor_height=$(normalize_uint "$(echo "$monitor_info" | jq -r '.height')" 0)

  # Get gaps to account for them
  gaps_out=$(normalize_uint "$(hyprctl -j getoption general:gaps_out | jq -r '.int')" 0)

  # Account for waybar (check if it exists and get its dimensions)
  waybar_width=0
  waybar_height=0
  if pgrep -x waybar >/dev/null; then
    waybar_info=$(hyprctl layers | grep -A1 "namespace: waybar" | grep "xywh:" | head -1)
    if [[ -n "$waybar_info" ]]; then
      # Extract width and height from "xywh: x y w h"
      waybar_width=$(normalize_uint "$(echo "$waybar_info" | awk '{print $4}')" 0)
      waybar_height=$(normalize_uint "$(echo "$waybar_info" | awk '{print $5}' | tr -d ',')" 0)
    fi
  fi

  # Effective usable area (subtract gaps and waybar)
  usable_width=$((monitor_width - gaps_out * 2 - waybar_width))
  usable_height=$((monitor_height - gaps_out * 2 - waybar_height))

  # Calculate 70% of usable area for PiP window
  pip_width=$(awk "BEGIN {printf \"%.0f\", $usable_width * 0.7}")
  pip_height=$(awk "BEGIN {printf \"%.0f\", $usable_height * 0.7}")

  hyprctl -q --batch \
    "dispatch togglefloating address:$addr;" \
    "dispatch resizewindowpixel exact ${pip_width} ${pip_height},address:$addr;" \
    "dispatch centerwindow address:$addr;" \
    "dispatch pin address:$addr;" \
    "dispatch alterzorder top address:$addr;" \
    "dispatch tagwindow +pop address:$addr;"
fi

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
  # Read the focused monitor's logical size and reserved edges directly from
  # Hyprland instead of inferring usable space from Waybar layer geometry.
  monitor_info=$(
    hyprctl -j monitors | jq -r '
      (map(select(.focused == true))[0] // .[0]) as $monitor
      | [
          ($monitor.width // 0),
          ($monitor.height // 0),
          ($monitor.reserved[0] // 0),
          ($monitor.reserved[1] // 0),
          ($monitor.reserved[2] // 0),
          ($monitor.reserved[3] // 0)
        ]
      | @tsv
    '
  )
  IFS=$'\t' read -r monitor_width_raw monitor_height_raw reserved_left_raw reserved_top_raw reserved_right_raw reserved_bottom_raw <<<"$monitor_info"
  monitor_width=$(normalize_uint "${monitor_width_raw}" 0)
  monitor_height=$(normalize_uint "${monitor_height_raw}" 0)
  reserved_left=$(normalize_uint "${reserved_left_raw}" 0)
  reserved_top=$(normalize_uint "${reserved_top_raw}" 0)
  reserved_right=$(normalize_uint "${reserved_right_raw}" 0)
  reserved_bottom=$(normalize_uint "${reserved_bottom_raw}" 0)

  # Get gaps to account for them
  gaps_out=$(normalize_uint "$(hyprctl -j getoption general:gaps_out | jq -r '.int')" 0)

  # Effective usable area in logical pixels.
  usable_width=$((monitor_width - reserved_left - reserved_right - gaps_out * 2))
  usable_height=$((monitor_height - reserved_top - reserved_bottom - gaps_out * 2))

  # Calculate 70% of usable area for PiP window
  pip_width=$(awk "BEGIN {printf \"%.0f\", $usable_width * 0.7}")
  pip_height=$(awk "BEGIN {printf \"%.0f\", $usable_height * 0.7}")

  hyprctl -q --batch \
    "dispatch togglefloating address:$addr;" \
    "dispatch resizewindowpixel exact ${pip_width} ${pip_height},address:$addr;" \
    "dispatch centerwindow 1,address:$addr;" \
    "dispatch pin address:$addr;" \
    "dispatch alterzorder top address:$addr;" \
    "dispatch tagwindow +pop address:$addr;"
fi

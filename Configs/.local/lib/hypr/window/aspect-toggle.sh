#!/usr/bin/env bash
# Toggle single-window square aspect ratio

set -euo pipefail

CURRENT_VALUE=$(hyprctl getoption "layout:single_window_aspect_ratio" 2>/dev/null | head -1)

if [[ "$CURRENT_VALUE" == *"[1, 1]"* ]]; then
  hyprctl keyword layout:single_window_aspect_ratio "0 0"
  dunstify -a "Hyprland" -t 3000 -i "preferences-system" -h "string:x-dunst-stack-tag:aspect" "Square aspect ratio disabled"
else
  hyprctl keyword layout:single_window_aspect_ratio "1 1"
  dunstify -a "Hyprland" -t 3000 -i "preferences-system" -h "string:x-dunst-stack-tag:aspect" "Square aspect ratio enabled"
fi

#!/usr/bin/env bash
# Waybar color mode indicator

set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/waybar.state.common.sh"
waybar_state_init

# Read the selected color mode from state files without sourcing them.
selected_color_mode="$(waybar_state_value "selected_color_mode" "1")"

# Mode definitions
color_mode_labels=("Theme" "Auto" "Dark" "Light")
selected_color_mode_label="Unknown"
if [[ "${selected_color_mode}" =~ ^[0-9]+$ ]] && [ "${selected_color_mode}" -ge 0 ] && [ "${selected_color_mode}" -lt "${#color_mode_labels[@]}" ]; then
  selected_color_mode_label="${color_mode_labels[${selected_color_mode}]}"
fi

# Icons for each mode
case "${selected_color_mode}" in
  0) icon="󱥚" ;; # Theme mode - palette icon
  1) icon="󰔎" ;; # Auto mode - auto/wand icon
  2) icon="" ;; # Dark mode - moon icon
  3) icon="󰖙" ;; # Light mode - sun icon
  *) icon="󰏘" ;;
esac

# Output JSON for waybar
cat <<EOF
{ "text": "${icon}", "tooltip": "Color Mode: ${selected_color_mode_label}", "class": "colormode-${selected_color_mode}", "alt": "${selected_color_mode_label}" }
EOF

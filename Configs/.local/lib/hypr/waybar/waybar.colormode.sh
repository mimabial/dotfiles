#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/waybar.state.common.sh"
waybar_state_init

# Read the color policy from state files without sourcing them.
selected_color_source="$(waybar_state_value "selected_color_source" "")"
selected_color_mode="$(waybar_state_value "selected_color_mode" "")"
background_mode="$(waybar_state_value "BACKGROUND_MODE" "dark")"

case "${selected_color_source}" in
  theme | pywal) ;;
  *)
    if [[ "${selected_color_mode}" =~ ^[1-3]$ ]]; then
      selected_color_source="pywal"
    else
      selected_color_source="theme"
    fi
    ;;
esac

case "${selected_color_mode}" in
  1) selected_color_mode_label="Auto" ;;
  2) selected_color_mode_label="Dark" ;;
  3) selected_color_mode_label="Light" ;;
  *)
    if [[ "${background_mode}" == "light" ]]; then
      selected_color_mode=3
      selected_color_mode_label="Light"
    else
      selected_color_mode=2
      selected_color_mode_label="Dark"
    fi
    ;;
esac

selected_color_source_label="${selected_color_source^}"

case "${selected_color_mode}" in
  1) icon="󰔎" ;;
  2) icon="" ;;
  3) icon="󰖙" ;;
  *) icon="󰏘" ;;
esac

cat <<EOF
{ "text": "${icon}", "tooltip": "Colors: ${selected_color_source_label} · ${selected_color_mode_label}", "class": "colormode-${selected_color_source}-${selected_color_mode}", "alt": "${selected_color_source_label} ${selected_color_mode_label}" }
EOF

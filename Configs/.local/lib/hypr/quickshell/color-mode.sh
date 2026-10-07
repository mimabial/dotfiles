#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/provider-state.common.bash"
quickshell_state_init
declare -F state_resolve_color_mode >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/state.bash"

# Read the color policy from state files without sourcing them.
selected_color_source="$(quickshell_state_value "selected_color_source" "")"
selected_color_mode="$(quickshell_state_value "selected_color_mode" "")"
background_mode="$(quickshell_state_value "BACKGROUND_MODE" "dark")"

selected_color_source="$(state_resolve_color_source "${selected_color_source}" "${selected_color_mode}")"
selected_color_mode="$(state_resolve_color_mode "${selected_color_mode}" "${background_mode}")"

case "${selected_color_mode}" in
  "${STATE_COLOR_MODE_AUTO}") selected_color_mode_label="Auto" ;;
  "${STATE_COLOR_MODE_DARK}") selected_color_mode_label="Dark" ;;
  "${STATE_COLOR_MODE_LIGHT}") selected_color_mode_label="Light" ;;
esac

selected_color_source_label="${selected_color_source^}"

case "${selected_color_mode}" in
  "${STATE_COLOR_MODE_AUTO}") icon="󰔎" ;;
  "${STATE_COLOR_MODE_DARK}") icon="" ;;
  "${STATE_COLOR_MODE_LIGHT}") icon="󰖙" ;;
esac

cat <<EOF
{ "text": "${icon}", "tooltip": "Colors: ${selected_color_source_label} · ${selected_color_mode_label}", "class": "colormode-${selected_color_source}-${selected_color_mode}", "alt": "${selected_color_source_label} ${selected_color_mode_label}" }
EOF

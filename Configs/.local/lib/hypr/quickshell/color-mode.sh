#!/usr/bin/env bash
set -euo pipefail

declare -F state_resolve_color_mode_into >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/state.bash"

state_get_into selected_color_source selected_color_source ""
state_get_into selected_color_mode selected_color_mode ""
state_get_into background_mode BACKGROUND_MODE dark

state_resolve_color_source_into selected_color_source "${selected_color_source}" "${selected_color_mode}"
state_resolve_color_mode_into selected_color_mode "${selected_color_mode}" "${background_mode}"

case "${selected_color_mode}" in
  "${STATE_COLOR_MODE_AUTO}") selected_color_mode_label="Auto" icon="󰔎" ;;
  "${STATE_COLOR_MODE_DARK}") selected_color_mode_label="Dark" icon="" ;;
  "${STATE_COLOR_MODE_LIGHT}") selected_color_mode_label="Light" icon="󰖙" ;;
esac

selected_color_source_label="${selected_color_source^}"

printf '%s\n' "{ \"text\": \"${icon}\", \"tooltip\": \"Colors: ${selected_color_source_label} · ${selected_color_mode_label}\", \"class\": \"colormode-${selected_color_source}-${selected_color_mode}\", \"alt\": \"${selected_color_source_label} ${selected_color_mode_label}\" }"

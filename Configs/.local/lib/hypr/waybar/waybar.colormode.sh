#!/usr/bin/env bash
# Waybar color mode indicator

# Initialize hyprshell environment
if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  if ! eval "$(hyprshell init 2>/dev/null)"; then
    # Fallback if hyprshell init fails
    export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
    export HYPR_STATE_HOME="${XDG_STATE_HOME}/hypr"
  fi
fi

# Read the selected color mode from staterc (primary source)
[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc" ] && source "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc" 2>/dev/null

# Fallback to config if staterc doesn't have it
if [ -z "${selected_color_mode}" ]; then
  [ -f "$HYPR_STATE_HOME/config" ] && source "$HYPR_STATE_HOME/config" 2>/dev/null
fi

# Default to Auto mode if still not set
selected_color_mode="${selected_color_mode:-1}"

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

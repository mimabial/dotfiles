#!/usr/bin/env bash
# Waybar color mode indicator

# Initialize hyprshell environment
if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  if ! eval "$(hyprshell init 2>/dev/null)"; then
    # Fallback if hyprshell init fails
    export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
    export HYPR_STATE_HOME="${XDG_STATE_HOME}/hypr"
  fi
fi

# Read current mode from staterc (primary source)
[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc" ] && source "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc" 2>/dev/null

# Fallback to config if staterc doesn't have it
if [ -z "${enableWallDcol}" ]; then
  [ -f "$HYPR_STATE_HOME/config" ] && source "$HYPR_STATE_HOME/config" 2>/dev/null
fi

# Default to Auto mode if still not set
enableWallDcol="${enableWallDcol:-1}"

# Mode definitions
colorModes=("Theme" "Auto" "Dark" "Light")
mode="Unknown"
if [[ "${enableWallDcol}" =~ ^[0-9]+$ ]] && [ "${enableWallDcol}" -ge 0 ] && [ "${enableWallDcol}" -lt "${#colorModes[@]}" ]; then
  mode="${colorModes[${enableWallDcol}]}"
fi

# Icons for each mode
case "${enableWallDcol}" in
  0) icon="󱥚" ;; # Theme mode - palette icon
  1) icon="󰔎" ;; # Auto mode - auto/wand icon
  2) icon="" ;; # Dark mode - moon icon
  3) icon="󰖙" ;; # Light mode - sun icon
  *) icon="󰏘" ;;
esac

# Output JSON for waybar
cat <<EOF
{ "text": "${icon}", "tooltip": "Color Mode: ${mode}", "class": "colormode-${enableWallDcol}", "alt": "${mode}" }
EOF

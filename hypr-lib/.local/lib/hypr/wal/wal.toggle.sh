#!/usr/bin/env bash

#// set variables

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

# Lock file to prevent concurrent mode switching
MODE_SWITCH_LOCK="${XDG_RUNTIME_DIR:-/tmp}/mode-switch.lock"
exec 203>"${MODE_SWITCH_LOCK}"
! flock -n 203 && {
  print_log -sec "wal.toggle" -stat "wait" "Another mode operation in progress, waiting..."
  flock 203
}
trap 'flock -u 203 2>/dev/null' EXIT

colorModes=("Theme" "Auto" "Dark" "Light" "Auto Detect")

# Read current mode
[ -f "$HYPR_STATE_HOME/config" ] && source "$HYPR_STATE_HOME/config"
enableWallDcol="${enableWallDcol:-1}"

# Rofi selector
rofi_pywal16() {
  pkill -u "$USER" rofi && exit 0
  font_scale=$ROFI_PYWAL16_SCALE
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}
  font_name=${ROFI_PYWAL16_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}
  r_scale="configuration {font: \"${font_name} ${font_scale}\";}"
  hypr_border="${hypr_border:-5}"
  elem_border=$((hypr_border * 4))
  r_override="prompt{border-radius:${hypr_border}px;} textbox-prompt-colon {border-radius:${hypr_border}px;} window{border-radius:${elem_border}px;} element{border-radius:${hypr_border}px;}"
  rofiSel=$(parallel echo {} ::: "${colorModes[@]}" | rofi -dmenu \
    -theme-str "${r_scale}" \
    -theme-str "${r_override}" \
    -theme-str 'textbox-prompt-colon {str: "";}' \
    -p "Color Mode" \
    -theme "${XDG_CONFIG_HOME:-$HOME/.config}/rofi/pywal16.rasi" \
    -select "${colorModes[${enableWallDcol}]}")
  if [ ! -z "${rofiSel}" ]; then
    setMode="$(parallel --link echo {} ::: "${!colorModes[@]}" ::: "${colorModes[@]}" ::: "${rofiSel}" | awk '{if ($2 == $3) print $1}')"
  else
    exit 0
  fi
}

#// switch mode

step_pywal16() {
  for i in "${!colorModes[@]}"; do
    if [ "${enableWallDcol}" == "${i}" ]; then
      if [ "${1}" == "n" ]; then
        setMode=$(((i + 1) % ${#colorModes[@]}))
      elif [ "${1}" == "p" ]; then
        setMode=$((i - 1))
      fi
      break
    fi
  done
}

#// apply pywal16 mode

case "${1}" in
  m | -m | --menu) rofi_pywal16 ;;
  n | -n | --next) step_pywal16 n ;;
  p | -p | --prev) step_pywal16 p ;;
  *) step_pywal16 n ;;
esac

export reload_flag=1
[[ "${setMode}" -lt 0 ]] && setMode=$((${#colorModes[@]} - 1))

if [ -z "${setMode}" ]; then
  echo "Error: setMode not set"
  exit 1
fi

set_conf "enableWallDcol" "${setMode}"

# Handle Auto Detect mode (enableWallDcol=4)
if [ "${setMode}" -eq 4 ]; then
  # Start auto_theme daemon if not running
  if ! systemctl --user is-active auto-theme.service &>/dev/null; then
    systemctl --user start auto-theme.service 2>/dev/null || {
      # Fallback: run daemon directly if systemd service not available
      "${HOME}/.local/state/hypr/pip_env/bin/python" "${HOME}/.local/lib/hypr/theme/auto_theme.py" --once
    }
  fi
  # Run once immediately to apply current state
  "${HOME}/.local/state/hypr/pip_env/bin/python" "${HOME}/.local/lib/hypr/theme/auto_theme.py" --once 2>/dev/null
else
  # Stop auto_theme daemon when switching away from Auto Detect mode
  systemctl --user stop auto-theme.service 2>/dev/null || true
fi

"${LIB_DIR}/hypr/theme/theme.switch.sh"
notify-send -a "Pywal16" -i "${ICONS_DIR}/hypr.png" " ${colorModes[setMode]} mode"
pkill -RTMIN+8 waybar # Update waybar colormode indicator

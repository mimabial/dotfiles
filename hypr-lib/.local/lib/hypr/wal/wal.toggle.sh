#!/usr/bin/env bash

#// set variables

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
elif ! declare -F set_conf >/dev/null; then
  # HYPR_SHELL_INIT can be exported from non-bash shells; ensure functions exist.
  if [[ -r "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh" ]]; then
    # shellcheck disable=SC1090
    source "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh"
  else
    eval "$(hyprshell init)"
  fi
fi

# Lock file to prevent concurrent mode switching
MODE_SWITCH_LOCK="${XDG_RUNTIME_DIR:-/tmp}/mode-switch.lock"
exec 203>"${MODE_SWITCH_LOCK}"
! flock -n 203 && {
  print_log -sec "wal.toggle" -stat "wait" "Another mode operation in progress, waiting..."
  flock 203
}
trap 'flock -u 203 2>/dev/null' EXIT

colorModes=("Theme" "Auto" "Dark" "Light")
AUTO_THEME_PY="${HOME}/.local/lib/hypr/theme/auto_theme.py"

# Read current mode (prefer staterc, fall back to config)
[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc" ] && source "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc"
if [ -z "${enableWallDcol}" ]; then
  [ -f "$HYPR_STATE_HOME/config" ] && source "$HYPR_STATE_HOME/config"
fi
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
  rofiSel=$(printf '%s\n' "${colorModes[@]}" | rofi -dmenu \
    -theme-str "${r_scale}" \
    -theme-str "${r_override}" \
    -theme-str 'textbox-prompt-colon {str: "";}' \
    -p "Color Mode" \
    -theme "${XDG_CONFIG_HOME:-$HOME/.config}/rofi/pywal16.rasi" \
    -select "${colorModes[${enableWallDcol}]}")
  if [[ -n "${rofiSel}" ]]; then
    # Find index of selected mode
    for i in "${!colorModes[@]}"; do
      [[ "${colorModes[i]}" == "${rofiSel}" ]] && setMode="$i" && break
    done
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
        setMode=$(((i - 1 + ${#colorModes[@]}) % ${#colorModes[@]}))
      fi
      break
    fi
  done
}

set_mode_from_arg() {
  local mode_arg="$1"
  if [[ -z "${mode_arg}" ]]; then
    echo "Error: --set requires a mode (theme|auto|dark|light|0-3)"
    exit 1
  fi

  case "${mode_arg,,}" in
    0 | theme) setMode=0 ;;
    1 | auto) setMode=1 ;;
    2 | dark) setMode=2 ;;
    3 | light) setMode=3 ;;
    *)
      echo "Error: invalid mode: ${mode_arg}"
      echo "Valid modes: theme, auto, dark, light (or 0-3)"
      exit 1
      ;;
  esac
}

resolve_auto_theme_python() {
  local venv_py="${HOME}/.local/state/hypr/pip_env/bin/python"
  if [[ -x "${venv_py}" ]]; then
    echo "${venv_py}"
    return 0
  fi
  if command -v python3 &>/dev/null; then
    echo "python3"
    return 0
  fi
  if command -v python &>/dev/null; then
    echo "python"
    return 0
  fi
  return 1
}

auto_theme_pid_running() {
  local pidfile pid
  for pidfile in /tmp/auto_theme_*.pid; do
    [[ -e "${pidfile}" ]] || break
    pid="$(cat "${pidfile}" 2>/dev/null)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      return 0
    fi
    rm -f "${pidfile}" 2>/dev/null || true
  done
  return 1
}

start_auto_theme_fallback() {
  auto_theme_pid_running && return 0
  local python_bin
  python_bin="$(resolve_auto_theme_python)" || {
    print_log -sec "wal.toggle" -warn "auto" "python not found, cannot start daemon"
    return 1
  }
  if [[ ! -f "${AUTO_THEME_PY}" ]]; then
    print_log -sec "wal.toggle" -warn "auto" "missing ${AUTO_THEME_PY}"
    return 1
  fi
  nohup "${python_bin}" "${AUTO_THEME_PY}" >/dev/null 2>&1 &
}

stop_auto_theme_fallback() {
  local pidfile pid
  for pidfile in /tmp/auto_theme_*.pid; do
    [[ -e "${pidfile}" ]] || break
    pid="$(cat "${pidfile}" 2>/dev/null)"
    if [[ -n "${pid}" ]]; then
      kill "${pid}" 2>/dev/null || true
    fi
    rm -f "${pidfile}" 2>/dev/null || true
  done
}

auto_theme_run_once() {
  local python_bin
  python_bin="$(resolve_auto_theme_python)" || {
    print_log -sec "wal.toggle" -warn "auto" "python not found, cannot apply"
    return 1
  }
  if [[ ! -f "${AUTO_THEME_PY}" ]]; then
    print_log -sec "wal.toggle" -warn "auto" "missing ${AUTO_THEME_PY}"
    return 1
  fi
  "${python_bin}" "${AUTO_THEME_PY}" --once 2>/dev/null
}

resolve_wallpaper() {
  local resolved_path=""
  local cache_wall="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.set"
  if [ -e "${cache_wall}" ]; then
    resolved_path="$(readlink -f "${cache_wall}")"
    # Verify resolved path exists
    if [ -f "${resolved_path}" ]; then
      echo "${resolved_path}"
      return 0
    fi
  fi

  local theme="${HYPR_THEME:-}"
  if [ -z "${theme}" ] && [ -r "${HYPR_STATE_HOME}/staterc" ]; then
    theme="$(awk -F= '/^HYPR_THEME=/{gsub(/"/,"",$2);print $2; exit}' "${HYPR_STATE_HOME}/staterc")"
  fi
  if [ -z "${theme}" ] && [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/wal.conf" ]; then
    theme="$(awk -F= '/^\\$HYPR_THEME=/{gsub(/"/,"",$2);print $2; exit}' "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/wal.conf")"
  fi

  if [ -n "${theme}" ]; then
    local theme_wall="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/${theme}/wall.set"
    if [ -e "${theme_wall}" ]; then
      resolved_path="$(readlink -f "${theme_wall}")"
      # Verify resolved path exists
      if [ -f "${resolved_path}" ]; then
        echo "${resolved_path}"
        return 0
      fi
    fi
  fi

  return 1
}

apply_color_mode() {
  local wallpaper
  local state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/color.gen.state"

  wallpaper="$(resolve_wallpaper)" || return 1

  if [ "${setMode}" -eq 2 ] || [ "${setMode}" -eq 3 ]; then
    local target_mode="dark"
    [ "${setMode}" -eq 3 ] && target_mode="light"

    if [ -r "${state_file}" ]; then
      local state_wall state_mode state_colormode
      state_wall="$(awk -F= '/^wallpaper=/{print $2; exit}' "${state_file}")"
      state_mode="$(awk -F= '/^mode=/{print $2; exit}' "${state_file}")"
      state_colormode="$(awk -F= '/^colormode=/{print $2; exit}' "${state_file}")"
      if [ "${state_wall}" == "${wallpaper}" ] && [ "${state_mode}" == "${target_mode}" ]; then
        if [ -n "${state_colormode}" ] && [ "${state_colormode}" != "0" ]; then
          print_log -sec "wal.toggle" -stat "skip" "colors already ${target_mode}"
          return 0
        fi
      fi
    fi
  fi

  if [ "${setMode}" -eq 2 ] || [ "${setMode}" -eq 3 ]; then
    HYPR_WAL_ASYNC_APPS=1 "${LIB_DIR}/hypr/theme/color.set.sh" "${wallpaper}"
  else
    "${LIB_DIR}/hypr/theme/color.set.sh" "${wallpaper}"
  fi

  # Sync nvim after colors are generated
  [[ -x "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" ]] && "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" >/dev/null 2>&1 &
}

#// apply pywal16 mode

case "${1}" in
  m | -m | --menu) rofi_pywal16 ;;
  n | -n | --next) step_pywal16 n ;;
  p | -p | --prev) step_pywal16 p ;;
  -s | --set) set_mode_from_arg "${2}" ;;
  --set=*) set_mode_from_arg "${1#--set=}" ;;
  *) step_pywal16 n ;;
esac

export reload_flag=1
[[ "${setMode}" -lt 0 ]] && setMode=$((${#colorModes[@]} - 1))

if [ -z "${setMode}" ]; then
  echo "Error: setMode not set"
  exit 1
fi

set_conf "enableWallDcol" "${setMode}"

# Auto mode uses auto_theme daemon
if [ "${setMode}" -eq 1 ]; then
  # Start auto_theme daemon if not running
  if ! systemctl --user is-active auto-theme.service &>/dev/null; then
    systemctl --user start auto-theme.service 2>/dev/null || {
      # Fallback: run daemon directly if systemd service not available
      start_auto_theme_fallback
    }
  fi
  # Run once immediately to apply current state
  auto_theme_run_once
else
  # Stop auto_theme daemon when switching away from Auto mode
  systemctl --user stop auto-theme.service 2>/dev/null || true
  stop_auto_theme_fallback
  if ! apply_color_mode; then
    print_log -sec "wal.toggle" -warn "wallpaper" "no current wallpaper, falling back to theme switch"
    "${LIB_DIR}/hypr/theme/theme.switch.sh"
  fi
fi

pkill -RTMIN+8 waybar # Update waybar colormode indicator

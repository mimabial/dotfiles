#!/usr/bin/env bash
# Requires bash 4+ for dynamic exec {fd}> lock descriptors.
#
# color-mode.sh - Color mode controller for theme/wallpaper color policy.
#
# Handles:
#   - interactive menu / next / previous / explicit mode selection
#   - selected_color_mode state updates
#   - auto-theme daemon start/stop coordination

#// set variables

set -euo pipefail

# shellcheck source=/dev/null
source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"
export_hypr_config

hypr_help_guard "Usage: hyprshell theme/color-mode [-q] [m|n|p|--set <theme|auto|dark|light|0-3>]
Switch the colour mode: menu (m), next (n), prev (p), or explicit --set (default: next)." "$@"

color_mode_labels=("Theme" "Auto" "Dark" "Light")
MODE_SWITCH_LOCK_FD=""
COLOR_MODE_NOTIFY_ID="${COLOR_MODE_NOTIFY_ID:-95}"
COLOR_MODE_NOTIFY_STACK_TAG="${COLOR_MODE_NOTIFY_STACK_TAG:-color-mode}"
color_mode_notify=1

color_mode_resolve_existing_path() {
  local path="$1"
  local resolved_dir=""

  [[ -e "${path}" ]] || return 1

  if command -v realpath >/dev/null 2>&1; then
    realpath "${path}"
    return
  fi

  if command -v readlink >/dev/null 2>&1; then
    readlink -f "${path}" 2>/dev/null && return
  fi

  resolved_dir="$(cd "$(dirname "${path}")" && pwd -P)" || return 1
  printf '%s/%s\n' "${resolved_dir}" "$(basename "${path}")"
}

color_mode_load_selected_color_mode() {
  if declare -F state_get >/dev/null 2>&1; then
    selected_color_mode="$(state_get "selected_color_mode" "1")"
  else
    selected_color_mode="1"
  fi

  [[ "${selected_color_mode}" =~ ^[0-3]$ ]] || selected_color_mode=1
}

color_mode_load_selected_color_mode

rofi_color_mode_script_mode() {
  case "${ROFI_RETV:-0}" in
    0)
      printf '\0prompt\x1fColor Mode\n'
      printf '\0no-custom\x1ftrue\n'
      printf '%s\n' "${color_mode_labels[@]}"
      ;;
    1)
      [[ -n "${ROFI_COLOR_MODE_OUT:-}" ]] && printf '%s\n' "$1" >"${ROFI_COLOR_MODE_OUT}"
      ;;
  esac
}

if [[ "${1:-}" == "--rofi-script-mode" ]]; then
  rofi_color_mode_script_mode "${2:-}"
  exit 0
fi

acquire_mode_switch_lock() {
  MODE_SWITCH_LOCK="$(hypr_lock_path mode_switch)"
  # Keep the mode-switch lock FD dynamic so the lock ownership is explicit and
  # we do not depend on an unexplained fixed descriptor number.
  exec {MODE_SWITCH_LOCK_FD}>"${MODE_SWITCH_LOCK}"
  ! flock -n "${MODE_SWITCH_LOCK_FD}" && {
    print_log -sec "color-mode" -stat "wait" "Another mode operation in progress, waiting..."
    flock "${MODE_SWITCH_LOCK_FD}"
  }
  trap 'color_mode_release_lock "$?"' EXIT
}

color_mode_release_lock() {
  local exit_code="${1:-$?}"
  if [[ -n "${MODE_SWITCH_LOCK_FD}" ]]; then
    flock -u "${MODE_SWITCH_LOCK_FD}" 2>/dev/null || true
    exec {MODE_SWITCH_LOCK_FD}>&-
    MODE_SWITCH_LOCK_FD=""
  fi
  return "${exit_code}"
}

# Rofi selector
select_color_mode_with_rofi() {
  local selection_file=""
  local script_path=""
  local rofi_mode_name="color-mode"
  local font_scale=""
  local font_name=""
  local r_scale=""
  local r_override=""
  local rofi_theme_file=""
  local width_override=""
  local margin_px=""
  local selected_color_mode_label=""
  local -a width_override_args=()
  local i=""

  pkill -u "$USER" rofi && exit 0
  font_scale="$(rofi_effective_font_scale "${ROFI_LAUNCH_SCALE:-${ROFI_PYWAL16_SCALE:-}}")"
  font_name="$(rofi_effective_font_name "${ROFI_LAUNCH_FONT:-${ROFI_PYWAL16_FONT:-${ROFI_FONT:-}}}")"
  r_scale="$(rofi_font_override "${font_name}" "${font_scale}")"
  local launch_style suffix
  launch_style="$(state_get "ROFI_LAUNCH_STYLE" "style_11")"
  suffix="${launch_style#style_}"
  [[ "${suffix}" =~ ^[0-9]+$ ]] || suffix=11
  rofi_theme_file="$(rofi_resolve_theme "color_mode_${suffix}" 2>/dev/null || true)"
  [[ -f "${rofi_theme_file}" ]] || rofi_theme_file="$(rofi_resolve_theme color_mode_11)"
  r_override="$(rofi_window_override "${rofi_theme_file}")"
  margin_px="${ROFI_PYWAL16_MARGIN_PX:-${ROFI_PYWAL16_MARGIN:-0}}"
  [[ "${margin_px}" =~ ^[0-9]+$ ]] || margin_px=0
  width_override="$(rofi_wallpaper_width_override "${rofi_theme_file}" "${font_name}" "${font_scale}" "${margin_px}" 2>/dev/null || true)"
  if [[ -n "${width_override}" ]]; then
    width_override_args=(-theme-str "${width_override}")
  fi

  selection_file="$(mktemp "${TMPDIR:-/tmp}/rofi-color-mode.XXXXXX")" || exit 1
  script_path="$(color_mode_resolve_existing_path "${BASH_SOURCE[0]}" || printf '%s\n' "${BASH_SOURCE[0]}")"

  selected_color_mode_label="$(
    ROFI_COLOR_MODE_OUT="${selection_file}" rofi \
      -show "${rofi_mode_name}" \
      -modi "${rofi_mode_name}:${script_path} --rofi-script-mode" \
      -theme-str "${r_scale}" \
      -theme-str "${r_override}" \
      "${width_override_args[@]}" \
      -theme-str 'textbox-prompt-colon {str: "";}' \
      -theme "${rofi_theme_file}" \
      -selected-row "${selected_color_mode}"
  )"

  if [[ -z "${selected_color_mode_label}" && -s "${selection_file}" ]]; then
    selected_color_mode_label="$(<"${selection_file}")"
  fi
  rm -f "${selection_file}"

  if [[ -n "${selected_color_mode_label}" ]]; then
    for i in "${!color_mode_labels[@]}"; do
      [[ "${color_mode_labels[i]}" == "${selected_color_mode_label}" ]] && target_color_mode="$i" && break
    done
  else
    exit 0
  fi
}

#// switch mode

cycle_color_mode() {
  local i=""
  for i in "${!color_mode_labels[@]}"; do
    if [ "${selected_color_mode}" == "${i}" ]; then
      if [ "${1}" == "n" ]; then
        target_color_mode=$(((i + 1) % ${#color_mode_labels[@]}))
      elif [ "${1}" == "p" ]; then
        target_color_mode=$(((i - 1 + ${#color_mode_labels[@]}) % ${#color_mode_labels[@]}))
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
    0 | theme) target_color_mode=0 ;;
    1 | auto) target_color_mode=1 ;;
    2 | dark) target_color_mode=2 ;;
    3 | light) target_color_mode=3 ;;
    *)
      echo "Error: invalid mode: ${mode_arg}"
      echo "Valid modes: theme, auto, dark, light (or 0-3)"
      exit 1
      ;;
  esac
}

auto_theme_systemd_available() {
  command -v systemctl &>/dev/null || return 1
  systemctl --user show-environment &>/dev/null
}

start_auto_theme_service() {
  if ! auto_theme_systemd_available; then
    print_log -sec "color-mode" -warn "auto" "systemd --user unavailable, auto-theme.service is required"
    return 1
  fi

  systemctl --user start auto-theme.service 2>/dev/null || {
    print_log -sec "color-mode" -warn "auto" "failed to start auto-theme.service"
    return 1
  }
}

refresh_auto_theme_service() {
  auto_theme_systemd_available || return 0
  systemctl --user kill -s USR2 auto-theme.service 2>/dev/null || true
}

stop_auto_theme_service() {
  if auto_theme_systemd_available; then
    systemctl --user stop auto-theme.service 2>/dev/null || true
  fi
}

resolve_wallpaper() {
  local resolved_path=""
  local cache_wall="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.set"
  if [ -e "${cache_wall}" ]; then
    resolved_path="$(color_mode_resolve_existing_path "${cache_wall}" || true)"
    # Verify resolved path exists
    if [ -f "${resolved_path}" ]; then
      echo "${resolved_path}"
      return 0
    fi
  fi

  local theme="${HYPR_THEME:-}"
  if [[ -z "${theme}" ]] && declare -F state_get >/dev/null 2>&1; then
    theme="$(state_get "HYPR_THEME" "")"
  fi

  if [[ -z "${theme}" ]]; then
    print_log -sec "color-mode" -err "wallpaper" "HYPR_THEME is not set"
    return 1
  fi

  local theme_wall="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/${theme}/wall.set"
  if [ -e "${theme_wall}" ]; then
    resolved_path="$(color_mode_resolve_existing_path "${theme_wall}" || true)"
    # Verify resolved path exists
    if [ -f "${resolved_path}" ]; then
      echo "${resolved_path}"
      return 0
    fi
  fi

  return 1
}

apply_color_mode() {
  local wallpaper
  local target_mode="dark"
  local hypr_theme_cmd=""

  hypr_theme_cmd="$(command -v hypr-theme || true)"
  [[ -n "${hypr_theme_cmd}" ]] || {
    print_log -sec "color-mode" -err "hypr-theme" "command not found"
    return 1
  }

  if [ "${target_color_mode}" -eq 0 ]; then
    "${hypr_theme_cmd}" apply "${HYPR_THEME}"
    return $?
  fi

  wallpaper="$(resolve_wallpaper)" || return 1

  case "${target_color_mode}" in
    2) target_mode="dark" ;;
    3) target_mode="light" ;;
    *)
      target_mode="$(state_get_color_variant 2>/dev/null || true)"
      [[ "${target_mode}" =~ ^(dark|light)$ ]] || target_mode="${BACKGROUND_MODE:-}"
      [[ "${target_mode}" =~ ^(dark|light)$ ]] || target_mode="dark"
      ;;
  esac

  state_set "BACKGROUND_MODE" "${target_mode}" "staterc"
  state_set_color_variant "${target_mode}"

  "${hypr_theme_cmd}" wallpaper --variant "${target_mode}" "${wallpaper}"

  if ! hypr_user_pgrep -x waybar >/dev/null 2>&1; then
    local waybar_script="${LIB_DIR}/hypr/waybar/waybar.py"
    if [[ -x "${waybar_script}" ]]; then
      "${waybar_script}" --restart-direct >/dev/null 2>&1 \
        || print_log -sec "color-mode" -warn "waybar" "start failed"
    fi
  fi

}

parse_target_mode() {
  case "${1:-}" in
    m | -m | --menu) select_color_mode_with_rofi ;;
    n | -n | --next) cycle_color_mode n ;;
    p | -p | --prev) cycle_color_mode p ;;
    -s | --set) set_mode_from_arg "${2:-}" ;;
    --set=*) set_mode_from_arg "${1#--set=}" ;;
    *) cycle_color_mode n ;;
  esac

  [[ "${target_color_mode}" -lt 0 ]] && target_color_mode=$((${#color_mode_labels[@]} - 1))
  if [ -z "${target_color_mode:-}" ]; then
    echo "Error: target_color_mode not set"
    exit 1
  fi
}

load_previous_color_mode() {
  previous_color_mode="${selected_color_mode}"
  if [[ ! "${previous_color_mode}" =~ ^[0-3]$ ]]; then
    previous_color_mode=1
  fi
}

notify_waybar_color_mode() {
  pkill -RTMIN+8 waybar >/dev/null 2>&1 || true
}

notify_color_mode_changed() {
  [[ "${color_mode_notify}" -eq 1 ]] || return 0
  local label="${color_mode_labels[target_color_mode]:-${target_color_mode}}"
  local -a args=(-a "Color mode" -t 2000 -i "preferences-desktop-theme")

  if command -v dunstify >/dev/null 2>&1; then
    dunstify "${args[@]}" -r "${COLOR_MODE_NOTIFY_ID}" --stack-tag "${COLOR_MODE_NOTIFY_STACK_TAG}" \
      "Color mode" "${label}" >/dev/null 2>&1 || true
    return 0
  fi

  notify_send_safe "${args[@]}" \
    -h "string:x-canonical-private-synchronous:${COLOR_MODE_NOTIFY_STACK_TAG}" \
    "Color mode" "${label}" >/dev/null 2>&1 || true
}

revert_failed_auto_mode() {
  print_log -sec "color-mode" -warn "auto" "activation failed, reverting mode"
  target_color_mode="${previous_color_mode}"
  state_set "selected_color_mode" "${target_color_mode}" "staterc"
  if [ "${target_color_mode}" -ne 1 ]; then
    stop_auto_theme_service
    apply_color_mode || exit 1
  fi
  notify_waybar_color_mode
  exit 1
}

apply_auto_mode() {
  state_set "selected_color_mode" "${target_color_mode}" "staterc"
  start_auto_theme_service || revert_failed_auto_mode
  refresh_auto_theme_service
}

apply_manual_mode() {
  stop_auto_theme_service
  state_set "selected_color_mode" "${target_color_mode}" "staterc"
  if ! apply_color_mode; then
    state_set "selected_color_mode" "${previous_color_mode}" "staterc"
    notify_waybar_color_mode
    exit 1
  fi
}

main() {
  acquire_mode_switch_lock
  if [[ "${1:-}" == "-q" || "${1:-}" == "--quiet" ]]; then
    color_mode_notify=0
    shift
  fi
  parse_target_mode "$@"
  load_previous_color_mode

  if [ "${target_color_mode}" -eq 1 ]; then
    apply_auto_mode
  else
    apply_manual_mode
  fi

  notify_waybar_color_mode
  notify_color_mode_changed
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/controls/lib/brightness.common.bash"

readonly BRIGHTNESS_DIM_PERCENT=1
readonly KEYBOARD_BACKLIGHT_DEVICE='*::kbd_backlight'

keyboard_backlight_ctl() {
  compgen -G "/sys/class/leds/${KEYBOARD_BACKLIGHT_DEVICE}" >/dev/null || return 0
  brightnessctl -d "${KEYBOARD_BACKLIGHT_DEVICE}" "$@" >/dev/null
}

usage() {
  printf 'Usage: %s <dim|restore>\n' "${0##*/}"
}

read_current_brightness_raw_into() {
  local -n brightness_raw_ref="$1"
  local _device _class

  IFS=, read -r _device _class brightness_raw_ref _ < <(brightnessctl -m 2>/dev/null)
}

save_idle_brightness() {
  local state_file="$1"
  local runtime_dir="$2"
  local current_brightness=""

  [[ -e "${state_file}" ]] && return 0
  read_current_brightness_raw_into current_brightness
  [[ "${current_brightness}" =~ ^[0-9]+$ ]] || return 1

  mkdir -p "${runtime_dir}"
  printf '%s\n' "${current_brightness}" >"${state_file}"
}

restore_idle_brightness() {
  local state_file="$1"
  local saved_brightness=""

  [[ -r "${state_file}" ]] || return 1
  saved_brightness="$(<"${state_file}")"
  [[ "${saved_brightness}" =~ ^[0-9]+$ ]] || return 1

  brightnessctl s "${saved_brightness}" >/dev/null
  rm -f "${state_file}"
}

main() {
  local action="${1:-}"
  local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
  local state_file="${runtime_dir}/brightness-idle.raw"

  brightness_idle_enabled || return 0

  case "${action}" in
    dim)
      save_idle_brightness "${state_file}" "${runtime_dir}"
      brightnessctl s "${BRIGHTNESS_DIM_PERCENT}%" >/dev/null
      keyboard_backlight_ctl --save set 0
      ;;
    restore)
      restore_idle_brightness "${state_file}" || brightnessctl -r >/dev/null
      keyboard_backlight_ctl --restore
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"

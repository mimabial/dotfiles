#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${script_dir}/lib/brightness.common.bash"

action="${1:-}"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
brightness_idle_state_file="${runtime_dir}/brightness-idle.raw"

brightness_idle_enabled || exit 0

read_current_brightness_raw() {
  brightnessctl -m 2>/dev/null | awk -F, 'NR == 1 { print $3; exit }'
}

save_idle_brightness() {
  local current_brightness=""

  [[ -e "${brightness_idle_state_file}" ]] && return 0
  current_brightness="$(read_current_brightness_raw)"
  [[ "${current_brightness}" =~ ^[0-9]+$ ]] || return 1

  mkdir -p "${runtime_dir}"
  printf '%s\n' "${current_brightness}" >"${brightness_idle_state_file}"
}

restore_idle_brightness() {
  local saved_brightness=""

  [[ -r "${brightness_idle_state_file}" ]] || return 1
  saved_brightness="$(<"${brightness_idle_state_file}")"
  [[ "${saved_brightness}" =~ ^[0-9]+$ ]] || return 1

  brightnessctl s "${saved_brightness}" >/dev/null
  rm -f "${brightness_idle_state_file}"
}

case "${action}" in
  dim)
    save_idle_brightness
    brightnessctl s 1% >/dev/null
    ;;
  restore)
    restore_idle_brightness || brightnessctl -r >/dev/null
    ;;
  *)
    exit 2
    ;;
esac

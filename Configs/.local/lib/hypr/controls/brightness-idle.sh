#!/usr/bin/env bash
#
# brightness-idle.sh — Save/restore screen brightness around idle dimming.
#
# Usage: brightness-idle.sh <dim|restore>
#
# Depends on: brightnessctl, controls/lib/brightness.common.bash, runtime/init.bash
#
set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/controls/lib/brightness.common.bash"

readonly BRIGHTNESS_DIM_PERCENT=1

usage() {
  cat <<EOF
Usage: $(basename "$0") <dim|restore>
EOF
}

read_current_brightness_raw() {
  brightnessctl -m 2>/dev/null | awk -F, 'NR == 1 { print $3; exit }'
}

save_idle_brightness() {
  local state_file="$1"
  local runtime_dir="$2"
  local current_brightness=""

  [[ -e "${state_file}" ]] && return 0
  current_brightness="$(read_current_brightness_raw)"
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
      ;;
    restore)
      restore_idle_brightness "${state_file}" || brightnessctl -r >/dev/null
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"

#!/usr/bin/env bash
set -u

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/controls/lib/brightness.common.bash"

readonly BRIGHTNESS_DEFAULT_STEP=5
readonly BRIGHTNESS_FINE_STEP=1
readonly BRIGHTNESS_LOW_THRESHOLD=10
readonly BRIGHTNESS_VERY_LOW_THRESHOLD=1

usage() {
  local cmd="${0##*/}"
  cat <<EOF
Usage: ${cmd} <action> [step]

Actions:
  i | -i   Increase brightness
  d | -d   Decrease brightness

Examples:
  ${cmd} i 10
  ${cmd} d
EOF
}

brightness_percent_into() {
  local -n brightness_percent_ref="$1"
  local _device _class _raw percent_field _max
  IFS=, read -r _device _class _raw percent_field _max <<<"$2"
  brightness_percent_ref="$((10#${percent_field%%%}))"
}

notify_unavailable() {
  command -v dunstify >/dev/null 2>&1 || return 0
  dunstify -a "Brightness control" -r "${NOTIFY_ID_BRIGHTNESS_UNAVAILABLE}" -t "${NOTIFY_OSD_ALERT_MS}" \
    "Brightness unavailable" "$(brightness_unavailable_reason)"
}

notify_brightness() {
  local notify_enabled="$1"
  local info="$2"
  local percent=""

  is_true "${notify_enabled}" || return 0
  command -v dunstify >/dev/null 2>&1 || return 0

  [[ -n "${info}" ]] || info="$(brightnessctl -m 2>/dev/null)" || return 0
  brightness_percent_into percent "${info}"
  notify_level "Brightness control" "${NOTIFY_ID_BRIGHTNESS}" "${percent}" "${info%%,*}"
}

apply_increase() {
  local -n applied_info_ref="$1"
  local step="$2" current="$3"
  ((current < BRIGHTNESS_LOW_THRESHOLD)) && step=${BRIGHTNESS_FINE_STEP}
  applied_info_ref="$(brightnessctl -m set +"${step}%")"
}

apply_decrease() {
  local -n applied_info_ref="$1"
  local step="$2" current="$3"
  ((current <= BRIGHTNESS_LOW_THRESHOLD)) && step=${BRIGHTNESS_FINE_STEP}
  if ((current <= BRIGHTNESS_VERY_LOW_THRESHOLD)); then
    applied_info_ref="$(brightnessctl -m set "${step}%")"
  else
    applied_info_ref="$(brightnessctl -m set "${step}%-")"
  fi
}

main() {
  local notify_enabled="${BRIGHTNESS_NOTIFY:-true}"
  local default_step="${BRIGHTNESS_STEPS:-${BRIGHTNESS_DEFAULT_STEP}}"
  local action="${1:-}"
  local step="${2:-${default_step}}"
  local info="" current=""

  [[ "${action}" == -h || "${action}" == --help ]] && { usage; return; }

  if ! require_cmd brightnessctl || ! info="$(brightnessctl -m 2>/dev/null)"; then
    notify_unavailable
    return 0
  fi
  brightness_percent_into current "${info}"

  if [[ ! "${step}" =~ ^[0-9]+$ ]]; then
    print_log -sec "brightness" -err "step" "Invalid step: ${step}"
    usage >&2
    return 2
  fi

  case "${action}" in
    i | -i)
      apply_increase info "${step}" "${current}"
      notify_brightness "${notify_enabled}" "${info}"
      ;;
    d | -d)
      apply_decrease info "${step}" "${current}"
      notify_brightness "${notify_enabled}" "${info}"
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"

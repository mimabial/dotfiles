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

brightness_percent() {
  local _device _class _raw percent _max
  IFS=, read -r _device _class _raw percent _max <<<"$1"
  printf '%s\n' "$((10#${percent%%%}))"
}

notify_unavailable() {
  command -v dunstify >/dev/null 2>&1 || return 0
  dunstify -a "Brightness control" -r "${NOTIFY_ID_BRIGHTNESS_UNAVAILABLE}" -t "${NOTIFY_OSD_ALERT_MS}" \
    "Brightness unavailable" "$(brightness_unavailable_reason)"
}

notify_brightness() {
  local notify_enabled="$1"
  local info=""

  is_true "${notify_enabled}" || return 0
  command -v dunstify >/dev/null 2>&1 || return 0

  info="$(brightnessctl -m 2>/dev/null)" || return 0
  notify_level "Brightness control" "${NOTIFY_ID_BRIGHTNESS}" "$(brightness_percent "${info}")" "${info%%,*}"
}

apply_increase() {
  local step="$1" current="$2"
  ((current < BRIGHTNESS_LOW_THRESHOLD)) && step=${BRIGHTNESS_FINE_STEP}
  brightnessctl set +"${step}%" >/dev/null
}

apply_decrease() {
  local step="$1" current="$2"
  ((current <= BRIGHTNESS_LOW_THRESHOLD)) && step=${BRIGHTNESS_FINE_STEP}
  if ((current <= BRIGHTNESS_VERY_LOW_THRESHOLD)); then
    brightnessctl set "${step}%" >/dev/null
  else
    brightnessctl set "${step}%-" >/dev/null
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
  current="$(brightness_percent "${info}")"

  if [[ ! "${step}" =~ ^[0-9]+$ ]]; then
    print_log -sec "brightness" -err "step" "Invalid step: ${step}"
    usage >&2
    return 2
  fi

  case "${action}" in
    i | -i)
      apply_increase "${step}" "${current}"
      notify_brightness "${notify_enabled}"
      ;;
    d | -d)
      apply_decrease "${step}" "${current}"
      notify_brightness "${notify_enabled}"
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"

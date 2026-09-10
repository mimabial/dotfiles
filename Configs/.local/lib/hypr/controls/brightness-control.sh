#!/usr/bin/env bash
set -u

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/controls/lib/brightness.common.bash"

readonly BRIGHTNESS_NOTIFY_REPLACE_ID=7
readonly BRIGHTNESS_UNAVAILABLE_REPLACE_ID=9
readonly BRIGHTNESS_NOTIFY_TIMEOUT_MS=800
readonly BRIGHTNESS_UNAVAILABLE_TIMEOUT_MS=1200
readonly BRIGHTNESS_BAR_DIVISOR=15
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
  dunstify -a "Brightness control" -r "${BRIGHTNESS_UNAVAILABLE_REPLACE_ID}" -t "${BRIGHTNESS_UNAVAILABLE_TIMEOUT_MS}" \
    "Brightness unavailable" "$(brightness_unavailable_reason)"
}

notify_brightness() {
  local notify_enabled="$1"
  local info="" device_name="" _class _raw percent _max brightness=""
  local angle=0
  local icon=""
  local bar=""
  local icon_dir=""

  is_true "${notify_enabled}" || return 0
  command -v dunstify >/dev/null 2>&1 || return 0

  info="$(brightnessctl -m 2>/dev/null)" || return 0
  IFS=, read -r device_name _class _raw percent _max <<<"${info}"
  brightness="$((10#${percent%%%}))"
  angle=$((((brightness + 2) / 5) * 5))
  ((angle < 0)) && angle=0
  ((angle > 100)) && angle=100

  icon_dir="${ICONS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}"
  icon="${icon_dir}/Pywal16-Icon/media/knob-${angle}.svg"
  printf -v bar '%*s' "$((brightness / BRIGHTNESS_BAR_DIVISOR))" ''
  bar="${bar// /.}"

  dunstify -a "Brightness control" -r "${BRIGHTNESS_NOTIFY_REPLACE_ID}" -t "${BRIGHTNESS_NOTIFY_TIMEOUT_MS}" \
    -e -i "${icon}" "${brightness}${bar}" "${device_name}"
}

apply_increase() {
  local step="$1" current="$2"
  ((current < BRIGHTNESS_LOW_THRESHOLD)) && step=1
  brightnessctl set +"${step}%" >/dev/null
}

apply_decrease() {
  local step="$1" current="$2"
  ((current <= BRIGHTNESS_LOW_THRESHOLD)) && step=1
  if ((current <= BRIGHTNESS_VERY_LOW_THRESHOLD)); then
    brightnessctl set "${step}%" >/dev/null
  else
    brightnessctl set "${step}%-" >/dev/null
  fi
}

main() {
  local notify_enabled="${BRIGHTNESS_NOTIFY:-true}"
  local default_step="${BRIGHTNESS_STEPS:-5}"
  local action="${1:-}"
  local step="${2:-${default_step}}"
  local info="" current=""

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

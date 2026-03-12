#!/usr/bin/env bash

set -u

scr_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${scr_dir}/lib/control.common.bash"

is_notify="${BRIGHTNESS_NOTIFY:-true}"
default_step="${BRIGHTNESS_STEPS:-5}"

print_usage() {
  local cmd
  cmd="$(basename "$0")"
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

require_cmd brightnessctl || {
  echo "brightnessctl is required"
  exit 1
}

current_brightness() {
  brightnessctl -m | awk -F, 'NR==1 { gsub(/%/, "", $4); print $4 + 0 }'
}

brightness_device() {
  brightnessctl info | awk -F"'" '/Device/ { print $2; exit }'
}

send_notification() {
  is_true "${is_notify}" || return 0

  local brightness brightinfo angle icon bar icon_dir
  brightness="$(current_brightness)"
  brightinfo="$(brightness_device)"
  angle=$((((brightness + 2) / 5) * 5))
  ((angle < 0)) && angle=0
  ((angle > 100)) && angle=100

  icon_dir="${ICONS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}"
  icon="${icon_dir}/Pywal16-Icon/media/knob-${angle}.svg"
  bar="$(printf '%*s' $((brightness / 15)) '' | tr ' ' '.')"

  notify-send -a "Brightness control" -r 7 -t 800 -i "${icon}" "${brightness}${bar}" "${brightinfo}"
}

action="${1:-}"
step="${2:-${default_step}}"

if [[ ! "${step}" =~ ^[0-9]+$ ]]; then
  echo "Invalid step: ${step}"
  print_usage
  exit 1
fi

case "${action}" in
  i | -i)
    current="$(current_brightness)"
    ((current < 10)) && step=1
    brightnessctl set +"${step}%" >/dev/null
    send_notification
    ;;
  d | -d)
    current="$(current_brightness)"
    ((current <= 10)) && step=1
    if ((current <= 1)); then
      brightnessctl set "${step}%" >/dev/null
    else
      brightnessctl set "${step}%-" >/dev/null
    fi
    send_notification
    ;;
  *)
    print_usage
    exit 1
    ;;
esac

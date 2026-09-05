#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

usage='Usage: hyprshell system/monitor-brightness [--no-osd] --monitor OUTPUT [PERCENT]'
output=""
value=""
while (($#)); do
  case "$1" in
    --no-osd) shift ;;
    -m | --monitor) output="${2:-}"; shift 2 ;;
    [0-9]* | [0-9]*%) value="${1%\%}"; shift ;;
    *) printf '%s\n' "${usage}" >&2; exit 2 ;;
  esac
done
[[ -n "${output}" ]] || { printf '%s\n' "${usage}" >&2; exit 2; }
[[ -z "${value}" || "${value}" =~ ^[0-9]+$ ]] || { printf 'Invalid brightness: %s\n' "${value}" >&2; exit 2; }
if [[ -n "${value}" ]] && ((value < 1 || value > 100)); then
  printf 'Brightness must be between 1 and 100\n' >&2
  exit 2
fi

backlight_for_output() {
  local path="" target=""
  for path in /sys/class/backlight/*; do
    [[ -e "${path}" ]] || continue
    target="$(realpath "${path}" 2>/dev/null || true)"
    [[ "${target}" == *"/${output}/"* || "${target}" == *"-${output}/"* ]] || continue
    basename "${path}"
    return 0
  done
  return 1
}

ddc_bus_for_output() {
  local connector="" bus=""
  for connector in /sys/class/drm/card*-"${output}"; do
    [[ -e "${connector}" ]] || continue
    for bus in "${connector}"/ddc/i2c-dev/i2c-* "${connector}"/i2c-*/i2c-dev/i2c-*; do
      [[ -e "${bus}" ]] || continue
      basename "${bus}" | sed 's/^i2c-//'
      return 0
    done
  done
  return 1
}

device="$(backlight_for_output || true)"
if [[ -n "${device}" ]]; then
  if [[ -n "${value}" ]]; then
    brightnessctl -q -d "${device}" set "${value}%"
  else
    brightnessctl -m -d "${device}" | awk -F, '{gsub(/%/, "", $4); print $4; exit}'
  fi
  exit
fi

bus="$(ddc_bus_for_output || true)"
[[ -n "${bus}" && -x "$(command -v ddcutil 2>/dev/null || true)" ]] || {
  printf 'Brightness control is unavailable for %s\n' "${output}" >&2
  exit 1
}
if [[ -n "${value}" ]]; then
  ddcutil --noverify --bus "${bus}" setvcp 10 "${value}" >/dev/null
else
  read -r current maximum < <(ddcutil --brief --bus "${bus}" getvcp 10 | awk '/VCP 10/ {print $(NF-1), $NF; exit}')
  [[ "${current:-}" =~ ^[0-9]+$ && "${maximum:-}" =~ ^[0-9]+$ && "${maximum}" -gt 0 ]] || exit 1
  printf '%d\n' "$((current * 100 / maximum))"
fi

#!/usr/bin/env bash
# Colour comes from the reading
# NORMALISED to the sensor's critical point (temp*100/crit), so one ramp fits
# any chip: a value at its crit is always the hottest colour, whatever the
# chip's absolute limit.
# Callers without a known crit omit it, so crit defaults to 100 and the ramp is
# read as a plain degC scale (the long-standing cpu/gpu behaviour).
#
# The stops come from render/tempramp.py, which derives them from the active
# palette. The table below is only what the widgets show before the first theme
# apply has written one.
TEMP_RAMP_DEFAULT_CRITICAL_C=100
HYPR_TEMP_RAMP_FILE="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/tempramp/ramp.psv"

declare -A HYPR_TEMP_RAMP=()
HYPR_TEMP_RAMP_LOADED=0

load_temperature_ramp() {
  ((HYPR_TEMP_RAMP_LOADED)) && return 0
  HYPR_TEMP_RAMP_LOADED=1

  local threshold color
  if [[ -r "${HYPR_TEMP_RAMP_FILE}" ]]; then
    while IFS='|' read -r threshold color; do
      [[ "${threshold}" =~ ^[0-9]+$ ]] && HYPR_TEMP_RAMP["${threshold}"]="${color}"
    done <"${HYPR_TEMP_RAMP_FILE}"
  fi
  ((${#HYPR_TEMP_RAMP[@]})) && return 0

  HYPR_TEMP_RAMP=(
    [90]="#8b0000" [85]="#ad1f2f" [80]="#d22f2f" [75]="#ff471a"
    [70]="#ff6347" [65]="#ff8c00" [60]="#ffa500" [45]=""
    [40]="#add8e6" [35]="#87ceeb" [30]="#4682b4" [25]="#4169e1"
    [20]="#0000ff" [0]="#00008b"
  )
}

temperature_color() {
  local temperature_c="${1%%.*}"
  local critical_temperature_c="${2:-${TEMP_RAMP_DEFAULT_CRITICAL_C}}"
  critical_temperature_c="${critical_temperature_c%%.*}"
  [[ "${temperature_c}" =~ ^-?[0-9]+$ ]] || return 0
  ((critical_temperature_c > 0)) || critical_temperature_c="${TEMP_RAMP_DEFAULT_CRITICAL_C}"
  local normalized_percent=$((temperature_c * 100 / critical_temperature_c))

  load_temperature_ramp
  local threshold selected_threshold=""
  for threshold in "${!HYPR_TEMP_RAMP[@]}"; do
    if ((normalized_percent >= threshold)) && [[ -z "$selected_threshold" || "$threshold" -gt "$selected_threshold" ]]; then
      selected_threshold="$threshold"
    fi
  done
  if [[ -n "$selected_threshold" ]]; then printf '%s\n' "${HYPR_TEMP_RAMP[$selected_threshold]}"; fi
}

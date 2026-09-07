#!/usr/bin/env bash
# Shared temperature -> colour ramp for the sysinfo widgets (cpuinfo, gpuinfo;
# also read by sensorsinfo.py). Colour comes from the reading NORMALISED to the
# sensor's critical point (temp*100/crit), so one ramp fits any chip: a value at
# its crit is always the hottest colour, whatever the chip's absolute limit.
# Callers without a known crit omit it, so crit defaults to 100 and the ramp is
# read as a plain degC scale (the long-standing cpu/gpu behaviour).
#
# The stops come from render/tempramp.py, which derives them from the active
# palette. The table below is only what the widgets show before the first theme
# apply has written one.
HYPR_TEMP_RAMP_FILE="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/tempramp/ramp.psv"

declare -A HYPR_TEMP_RAMP=()
HYPR_TEMP_RAMP_LOADED=0

load_temp_ramp() {
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

get_temp_color() {
  local temp="${1%%.*}"
  local crit="${2:-100}"
  crit="${crit%%.*}"
  [[ "${temp}" =~ ^-?[0-9]+$ ]] || return 0
  ((crit > 0)) || crit=100
  local norm=$((temp * 100 / crit))

  load_temp_ramp
  local threshold=""
  for threshold in $(printf '%s\n' "${!HYPR_TEMP_RAMP[@]}" | sort -nr); do
    if ((norm >= threshold)); then
      echo "${HYPR_TEMP_RAMP[$threshold]}"
      return
    fi
  done
}

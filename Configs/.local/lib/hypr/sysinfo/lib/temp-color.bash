#!/usr/bin/env bash
# Shared temperature -> colour ramp for the sysinfo widgets (cpuinfo, gpuinfo;
# mirrored in sensorsinfo.py). Colour comes from the reading NORMALISED to the
# sensor's critical point (temp*100/crit), so one ramp fits any chip: a value at
# its crit is always the hottest colour, whatever the chip's absolute limit.
# Callers without a known crit omit it, so crit defaults to 100 and the ramp is
# read as a plain degC scale (the long-standing cpu/gpu behaviour).
#
# Keep the ramp in sync with sensorsinfo.py:get_temp_color.
get_temp_color() {
  local temp="${1%%.*}"
  local crit="${2:-100}"
  crit="${crit%%.*}"
  [[ "${temp}" =~ ^-?[0-9]+$ ]] || return 0
  ((crit > 0)) || crit=100
  local norm=$((temp * 100 / crit))

  declare -A temp_colors=(
    [90]="#8b0000" [85]="#ad1f2f" [80]="#d22f2f" [75]="#ff471a"
    [70]="#ff6347" [65]="#ff8c00" [60]="#ffa500" [45]=""
    [40]="#add8e6" [35]="#87ceeb" [30]="#4682b4" [25]="#4169e1"
    [20]="#0000ff" [0]="#00008b"
  )
  local threshold=""
  for threshold in $(printf '%s\n' "${!temp_colors[@]}" | sort -nr); do
    if ((norm >= threshold)); then
      echo "${temp_colors[$threshold]}"
      return
    fi
  done
}

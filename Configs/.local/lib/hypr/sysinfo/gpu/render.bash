#!/usr/bin/env bash
gpu_vendor_temperature_icon() {
  if ((GPUINFO_NVIDIA_ENABLE || GPUINFO_AMD_ENABLE)); then
    printf '%s\n' '󰾲'
  elif ((GPUINFO_INTEL_ENABLE)); then
    printf '%s\n' '󰢮'
  else
    printf '%s\n' '󰍺'
  fi
}

gpu_render_temperature_icon() {
  local temperature_color_hex="$1"
  local vendor_icon=""

  vendor_icon="$(gpu_vendor_temperature_icon)"
  if [[ -n "${temperature_color_hex}" ]]; then
    printf "<span size='16pt' color='%s'>%s</span>\n" "${temperature_color_hex}" "${vendor_icon}"
    return 0
  fi

  printf "<span size='16pt'>%s</span>\n" "${vendor_icon}"
}

gpu_append_tooltip_line() {
  local -n tooltip_result="$1"
  local line="$2"
  [[ -n "${line}" && "${line}" =~ [a-zA-Z0-9] ]] || return 0
  tooltip_result+=$'\n'"${line}"
}

gpu_temperature_text_into() {
  local -n temperature_text_ref="$1"
  temperature_text_ref="${gpu_temperature_c:+${gpu_temperature_c}°C${gpu_temperature_from_cpu_package:+ (CPU package)}}"
}

gpu_utilization_text_into() {
  local -n utilization_text_ref="$1"
  utilization_text_ref="${gpu_utilization_percent:+${gpu_utilization_from_clock:+~}${gpu_utilization_percent}%${gpu_utilization_from_clock:+ (estimated from clock)}}"
}

gpu_build_tooltip() {
  local -n tooltip_text="$1"
  local temperature_icon="$2" utilization_icon="$3" clock="$4"
  local line="" temperature_text="" utilization_text=""

  gpu_temperature_text_into temperature_text
  gpu_utilization_text_into utilization_text
  tooltip_text="$gpu_model
$temperature_icon Temperature: ${temperature_text}"

  if [[ -n "${utilization_text}" ]]; then
    gpu_append_tooltip_line tooltip_text "$utilization_icon Utilization: ${utilization_text}"
  fi
  if [[ -n "${clock}" ]]; then
    gpu_append_tooltip_line tooltip_text " Clock Speed: ${clock}"
  fi
  if [[ -n "${gpu_power_w:-}" ]]; then
    line="󱪉 Power Usage: ${gpu_power_w} W"
    if [[ -n "${gpu_power_limit_w:-}" && "${gpu_power_limit_w}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      line="󱪉 Power Usage: ${gpu_power_w}/${gpu_power_limit_w} W"
    fi
    gpu_append_tooltip_line tooltip_text "${line}"
  fi
  if [[ -n "${battery_discharge_w:-}" ]] && [[ "${battery_discharge_w}" != "0" ]]; then
    gpu_append_tooltip_line tooltip_text " Power Discharge: ${battery_discharge_w} W"
  fi
  if [[ -n "${gpu_fan_rpm:-}" ]]; then
    gpu_append_tooltip_line tooltip_text " Fan Speed: ${gpu_fan_rpm} RPM"
  fi
  if [[ -n "${gpu_query_error:-}" ]]; then
    gpu_append_tooltip_line tooltip_text "NVIDIA-SMI: ${gpu_query_error}"
  fi
}

GPU_BAR_UTILIZATION_DIGITS=2

gpu_format_utilization() {
  if [[ -n "${gpu_utilization_percent}" && "${gpu_utilization_percent}" != "N/A" ]]; then
    # Keep the bar at two digits; the tooltip retains the raw value.
    local display_utilization_percent="${gpu_utilization_percent%%.*}"
    local display_max_percent=$((10 ** GPU_BAR_UTILIZATION_DIGITS - 1))
    [[ "${display_utilization_percent}" =~ ^[0-9]+$ ]] && ((display_utilization_percent > display_max_percent)) && display_utilization_percent="${display_max_percent}"
    printf '%s%0*d󱉸\n' "${gpu_utilization_from_clock:+~}" "${GPU_BAR_UTILIZATION_DIGITS}" "${display_utilization_percent}"
    return 0
  fi

  printf -- '--󱉸\n'
}

gpu_clock_text_into() {
  local -n clock_ref="$1"
  clock_ref=""
  if [[ -n "${gpu_core_clock_mhz:-}" ]]; then
    clock_ref="${gpu_core_clock_mhz} MHz"
  elif [[ -n "${gpu_current_clock_mhz:-}" && -n "${gpu_max_clock_mhz:-}" ]]; then
    clock_ref="${gpu_current_clock_mhz}/${gpu_max_clock_mhz} MHz"
  fi
}

gpu_vendor_choices_into() {
  local -n vendor_choices_ref="$1"
  local line entry gpu_vendor name
  vendor_choices_ref=""
  while IFS= read -r line; do
    entry="${line#\#}"
    [[ "$entry" == GPUINFO_*_ENABLE=1 ]] || continue
    entry="${entry%=1}"
    gpu_vendor="${entry#GPUINFO_}"
    gpu_vendor="${gpu_vendor%_ENABLE}"
    name="GPUINFO_${gpu_vendor}_GPU"
    vendor_choices_ref+="${gpu_vendor,,}"$'\t'"${!name:-${gpu_vendor,,}}"$'\t'
    [[ "$entry" == "${GPUINFO_PRIORITY:-}" ]] && vendor_choices_ref+=true || vendor_choices_ref+=false
    vendor_choices_ref+=$'\n'
  done <"$gpu_cache_file"
}

gpu_render_bar_json() {
  local utilization_hysteresis_percent="${GPUINFO_UTIL_HYSTERESIS:-5}"
  local temperature_hysteresis_c="${GPUINFO_TEMP_HYSTERESIS:-2}"
  local utilization_icon temperature_icon temperature_color_hex icon_text tooltip utilization_text clock choices
  local temperature_row="" utilization_row=""
  local text_separator=$'\r'

  utilization_icon="$(gpu_cached_level_icon "${gpu_utilization_percent}" "${GPUINFO_UTIL_BUCKET:-}" "${utilization_hysteresis_percent}" GPUINFO_UTIL_BUCKET GPU_UTILIZATION_THRESHOLDS_PERCENT GPU_UTILIZATION_ICONS)"
  temperature_icon="$(gpu_cached_level_icon "${gpu_temperature_c}" "${GPUINFO_TEMP_BUCKET:-}" "${temperature_hysteresis_c}" GPUINFO_TEMP_BUCKET GPU_TEMPERATURE_THRESHOLDS_C GPU_TEMPERATURE_ICONS)"
  temperature_color_hex=$(temperature_color "${gpu_temperature_c}")
  icon_text="$(gpu_render_temperature_icon "${temperature_color_hex}")"
  gpu_clock_text_into clock
  gpu_build_tooltip tooltip "${temperature_icon}" "${utilization_icon}" "${clock}"
  utilization_text="$(gpu_format_utilization)"
  gpu_vendor_choices_into choices
  gpu_temperature_text_into temperature_row
  gpu_utilization_text_into utilization_row

  jq -n -c \
    --arg icon "$icon_text" \
    --arg util "${utilization_text}" \
    --arg tooltip "$tooltip" \
    --arg text_separator "$text_separator" \
    --arg model "${gpu_model:-}" \
    --arg usage "${utilization_row}" \
    --arg temp "${temperature_row}" \
    --arg clock "$clock" \
    --arg power "${gpu_power_w:+${gpu_power_w} W}" \
    --arg choices "$choices" '
      [{label:"Model",value:$model},{label:"Utilization",value:$usage},
       {label:"Temperature",value:$temp},{label:"Clock",value:$clock},
       {label:"Power",value:$power}] | map(select(.value != "")) as $rows
      | ($choices | split("\n") | map(select(length > 0) | split("\t") |
          {id:.[0], label:.[1], active:(.[2] == "true")})) as $choices
      | {text:($icon + $text_separator + $util), tooltip:$tooltip, title:"GPU",
         rows:$rows, choices:$choices}'
}

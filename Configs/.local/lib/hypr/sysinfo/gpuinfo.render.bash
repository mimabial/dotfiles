#!/usr/bin/env bash
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/lib/temp-color.bash"
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/lib/map-floor.bash"

# Levels run high, mid, low; icons run from below low up to at-or-above high.
GPUINFO_UTIL_LEVELS=(90 60 30)
GPUINFO_UTIL_ICONS=("󰾆" "󰾅" "󰓅" "")
GPUINFO_TEMP_LEVELS=(85 65 45)
GPUINFO_TEMP_ICONS=("" "" "" "")

is_number() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

update_state_var() {
  local key="$1" value="$2" line found=false

  [[ -z "${key}" ]] && return
  while IFS= read -r line; do
    [[ "$line" == "$key="* ]] || continue
    found=true
    break
  done <"$gpuinfo_file"
  if "$found"; then
    sed -i "s/^${key}=.*/${key}=${value}/" "$gpuinfo_file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$gpuinfo_file"
  fi
}

hysteresis_bucket() {
  local value="$1" prev="$2" high="$3" mid="$4" low="$5" hyst="$6"
  local val raw=0 next threshold

  if [[ -z "$value" ]] || ! is_number "$value"; then
    [[ "$prev" =~ ^[0-3]$ ]] && printf '%s\n' "$prev"
    return
  fi
  val="${value%%.*}"
  ((val >= low)) && raw=1
  ((val >= mid)) && raw=2
  ((val >= high)) && raw=3
  if [[ ! "$prev" =~ ^[0-3]$ || ! "$hyst" =~ ^[0-9]+$ ]] || ((hyst <= 0)); then
    printf '%s\n' "$raw"
    return
  fi

  next="$prev"
  if ((raw > prev)); then
    case "$raw" in
      1) threshold="$low" ;;
      2) threshold="$mid" ;;
      3) threshold="$high" ;;
    esac
    ((val >= threshold + hyst)) && next="$raw"
  elif ((raw < prev)); then
    case "$prev" in
      1) threshold="$low" ;;
      2) threshold="$mid" ;;
      3) threshold="$high" ;;
    esac
    ((val < threshold - hyst)) && next="$raw"
  else
    next="$raw"
  fi
  printf '%s\n' "$next"
}

intel_gpu_top_util() {
  command -v intel_gpu_top &>/dev/null || return 1

  local sample util jq_filter
  sample=$(intel_gpu_top -J -s 1000 -o - 2>/dev/null | head -n 1)
  [[ -z "${sample}" ]] && return 1

  jq_filter='
    def asnum:
      if type == "number" then .
      elif type == "string" then (tonumber? // empty)
      elif type == "object" then
        (.busy? // .["busy"]? // .["busy%"]? // .["busy_percent"]? // empty) | asnum
      else empty end;
    def sum_busy($obj):
      [ $obj | to_entries[] |
        select(.key|test("render|blitter|video|vecs|vcs|rcs|bcs|compute|ccs|copy|3d|media|engine"; "i")) |
        .value | asnum
      ] | add;
    (if has("engines") then sum_busy(.engines) else sum_busy(.) end) as $sum
    | if ($sum|type) == "number" then $sum
      elif has("rc6") then (.rc6 | asnum) as $rc6 | if ($rc6|type) == "number" then 100 - $rc6 else empty end
      else empty end
  '

  util=$(jq -r "${jq_filter}" <<<"${sample}" 2>/dev/null)
  [[ -z "${util}" || "${util}" == "null" ]] && return 1
  [[ ! "${util}" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && return 1

  printf "%.0f" "${util}"
}

resolve_bucket_icon() {
  local value="$1" prev="$2" hyst="$3" state_key="$4"
  local -n levels_ref="$5" icons_ref="$6"
  local bucket=""

  bucket=$(hysteresis_bucket "${value}" "${prev}" "${levels_ref[@]}" "${hyst}")
  if [[ -n "${bucket}" ]]; then
    update_state_var "${state_key}" "${bucket}"
    printf '%s\n' "${icons_ref[bucket]}"
    return 0
  fi
  map_floor "${levels_ref[0]}:${icons_ref[3]}, ${levels_ref[1]}:${icons_ref[2]}, ${levels_ref[2]}:${icons_ref[1]}, ${icons_ref[0]}" "${value}"
}

vendor_thermo_icon() {
  if ((GPUINFO_NVIDIA_ENABLE || GPUINFO_AMD_ENABLE)); then
    printf '%s\n' '󰾲'
  elif ((GPUINFO_INTEL_ENABLE)); then
    printf '%s\n' '󰢮'
  else
    printf '%s\n' '󰍺'
  fi
}

render_thermo_icon() {
  local temp_color="$1"
  local thermo_alt=""

  thermo_alt="$(vendor_thermo_icon)"
  if [[ -n "${temp_color}" ]]; then
    printf "<span size='16pt' color='%s'>%s</span>\n" "${temp_color}" "${thermo_alt}"
    return 0
  fi

  printf "<span size='16pt'>%s</span>\n" "${thermo_alt}"
}

append_tooltip_line() {
  local line="$1"
  [[ -n "${line}" && "${line}" =~ [a-zA-Z0-9] ]] || return 0
  tooltip+=$'\n'"${line}"
}

build_tooltip() {
  local thermo="$1"
  local speed="$2"
  local clock="$3"
  local line=""

  tooltip="$primary_gpu
$thermo Temperature: ${temperature}°C"

  if [[ -n "${utilization:-}" ]]; then
    append_tooltip_line "$speed Utilization: ${utilization}%"
  fi
  if [[ -n "${clock}" ]]; then
    append_tooltip_line " Clock Speed: ${clock}"
  fi
  if [[ -n "${power_usage:-}" ]]; then
    line="󱪉 Power Usage: ${power_usage} W"
    if [[ -n "${power_limit:-}" && "${power_limit}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      line="󱪉 Power Usage: ${power_usage}/${power_limit} W"
    fi
    append_tooltip_line "${line}"
  fi
  if [[ -n "${power_discharge:-}" ]] && [[ "${power_discharge}" != "0" ]]; then
    append_tooltip_line " Power Discharge: ${power_discharge} W"
  fi
  if [[ -n "${fan_speed:-}" ]]; then
    append_tooltip_line " Fan Speed: ${fan_speed} RPM"
  fi
  if [[ -n "${gpu_error:-}" ]]; then
    append_tooltip_line "NVIDIA-SMI: ${gpu_error}"
  fi
}

format_utilization_text() {
  if [[ -n "${utilization}" && "${utilization}" != "N/A" ]]; then
    # Keep the bar at two digits; the tooltip retains the raw value.
    local util_int="${utilization%%.*}"
    [[ "${util_int}" =~ ^[0-9]+$ ]] && ((util_int > 99)) && util_int=99
    printf '%02d󱉸\n' "${util_int}"
    return 0
  fi

  printf -- '--󱉸\n'
}

gpu_clock_text_into() {
  local -n clock_ref="$1"
  clock_ref=""
  if [[ -n "${core_clock:-}" ]]; then
    clock_ref="${core_clock} MHz"
  elif [[ -n "${current_clock_speed:-}" && -n "${max_clock_speed:-}" ]]; then
    clock_ref="${current_clock_speed}/${max_clock_speed} MHz"
  fi
}

gpu_vendor_choices_into() {
  local -n vendor_choices_ref="$1"
  local line entry vendor name
  vendor_choices_ref=""
  while IFS= read -r line; do
    entry="${line#\#}"
    [[ "$entry" == GPUINFO_*_ENABLE=1 ]] || continue
    entry="${entry%=1}"
    vendor="${entry#GPUINFO_}"
    vendor="${vendor%_ENABLE}"
    name="GPUINFO_${vendor}_GPU"
    vendor_choices_ref+="${vendor,,}"$'\t'"${!name:-${vendor,,}}"$'\t'
    [[ "$entry" == "${GPUINFO_PRIORITY:-}" ]] && vendor_choices_ref+=true || vendor_choices_ref+=false
    vendor_choices_ref+=$'\n'
  done <"$gpuinfo_file"
}

generate_json() {
  local util_hyst="${GPUINFO_UTIL_HYSTERESIS:-5}"
  local temp_hyst="${GPUINFO_TEMP_HYSTERESIS:-2}"
  local speed thermo temp_color icon_text tooltip formatted_util clock choices
  local sep=$'\r'

  speed="$(resolve_bucket_icon "${utilization}" "${GPUINFO_UTIL_BUCKET:-}" "${util_hyst}" GPUINFO_UTIL_BUCKET GPUINFO_UTIL_LEVELS GPUINFO_UTIL_ICONS)"
  thermo="$(resolve_bucket_icon "${temperature}" "${GPUINFO_TEMP_BUCKET:-}" "${temp_hyst}" GPUINFO_TEMP_BUCKET GPUINFO_TEMP_LEVELS GPUINFO_TEMP_ICONS)"
  temp_color=$(get_temp_color "${temperature}")
  icon_text="$(render_thermo_icon "${temp_color}")"
  gpu_clock_text_into clock
  build_tooltip "${thermo}" "${speed}" "${clock}"
  formatted_util="$(format_utilization_text)"
  gpu_vendor_choices_into choices

  jq -n -c \
    --arg icon "$icon_text" \
    --arg util "${formatted_util}" \
    --arg tooltip "$tooltip" \
    --arg sep "$sep" \
    --arg model "${primary_gpu:-}" \
    --arg usage "${utilization:+${utilization}%}" \
    --arg temp "${temperature:+${temperature}°C}" \
    --arg clock "$clock" \
    --arg power "${power_usage:+${power_usage} W}" \
    --arg choices "$choices" '
      [{label:"Model",value:$model},{label:"Utilization",value:$usage},
       {label:"Temperature",value:$temp},{label:"Clock",value:$clock},
       {label:"Power",value:$power}] | map(select(.value != "")) as $rows
      | ($choices | split("\n") | map(select(length > 0) | split("\t") |
          {id:.[0], label:.[1], active:(.[2] == "true")})) as $choices
      | {text:($icon + $sep + $util), tooltip:$tooltip, title:"GPU",
         rows:$rows, choices:$choices}'
}

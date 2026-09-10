#!/usr/bin/env bash
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/lib/temp-color.bash"
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/lib/map-floor.bash"

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
  local value="$1" prev="$2" high="$3" mid="$4" low="$5" hyst="$6"
  local state_key="$7" fallback_map="$8" bucket icon
  shift 8
  local -a icons=("$@")

  bucket=$(hysteresis_bucket "${value}" "${prev}" "${high}" "${mid}" "${low}" "${hyst}")
  if [[ -n "${bucket}" ]]; then
    update_state_var "${state_key}" "${bucket}"
    printf '%s\n' "${icons[${bucket}]}"
    return 0
  fi

  icon="$(map_floor "${fallback_map}" "${value}")"
  if [[ "${state_key}" == "GPUINFO_TEMP_BUCKET" ]]; then
    printf '%s\n' "${icon:0:1}"
    return 0
  fi

  printf '%s\n' "${icon}"
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
  local line=""

  tooltip="$primary_gpu
$thermo Temperature: ${temperature}°C"

  if [[ -n "${utilization:-}" ]]; then
    append_tooltip_line "$speed Utilization: ${utilization}%"
  fi
  if [[ -n "${core_clock:-}" ]]; then
    append_tooltip_line " Clock Speed: ${core_clock} MHz"
  elif [[ -n "${current_clock_speed:-}" ]] && [[ -n "${max_clock_speed:-}" ]]; then
    append_tooltip_line " Clock Speed: ${current_clock_speed}/${max_clock_speed} MHz"
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

generate_json() {
  local util_high=90 util_mid=60 util_low=30
  local temp_high=85 temp_mid=65 temp_low=45
  local util_hyst="${GPUINFO_UTIL_HYSTERESIS:-5}"
  local temp_hyst="${GPUINFO_TEMP_HYSTERESIS:-2}"

  temp_lv="85:, 65:, 45:, "
  util_lv="90:, 60:󰓅, 30:󰾅, 󰾆"

  local speed thermo temp_color icon_text tooltip formatted_util
  local util_icons=("󰾆" "󰾅" "󰓅" "")
  local temp_icons=("" "" "" "")

  speed="$(resolve_bucket_icon "${utilization}" "${GPUINFO_UTIL_BUCKET:-}" "${util_high}" "${util_mid}" "${util_low}" "${util_hyst}" "GPUINFO_UTIL_BUCKET" "${util_lv}" "${util_icons[@]}")"
  thermo="$(resolve_bucket_icon "${temperature}" "${GPUINFO_TEMP_BUCKET:-}" "${temp_high}" "${temp_mid}" "${temp_low}" "${temp_hyst}" "GPUINFO_TEMP_BUCKET" "${temp_lv}" "${temp_icons[@]}")"
  temp_color=$(get_temp_color "${temperature}")
  icon_text="$(render_thermo_icon "${temp_color}")"
  build_tooltip "${thermo}" "${speed}"
  formatted_util="$(format_utilization_text)"

  local sep=$'\r'
  [[ "${HYPR_SYSINFO_ALT:-0}" == "1" ]] && sep=" "

  local clock=""
  if [[ -n "${core_clock:-}" ]]; then
    clock="${core_clock} MHz"
  elif [[ -n "${current_clock_speed:-}" && -n "${max_clock_speed:-}" ]]; then
    clock="${current_clock_speed}/${max_clock_speed} MHz"
  fi

  local line entry vendor name choices=""
  while IFS= read -r line; do
    entry="${line#\#}"
    [[ "$entry" == GPUINFO_*_ENABLE=1 ]] || continue
    entry="${entry%=1}"
    vendor="${entry#GPUINFO_}"
    vendor="${vendor%_ENABLE}"
    name="GPUINFO_${vendor}_GPU"
    choices+="${vendor,,}"$'\t'"${!name:-${vendor,,}}"$'\t'
    [[ "$entry" == "${GPUINFO_PRIORITY:-}" ]] && choices+=true || choices+=false
    choices+=$'\n'
  done <"$gpuinfo_file"

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

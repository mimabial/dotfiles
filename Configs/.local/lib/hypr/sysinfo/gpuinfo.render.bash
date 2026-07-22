#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# GPU render and bucket helpers.
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/lib/temp-color.bash"
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/lib/map-floor.bash"

# Keep icon levels stable near thresholds.
is_number() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

update_state_var() {
  local key="$1"
  local value="$2"

  [[ -z "${key}" ]] && return
  if grep -q "^${key}=" "${gpuinfo_file}"; then
    sed -i "s/^${key}=.*/${key}=${value}/" "${gpuinfo_file}"
  else
    echo "${key}=${value}" >>"${gpuinfo_file}"
  fi
}

hysteresis_bucket() {
  local value="$1"
  local prev="$2"
  local high="$3"
  local mid="$4"
  local low="$5"
  local hyst="$6"
  local val raw next threshold

  if [[ -z "${value}" ]] || ! is_number "${value}"; then
    if [[ "${prev}" =~ ^[0-3]$ ]]; then
      echo "${prev}"
    else
      echo ""
    fi
    return
  fi

  val="${value%%.*}"
  if ((val >= high)); then
    raw=3
  elif ((val >= mid)); then
    raw=2
  elif ((val >= low)); then
    raw=1
  else
    raw=0
  fi

  if [[ -z "${prev}" ]] || [[ ! "${prev}" =~ ^[0-3]$ ]]; then
    echo "${raw}"
    return
  fi

  if [[ -z "${hyst}" ]] || [[ ! "${hyst}" =~ ^[0-9]+$ ]] || [[ "${hyst}" -le 0 ]]; then
    echo "${raw}"
    return
  fi

  next="${prev}"
  threshold="${low}"

  if ((raw > prev)); then
    case "${raw}" in
      1) threshold="${low}" ;;
      2) threshold="${mid}" ;;
      3) threshold="${high}" ;;
    esac
    if ((val >= threshold + hyst)); then
      next="${raw}"
    fi
  elif ((raw < prev)); then
    case "${prev}" in
      1) threshold="${low}" ;;
      2) threshold="${mid}" ;;
      3) threshold="${high}" ;;
    esac
    if ((val < threshold - hyst)); then
      next="${raw}"
    fi
  else
    next="${raw}"
  fi

  echo "${next}"
}

# Try to read Intel utilization from intel_gpu_top JSON output.
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

# Function to determine color based on temperature

resolve_bucket_icon() {
  local value="$1"
  local prev="$2"
  local high="$3"
  local mid="$4"
  local low="$5"
  local hyst="$6"
  local state_key="$7"
  local fallback_map="$8"
  shift 8
  local -a icons=("$@")
  local bucket=""
  local icon=""

  bucket=$(hysteresis_bucket "${value}" "${prev}" "${high}" "${mid}" "${low}" "${hyst}")
  if [[ -n "${bucket}" ]]; then
    icon="${icons[${bucket}]}"
    update_state_var "${state_key}" "${bucket}"
    printf '%s\n' "${icon}"
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
  if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
    printf '%s\n' '󰾲'
  elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
    printf '%s\n' '󰾲'
  elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
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
    printf "<span size='14pt' color='%s'>%s</span>\n" "${temp_color}" "${thermo_alt}"
    return 0
  fi

  printf "<span size='14pt'>%s</span>\n" "${thermo_alt}"
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

  # ${VAR:-} fallbacks for optional metrics — each is populated by only some
  # of the GPU paths (general_query / nvidia_GPU / amd_GPU / intel_GPU), so a
  # bare ${VAR} crashes under set -u when the active path didn't set it.
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
  # ${VAR:-} for optional metrics: power_discharge is set only on battery,
  # fan_speed only by AMD/sensors paths, gpu_error only by nvidia-smi failure.
  # Without the fallback they crash under set -u on the other paths.
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
    # Cap module text at 99 so a 3-digit reading doesn't break the bar's
    # fixed-width slot. The tooltip (build_tooltip) still shows the raw
    # value, so 100% is visible there.
    local util_int="${utilization%%.*}"
    [[ "${util_int}" =~ ^[0-9]+$ ]] && (( util_int > 99 )) && util_int=99
    printf '%02d󱉸\n' "${util_int}"
    return 0
  fi

  # No reading available (e.g. nvidia-smi failed and there's no sysfs util
  # counter for this GPU). Print "--" so the module stays visually
  # populated and the user can see they're on a backend without data.
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

  # Bucket vars are persisted in gpuinfo_file across runs but unset on first
  # invocation; ${VAR:-} keeps that path safe under set -u.
  speed="$(resolve_bucket_icon "${utilization}" "${GPUINFO_UTIL_BUCKET:-}" "${util_high}" "${util_mid}" "${util_low}" "${util_hyst}" "GPUINFO_UTIL_BUCKET" "${util_lv}" "${util_icons[@]}")"
  thermo="$(resolve_bucket_icon "${temperature}" "${GPUINFO_TEMP_BUCKET:-}" "${temp_high}" "${temp_mid}" "${temp_low}" "${temp_hyst}" "GPUINFO_TEMP_BUCKET" "${temp_lv}" "${temp_icons[@]}")"
  temp_color=$(get_temp_color "${temperature}")
  icon_text="$(render_thermo_icon "${temp_color}")"
  build_tooltip "${thermo}" "${speed}"
  formatted_util="$(format_utilization_text)"

  local sep=$'\r'
  [[ "${HYPR_SYSINFO_ALT:-0}" == "1" ]] && sep=" "

  jq -n -c \
    --arg icon "$icon_text" \
    --arg util "${formatted_util}" \
    --arg tooltip "$tooltip" \
    --arg sep "$sep" \
    '{text: ($icon + $sep + $util), tooltip: $tooltip}'
}

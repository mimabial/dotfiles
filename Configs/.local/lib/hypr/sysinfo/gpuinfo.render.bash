#!/usr/bin/env bash
# GPU render and bucket helpers.
map_floor() {
  IFS=', ' read -r -a pairs <<<"$1"
  if [[ ${pairs[-1]} != *":"* ]]; then
    def_val="${pairs[-1]}"
    unset 'pairs[${#pairs[@]}-1]'
  fi
  for pair in "${pairs[@]}"; do
    IFS=':' read -r key value <<<"$pair"
    num="${2%%.*}"
    # if awk -v num="$2" -v k="$key" 'BEGIN { exit !(num > k) }'; then #! causes 50ms+ delay
    if [[ "$num" =~ ^-?[0-9]+$ && "$key" =~ ^-?[0-9]+$ ]]; then # Prefer bash integer compares here to avoid spawning awk in the hot path.
      if ((num > key)); then
        echo "$value"
        return
      fi
    elif [[ -n "$num" && -n "$key" && "$num" > "$key" ]]; then
      echo "$value"
      return
    fi
  done
  [ -n "$def_val" ] && echo $def_val || echo " "
}

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
get_temp_color() {
  local temp=$1
  if [[ -z "${temp}" || ! "${temp}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    return
  fi
  declare -A temp_colors=(
    [90]="#8b0000" # Dark Red for 90 and above
    [85]="#ad1f2f" # Red for 85 to 89
    [80]="#d22f2f" # Light Red for 80 to 84
    [75]="#ff471a" # Orange-Red for 75 to 79
    [70]="#ff6347" # Tomato for 70 to 74
    [65]="#ff8c00" # Dark Orange for 65 to 69
    [60]="#ffa500" # Orange for 60 to 64
    [45]=""        # No color for 45 to 59
    [40]="#add8e6" # Light Blue for 40 to 44
    [35]="#87ceeb" # Sky Blue for 35 to 39
    [30]="#4682b4" # Steel Blue for 30 to 34
    [25]="#4169e1" # Royal Blue for 25 to 29
    [20]="#0000ff" # Blue for 20 to 24
    [0]="#00008b"  # Dark Blue for below 20
  )

  for threshold in $(echo "${!temp_colors[@]}" | tr ' ' '\n' | sort -nr); do
    if ((temp >= threshold)); then
      echo "${temp_colors[$threshold]}"
      return
    fi
  done
}

generate_json() {

  local util_high=90 util_mid=60 util_low=30
  local temp_high=85 temp_mid=65 temp_low=45
  local util_hyst="${GPUINFO_UTIL_HYSTERESIS:-5}"
  local temp_hyst="${GPUINFO_TEMP_HYSTERESIS:-2}"

  temp_lv="85:, 65:, 45:, "
  util_lv="90:, 60:󰓅, 30:󰾅, 󰾆"

  local util_bucket temp_bucket speed thermo temp_color
  local util_icons=("󰾆" "󰾅" "󰓅" "")
  local temp_icons=("" "" "" "")

  util_bucket=$(hysteresis_bucket "${utilization}" "${GPUINFO_UTIL_BUCKET}" "${util_high}" "${util_mid}" "${util_low}" "${util_hyst}")
  temp_bucket=$(hysteresis_bucket "${temperature}" "${GPUINFO_TEMP_BUCKET}" "${temp_high}" "${temp_mid}" "${temp_low}" "${temp_hyst}")

  if [[ -n "${util_bucket}" ]]; then
    speed="${util_icons[${util_bucket}]}"
    update_state_var "GPUINFO_UTIL_BUCKET" "${util_bucket}"
  else
    speed="$(map_floor "$util_lv" "$utilization")"
  fi

  if [[ -n "${temp_bucket}" ]]; then
    thermo="${temp_icons[${temp_bucket}]}"
    update_state_var "GPUINFO_TEMP_BUCKET" "${temp_bucket}"
  else
    local temp_pair
    temp_pair="$(map_floor "$temp_lv" "${temperature}")"
    thermo="${temp_pair:0:1}"
  fi

  temp_color=$(get_temp_color "${temperature}")

  # Set vendor-specific icon for thermo_alt
  if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
    thermo_alt=󰾲 # NVIDIA icon (current default)
    # Alternative NVIDIA-specific options: 󰢮 󱤓 󰒓
  elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
    thermo_alt=󰾲 # AMD icon
    # Alternative AMD options: 󰜡
  elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
    thermo_alt=󰢮 # Intel icon
    # Alternative Intel options: 󰟀
  else
    thermo_alt=󰍺 # Default/fallback icon
  fi

  if [[ -n "$temp_color" ]]; then
    icon_text="<span size='14pt' color='$temp_color'>$thermo_alt</span>"
  else
    icon_text="<span size='14pt'>$thermo_alt</span>"
  fi

  # Build tooltip with ordered lines
  tooltip="$primary_gpu
$thermo Temperature: ${temperature}°C"

  local tooltip_lines=()
  if [[ -n "${utilization}" ]]; then tooltip_lines+=("$speed Utilization: ${utilization}%"); fi
  if [[ -n "${core_clock}" ]]; then
    tooltip_lines+=(" Clock Speed: ${core_clock} MHz")
  elif [[ -n "${current_clock_speed}" ]] && [[ -n "${max_clock_speed}" ]]; then
    tooltip_lines+=(" Clock Speed: ${current_clock_speed}/${max_clock_speed} MHz")
  fi
  if [[ -n "${power_usage}" ]]; then
    if [[ -n "${power_limit}" && "${power_limit}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      tooltip_lines+=("󱪉 Power Usage: ${power_usage}/${power_limit} W")
    else
      tooltip_lines+=("󱪉 Power Usage: ${power_usage} W")
    fi
  fi
  if [[ -n "${power_discharge}" ]] && [[ "${power_discharge}" != "0" ]]; then tooltip_lines+=(" Power Discharge: ${power_discharge} W"); fi
  if [[ -n "${fan_speed}" ]]; then tooltip_lines+=(" Fan Speed: ${fan_speed} RPM"); fi
  if [[ -n "${gpu_error}" ]]; then tooltip_lines+=("NVIDIA-SMI: ${gpu_error}"); fi

  for line in "${tooltip_lines[@]}"; do
    if [[ -n "${line}" && "${line}" =~ [a-zA-Z0-9] ]]; then
      tooltip+=$'\n'"${line}"
    fi
  done

  # Format utilization with two digits (pad with leading zero if needed)
  local formatted_util
  if [[ -n "${utilization}" && "${utilization}" != "N/A" ]]; then
    formatted_util=$(printf "%02d" "${utilization%%.*}")
  else
    formatted_util="${utilization}"
  fi

  jq -n -c \
    --arg icon "$icon_text" \
    --arg util "${formatted_util}󱉸" \
    --arg tooltip "$tooltip" \
    '{text: ($icon + "\r" + $util), tooltip: $tooltip}'
}

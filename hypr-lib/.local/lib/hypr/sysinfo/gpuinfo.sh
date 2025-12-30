#!/usr/bin/env bash
# shellcheck disable=SC2312
# shellcheck disable=SC1090

# Benchmark Tool: hyperfine
# NVIDIA: gpuinfo.sh
#   Time (mean ± σ):      75.7 ms ±   8.0 ms    [User: 31.0 ms, System: 41.9 ms]
#   Range (min … max):    45.7 ms …  91.4 ms    34 runs

# INTEL/GENERAL: gpuinfo.sh
#   Time (mean ± σ):     246.9 ms ±  22.5 ms    [User: 112.4 ms, System: 87.5 ms]
# Range (min … max):   184.0 ms … 272.1 ms    12 runs

# Parse arguments for output mode
OUTPUT_MODE=""
STARTUP_ARG=""
USE_ARG=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -i | --icon)
      OUTPUT_MODE="icon"
      shift
      ;;
    -u | --util)
      OUTPUT_MODE="util"
      shift
      ;;
    -a | --all)
      OUTPUT_MODE="all"
      shift
      ;;
    --startup)
      STARTUP_ARG="--startup"
      shift
      ;;
    --use)
      USE_ARG="$2"
      shift 2
      ;;
    --toggle | -t | --reset | -rf | --tired | --emoji | --stat) break ;;
    *) shift ;;
  esac
done

scrDir=$(dirname "$(realpath "$0")")
gpuinfo_file="/tmp/${UID}-gpuinfo"
cache_file="/tmp/gpuinfo-cache-${UID}.json"

# -i and -u read from cache if it exists
if [[ -n "$OUTPUT_MODE" && -f "$cache_file" ]]; then
  case $OUTPUT_MODE in
    "icon")
      jq -c '{text: .icon, tooltip: .tooltip}' "$cache_file"
      exit 0
      ;;
    "util")
      jq -c '{text: .util, tooltip: .tooltip}' "$cache_file"
      exit 0
      ;;
    "all")
      cat "$cache_file"
      exit 0
      ;;
  esac
fi

# Use the AQ_DRM_DEVICES variable to set the priority of the GPUs
AQ_DRM_DEVICES="${AQ_DRM_DEVICES:-WLR_DRM_DEVICES}"

tired=false
if [[ " $* " =~ " --tired " ]]; then
  if ! grep -q "tired" "${gpuinfo_file}"; then
    echo "tired=true" >>"${gpuinfo_file}"
    echo "set tired flag"
  else
    echo "already set tired flag"
  fi
  echo "Nvidia GPU will not be queried if it is in suspend mode"
  echo "run --reset to reset the flag"
  exit 0
fi

if [[ " $* " =~ " --emoji " ]]; then
  if ! grep -q "GPUINFO_EMOJI" "${gpuinfo_file}"; then
    echo "export GPUINFO_EMOJI=1" >>"${gpuinfo_file}"
    echo "set emoji flag"
  else
    echo "already set emoji flag"
  fi
  echo "run --reset to reset the flag"
  exit 0
fi

if [[ ! " $* " =~ " --startup " ]]; then
  gpuinfo_file="${gpuinfo_file}$2"
fi
detect() { # Auto detect Gpu used by Hyprland(declared using env = AQ_DRM_DEVICES) Sophisticated?
  card=$(echo "${AQ_DRM_DEVICES}" | cut -d':' -f1 | cut -d'/' -f4)

  # shellcheck disable=SC2010
  slot_number=$(ls -l /dev/dri/by-path/ | grep "${card}" | awk -F'pci-0000:|-card' '{print $2}')
  vendor_id=$(lspci -nn -s "${slot_number}")
  declare -A vendors=(["10de"]="nvidia" ["8086"]="intel" ["1002"]="amd")
  for vendor in "${!vendors[@]}"; do
    if [[ ${vendor_id} == *"${vendor}"* ]]; then
      initGPU="${vendors[${vendor}]}"
      break
    fi
  done
  if [[ -n ${initGPU} ]]; then
    $0 --use "${initGPU}" --startup
  fi
}

query() {
  GPUINFO_NVIDIA_ENABLE=0 GPUINFO_AMD_ENABLE=0 GPUINFO_INTEL_ENABLE=0
  touch "${gpuinfo_file}"

  if lsmod | grep -q 'nouveau'; then
    echo "GPUINFO_NVIDIA_GPU=\"Linux\"" >>"${gpuinfo_file}" #? Incase If nouveau is installed
    echo "GPUINFO_NVIDIA_ENABLE=1 # Using nouveau an open-source nvidia driver" >>"${gpuinfo_file}"
  elif command -v nvidia-smi &>/dev/null; then
    local nvidia_smi_output=""
    if nvidia_smi_output=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader,nounits 2>&1); then
      GPUINFO_NVIDIA_GPU=$(printf '%s\n' "${nvidia_smi_output}" | head -n 1)
    else
      GPUINFO_NVIDIA_GPU=""
    fi
    if [[ -n "${GPUINFO_NVIDIA_GPU}" ]]; then                             # Check for NVIDIA GPU
      if [[ "${GPUINFO_NVIDIA_GPU}" == *"NVIDIA-SMI has failed"* ]] || [[ "${GPUINFO_NVIDIA_GPU}" == *"Failed to initialize NVML"* ]]; then #? Second Layer for dGPU
        echo "GPUINFO_NVIDIA_ENABLE=0 # NVIDIA-SMI has failed" >>"${gpuinfo_file}"
      else
        NVIDIA_ADDR=$(lspci | grep -Ei "VGA|3D" | grep -i "${GPUINFO_NVIDIA_GPU/NVIDIA /}" | cut -d' ' -f1)
        {
          echo "NVIDIA_ADDR=\"${NVIDIA_ADDR}\""
          echo "GPUINFO_NVIDIA_GPU=\"${GPUINFO_NVIDIA_GPU/NVIDIA /}\""
          echo "GPUINFO_NVIDIA_ENABLE=1"
        } >>"${gpuinfo_file}"
      fi
    fi
  fi

  if ! grep -q "GPUINFO_NVIDIA_ENABLE=1" "${gpuinfo_file}"; then
    local nvidia_line=""
    nvidia_line=$(lspci -nn | grep -Ei "(VGA|3D)" | grep -m 1 "10de" || true)
    if [[ -n "${nvidia_line}" ]]; then
      NVIDIA_ADDR=$(echo "${nvidia_line}" | awk '{print $1}')
      local nvidia_name=""
      nvidia_name=$(echo "${nvidia_line}" | sed -n 's/.*\[\(.*\)\].*/\1/p')
      if [[ -z "${nvidia_name}" ]]; then
        nvidia_name=$(echo "${nvidia_line}" | sed -n 's/.*NVIDIA Corporation //p' | sed 's/ *\[[^]]*\]//; s/ *([^)]*)//')
      fi
      {
        echo "NVIDIA_ADDR=\"${NVIDIA_ADDR}\""
        echo "GPUINFO_NVIDIA_GPU=\"${nvidia_name}\""
        echo "GPUINFO_NVIDIA_ENABLE=1 # NVIDIA detected via lspci"
      } >>"${gpuinfo_file}"
    fi
  fi

  if lspci -nn | grep -E "(VGA|3D)" | grep -iq "1002"; then
    GPUINFO_AMD_GPU="$(lspci -nn | grep -Ei "VGA|3D" | grep -m 1 "1002" | awk -F'Advanced Micro Devices, Inc. ' '{gsub(/ *\[[^\]]*\]/,""); gsub(/ *\([^)]*\)/,""); print $2}')"
    AMD_ADDR=$(lspci | grep -Ei "VGA|3D" | grep -i "${GPUINFO_AMD_GPU}" | cut -d' ' -f1)
    {
      echo "AMD_ADDR=\"${AMD_ADDR}\""
      echo "GPUINFO_AMD_ENABLE=1" # Check for Amd GPU
      echo "GPUINFO_AMD_GPU=\"${GPUINFO_AMD_GPU}\""
    } >>"${gpuinfo_file}"
  fi

  if lspci -nn | grep -E "(VGA|3D)" | grep -iq "8086"; then
    GPUINFO_INTEL_GPU="$(lspci -nn | grep -Ei "VGA|3D" | grep -m 1 "8086" | awk -F'Intel Corporation ' '{gsub(/ *\[[^\]]*\]/,""); gsub(/ *\([^)]*\)/,""); print $2}')"
    INTEL_ADDR=$(lspci | grep -Ei "VGA|3D" | grep -i "${GPUINFO_INTEL_GPU}" | cut -d' ' -f1)
    {
      echo "INTEL_ADDR=\"${INTEL_ADDR}\""
      echo "GPUINFO_INTEL_ENABLE=1" # Check for Intel GPU
      echo "GPUINFO_INTEL_GPU=\"${GPUINFO_INTEL_GPU}\""
    } >>"${gpuinfo_file}"
  fi

  if ! grep -q "GPUINFO_PRIORITY=" "${gpuinfo_file}" && [[ -n "${AQ_DRM_DEVICES}" ]]; then
    trap detect EXIT
  fi

}

toggle() {
  if [[ -n "$1" ]]; then
    NEXT_PRIORITY="GPUINFO_${1^^}_ENABLE"
    if ! grep -q "${NEXT_PRIORITY}=1" "${gpuinfo_file}"; then
      echo Error: "${NEXT_PRIORITY}" not found in "${gpuinfo_file}"
    fi
  else
    # Initialize GPUINFO_AVAILABLE and GPUINFO_PRIORITY if they don't exist
    if ! grep -q "GPUINFO_AVAILABLE=" "${gpuinfo_file}"; then
      GPUINFO_AVAILABLE=$(grep "_ENABLE=1" "${gpuinfo_file}" | cut -d '=' -f 1 | tr '\n' ' ' | tr -d '#')
      echo "" >>"${gpuinfo_file}"
      echo "GPUINFO_AVAILABLE=\"${GPUINFO_AVAILABLE[*]}\"" >>"${gpuinfo_file}"
    fi

    if ! grep -q "GPUINFO_PRIORITY=" "${gpuinfo_file}"; then
      GPUINFO_AVAILABLE=$(grep "GPUINFO_AVAILABLE=" "${gpuinfo_file}" | cut -d'=' -f 2)
      initGPU=$(echo "${GPUINFO_AVAILABLE}" | cut -d ' ' -f 1)
      echo "GPUINFO_PRIORITY=${initGPU}" >>"${gpuinfo_file}"
    fi
    mapfile -t anchor < <(grep "_ENABLE=1" "${gpuinfo_file}" | cut -d '=' -f 1)
    GPUINFO_PRIORITY=$(grep "GPUINFO_PRIORITY=" "${gpuinfo_file}" | cut -d'=' -f 2) # Get the current GPUINFO_PRIORITY from the file
    # Find the index of the current GPUINFO_PRIORITY in the anchor array
    for index in "${!anchor[@]}"; do
      if [[ "${anchor[${index}]}" = "${GPUINFO_PRIORITY}" ]]; then
        current_index=${index}
      fi
    done
    next_index=$(((current_index + 1) % ${#anchor[@]}))
    NEXT_PRIORITY=${anchor[${next_index}]#\#}
  fi

  # Set the next GPUINFO_PRIORITY and remove the '#' character
  sed -i 's/^\(GPUINFO_NVIDIA_ENABLE=1\|GPUINFO_AMD_ENABLE=1\|GPUINFO_INTEL_ENABLE=1\)/#\1/' "${gpuinfo_file}" # Comment out all the gpu flags in the file
  sed -i "s/^#${NEXT_PRIORITY}/${NEXT_PRIORITY}/" "${gpuinfo_file}"                                            # Uncomment the next GPUINFO_PRIORITY in the file
  sed -i "s/GPUINFO_PRIORITY=${GPUINFO_PRIORITY}/GPUINFO_PRIORITY=${NEXT_PRIORITY}/" "${gpuinfo_file}"         # Update the GPUINFO_PRIORITY in the file
}

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
    if [[ "$num" =~ ^-?[0-9]+$ && "$key" =~ ^-?[0-9]+$ ]]; then # TODO Faster than awk but I might be dumb so checks might be lacking
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

  if [[ $GPUINFO_EMOJI -ne 1 ]]; then
    temp_lv="85:, 65:, 45:☁, ❄"
  else
    temp_lv="85:🌋, 65:🔥, 45:☁️, ❄️"
  fi
  util_lv="90:, 60:󰓅, 30:󰾅, 󰾆"

  # Generate glyphs
  icons="$(map_floor "$util_lv" "$utilization")$(map_floor "$temp_lv" "${temperature}")"
  speedo=${icons:0:1}
  thermo=${icons:1:1}
  emoji=${icons:2}
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

  # Build tooltip with newlines
  tooltip="$emoji $primary_gpu
$thermo Temperature: ${temperature}°C"

  #TODO Add Something incase needed.
  declare -A tooltip_parts
  if [[ -n "${utilization}" ]]; then tooltip_parts["$speedo Utilization: "]="${utilization}%"; fi
  if [[ -n "${current_clock_speed}" ]] && [[ -n "${max_clock_speed}" ]]; then tooltip_parts[" Clock Speed: "]="${current_clock_speed}/${max_clock_speed} MHz"; fi
  if [[ -n "${core_clock}" ]]; then tooltip_parts[" Clock Speed: "]="${core_clock} MHz"; fi
  if [[ -n "${power_usage}" ]]; then
    if [[ -n "${power_limit}" ]]; then
      tooltip_parts["󱪉 Power Usage: "]="${power_usage}/${power_limit} W"
    else
      tooltip_parts["󱪉 Power Usage: "]="${power_usage} W"
    fi
  fi
  if [[ -n "${power_discharge}" ]] && [[ "${power_discharge}" != "0" ]]; then tooltip_parts[" Power Discharge: "]="${power_discharge} W"; fi
  if [[ -n "${fan_speed}" ]]; then tooltip_parts[" Fan Speed: "]="${fan_speed} RPM"; fi
  if [[ -n "${gpu_error}" ]]; then tooltip_parts["NVIDIA-SMI: "]="${gpu_error}"; fi

  # Construct tooltip
  for key in "${!tooltip_parts[@]}"; do
    local value="${tooltip_parts[${key}]}"
    if [[ -n "${value}" && "${value}" =~ [a-zA-Z0-9] ]]; then
      json+=$'\n'"${key}${value}"
    fi
  done

  # Add the additional info to tooltip
  tooltip="${tooltip}${json}"

  # Write cache using jq

  # Format utilization with two digits (pad with leading zero if needed)
  local formatted_util
  if [[ -n "${utilization}" && "${utilization}" != "N/A" ]]; then
    formatted_util=$(printf "%02d" "${utilization%%.*}")
  else
    formatted_util="${utilization}"
  fi

  jq -n -c \
    --arg temp "${temperature}°C" \
    --arg icon "$icon_text" \
    --arg util "${formatted_util}󱉸" \
    --arg tooltip "$tooltip" \
    '{temp: $temp, icon: $icon, util: $util, tooltip: $tooltip}' >"$cache_file"
}

general_query() {
  # Determine which GPU address to use based on priority
  local gpu_addr=""
  local vendor=""

  if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
    gpu_addr="${NVIDIA_ADDR}"
    vendor="nvidia"
  elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
    gpu_addr="${AMD_ADDR}"
    vendor="amd"
  elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
    gpu_addr="${INTEL_ADDR}"
    vendor="intel"
  fi

  # Find the DRM card corresponding to this PCI address
  local card_path=""
  if [[ -n "${gpu_addr}" ]]; then
    for card in /sys/class/drm/card[0-9]*; do
      if [[ -L "${card}/device" ]]; then
        local device_path=$(readlink -f "${card}/device")
        if [[ "${device_path}" == *"${gpu_addr}"* ]]; then
          card_path="${card}"
          break
        fi
      fi
    done
  fi

  # Fallback: find any GPU card if address lookup fails
  if [[ -z "${card_path}" ]]; then
    for card in /sys/class/drm/card[0-9]*; do
      # Skip render nodes
      [[ "${card}" == *"-"* ]] && continue
      if [[ -d "${card}/device" ]]; then
        card_path="${card}"
        break
      fi
    done
  fi

  # Reset variables
  temperature="" utilization="" current_clock_speed="" max_clock_speed=""
  power_usage="" power_limit="" fan_speed="" power_discharge="" core_clock=""

  if [[ -n "${card_path}" ]]; then
    # === TEMPERATURE AND FAN FROM HWMON ===
    local hwmon_path="${card_path}/device/hwmon"
    if [[ -d "${hwmon_path}" ]]; then
      for hwmon in "${hwmon_path}"/hwmon*; do
        if [[ -d "${hwmon}" ]]; then
          # Temperature (look for edge, junction, or generic temp1)
          for temp_file in "${hwmon}"/temp*_input; do
            if [[ -f "${temp_file}" ]]; then
              local temp_label_file="${temp_file/_input/_label}"
              local temp_label=""
              [[ -f "${temp_label_file}" ]] && temp_label=$(cat "${temp_label_file}" 2>/dev/null)

              # Prefer edge temperature for AMD, or first available
              if [[ "${temp_label}" == "edge" ]] || [[ -z "${temperature}" ]]; then
                temperature=$(awk '{print int($1/1000)}' "${temp_file}" 2>/dev/null)
                [[ -n "${temperature}" && "${temp_label}" == "edge" ]] && break
              fi
            fi
          done

          # Fan speed
          for fan_file in "${hwmon}"/fan*_input; do
            if [[ -f "${fan_file}" ]]; then
              fan_speed=$(cat "${fan_file}" 2>/dev/null)
              [[ -n "${fan_speed}" ]] && break
            fi
          done

          # Power usage
          if [[ -f "${hwmon}/power1_average" ]]; then
            power_usage=$(awk '{printf "%.1f", $1/1000000}' "${hwmon}/power1_average" 2>/dev/null)
          elif [[ -f "${hwmon}/power1_input" ]]; then
            power_usage=$(awk '{printf "%.1f", $1/1000000}' "${hwmon}/power1_input" 2>/dev/null)
          fi

          # Power limit
          if [[ -f "${hwmon}/power1_cap" ]]; then
            power_limit=$(awk '{printf "%.1f", $1/1000000}' "${hwmon}/power1_cap" 2>/dev/null)
          elif [[ -f "${hwmon}/power1_cap_max" ]]; then
            power_limit=$(awk '{printf "%.1f", $1/1000000}' "${hwmon}/power1_cap_max" 2>/dev/null)
          fi
        fi
      done
    fi

    # === GPU UTILIZATION ===
    # AMD: gpu_busy_percent
    if [[ -f "${card_path}/device/gpu_busy_percent" ]]; then
      utilization=$(cat "${card_path}/device/gpu_busy_percent" 2>/dev/null)
    fi

    # Intel: Use i915 sysfs if available
    if [[ "${vendor}" == "intel" ]]; then
      # Intel GT frequency files
      if [[ -f "${card_path}/gt_cur_freq_mhz" ]]; then
        current_clock_speed=$(cat "${card_path}/gt_cur_freq_mhz" 2>/dev/null)
      fi
      if [[ -f "${card_path}/gt_max_freq_mhz" ]]; then
        max_clock_speed=$(cat "${card_path}/gt_max_freq_mhz" 2>/dev/null)
      elif [[ -f "${card_path}/gt_RP0_freq_mhz" ]]; then
        max_clock_speed=$(cat "${card_path}/gt_RP0_freq_mhz" 2>/dev/null)
      fi

      # Try to estimate utilization from frequency if not available
      if [[ -z "${utilization}" && -n "${current_clock_speed}" && -n "${max_clock_speed}" && "${max_clock_speed}" -gt 0 ]]; then
        utilization=$(awk -v cur="${current_clock_speed}" -v max="${max_clock_speed}" 'BEGIN {printf "%.0f", (cur/max)*100}')
      fi
    fi

    # AMD: Clock speeds from pp_dpm files or hwmon
    if [[ "${vendor}" == "amd" ]]; then
      # Try to get current clock from sysfs
      local pp_dpm_sclk="${card_path}/device/pp_dpm_sclk"
      if [[ -f "${pp_dpm_sclk}" ]]; then
        # Extract current clock (marked with *)
        current_clock_speed=$(grep '\*' "${pp_dpm_sclk}" 2>/dev/null | awk '{print $2}' | sed 's/Mhz//')
        # Extract max clock (last entry)
        max_clock_speed=$(tail -n1 "${pp_dpm_sclk}" 2>/dev/null | awk '{print $2}' | sed 's/Mhz//')
      fi

      # Alternative: freq1 from hwmon
      if [[ -z "${current_clock_speed}" ]]; then
        local hwmon_path="${card_path}/device/hwmon"
        for hwmon in "${hwmon_path}"/hwmon*; do
          if [[ -f "${hwmon}/freq1_input" ]]; then
            current_clock_speed=$(awk '{print int($1/1000000)}' "${hwmon}/freq1_input" 2>/dev/null)
          fi
          if [[ -f "${hwmon}/freq1_max" ]]; then
            max_clock_speed=$(awk '{print int($1/1000000)}' "${hwmon}/freq1_max" 2>/dev/null)
          fi
        done
      fi
    fi

    # === FALLBACK: Try sensors command for temperature if sysfs failed ===
    if [[ -z "${temperature}" ]]; then
      local sensors_data=$(sensors 2>/dev/null)
      temperature=$(echo "${sensors_data}" | grep -m 1 -E "(edge|Package id|GPU)" | awk -F ':' '{print int($2)}' 2>/dev/null)
    fi
  fi

  # === BATTERY POWER DISCHARGE (for laptops) ===
  for file in /sys/class/power_supply/BAT*/power_now; do
    [[ -f "${file}" ]] && power_discharge=$(awk '{printf "%.1f", $1*10^-6}' "${file}" 2>/dev/null) && break
  done

  if [[ -z "${power_discharge}" ]]; then
    for file in /sys/class/power_supply/BAT*/current_now; do
      if [[ -f "${file}" ]]; then
        local current=$(cat "${file}" 2>/dev/null)
        local voltage=$(cat "${file/current_now/voltage_now}" 2>/dev/null)
        if [[ -n "${current}" && -n "${voltage}" ]]; then
          power_discharge=$(awk -v c="${current}" -v v="${voltage}" 'BEGIN {printf "%.1f", (c*v)/10^12}')
          break
        fi
      fi
    done
  fi

  # === FALLBACK UTILIZATION: Estimate from GPU activity if available ===
  if [[ -z "${utilization}" ]]; then
    # Some Intel GPUs expose RC6 residency - we can estimate inverse utilization
    if [[ -f "${card_path}/power/rc6_residency_ms" ]]; then
      # This is a cumulative counter, would need previous value to calculate
      # For now, leave empty or set a placeholder
      utilization="N/A"
    else
      utilization="N/A"
    fi
  fi

  # Ensure numeric values or empty
  [[ "${temperature}" == "N/A" ]] && temperature=""
  [[ "${utilization}" == "N/A" ]] && utilization=""
}

intel_GPU() { #? Function to query basic intel GPU
  primary_gpu="Intel ${GPUINFO_INTEL_GPU}"
  general_query
}

nvidia_GPU() { #? Function to query Nvidia GPU
  primary_gpu="NVIDIA ${GPUINFO_NVIDIA_GPU}"
  gpu_error=""
  if [[ -z "${NVIDIA_ADDR}" ]]; then
    NVIDIA_ADDR=$(lspci -nn | grep -Ei "(VGA|3D)" | grep -m 1 "10de" | awk '{print $1}')
  fi
  if [[ "${GPUINFO_NVIDIA_GPU}" == "Linux" ]]; then
    general_query
    return
  fi #? Open source driver
  #? Tired Flag for not using nvidia-smi if GPU is in suspend mode.
  if ${tired} && [[ -n "${NVIDIA_ADDR}" ]]; then
    is_suspend="$(cat /sys/bus/pci/devices/0000:"${NVIDIA_ADDR}"/power/runtime_status)"
    if [[ ${is_suspend} == *"suspend"* ]]; then
      printf '{"text":"󰤂", "tooltip":"%s ⏾ Suspended mode"}' "${primary_gpu}"
      exit
    fi
  fi
  if ! gpu_info=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,clocks.current.graphics,clocks.max.graphics,power.draw,power.limit --format=csv,noheader,nounits 2>&1); then
    gpu_error="${gpu_info%%$'\n'*}"
    general_query
    return
  fi
  if [[ "${gpu_info}" == *"NVIDIA-SMI has failed"* ]] || [[ "${gpu_info}" == *"Failed to initialize NVML"* ]]; then
    gpu_error="${gpu_info%%$'\n'*}"
    general_query
    return
  fi
  # Split the comma-separated values into an array
  IFS=',' read -ra gpu_data <<<"${gpu_info}"
  # Extract individual values
  temperature="${gpu_data[0]// /}"
  utilization="${gpu_data[1]// /}"
  current_clock_speed="${gpu_data[2]// /}"
  max_clock_speed="${gpu_data[3]// /}"
  power_usage="${gpu_data[4]// /}"
  power_limit="${gpu_data[5]// /}"
}

amd_GPU() { #? Function to query amd GPU
  primary_gpu="AMD ${GPUINFO_AMD_GPU}"
  # Execute the AMD GPU Python script and use its output
  amd_output=$(python3 ${scrDir}/amdgpu.py)
  if [[ ! ${amd_output} == *"No AMD GPUs detected."* ]] && [[ ! ${amd_output} == *"Unknown query failure"* ]]; then
    # Extract GPU Temperature, GPU Load, GPU Core Clock, and GPU Power Usage from amd_output
    temperature=$(echo "${amd_output}" | jq -r '.["GPU Temperature"]' | sed 's/°C//')
    utilization=$(echo "${amd_output}" | jq -r '.["GPU Load"]' | sed 's/%//')
    core_clock=$(echo "${amd_output}" | jq -r '.["GPU Core Clock"]' | sed 's/ GHz//;s/ MHz//')
    power_usage=$(echo "${amd_output}" | jq -r '.["GPU Power Usage"]' | sed 's/ Watts//')

  else
    general_query
  fi
}

if [[ ! -f "${gpuinfo_file}" ]]; then
  query
  echo -e "Initialized Variable:\n$(cat "${gpuinfo_file}")\n\nReboot or '$0 --reset' to RESET Variables"
fi
source "${gpuinfo_file}"

case "$1" in
  "--toggle" | "-t")
    toggle
    echo -e "Sensor: ${NEXT_PRIORITY} GPU" | sed 's/_ENABLE//g'
    exit
    ;;
  "--use" | "-u")
    toggle "$2"
    ;;
  "--reset" | "-rf")
    rm -fr "${gpuinfo_file}"*
    query
    echo -e "Initialized Variable:\n$(cat "${gpuinfo_file}" || true)\n\nReboot or '$0 --reset' to RESET Variables"
    exit
    ;;
  "--stat")
    case "$2" in
      "amd")
        if [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
          echo "GPUINFO_AMD_ENABLE: ${GPUINFO_AMD_ENABLE}"
          exit 0
        fi
        ;;
      "intel")
        if [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
          echo "GPUINFO_INTEL_ENABLE: ${GPUINFO_INTEL_ENABLE}"
          exit 0
        fi
        ;;
      "nvidia")
        if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
          echo "GPUINFO_NVIDIA_ENABLE: ${GPUINFO_NVIDIA_ENABLE}"
          exit 0
        fi
        ;;
      *)
        echo "Error: Invalid argument for --stat. Use amd, intel, or nvidia."
        exit 1
        ;;
    esac
    echo "GPU not enabled."
    exit 1
    ;;
  *"-"*)
    GPUINFO_AVAILABLE=${GPUINFO_AVAILABLE//GPUINFO_/}
    cat <<EOF
  Available GPU: ${GPUINFO_AVAILABLE//_ENABLE/}
[options]
--toggle         * Toggle available GPU
--use [GPU]      * Only call the specified GPU (Useful for adding specific GPU on waybar)
--reset          *  Remove & restart all query

[output modes]
-i, --icon       * Output colored icon with tooltip
-u, --util       * Output utilization percentage with tooltip
-a, --all        * Output all data as JSON

[flags]
--tired            * Adding this option will not query nvidia-smi if gpu is in suspend mode
--startup          * Useful if you want a certain GPU to be set at startup
--emoji            * Use Emoji instead of Glyphs

* If ${USER} declared env = AQ_DRM_DEVICES on hyprland then use this as the primary GPU
EOF
    exit
    ;;
esac

GPUINFO_NVIDIA_ENABLE=${GPUINFO_NVIDIA_ENABLE:-0} GPUINFO_INTEL_ENABLE=${GPUINFO_INTEL_ENABLE:-0} GPUINFO_AMD_ENABLE=${GPUINFO_AMD_ENABLE:-0}
#? Based on the flags, call the corresponding function multi flags means multi GPU.
if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
  nvidia_GPU
elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
  amd_GPU
elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
  intel_GPU
else
  primary_gpu="Not found"
  general_query
fi

# Cap utilization at 99% if it exceeds that value
if [[ -n "${utilization}" && "${utilization}" != "N/A" ]]; then
  # Remove any non-numeric characters and check if > 99
  util_num="${utilization%%.*}" # Get integer part
  if [[ "${util_num}" =~ ^[0-9]+$ ]] && [[ "${util_num}" -gt 99 ]]; then
    utilization="99"
  fi
fi

generate_json #? AutoGen the Json txt for Waybar

case $OUTPUT_MODE in
  "icon") jq -c '{text: .icon, tooltip: .tooltip}' "$cache_file" ;;
  "util") jq -c '{text: .util, tooltip: .tooltip}' "$cache_file" ;;
  "all") cat "$cache_file" ;;
  *) jq -c '{text: (.icon + "\r" + .util), tooltip: .tooltip}' "$cache_file" ;;
esac

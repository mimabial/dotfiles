#!/usr/bin/env bash
# Vendor-specific GPU probe helpers.
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
      if [[ -z "${utilization}" ]]; then
        utilization=$(intel_gpu_top_util) || true
      fi

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
      # RC6 residency needs delta sampling, so report N/A here.
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
  amd_output=$(python3 ${script_dir}/amdgpu.py)
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

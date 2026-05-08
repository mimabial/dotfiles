#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Vendor-specific GPU probe helpers.

preferred_gpu_vendor() {
  if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
    gpu_addr="${NVIDIA_ADDR}"
    vendor="nvidia"
  elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
    gpu_addr="${AMD_ADDR}"
    vendor="amd"
  elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
    gpu_addr="${INTEL_ADDR}"
    vendor="intel"
  else
    gpu_addr=""
    vendor=""
  fi
}

find_card_path_by_addr() {
  local card=""
  local device_path=""

  [[ -n "${gpu_addr}" ]] || return 1
  for card in /sys/class/drm/card[0-9]*; do
    if [[ -L "${card}/device" ]]; then
      device_path="$(readlink -f "${card}/device")"
      if [[ "${device_path}" == *"${gpu_addr}"* ]]; then
        card_path="${card}"
        return 0
      fi
    fi
  done

  return 1
}

find_first_gpu_card() {
  local card=""

  for card in /sys/class/drm/card[0-9]*; do
    [[ "${card}" == *"-"* ]] && continue
    if [[ -d "${card}/device" ]]; then
      card_path="${card}"
      return 0
    fi
  done

  return 1
}

reset_gpu_metrics() {
  temperature=""
  utilization=""
  current_clock_speed=""
  max_clock_speed=""
  power_usage=""
  power_limit=""
  fan_speed=""
  power_discharge=""
  core_clock=""
}

read_hwmon_temperature() {
  local hwmon="$1"
  local temp_file="" temp_label_file="" temp_label=""

  for temp_file in "${hwmon}"/temp*_input; do
    [[ -f "${temp_file}" ]] || continue
    temp_label_file="${temp_file/_input/_label}"
    temp_label=""
    [[ -f "${temp_label_file}" ]] && temp_label=$(cat "${temp_label_file}" 2>/dev/null)

    if [[ "${temp_label}" == "edge" ]] || [[ -z "${temperature}" ]]; then
      temperature=$(awk '{print int($1/1000)}' "${temp_file}" 2>/dev/null)
      [[ -n "${temperature}" && "${temp_label}" == "edge" ]] && return 0
    fi
  done
}

read_hwmon_fan() {
  local hwmon="$1"
  local fan_file=""

  for fan_file in "${hwmon}"/fan*_input; do
    [[ -f "${fan_file}" ]] || continue
    fan_speed=$(cat "${fan_file}" 2>/dev/null)
    [[ -n "${fan_speed}" ]] && return 0
  done
}

read_hwmon_power() {
  local hwmon="$1"

  if [[ -f "${hwmon}/power1_average" ]]; then
    power_usage=$(awk '{printf "%.1f", $1/1000000}' "${hwmon}/power1_average" 2>/dev/null)
  elif [[ -f "${hwmon}/power1_input" ]]; then
    power_usage=$(awk '{printf "%.1f", $1/1000000}' "${hwmon}/power1_input" 2>/dev/null)
  fi

  if [[ -f "${hwmon}/power1_cap" ]]; then
    power_limit=$(awk '{printf "%.1f", $1/1000000}' "${hwmon}/power1_cap" 2>/dev/null)
  elif [[ -f "${hwmon}/power1_cap_max" ]]; then
    power_limit=$(awk '{printf "%.1f", $1/1000000}' "${hwmon}/power1_cap_max" 2>/dev/null)
  fi
}

read_hwmon_metrics() {
  local hwmon_path="${card_path}/device/hwmon"
  local hwmon=""

  [[ -d "${hwmon_path}" ]] || return 0
  for hwmon in "${hwmon_path}"/hwmon*; do
    [[ -d "${hwmon}" ]] || continue
    read_hwmon_temperature "${hwmon}"
    read_hwmon_fan "${hwmon}"
    read_hwmon_power "${hwmon}"
  done
}

read_intel_utilization() {
  [[ -n "${utilization}" ]] || utilization=$(intel_gpu_top_util) || true
}

read_intel_clocks() {
  if [[ -f "${card_path}/gt_cur_freq_mhz" ]]; then
    current_clock_speed=$(cat "${card_path}/gt_cur_freq_mhz" 2>/dev/null)
  fi
  if [[ -f "${card_path}/gt_max_freq_mhz" ]]; then
    max_clock_speed=$(cat "${card_path}/gt_max_freq_mhz" 2>/dev/null)
  elif [[ -f "${card_path}/gt_RP0_freq_mhz" ]]; then
    max_clock_speed=$(cat "${card_path}/gt_RP0_freq_mhz" 2>/dev/null)
  fi
}

estimate_intel_utilization_from_clock() {
  if [[ -z "${utilization}" && -n "${current_clock_speed}" && -n "${max_clock_speed}" && "${max_clock_speed}" -gt 0 ]]; then
    utilization=$(awk -v cur="${current_clock_speed}" -v max="${max_clock_speed}" 'BEGIN {printf "%.0f", (cur/max)*100}')
  fi
}

read_intel_metrics() {
  [[ "${vendor}" == "intel" ]] || return 0
  read_intel_utilization
  read_intel_clocks
  estimate_intel_utilization_from_clock
}

read_amd_utilization() {
  if [[ -f "${card_path}/device/gpu_busy_percent" ]]; then
    utilization=$(cat "${card_path}/device/gpu_busy_percent" 2>/dev/null)
  fi
}

read_amd_clocks_from_pp_dpm() {
  local pp_dpm_sclk="${card_path}/device/pp_dpm_sclk"
  [[ -f "${pp_dpm_sclk}" ]] || return 1

  current_clock_speed=$(grep '\*' "${pp_dpm_sclk}" 2>/dev/null | awk '{print $2}' | sed 's/Mhz//')
  max_clock_speed=$(tail -n1 "${pp_dpm_sclk}" 2>/dev/null | awk '{print $2}' | sed 's/Mhz//')
}

read_amd_clocks_from_hwmon() {
  local hwmon_path="${card_path}/device/hwmon"
  local hwmon=""

  for hwmon in "${hwmon_path}"/hwmon*; do
    if [[ -f "${hwmon}/freq1_input" ]]; then
      current_clock_speed=$(awk '{print int($1/1000000)}' "${hwmon}/freq1_input" 2>/dev/null)
    fi
    if [[ -f "${hwmon}/freq1_max" ]]; then
      max_clock_speed=$(awk '{print int($1/1000000)}' "${hwmon}/freq1_max" 2>/dev/null)
    fi
  done
}

read_amd_metrics() {
  [[ "${vendor}" == "amd" ]] || return 0
  read_amd_utilization
  read_amd_clocks_from_pp_dpm || read_amd_clocks_from_hwmon
}

read_sensors_temperature_fallback() {
  local sensors_data=""

  [[ -z "${temperature}" ]] || return 0
  sensors_data=$(sensors 2>/dev/null)
  temperature=$(awk -F ':' '/(edge|Package id|GPU)/ {print int($2); exit}' <<<"${sensors_data}" 2>/dev/null)
}

read_battery_discharge() {
  local file="" current="" voltage=""

  for file in /sys/class/power_supply/BAT*/power_now; do
    [[ -f "${file}" ]] && power_discharge=$(awk '{printf "%.1f", $1*10^-6}' "${file}" 2>/dev/null) && return 0
  done

  for file in /sys/class/power_supply/BAT*/current_now; do
    if [[ -f "${file}" ]]; then
      current=$(cat "${file}" 2>/dev/null)
      voltage=$(cat "${file/current_now/voltage_now}" 2>/dev/null)
      if [[ -n "${current}" && -n "${voltage}" ]]; then
        power_discharge=$(awk -v c="${current}" -v v="${voltage}" 'BEGIN {printf "%.1f", (c*v)/10^12}')
        return 0
      fi
    fi
  done
}

ensure_utilization_fallback() {
  [[ -z "${utilization}" ]] || return 0
  if [[ -f "${card_path}/power/rc6_residency_ms" ]]; then
    utilization="N/A"
  else
    utilization="N/A"
  fi
}

normalize_metric_output() {
  [[ "${temperature}" == "N/A" ]] && temperature=""
  [[ "${utilization}" == "N/A" ]] && utilization=""
  # Tests that don't fire return 1; under set -e the whole call chain
  # (general_query → intel_GPU → main) treats that as failure.
  return 0
}

select_card_path() {
  card_path=""
  find_card_path_by_addr || find_first_gpu_card || true
}

general_query() {
  preferred_gpu_vendor
  select_card_path
  reset_gpu_metrics

  if [[ -n "${card_path}" ]]; then
    read_hwmon_metrics
    read_intel_metrics
    read_amd_metrics
    read_sensors_temperature_fallback
  fi

  read_battery_discharge
  ensure_utilization_fallback
  normalize_metric_output
}

intel_GPU() {
  primary_gpu="Intel ${GPUINFO_INTEL_GPU}"
  general_query
}

nvidia_GPU() {
  primary_gpu="NVIDIA ${GPUINFO_NVIDIA_GPU}"
  gpu_error=""
  if [[ -z "${NVIDIA_ADDR}" ]]; then
    NVIDIA_ADDR=$(lspci -nn | grep -Ei "(VGA|3D)" | grep -m 1 "10de" | awk '{print $1}')
  fi
  if [[ "${GPUINFO_NVIDIA_GPU}" == "Linux" ]]; then
    general_query
    return
  fi
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
  IFS=',' read -ra gpu_data <<<"${gpu_info}"
  temperature="${gpu_data[0]// /}"
  utilization="${gpu_data[1]// /}"
  current_clock_speed="${gpu_data[2]// /}"
  max_clock_speed="${gpu_data[3]// /}"
  power_usage="${gpu_data[4]// /}"
  power_limit="${gpu_data[5]// /}"
}

amd_GPU() {
  primary_gpu="AMD ${GPUINFO_AMD_GPU}"
  amd_output=$(python3 "${script_dir}/amdgpu.py")
  if [[ ! ${amd_output} == *"No AMD GPUs detected."* ]] && [[ ! ${amd_output} == *"Unknown query failure"* ]]; then
    read -r temperature utilization core_clock power_usage < <(
      jq -r '[
        (.["GPU Temperature"] // "" | gsub("°C"; "")),
        (.["GPU Load"] // "" | gsub("%"; "")),
        (.["GPU Core Clock"] // "" | gsub(" GHz| MHz"; "")),
        (.["GPU Power Usage"] // "" | gsub(" Watts"; ""))
      ] | @tsv' <<<"${amd_output}"
    )
  else
    general_query
  fi
}

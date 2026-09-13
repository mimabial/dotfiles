#!/usr/bin/env bash

read_value() {
  local -n result="$1"
  IFS= read -r result <"$2"
}

read_scaled() {
  local value
  read_value value "$2" || return
  printf -v "$1" '%d' "$((value / $3))"
}

MICROWATTS_PER_DECIWATT=100000

read_microwatts() {
  local value tenths
  read_value value "$2" || return
  tenths=$(((value + MICROWATTS_PER_DECIWATT / 2) / MICROWATTS_PER_DECIWATT))
  printf -v "$1" '%d.%d' "$((tenths / 10))" "$((tenths % 10))"
}

preferred_gpu_vendor() {
  if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
    gpu_addr="${NVIDIA_ADDR:-}"
    vendor="nvidia"
  elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
    gpu_addr="${AMD_ADDR:-}"
    vendor="amd"
  elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
    gpu_addr="${INTEL_ADDR:-}"
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
    [[ -f "${temp_label_file}" ]] && read_value temp_label "${temp_label_file}" || true

    if [[ "${temp_label}" == "edge" ]] || [[ -z "${temperature}" ]]; then
      read_scaled temperature "${temp_file}" 1000 || true
      [[ -n "${temperature}" && "${temp_label}" == "edge" ]] && return 0
    fi
  done
}

read_hwmon_fan() {
  local hwmon="$1"
  local fan_file=""

  for fan_file in "${hwmon}"/fan*_input; do
    [[ -f "${fan_file}" ]] || continue
    read_value fan_speed "${fan_file}" || true
    [[ -n "${fan_speed}" ]] && return 0
  done
}

read_hwmon_power() {
  local hwmon="$1"

  if [[ -f "${hwmon}/power1_average" ]]; then
    read_microwatts power_usage "${hwmon}/power1_average" || true
  elif [[ -f "${hwmon}/power1_input" ]]; then
    read_microwatts power_usage "${hwmon}/power1_input" || true
  fi

  if [[ -f "${hwmon}/power1_cap" ]]; then
    read_microwatts power_limit "${hwmon}/power1_cap" || true
  elif [[ -f "${hwmon}/power1_cap_max" ]]; then
    read_microwatts power_limit "${hwmon}/power1_cap_max" || true
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
    read_value current_clock_speed "${card_path}/gt_cur_freq_mhz" || true
  fi
  if [[ -f "${card_path}/gt_max_freq_mhz" ]]; then
    read_value max_clock_speed "${card_path}/gt_max_freq_mhz" || true
  elif [[ -f "${card_path}/gt_RP0_freq_mhz" ]]; then
    read_value max_clock_speed "${card_path}/gt_RP0_freq_mhz" || true
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
    read_value utilization "${card_path}/device/gpu_busy_percent" || true
  fi
}

read_amd_clocks_from_pp_dpm() {
  local pp_dpm_sclk="${card_path}/device/pp_dpm_sclk"
  [[ -f "${pp_dpm_sclk}" ]] || return 1

  read -r current_clock_speed max_clock_speed < <(
    awk '{max=$2; if (/\*/) current=$2} END {gsub(/Mhz/, "", current); gsub(/Mhz/, "", max); print current, max}' "${pp_dpm_sclk}"
  )
}

read_amd_clocks_from_hwmon() {
  local hwmon_path="${card_path}/device/hwmon"
  local hwmon=""

  for hwmon in "${hwmon_path}"/hwmon*; do
    if [[ -f "${hwmon}/freq1_input" ]]; then
      read_scaled current_clock_speed "${hwmon}/freq1_input" 1000000 || true
    fi
    if [[ -f "${hwmon}/freq1_max" ]]; then
      read_scaled max_clock_speed "${hwmon}/freq1_max" 1000000 || true
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
    [[ -f "${file}" ]] && read_microwatts power_discharge "${file}" && return 0
  done

  for file in /sys/class/power_supply/BAT*/current_now; do
    if [[ -f "${file}" ]]; then
      read_value current "${file}" || true
      read_value voltage "${file/current_now/voltage_now}" || true
      if [[ -n "${current}" && -n "${voltage}" ]]; then
        power_discharge=$(awk -v c="${current}" -v v="${voltage}" 'BEGIN {printf "%.1f", (c*v)/10^12}')
        return 0
      fi
    fi
  done
}

ensure_utilization_fallback() {
  [[ -n "${utilization}" ]] || utilization="N/A"
}

normalize_metric_output() {
  [[ "${temperature}" == "N/A" ]] && temperature=""
  [[ "${utilization}" == "N/A" ]] && utilization=""
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

query_intel_gpu() {
  primary_gpu="Intel ${GPUINFO_INTEL_GPU}"
  general_query
}

query_nvidia_gpu() {
  primary_gpu="NVIDIA ${GPUINFO_NVIDIA_GPU}"
  gpu_error=""
  if [[ -z "${NVIDIA_ADDR:-}" ]]; then
    NVIDIA_ADDR=$(lspci -nn | awk 'toupper($0) ~ /(VGA|3D)/ && tolower($0) ~ /\[10de:/ {print $1; exit}')
  fi
  if [[ "${GPUINFO_NVIDIA_GPU}" == "Linux" ]]; then
    general_query
    return
  fi
  if ${tired} && [[ -n "${NVIDIA_ADDR}" ]]; then
    read_value is_suspend "/sys/bus/pci/devices/0000:${NVIDIA_ADDR}/power/runtime_status" || is_suspend=""
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

query_amd_gpu() {
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

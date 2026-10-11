#!/usr/bin/env bash

read_sensor_value_into() {
  local -n result="$1"
  IFS= read -r result <"$2"
}

read_scaled_sensor_into() {
  local value divisor="$3"
  read_sensor_value_into value "$2" || return
  printf -v "$1" '%d' "$((value / divisor))"
}

MICROWATTS_PER_DECIWATT=100000
MILLIDEGREES_PER_CELSIUS=1000
HERTZ_PER_MHZ=1000000

read_power_watts_into() {
  local value tenths
  read_sensor_value_into value "$2" || return
  tenths=$(((value + MICROWATTS_PER_DECIWATT / 2) / MICROWATTS_PER_DECIWATT))
  printf -v "$1" '%d.%d' "$((tenths / 10))" "$((tenths % 10))"
}

gpu_resolve_selected_vendor() {
  if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
    gpu_pci_address="${NVIDIA_ADDR:-}"
    gpu_vendor="nvidia"
  elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
    gpu_pci_address="${AMD_ADDR:-}"
    gpu_vendor="amd"
  elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
    gpu_pci_address="${INTEL_ADDR:-}"
    gpu_vendor="intel"
  else
    gpu_pci_address=""
    gpu_vendor=""
  fi
}

gpu_find_card_by_pci_address() {
  local card=""
  local device_path=""

  [[ -n "${gpu_pci_address}" ]] || return 1
  for card in /sys/class/drm/card[0-9]*; do
    if [[ -L "${card}/device" ]]; then
      device_path="$(readlink -f "${card}/device")"
      if [[ "${device_path}" == *"${gpu_pci_address}"* ]]; then
        gpu_card_path="${card}"
        return 0
      fi
    fi
  done

  return 1
}

gpu_find_first_card() {
  local card=""

  for card in /sys/class/drm/card[0-9]*; do
    [[ "${card}" == *"-"* ]] && continue
    if [[ -d "${card}/device" ]]; then
      gpu_card_path="${card}"
      return 0
    fi
  done

  return 1
}

gpu_reset_metrics() {
  gpu_temperature_c=""
  gpu_temperature_from_cpu_package=""
  gpu_utilization_percent=""
  gpu_utilization_from_clock=""
  gpu_current_clock_mhz=""
  gpu_max_clock_mhz=""
  gpu_power_w=""
  gpu_power_limit_w=""
  gpu_fan_rpm=""
  battery_discharge_w=""
  gpu_core_clock_mhz=""
}

read_hwmon_temperature() {
  local hwmon="$1"
  local temp_file="" temp_label_file="" temp_label=""

  for temp_file in "${hwmon}"/temp*_input; do
    [[ -f "${temp_file}" ]] || continue
    temp_label_file="${temp_file/_input/_label}"
    temp_label=""
    [[ -f "${temp_label_file}" ]] && read_sensor_value_into temp_label "${temp_label_file}" || true

    if [[ "${temp_label}" == "edge" ]] || [[ -z "${gpu_temperature_c}" ]]; then
      read_scaled_sensor_into gpu_temperature_c "${temp_file}" "$MILLIDEGREES_PER_CELSIUS" || true
      [[ -n "${gpu_temperature_c}" && "${temp_label}" == "edge" ]] && return 0
    fi
  done
  return 0
}

read_hwmon_fan() {
  local hwmon="$1"
  local fan_file=""

  for fan_file in "${hwmon}"/fan*_input; do
    [[ -f "${fan_file}" ]] || continue
    read_sensor_value_into gpu_fan_rpm "${fan_file}" || true
    [[ -n "${gpu_fan_rpm}" ]] && return 0
  done
}

read_hwmon_power() {
  local hwmon="$1"

  if [[ -f "${hwmon}/power1_average" ]]; then
    read_power_watts_into gpu_power_w "${hwmon}/power1_average" || true
  elif [[ -f "${hwmon}/power1_input" ]]; then
    read_power_watts_into gpu_power_w "${hwmon}/power1_input" || true
  fi

  if [[ -f "${hwmon}/power1_cap" ]]; then
    read_power_watts_into gpu_power_limit_w "${hwmon}/power1_cap" || true
  elif [[ -f "${hwmon}/power1_cap_max" ]]; then
    read_power_watts_into gpu_power_limit_w "${hwmon}/power1_cap_max" || true
  fi
}

read_hwmon_metrics() {
  local hwmon_path="${gpu_card_path}/device/hwmon"
  local hwmon=""

  [[ -d "${hwmon_path}" ]] || return 0
  for hwmon in "${hwmon_path}"/hwmon*; do
    [[ -d "${hwmon}" ]] || continue
    read_hwmon_temperature "${hwmon}"
    read_hwmon_fan "${hwmon}"
    read_hwmon_power "${hwmon}"
  done
}

gpu_sample_intel_utilization() {
  command -v intel_gpu_top &>/dev/null || return 1

  local sample util jq_filter
  sample=$(intel_gpu_top -J -n 1 -o - 2>/dev/null)
  [[ -z "${sample}" ]] && return 1

  jq_filter='
    (if type == "array" then .[0] else . end) |
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

read_intel_utilization() {
  [[ -n "${gpu_utilization_percent}" ]] || gpu_utilization_percent=$(gpu_sample_intel_utilization) || true
}

read_intel_clocks() {
  if [[ -f "${gpu_card_path}/gt_cur_freq_mhz" ]]; then
    read_sensor_value_into gpu_current_clock_mhz "${gpu_card_path}/gt_cur_freq_mhz" || true
  fi
  if [[ -f "${gpu_card_path}/gt_max_freq_mhz" ]]; then
    read_sensor_value_into gpu_max_clock_mhz "${gpu_card_path}/gt_max_freq_mhz" || true
  elif [[ -f "${gpu_card_path}/gt_RP0_freq_mhz" ]]; then
    read_sensor_value_into gpu_max_clock_mhz "${gpu_card_path}/gt_RP0_freq_mhz" || true
  fi
}

estimate_intel_utilization_from_clock() {
  if [[ -z "${gpu_utilization_percent}" && -n "${gpu_current_clock_mhz}" && -n "${gpu_max_clock_mhz}" && "${gpu_max_clock_mhz}" -gt 0 ]]; then
    gpu_utilization_percent=$(awk -v cur="${gpu_current_clock_mhz}" -v max="${gpu_max_clock_mhz}" 'BEGIN {printf "%.0f", (cur/max)*100}')
    gpu_utilization_from_clock=1
  fi
}

gpu_read_intel_sysfs_metrics() {
  [[ "${gpu_vendor}" == "intel" ]] || return 0
  read_intel_utilization
  read_intel_clocks
  estimate_intel_utilization_from_clock
}

read_amd_utilization() {
  if [[ -f "${gpu_card_path}/device/gpu_busy_percent" ]]; then
    read_sensor_value_into gpu_utilization_percent "${gpu_card_path}/device/gpu_busy_percent" || true
  fi
}

read_amd_clocks_from_pp_dpm() {
  local pp_dpm_sclk="${gpu_card_path}/device/pp_dpm_sclk"
  [[ -f "${pp_dpm_sclk}" ]] || return 1

  read -r gpu_current_clock_mhz gpu_max_clock_mhz < <(
    awk '{max=$2; if (/\*/) current=$2} END {gsub(/Mhz/, "", current); gsub(/Mhz/, "", max); print current, max}' "${pp_dpm_sclk}"
  )
}

read_amd_clocks_from_hwmon() {
  local hwmon_path="${gpu_card_path}/device/hwmon"
  local hwmon=""

  for hwmon in "${hwmon_path}"/hwmon*; do
    if [[ -f "${hwmon}/freq1_input" ]]; then
      read_scaled_sensor_into gpu_current_clock_mhz "${hwmon}/freq1_input" "$HERTZ_PER_MHZ" || true
    fi
    if [[ -f "${hwmon}/freq1_max" ]]; then
      read_scaled_sensor_into gpu_max_clock_mhz "${hwmon}/freq1_max" "$HERTZ_PER_MHZ" || true
    fi
  done
}

gpu_read_amd_sysfs_metrics() {
  [[ "${gpu_vendor}" == "amd" ]] || return 0
  read_amd_utilization
  read_amd_clocks_from_pp_dpm || read_amd_clocks_from_hwmon
}

read_sensors_temperature_fallback() {
  local sensors_data="" sensor_label=""

  [[ -z "${gpu_temperature_c}" ]] || return 0
  sensors_data=$(sensors 2>/dev/null || true)
  IFS=$'\t' read -r sensor_label gpu_temperature_c \
    < <(awk -F ':' '/(edge|Package id|GPU)/ {print $1 "\t" int($2); exit}' <<<"${sensors_data}" 2>/dev/null) || return 0
  [[ "${sensor_label}" != "Package id"* ]] || gpu_temperature_from_cpu_package=1
}

read_battery_discharge_watts() {
  local file="" current="" voltage=""

  for file in /sys/class/power_supply/BAT*/power_now; do
    [[ -f "${file}" ]] && read_power_watts_into battery_discharge_w "${file}" && return 0
  done

  for file in /sys/class/power_supply/BAT*/current_now; do
    if [[ -f "${file}" ]]; then
      read_sensor_value_into current "${file}" || true
      read_sensor_value_into voltage "${file/current_now/voltage_now}" || true
      if [[ -n "${current}" && -n "${voltage}" ]]; then
        battery_discharge_w=$(awk -v c="${current}" -v v="${voltage}" 'BEGIN {printf "%.1f", (c*v)/10^12}')
        return 0
      fi
    fi
  done
}


gpu_normalize_metrics() {
  [[ "${gpu_temperature_c}" == "N/A" ]] && gpu_temperature_c=""
  [[ "${gpu_utilization_percent}" == "N/A" ]] && gpu_utilization_percent=""
  return 0
}

gpu_resolve_card_path() {
  gpu_card_path=""
  gpu_find_card_by_pci_address || gpu_find_first_card || true
}

gpu_read_sysfs_metrics() {
  gpu_resolve_selected_vendor
  gpu_resolve_card_path
  gpu_reset_metrics

  if [[ -n "${gpu_card_path}" ]]; then
    read_hwmon_metrics
    gpu_read_intel_sysfs_metrics
    gpu_read_amd_sysfs_metrics
    read_sensors_temperature_fallback
  fi

  read_battery_discharge_watts
  gpu_normalize_metrics
}

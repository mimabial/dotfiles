source "${BASH_SOURCE[0]%/*}/sysfs-metrics.bash"

gpu_read_intel_metrics() {
  gpu_model="Intel ${GPUINFO_INTEL_GPU}"
  gpu_read_sysfs_metrics
}

gpu_read_nvidia_metrics() {
  local gpu_info is_suspend
  local -a gpu_data=()
  gpu_model="NVIDIA ${GPUINFO_NVIDIA_GPU}"
  gpu_query_error=""
  if [[ -z "${NVIDIA_ADDR:-}" ]]; then
    IFS=$'\t' read -r NVIDIA_ADDR _ < <(gpu_pci_record "${GPU_PCI_VENDOR_IDS[nvidia]}" 'NVIDIA Corporation' "$(lspci -nn 2>/dev/null)") || true
  fi
  if [[ "${GPUINFO_NVIDIA_GPU}" == "Linux" ]]; then
    gpu_read_sysfs_metrics
    return
  fi
  if "$skip_suspended_nvidia" && [[ -n "${NVIDIA_ADDR}" ]]; then
    read_sensor_value_into is_suspend "/sys/bus/pci/devices/0000:${NVIDIA_ADDR}/power/runtime_status" || is_suspend=""
    if [[ ${is_suspend} == *"suspend"* ]]; then
      jq -nc --arg model "$gpu_model" '{text:"󰤂", tooltip:($model + " ⏾ Suspended mode")}'
      exit
    fi
  fi
  if ! gpu_info=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,clocks.current.graphics,clocks.max.graphics,power.draw,power.limit --format=csv,noheader,nounits 2>&1) ||
    gpu_nvidia_smi_failed "${gpu_info}"; then
    gpu_query_error="${gpu_info%%$'\n'*}"
    gpu_read_sysfs_metrics
    return
  fi
  IFS=',' read -ra gpu_data <<<"${gpu_info}"
  gpu_temperature_c="${gpu_data[0]// /}"
  gpu_utilization_percent="${gpu_data[1]// /}"
  gpu_current_clock_mhz="${gpu_data[2]// /}"
  gpu_max_clock_mhz="${gpu_data[3]// /}"
  gpu_power_w="${gpu_data[4]// /}"
  gpu_power_limit_w="${gpu_data[5]// /}"
}

gpu_read_amd_metrics() {
  local amd_metrics_json amd_metric_values
  gpu_model="AMD ${GPUINFO_AMD_GPU}"
  if amd_metrics_json=$(python3 "${sysinfo_dir}/gpu/amd-metrics.py") &&
    amd_metric_values=$(jq -er '[.temperature_c, .utilization_percent, .clock_mhz, .power_w] | join("|")' <<<"$amd_metrics_json"); then
    IFS='|' read -r gpu_temperature_c gpu_utilization_percent gpu_core_clock_mhz gpu_power_w <<<"$amd_metric_values"
  else
    gpu_read_sysfs_metrics
  fi
}

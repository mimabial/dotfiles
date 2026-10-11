#!/usr/bin/env bash
declare -A GPU_PCI_VENDOR_IDS=([nvidia]=10de [amd]=1002 [intel]=8086)

gpu_nvidia_smi_failed() {
  [[ "$1" == *'NVIDIA-SMI has failed'* || "$1" == *'Failed to initialize NVML'* ]]
}

gpu_pci_record() {
  awk -v id="$1" -v prefix="$2" '
    toupper($0) ~ "(VGA|3D)" && tolower($0) ~ "\\[" tolower(id) ":" {
      addr=$1; name=$0; sub("^.*" prefix " ", "", name)
      gsub(/ *\[[^]]*\]/, "", name); gsub(/ *\([^)]*\)/, "", name)
      print addr "\t" name; exit
    }' <<<"$3"
}

gpu_select_primary_device() {
  [[ -n "$AQ_DRM_DEVICES" ]] || return 1
  local device="${AQ_DRM_DEVICES%%:*}" card link slot vendor_id vendor primary_vendor=""
  card="${device##*/}"

  for link in /dev/dri/by-path/*-card; do
    [[ -L "$link" && "$(readlink "$link")" == *"/$card" ]] || continue
    slot="${link##*/pci-0000:}"
    slot="${slot%-card}"
    break
  done
  [[ -n "${slot:-}" ]] || return 1
  vendor_id=$(lspci -nn -s "${slot:-}" 2>/dev/null) || return
  for vendor in "${!GPU_PCI_VENDOR_IDS[@]}"; do
    [[ "$vendor_id" == *"${GPU_PCI_VENDOR_IDS[$vendor]}"* ]] && primary_vendor="${vendor}" && break
  done
  [[ -n "$primary_vendor" ]] && gpu_select_vendor "$primary_vendor"
}

gpu_detect_inventory() {
  local pci nvidia_smi_output="" nvidia_pci_name=""
  local NVIDIA_ADDR="" AMD_ADDR="" INTEL_ADDR=""
  local GPUINFO_NVIDIA_GPU="" GPUINFO_AMD_GPU="" GPUINFO_INTEL_GPU=""
  local GPUINFO_NVIDIA_ENABLE=0 GPUINFO_AMD_ENABLE=0 GPUINFO_INTEL_ENABLE=0
  pci=$(lspci -nn 2>/dev/null || true)
  IFS=$'\t' read -r NVIDIA_ADDR nvidia_pci_name < <(gpu_pci_record "${GPU_PCI_VENDOR_IDS[nvidia]}" 'NVIDIA Corporation' "$pci") || true
  IFS=$'\t' read -r AMD_ADDR GPUINFO_AMD_GPU < <(gpu_pci_record "${GPU_PCI_VENDOR_IDS[amd]}" 'Advanced Micro Devices, Inc.' "$pci") || true
  IFS=$'\t' read -r INTEL_ADDR GPUINFO_INTEL_GPU < <(gpu_pci_record "${GPU_PCI_VENDOR_IDS[intel]}" 'Intel Corporation' "$pci") || true

  if lsmod | grep -q nouveau; then
    GPUINFO_NVIDIA_GPU=Linux
    GPUINFO_NVIDIA_ENABLE=1
  elif command -v nvidia-smi &>/dev/null &&
    nvidia_smi_output=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader,nounits 2>&1); then
    GPUINFO_NVIDIA_GPU="${nvidia_smi_output%%$'\n'*}"
    GPUINFO_NVIDIA_GPU="${GPUINFO_NVIDIA_GPU#NVIDIA }"
    if [[ -n "$GPUINFO_NVIDIA_GPU" ]] && ! gpu_nvidia_smi_failed "$GPUINFO_NVIDIA_GPU"; then
      GPUINFO_NVIDIA_ENABLE=1
    fi
  fi
  if (( ! GPUINFO_NVIDIA_ENABLE )) && [[ -n "$NVIDIA_ADDR" ]]; then
    GPUINFO_NVIDIA_GPU="$nvidia_pci_name"
    GPUINFO_NVIDIA_ENABLE=1
  fi
  [[ -n "$AMD_ADDR" ]] && GPUINFO_AMD_ENABLE=1
  [[ -n "$INTEL_ADDR" ]] && GPUINFO_INTEL_ENABLE=1

  {
    if (( GPUINFO_NVIDIA_ENABLE )); then printf 'NVIDIA_ADDR=%q\nGPUINFO_NVIDIA_GPU=%q\nGPUINFO_NVIDIA_ENABLE=1\n' "$NVIDIA_ADDR" "$GPUINFO_NVIDIA_GPU"; fi
    if (( GPUINFO_AMD_ENABLE )); then printf 'AMD_ADDR=%q\nGPUINFO_AMD_ENABLE=1\nGPUINFO_AMD_GPU=%q\n' "$AMD_ADDR" "$GPUINFO_AMD_GPU"; fi
    if (( GPUINFO_INTEL_ENABLE )); then printf 'INTEL_ADDR=%q\nGPUINFO_INTEL_ENABLE=1\nGPUINFO_INTEL_GPU=%q\n' "$INTEL_ADDR" "$GPUINFO_INTEL_GPU"; fi
    printf 'tired=%s\n' "$tired"
  } >"$gpu_cache_file"
  gpu_restore_selection || gpu_select_primary_device || gpu_select_first_available
}

gpu_select_first_available() {
  local cache_line
  while IFS= read -r cache_line; do
    [[ "$cache_line" == GPUINFO_*_ENABLE=1 ]] || continue
    gpu_activate_selection "${cache_line%=1}"
    return
  done <"$gpu_cache_file"
}

#!/usr/bin/env bash

gpu_pci_record() {
  awk -v id="$1" -v prefix="$2" '
    toupper($0) ~ "(VGA|3D)" && tolower($0) ~ "\\[" tolower(id) ":" {
      addr=$1; name=$0; sub("^.*" prefix " ", "", name)
      gsub(/ *\[[^]]*\]/, "", name); gsub(/ *\([^)]*\)/, "", name)
      print addr "\t" name; exit
    }' <<<"$3"
}

detect() {
  local device="${AQ_DRM_DEVICES%%:*}" card link slot vendor_id initGPU=""
  local -A vendors=([10de]=nvidia [8086]=intel [1002]=amd)
  card="${device##*/}"

  for link in /dev/dri/by-path/*-card; do
    [[ -L "$link" && "$(readlink "$link")" == *"/$card" ]] || continue
    slot="${link##*/pci-0000:}"
    slot="${slot%-card}"
    break
  done
  vendor_id=$(lspci -nn -s "${slot:-}" 2>/dev/null) || return
  for vendor in "${!vendors[@]}"; do
    [[ "$vendor_id" == *"$vendor"* ]] && initGPU="${vendors[$vendor]}" && break
  done
  [[ -n "$initGPU" ]] && "$0" --use "$initGPU" --startup
}

query() {
  local pci nvidia_smi_output="" nvidia_pci_name=""
  local NVIDIA_ADDR="" AMD_ADDR="" INTEL_ADDR=""
  local GPUINFO_NVIDIA_GPU="" GPUINFO_AMD_GPU="" GPUINFO_INTEL_GPU=""
  local GPUINFO_NVIDIA_ENABLE=0 GPUINFO_AMD_ENABLE=0 GPUINFO_INTEL_ENABLE=0
  pci=$(lspci -nn 2>/dev/null || true)
  IFS=$'\t' read -r NVIDIA_ADDR nvidia_pci_name < <(gpu_pci_record 10de 'NVIDIA Corporation' "$pci") || true
  IFS=$'\t' read -r AMD_ADDR GPUINFO_AMD_GPU < <(gpu_pci_record 1002 'Advanced Micro Devices, Inc.' "$pci") || true
  IFS=$'\t' read -r INTEL_ADDR GPUINFO_INTEL_GPU < <(gpu_pci_record 8086 'Intel Corporation' "$pci") || true

  if lsmod | grep -q nouveau; then
    GPUINFO_NVIDIA_GPU=Linux
    GPUINFO_NVIDIA_ENABLE=1
  elif command -v nvidia-smi &>/dev/null &&
    nvidia_smi_output=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader,nounits 2>&1); then
    GPUINFO_NVIDIA_GPU="${nvidia_smi_output%%$'\n'*}"
    GPUINFO_NVIDIA_GPU="${GPUINFO_NVIDIA_GPU#NVIDIA }"
    if [[ -n "$GPUINFO_NVIDIA_GPU" && "$GPUINFO_NVIDIA_GPU" != *'NVIDIA-SMI has failed'* && "$GPUINFO_NVIDIA_GPU" != *'Failed to initialize NVML'* ]]; then
      GPUINFO_NVIDIA_ENABLE=1
    fi
  fi
  if (( ! GPUINFO_NVIDIA_ENABLE )) && [[ -n "$NVIDIA_ADDR" ]]; then
    GPUINFO_NVIDIA_GPU="$nvidia_pci_name"
    GPUINFO_NVIDIA_ENABLE=1
  fi
  [[ -n "$AMD_ADDR" ]] && GPUINFO_AMD_ENABLE=1
  [[ -n "$INTEL_ADDR" ]] && GPUINFO_INTEL_ENABLE=1

  touch "$gpuinfo_file"
  {
    (( GPUINFO_NVIDIA_ENABLE )) && printf 'NVIDIA_ADDR=%q\nGPUINFO_NVIDIA_GPU=%q\nGPUINFO_NVIDIA_ENABLE=1\n' "$NVIDIA_ADDR" "$GPUINFO_NVIDIA_GPU"
    (( GPUINFO_AMD_ENABLE )) && printf 'AMD_ADDR=%q\nGPUINFO_AMD_ENABLE=1\nGPUINFO_AMD_GPU=%q\n' "$AMD_ADDR" "$GPUINFO_AMD_GPU"
    (( GPUINFO_INTEL_ENABLE )) && printf 'INTEL_ADDR=%q\nGPUINFO_INTEL_ENABLE=1\nGPUINFO_INTEL_GPU=%q\n' "$INTEL_ADDR" "$GPUINFO_INTEL_GPU"
  } >>"$gpuinfo_file"
  if ! grep -q '^GPUINFO_PRIORITY=' "$gpuinfo_file" && [[ -n "$AQ_DRM_DEVICES" ]]; then
    trap detect EXIT
  fi
}

toggle() {
  local line entry current_index=0 index
  local -a anchor=()
  while IFS= read -r line; do
    entry="${line#\#}"
    [[ "$entry" == GPUINFO_*_ENABLE=1 ]] && anchor+=("${entry%=1}")
  done <"$gpuinfo_file"

  if [[ -n "${1:-}" ]]; then
    NEXT_PRIORITY="GPUINFO_${1^^}_ENABLE"
    [[ " ${anchor[*]} " == *" $NEXT_PRIORITY "* ]] || { printf 'Error: %s not found in %s\n' "$NEXT_PRIORITY" "$gpuinfo_file" >&2; return 1; }
  else
    ((${#anchor[@]})) || { printf 'Error: no GPU found\n' >&2; return 1; }
    if [[ -z "${GPUINFO_AVAILABLE:-}" ]]; then
      printf 'GPUINFO_AVAILABLE=%q\n' "${anchor[*]}" >>"$gpuinfo_file"
    fi
    GPUINFO_PRIORITY="${GPUINFO_PRIORITY:-${anchor[0]}}"
    for index in "${!anchor[@]}"; do
      [[ "${anchor[$index]}" == "$GPUINFO_PRIORITY" ]] && current_index=$index
    done
    NEXT_PRIORITY="${anchor[$(((current_index + 1) % ${#anchor[@]}))]}"
  fi

  sed -i -e 's/^\(GPUINFO_NVIDIA_ENABLE=1\|GPUINFO_AMD_ENABLE=1\|GPUINFO_INTEL_ENABLE=1\)/#\1/' \
    -e "s/^#$NEXT_PRIORITY/$NEXT_PRIORITY/" "$gpuinfo_file"
  update_state_var GPUINFO_PRIORITY "$NEXT_PRIORITY"
  gpu_state_lib && state_set GPUINFO_PRIORITY "$NEXT_PRIORITY" >/dev/null 2>&1
}

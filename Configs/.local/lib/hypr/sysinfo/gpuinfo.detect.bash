#!/usr/bin/env bash
# GPU detection and state-toggle helpers.
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
    if [[ -n "${GPUINFO_NVIDIA_GPU}" ]]; then                                                                                               # Check for NVIDIA GPU
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

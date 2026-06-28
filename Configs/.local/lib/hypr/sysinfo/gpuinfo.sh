#!/usr/bin/env bash
# shellcheck disable=SC2312

# Benchmark Tool: hyperfine
# NVIDIA: gpuinfo.sh
#   Time (mean ± σ):      75.7 ms ±   8.0 ms    [User: 31.0 ms, System: 41.9 ms]
#   Range (min … max):    45.7 ms …  91.4 ms    34 runs

# INTEL/GENERAL: gpuinfo.sh
#   Time (mean ± σ):     246.9 ms ±  22.5 ms    [User: 112.4 ms, System: 87.5 ms]
# Range (min … max):   184.0 ms … 272.1 ms    12 runs

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell sysinfo/gpuinfo [--toggle|--use <gpu>|--reset|--stat <amd|intel|nvidia>]
Emit GPU stats as waybar JSON; flags manage GPU selection and cached state." "$@"

script_dir=$(dirname "$(realpath "$0")")
gpuinfo_file="${TMPDIR:-/tmp}/hypr-${UID}-gpuinfo"

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

# Namespace the state file by the second positional arg so multi-GPU contexts
# (e.g. `gpuinfo --use NVIDIA`) get their own cache. ${2:-} keeps no-arg
# polling invocations safe under set -u — they fall through to the base file.
if [[ ! " $* " =~ " --startup " ]]; then
  gpuinfo_file="${gpuinfo_file}${2:-}"
fi
# shellcheck source=/dev/null
source "${script_dir}/gpuinfo.detect.bash"
# shellcheck source=/dev/null
source "${script_dir}/gpuinfo.render.bash"
# shellcheck source=/dev/null
source "${script_dir}/gpuinfo.vendor.bash"

# Re-query when the state file is missing OR when it lost its GPU detection
# entries (e.g. truncated by a previous run that crashed mid-write, or hand
# edited). Without this, a stale file containing only persistent flags like
# GPUINFO_TEMP_BUCKET leaves the script stuck reporting primary_gpu="Not found".
if [[ ! -f "${gpuinfo_file}" ]] || ! grep -q "_ENABLE=1" "${gpuinfo_file}"; then
  query
fi
# shellcheck source=/dev/null
source "${gpuinfo_file}"

case "${1:-}" in
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

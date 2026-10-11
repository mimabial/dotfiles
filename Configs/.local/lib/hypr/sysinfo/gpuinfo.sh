#!/usr/bin/env bash
# shellcheck disable=SC2312

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell sysinfo/gpuinfo [--toggle|--use <gpu>|--reset|--stat <amd|intel|nvidia>]
Emit GPU stats as bar JSON; flags manage GPU selection and cached state." "$@"

sysinfo_dir="${BASH_SOURCE[0]%/*}"
gpu_cache_file="${TMPDIR:-/tmp}/hypr-${UID}-gpuinfo"

# WLR_DRM_DEVICES is the legacy name; detection needs the value, not its name.
AQ_DRM_DEVICES="${AQ_DRM_DEVICES:-${WLR_DRM_DEVICES:-}}"

tired=false
if [[ " $* " == *" --tired "* ]]; then
  if [[ -f "${gpu_cache_file}" ]] && grep -q '^tired=true$' "${gpu_cache_file}"; then
    printf 'already set tired flag\n'
  else
    [[ ! -f "$gpu_cache_file" ]] || sed -i '/^tired=/d' "$gpu_cache_file"
    printf 'tired=true\n' >>"${gpu_cache_file}"
    printf 'set tired flag\n'
  fi
  printf 'Nvidia GPU will not be queried if it is in suspend mode\nrun --reset to reset the flag\n'
  exit 0
fi

source "${sysinfo_dir}/gpu/selection.bash"
source "${sysinfo_dir}/gpu/detection.bash"

if [[ ! -f "$gpu_cache_file" ]] || ! grep -q "_ENABLE=1" "$gpu_cache_file"; then
  [[ ! -f "$gpu_cache_file" ]] || source "$gpu_cache_file"
  gpu_detect_inventory
fi
source "$gpu_cache_file"

case "${1:-}" in
  "--toggle" | "-t")
    gpu_select_vendor
    printf 'Sensor: %s GPU\n' "${GPUINFO_PRIORITY//_ENABLE/}"
    exit
    ;;
  "--use" | "-u")
    [[ -n "${2:-}" ]] || { printf '%s requires a GPU\n' "$1" >&2; exit 1; }
    gpu_select_vendor "$2"
    ;;
  "--reset" | "-rf")
    rm -f "${gpu_cache_file}"
    gpu_load_state_helpers && state_set GPUINFO_PRIORITY "" >/dev/null 2>&1
    gpu_detect_inventory
    echo -e "Initialized Variable:\n$(cat "${gpu_cache_file}" || true)\n\nReboot or '$0 --reset' to RESET Variables"
    exit
    ;;
  "--stat")
    # Inactive GPU flags are commented out and therefore unset.
    case "${2:-}" in
      "amd" | "intel" | "nvidia")
        stat_flag="GPUINFO_${2^^}_ENABLE"
        if [[ "${!stat_flag:-0}" -eq 1 ]]; then
          echo "${stat_flag}: 1"
          exit 0
        fi
        echo "${stat_flag}: 0"
        exit 1
        ;;
      *)
        echo "Error: Invalid argument for --stat. Use amd, intel, or nvidia."
        exit 1
        ;;
    esac
    ;;
  *"-"*)
    GPUINFO_AVAILABLE=${GPUINFO_AVAILABLE:-}
    GPUINFO_AVAILABLE=${GPUINFO_AVAILABLE//GPUINFO_/}
    cat <<EOF
  Available GPU: ${GPUINFO_AVAILABLE//_ENABLE/}
[options]
--toggle         * Toggle available GPU
--use [GPU]      * Only call the specified GPU
--reset          *  Remove & restart all query

[flags]
--tired            * Adding this option will not query nvidia-smi if gpu is in suspend mode

* AQ_DRM_DEVICES selects the primary GPU when set
EOF
    exit
    ;;
esac

GPUINFO_NVIDIA_ENABLE=${GPUINFO_NVIDIA_ENABLE:-0} GPUINFO_INTEL_ENABLE=${GPUINFO_INTEL_ENABLE:-0} GPUINFO_AMD_ENABLE=${GPUINFO_AMD_ENABLE:-0}
source "${sysinfo_dir}/gpu/metrics.bash"
source "${sysinfo_dir}/gpu/icon-levels.bash"
source "${sysinfo_dir}/lib/temperature-color.bash"
source "${sysinfo_dir}/gpu/render.bash"
gpu_reset_metrics
skip_suspended_nvidia=$tired

if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
  gpu_read_nvidia_metrics
elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
  gpu_read_amd_metrics
elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
  gpu_read_intel_metrics
else
  gpu_model="Not found"
  gpu_read_sysfs_metrics
fi

gpu_render_bar_json

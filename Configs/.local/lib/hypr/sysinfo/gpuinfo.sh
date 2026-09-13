#!/usr/bin/env bash
# shellcheck disable=SC2312

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell sysinfo/gpuinfo [--toggle|--use <gpu>|--reset|--stat <amd|intel|nvidia>]
Emit GPU stats as bar JSON; flags manage GPU selection and cached state." "$@"

script_dir="$(realpath "$0")"
script_dir="${script_dir%/*}"
gpuinfo_file="${TMPDIR:-/tmp}/hypr-${UID}-gpuinfo"

# WLR_DRM_DEVICES is the legacy name; detection needs the value, not its name.
AQ_DRM_DEVICES="${AQ_DRM_DEVICES:-${WLR_DRM_DEVICES:-}}"

tired=false
if [[ " $* " == *" --tired "* ]]; then
  if [[ -f "${gpuinfo_file}" ]] && grep -q "tired" "${gpuinfo_file}"; then
    printf 'already set tired flag\n'
  else
    printf 'tired=true\n' >>"${gpuinfo_file}"
    printf 'set tired flag\n'
  fi
  printf 'Nvidia GPU will not be queried if it is in suspend mode\nrun --reset to reset the flag\n'
  exit 0
fi

# Hardware detection is ephemeral; the user's selection survives in state.
gpu_state_lib() {
  declare -F state_get >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/state.sh" 2>/dev/null || return 1
}

restore_gpu_selection() {
  local saved
  gpu_state_lib || return 0
  saved="$(state_get GPUINFO_PRIORITY)"
  [[ -n "${saved}" ]] || return 0
  grep -q "^#\?${saved}=1" "${gpuinfo_file}" || return 0

  sed -i \
    -e 's/^\(GPUINFO_NVIDIA_ENABLE=1\|GPUINFO_AMD_ENABLE=1\|GPUINFO_INTEL_ENABLE=1\)/#\1/' \
    -e "s/^#${saved}=1/${saved}=1/" "${gpuinfo_file}"
  update_state_var GPUINFO_PRIORITY "${saved}"

  # An explicit choice outranks query()'s automatic EXIT selection.
  trap - EXIT
}

source "${script_dir}/gpuinfo.detect.bash"
# shellcheck source=/dev/null
source "${script_dir}/gpuinfo.render.bash"
# shellcheck source=/dev/null
source "${script_dir}/gpuinfo.vendor.bash"

# Recover incomplete or stale detection caches.
if [[ ! -f "${gpuinfo_file}" ]] || ! grep -q "_ENABLE=1" "${gpuinfo_file}"; then
  query
  restore_gpu_selection
fi
# shellcheck source=/dev/null
source "${gpuinfo_file}"

case "${1:-}" in
  "--toggle" | "-t")
    toggle
    printf 'Sensor: %s GPU\n' "${NEXT_PRIORITY//_ENABLE/}"
    exit
    ;;
  "--use" | "-u")
    [[ -n "${2:-}" ]] || { printf '%s requires a GPU\n' "$1" >&2; exit 1; }
    toggle "$2"
    ;;
  "--reset" | "-rf")
    rm -f "${gpuinfo_file}"
    gpu_state_lib && state_set GPUINFO_PRIORITY "" >/dev/null 2>&1
    query
    echo -e "Initialized Variable:\n$(cat "${gpuinfo_file}" || true)\n\nReboot or '$0 --reset' to RESET Variables"
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
if [[ "${GPUINFO_NVIDIA_ENABLE}" -eq 1 ]]; then
  query_nvidia_gpu
elif [[ "${GPUINFO_AMD_ENABLE}" -eq 1 ]]; then
  query_amd_gpu
elif [[ "${GPUINFO_INTEL_ENABLE}" -eq 1 ]]; then
  query_intel_gpu
else
  primary_gpu="Not found"
  general_query
fi

generate_json

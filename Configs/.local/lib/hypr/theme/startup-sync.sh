#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

sweep_orphaned_cache_temps() {
  local cache_root="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
  local age_min="${HYPR_STARTUP_SWEEP_AGE_MIN:-60}"

  [[ -d "${cache_root}" ]] || return 0
  [[ "${age_min}" =~ ^[0-9]+$ ]] || age_min=60

  find "${cache_root}" -mindepth 1 -maxdepth 1 -type d \
    -name 'wal-cache-only.*' -mmin "+${age_min}" \
    -exec rm -rf -- {} + 2>/dev/null || true

  if [[ -d "${cache_root}/wal/cache" ]]; then
    find "${cache_root}/wal/cache" -mindepth 1 -maxdepth 1 \
      \( -name '*.tmp.*' -o -name '*.bak.*' \) -mmin "+${age_min}" \
      -exec rm -rf -- {} + 2>/dev/null || true
  fi
}

sweep_orphaned_cache_temps

#!/usr/bin/env bash

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

run_startup_theme_sync_step() {
  local script_path="$1"
  local label="$2"

  [[ -r "${script_path}" ]] || return 0
  if ! bash "${script_path}" >/dev/null 2>&1; then
    print_log -sec "startup" -warn "${label}" "sync failed"
    return 1
  fi
}

run_startup_theme_sync_step "${LIB_DIR}/hypr/wal/wal.kvantum.sh" "kvantum" || exit 1
run_startup_theme_sync_step "${LIB_DIR}/hypr/wal/wal.qt.sh" "qt" || exit 1

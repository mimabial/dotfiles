#!/usr/bin/env bash
#
# globalcontrol.sh - Core utilities for Hypr shell scripts
#
# This file provides common functions and environment setup for all Hypr scripts.
# Source this file at the start of any script that needs access to theme settings,
# wallpaper management, or system configuration.
#
# Key exports:
#   HYPR_CONFIG_HOME, HYPR_DATA_HOME, HYPR_CACHE_HOME, HYPR_STATE_HOME
#   LIB_DIR, HYPR_LIB_DIR
#
# Key functions:
#   print_log()        - Colored logging output
#   get_hashmap()      - Find wallpapers with hashes for caching
#   get_themes()       - Populate theme list arrays
#   export_hypr_config() - Load state variables from staterc/config
#   get_hypr_conf()     - Get value from theme's hypr.theme file
#   pkg_installed()    - Check if a package is installed
#   state_get/set()    - Unified state management API

__hypr_globalcontrol_force="${HYPR_FORCE_RESOURCE_GLOBALCONTROL:-0}"
__hypr_globalcontrol_guard_pid="${HYPR_GLOBALCONTROL_GUARD_PID:-}"
[[ "${__hypr_globalcontrol_force}" =~ ^[0-9]+$ ]] || __hypr_globalcontrol_force=0

if (( __hypr_globalcontrol_force == 0 )) \
  && [[ "${__hypr_globalcontrol_guard_pid}" == "${BASHPID}" ]] \
  && declare -F export_hypr_config >/dev/null 2>&1; then
  unset __hypr_globalcontrol_force __hypr_globalcontrol_guard_pid
  return 0 2>/dev/null || exit 0
else
  HYPR_GLOBALCONTROL_GUARD_PID="${BASHPID}"
  unset HYPR_GLOBALCONTROL_SOURCED
  unset __hypr_globalcontrol_force __hypr_globalcontrol_guard_pid

  _hypr_xdg_lib="${LIB_DIR:-$HOME/.local/lib}/hypr/core/xdg.sh"
  [[ -r "${_hypr_xdg_lib}" ]] || {
    printf 'ERROR: missing core module %s\n' "${_hypr_xdg_lib}" >&2
    return 1 2>/dev/null || exit 1
  }
  # shellcheck source=/dev/null
  source "${_hypr_xdg_lib}" || { return 1 2>/dev/null || exit 1; }
  hypr_init_xdg_env
  unset _hypr_xdg_lib

  # hypr envs
  export HYPR_CONFIG_HOME="${XDG_CONFIG_HOME}/hypr"
  export HYPR_DATA_HOME="${XDG_DATA_HOME}/hypr"
  export HYPR_CACHE_HOME="${XDG_CACHE_HOME}/hypr"
  export HYPR_STATE_HOME="${XDG_STATE_HOME}/hypr"
  export HYPR_RUNTIME_DIR="${XDG_RUNTIME_DIR}/hypr"
  export ICONS_DIR="${XDG_DATA_HOME}/icons"
  export FONTS_DIR="${XDG_DATA_HOME}/fonts"
  export THEMES_DIR="${XDG_DATA_HOME}/themes"

  # Shared helper exports used across Hypr scripts.
  export HYPR_LIB_DIR="${LIB_DIR:-$HOME/.local/lib}/hypr"
  export WALLPAPER_CACHE_DIR="${HYPR_CACHE_HOME}/wallpaper"
  export WALLPAPER_CURRENT_DIR="${WALLPAPER_CACHE_DIR}/current"
  export WALLPAPER_THUMB_DIR="${WALLPAPER_CACHE_DIR}/thumbs"
  export WALLPAPER_VIDEO_DIR="${WALLPAPER_CURRENT_DIR}/thumbnails"
  # Use xxh64sum for faster hashing (3x faster than sha1sum)
  export HYPR_HASH_COMMAND="xxh64sum"

  if [[ -r "${HYPR_LIB_DIR}/runtime/lock_paths.sh" ]]; then
    # shellcheck source=/dev/null
    source "${HYPR_LIB_DIR}/runtime/lock_paths.sh"
  fi

  hypr_ensure_global_arrays() {
    local array_name=""

    for array_name in "$@"; do
      [[ "${array_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
        printf 'ERROR: invalid array name %s\n' "${array_name}" >&2
        return 1
      }
      declare -p "${array_name}" >/dev/null 2>&1 || declare -ga "${array_name}=()"
    done
  }

  # Wallpaper helpers expect these arrays to exist, even when empty.
  hypr_ensure_global_arrays \
    WALLPAPER_FILETYPES \
    WALLPAPER_OVERRIDE_FILETYPES \
    WALLPAPER_CUSTOM_PATHS \
    wallHash \
    wallList \
    wallPathArray

  hypr_source_core_module() {
    local module_path="${HYPR_LIB_DIR}/core/$1"
    [[ -r "${module_path}" ]] || {
      printf 'ERROR: missing core module %s\n' "${module_path}" >&2
      return 1
    }
    # shellcheck source=/dev/null
    source "${module_path}"
  }

  hypr_source_required_core_modules() {
    local module_name=""

    for module_name in "$@"; do
      hypr_source_core_module "${module_name}" || { return 1 2>/dev/null || exit 1; }
    done
  }

  hypr_source_required_core_modules \
    "common.sh" \
    "rofi.sh" \
    "notify.sh" \
    "wallpaper.catalog.sh" \
    "state.sh" \
    "system.sh"

  # ============================================================================
  # GLOBAL INITIALIZATION
  # ============================================================================
  # This section handles initialization that happens when the script is sourced.
  # Use HYPR_SKIP_INIT=1 to skip auto-initialization (for scripts that need
  # to control when state is loaded).
  #
  # To reload state after changes: call export_hypr_config explicitly
  # To force a full re-source in the same shell:
  #   HYPR_FORCE_RESOURCE_GLOBALCONTROL=1 source .../globalcontrol.sh
  # ============================================================================

  # Initialize hypr environment (loads state, sets defaults)
  # Called automatically unless HYPR_SKIP_INIT=1
  init_hypr_globals() {
  # Guard against re-initialization. Call export_hypr_config explicitly when a
  # script needs fresh state in the current shell.
    local hypr_global_init="${HYPR_GLOBAL_INIT:-0}"
    local runtime_border_radius=""
    local runtime_border_width=""

    [[ "${hypr_global_init}" =~ ^[0-9]+$ ]] || hypr_global_init=0

    if (( hypr_global_init == 1 )); then
      return 0
    fi

    # Load user state
    export_hypr_config

    refresh_hypr_runtime_state

  # Hyprland-specific settings (only if running under Hyprland)
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hypr_border_metrics_into runtime_border_radius runtime_border_width 2>/dev/null || true
  fi
    export HYPR_RUNTIME_BORDER_RADIUS="${runtime_border_radius:-${HYPR_BORDER_RADIUS:-2}}"
    export HYPR_RUNTIME_BORDER_WIDTH="${runtime_border_width:-${HYPR_BORDER_WIDTH:-2}}"

    # Mark as initialized
    HYPR_GLOBAL_INIT=1
  }

  # Auto-initialize unless explicitly skipped
  if [[ "${HYPR_SKIP_INIT:-0}" -ne 1 ]]; then
    init_hypr_globals
  fi
fi

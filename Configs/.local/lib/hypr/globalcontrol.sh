#!/usr/bin/env bash
# shellcheck disable=SC1091
# shellcheck disable=SC1090
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

# xdg resolution
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

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
  source "${HYPR_LIB_DIR}/runtime/lock_paths.sh"
fi

# Wallpaper helpers expect these arrays to exist, even when empty.
declare -p WALLPAPER_FILETYPES >/dev/null 2>&1 || declare -ag WALLPAPER_FILETYPES=()
declare -p WALLPAPER_OVERRIDE_FILETYPES >/dev/null 2>&1 || declare -ag WALLPAPER_OVERRIDE_FILETYPES=()
declare -p WALLPAPER_CUSTOM_PATHS >/dev/null 2>&1 || declare -ag WALLPAPER_CUSTOM_PATHS=()
declare -p wallHash >/dev/null 2>&1 || declare -ag wallHash=()
declare -p wallList >/dev/null 2>&1 || declare -ag wallList=()
declare -p wallPathArray >/dev/null 2>&1 || declare -ag wallPathArray=()

hypr_source_core_module() {
  local module_path="${HYPR_LIB_DIR}/core/$1"
  [[ -r "${module_path}" ]] || {
    printf 'ERROR: missing core module %s\n' "${module_path}" >&2
    return 1
  }
  source "${module_path}"
}

hypr_source_core_module "common.sh" || { return 1 2>/dev/null || exit 1; }
hypr_source_core_module "rofi.sh" || { return 1 2>/dev/null || exit 1; }
hypr_source_core_module "notify.sh" || { return 1 2>/dev/null || exit 1; }
hypr_source_core_module "wallpaper.sh" || { return 1 2>/dev/null || exit 1; }
hypr_source_core_module "state.sh" || { return 1 2>/dev/null || exit 1; }
hypr_source_core_module "system.sh" || { return 1 2>/dev/null || exit 1; }

# ============================================================================
# GLOBAL INITIALIZATION
# ============================================================================
# This section handles initialization that happens when the script is sourced.
# Use HYPR_SKIP_INIT=1 to skip auto-initialization (for scripts that need
# to control when state is loaded).
#
# To reload state after changes: call export_hypr_config explicitly
# To force full re-init: unset HYPR_GLOBAL_INIT and source again
# ============================================================================

# Initialize hypr environment (loads state, sets defaults)
# Called automatically unless HYPR_SKIP_INIT=1
init_hypr_globals() {
# Guard against re-initialization. Call export_hypr_config explicitly when a
# script needs fresh state in the current shell.
  if [[ "${HYPR_GLOBAL_INIT:-0}" -eq 1 ]]; then
    return 0
  fi

  # Load user state
  export_hypr_config

  refresh_hypr_runtime_state

  # Hyprland-specific settings (only if running under Hyprland)
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hypr_border="$(hyprctl -j getoption decoration:rounding 2>/dev/null | jq '.int' 2>/dev/null)"
    hypr_width="$(hyprctl -j getoption general:border_size 2>/dev/null | jq '.int' 2>/dev/null)"
  fi
  export hypr_border=${hypr_border:-${HYPR_BORDER_RADIUS:-2}}
  export hypr_width=${hypr_width:-${HYPR_BORDER_WIDTH:-2}}

  # Mark as initialized
  HYPR_GLOBAL_INIT=1
}

# Auto-initialize unless explicitly skipped
if [[ "${HYPR_SKIP_INIT:-0}" -ne 1 ]]; then
  init_hypr_globals
fi

if [ -n "$BASH_VERSION" ]; then
  export -f get_hypr_conf get_rofi_pos \
    rofi_user_dir rofi_shared_dir \
    rofi_resolve_theme rofi_resolve_asset \
    rofi_list_theme_files rofi_list_asset_files \
    hypr_core_file hypr_variables_file hypr_config_layer_files hypr_config_value_from_layers hypr_compact_path \
    is_hovered toml_write \
    find_wallpapers get_hashmap get_aur_helper \
    set_hash \
    get_themes print_log \
    pkg_installed paste_string \
    sed_escape_replacement \
    extract_thumbnail accepted_mime_types \
    notify_send_safe \
    refresh_hypr_runtime_state export_hypr_config init_hypr_globals \
    state_read_value_from_file state_get state_set \
    state_get_color_variant state_set_color_variant \
    send_ephemeral_notif \
    hypr_lock_manifest_file hypr_lock_runtime_dir hypr_load_lock_manifest \
    hypr_lock_template hypr_lock_path
fi

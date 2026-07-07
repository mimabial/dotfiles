#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

__hypr_runtime_force="${HYPR_RUNTIME_FORCE_REINIT:-0}"
__hypr_runtime_guard_pid="${HYPR_RUNTIME_GUARD_PID:-}"
[[ "${__hypr_runtime_force}" =~ ^[0-9]+$ ]] || __hypr_runtime_force=0

if (( __hypr_runtime_force == 0 )) \
  && [[ "${__hypr_runtime_guard_pid}" == "${BASHPID}" ]] \
  && declare -F hypr_runtime_require >/dev/null 2>&1; then
  unset __hypr_runtime_force __hypr_runtime_guard_pid
  return 0 2>/dev/null || exit 0
fi

HYPR_RUNTIME_GUARD_PID="${BASHPID}"
unset __hypr_runtime_force __hypr_runtime_guard_pid

__hypr_runtime_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
__hypr_runtime_root="$(cd -- "${__hypr_runtime_dir}/.." && pwd)"
LIB_DIR="${LIB_DIR:-$(cd -- "${__hypr_runtime_root}/.." && pwd)}"
HYPR_LIB_DIR="${HYPR_LIB_DIR:-${__hypr_runtime_root}}"
BIN_DIR="${BIN_DIR:-${HOME}/.local/bin}"

_hypr_xdg_lib="${HYPR_LIB_DIR}/core/xdg.sh"
[[ -r "${_hypr_xdg_lib}" ]] || {
  printf 'ERROR: missing runtime module %s\n' "${_hypr_xdg_lib}" >&2
  return 1 2>/dev/null || exit 1
}
# shellcheck source=/dev/null
source "${_hypr_xdg_lib}" || { return 1 2>/dev/null || exit 1; }
hypr_init_xdg_env
unset _hypr_xdg_lib

export BIN_DIR LIB_DIR HYPR_LIB_DIR
export HYPR_CONFIG_HOME="${XDG_CONFIG_HOME}/hypr"
export HYPR_DATA_HOME="${XDG_DATA_HOME}/hypr"
export HYPR_CACHE_HOME="${XDG_CACHE_HOME}/hypr"
export HYPR_STATE_HOME="${XDG_STATE_HOME}/hypr"
export HYPR_RUNTIME_DIR="${XDG_RUNTIME_DIR}/hypr"
export ICONS_DIR="${XDG_DATA_HOME}/icons"
export FONTS_DIR="${XDG_DATA_HOME}/fonts"
export THEMES_DIR="${XDG_DATA_HOME}/themes"
export WALLPAPER_CACHE_DIR="${HYPR_CACHE_HOME}/wallpaper"
export WALLPAPER_CURRENT_DIR="${WALLPAPER_CACHE_DIR}/current"
export WALLPAPER_THUMB_DIR="${WALLPAPER_CACHE_DIR}/thumbs"
export WALLPAPER_VIDEO_DIR="${WALLPAPER_CURRENT_DIR}/thumbnails"
export HYPR_HASH_COMMAND="${HYPR_HASH_COMMAND:-xxh64sum}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-${HYPR_CACHE_HOME}/pycache}"  # keep .pyc out of the live lib

declare -p WALLPAPER_FILETYPES >/dev/null 2>&1 || declare -ga WALLPAPER_FILETYPES=()
declare -p WALLPAPER_OVERRIDE_FILETYPES >/dev/null 2>&1 || declare -ga WALLPAPER_OVERRIDE_FILETYPES=()
declare -p WALLPAPER_CUSTOM_PATHS >/dev/null 2>&1 || declare -ga WALLPAPER_CUSTOM_PATHS=()
declare -p wallHash >/dev/null 2>&1 || declare -ga wallHash=()
declare -p wallList >/dev/null 2>&1 || declare -ga wallList=()
declare -p wallPathArray >/dev/null 2>&1 || declare -ga wallPathArray=()

for _hypr_runtime_core in \
  "${HYPR_LIB_DIR}/core/notify.sh" \
  "${HYPR_LIB_DIR}/core/common.sh" \
  "${HYPR_LIB_DIR}/runtime/lock_paths.sh"; do
  [[ -r "${_hypr_runtime_core}" ]] || {
    printf 'ERROR: missing runtime module %s\n' "${_hypr_runtime_core}" >&2
    return 1 2>/dev/null || exit 1
  }
  # shellcheck source=/dev/null
  source "${_hypr_runtime_core}" || { return 1 2>/dev/null || exit 1; }
done
unset _hypr_runtime_core

declare -gA HYPR_RUNTIME_MODULE_PATHS
HYPR_RUNTIME_MODULE_PATHS[notify]="${HYPR_LIB_DIR}/core/notify.sh"
HYPR_RUNTIME_MODULE_PATHS[common]="${HYPR_LIB_DIR}/core/common.sh"
HYPR_RUNTIME_MODULE_PATHS[state]="${HYPR_LIB_DIR}/core/state.sh"
HYPR_RUNTIME_MODULE_PATHS[system]="${HYPR_LIB_DIR}/core/system.sh"
HYPR_RUNTIME_MODULE_PATHS[rofi]="${HYPR_LIB_DIR}/core/rofi.sh"
HYPR_RUNTIME_MODULE_PATHS[wallpaper_catalog]="${HYPR_LIB_DIR}/core/wallpaper.catalog.sh"
HYPR_RUNTIME_MODULE_PATHS[lock_paths]="${HYPR_LIB_DIR}/runtime/lock_paths.sh"

declare -gA HYPR_RUNTIME_MODULES_LOADED
HYPR_RUNTIME_MODULES_LOADED[notify]=1
HYPR_RUNTIME_MODULES_LOADED[common]=1
HYPR_RUNTIME_MODULES_LOADED[lock_paths]=1

hypr_runtime_require() {
  local module_name=""
  local module_path=""

  for module_name in "$@"; do
    [[ -n "${module_name}" ]] || continue
    [[ -n "${HYPR_RUNTIME_MODULES_LOADED[${module_name}]:-}" ]] && continue

    module_path="${HYPR_RUNTIME_MODULE_PATHS[${module_name}]:-}"
    [[ -n "${module_path}" && -r "${module_path}" ]] || {
      printf 'ERROR: unknown runtime module %s\n' "${module_name}" >&2
      return 1
    }

    # shellcheck source=/dev/null
    source "${module_path}" || return 1
    HYPR_RUNTIME_MODULES_LOADED["${module_name}"]=1
  done
}

hypr_runtime_load_state() {
  hypr_runtime_require state wallpaper_catalog || return 1
  export_hypr_config || return 1
  hypr_runtime_refresh_border_metrics
}

hypr_runtime_refresh_border_metrics() {
  local runtime_border_radius=""
  local runtime_border_width=""

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hypr_border_metrics_into runtime_border_radius runtime_border_width 2>/dev/null || true
  fi

  export HYPR_RUNTIME_BORDER_RADIUS="${runtime_border_radius:-${HYPR_BORDER_RADIUS:-2}}"
  export HYPR_RUNTIME_BORDER_WIDTH="${runtime_border_width:-${HYPR_BORDER_WIDTH:-2}}"
}

hypr_runtime_bootstrap() {
  hypr_runtime_require state system rofi wallpaper_catalog || return 1
  hypr_runtime_load_state
}

unset __hypr_runtime_dir __hypr_runtime_root

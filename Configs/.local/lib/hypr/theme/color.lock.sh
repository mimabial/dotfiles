#!/usr/bin/env bash
# Requires bash 4+ for dynamic exec {fd}> lock descriptors.

color_lock_init() {
  # This FD tracks the main color-generation lock for the current process so
  # cleanup can temporarily release it before spawning a cache-only prewarm.
  COLOR_RUN_LOCK_FD=""
  LOCK_FILE="$(hypr_lock_path color_gen)"
  CACHE_ONLY_LOCK_FILE="$(hypr_lock_path color_cache_only)"
  STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/color.gen.state"
  THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"
  THEME_UPDATE_META="$(hypr_lock_path theme_update_meta)"
  THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"
  CACHE_ONLY="${CACHE_ONLY:-${HYPR_WAL_CACHE_ONLY:-0}}"
  ASYNC_OPTIONAL_UPDATES=1
  ASYNC_POST_UPDATES=1
  MODE_OVERRIDE="${HYPR_WAL_MODE_OVERRIDE:-}"
  CACHE_ONLY_ROOT=""
  HYPR_AUTO_RELOAD_PREV=""
  THEME_UPDATE_LOCK_OWNED=0
  # The theme-update lock is allocated only when this process owns the external
  # theme-update section, so keep its descriptor dynamic as well.
  THEME_UPDATE_LOCK_FD=""

  mkdir -p "$(dirname "${LOCK_FILE}")" "$(dirname "${STATE_FILE}")"
}

color_lock_acquire_run_lock() {
  if [[ "${CACHE_ONLY}" -eq 1 ]]; then
    exec {COLOR_RUN_LOCK_FD}>"${CACHE_ONLY_LOCK_FILE}"
    if ! flock -n "${COLOR_RUN_LOCK_FD}"; then
      print_log -sec "pywal16" -stat "skip" "cache-only: another prewarm process running"
      exit 0
    fi
    return 0
  fi

  exec {COLOR_RUN_LOCK_FD}>"${LOCK_FILE}"
  if ! flock -n "${COLOR_RUN_LOCK_FD}"; then
    print_log -sec "pywal16" -stat "wait" "Another process running"
    flock "${COLOR_RUN_LOCK_FD}"
  fi
}

color_lock_release_run_lock() {
  [[ -n "${COLOR_RUN_LOCK_FD}" ]] || return 0

  flock -u "${COLOR_RUN_LOCK_FD}" 2>/dev/null || true
  exec {COLOR_RUN_LOCK_FD}>&-
  COLOR_RUN_LOCK_FD=""
}

color_lock_acquire_theme_update() {
  local lock_tmp=""

  [[ "${CACHE_ONLY}" -ne 1 ]] || return 0
  [[ "${HYPR_THEME_UPDATE_EXTERNAL_LOCK:-0}" -ne 1 ]] || return 0

  exec {THEME_UPDATE_LOCK_FD}>"${THEME_UPDATE_LOCK}"
  flock "${THEME_UPDATE_LOCK_FD}"
  lock_tmp="$(mktemp "$(dirname "${THEME_UPDATE_META}")/.$(basename "${THEME_UPDATE_META}").XXXXXX")" || return 1
  if ! {
    printf 'pid=%s\n' "$$"
    printf 'started=%s\n' "$(date +%s)"
    printf 'cmd=%s\n' "${BASH_SOURCE[0]##*/}"
  } >"${lock_tmp}" || ! mv -f "${lock_tmp}" "${THEME_UPDATE_META}"; then
    rm -f "${lock_tmp}" 2>/dev/null || true
    return 1
  fi
  THEME_UPDATE_LOCK_OWNED=1
}

color_lock_release_theme_update() {
  [[ "${CACHE_ONLY}" -ne 1 ]] || return 0
  [[ "${THEME_UPDATE_LOCK_OWNED}" -eq 1 ]] || return 0

  rm -f "${THEME_UPDATE_META}"
  flock -u "${THEME_UPDATE_LOCK_FD}" 2>/dev/null || true
  exec {THEME_UPDATE_LOCK_FD}>&-
  THEME_UPDATE_LOCK_FD=""
  THEME_UPDATE_LOCK_OWNED=0
}

color_lock_enable_hypr_autoreload_guard() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] || return 0
  [[ "${CACHE_ONLY}" -ne 1 ]] || return 0

  HYPR_AUTO_RELOAD_PREV="$(hyprctl getoption misc:disable_autoreload 2>/dev/null | awk -F': ' '/int/ {print $2; exit}')"
  [[ -n "${HYPR_AUTO_RELOAD_PREV}" ]] && hyprctl keyword misc:disable_autoreload 1 -q
}

color_lock_spawn_precache() {
  [[ "${PRECACHE_ENABLED}" -eq 1 ]] || return 0
  [[ -n "${PRECACHE_MODE}" ]] || return 0
  [[ -n "${PRECACHE_WALLPAPER}" ]] || return 0
  [[ "${PRECACHE_MODE}" =~ ^(dark|light)$ ]] || return 0
  [[ -f "${PRECACHE_WALLPAPER}" ]] || return 0
  [[ -n "${COLOR_RUN_LOCK_FD}" ]] || return 0

  color_lock_release_run_lock
  (
    export HYPR_WAL_CACHE_ONLY=1
    export HYPR_WAL_MODE_OVERRIDE="${PRECACHE_MODE}"
    bash "${LIB_DIR}/hypr/theme/color-sync.sh" "${PRECACHE_WALLPAPER}" &>/dev/null
  ) &
  disown
}

color_lock_cleanup() {
  local exit_code="${1:-$?}"
  if [[ -n "${CACHE_ONLY_ROOT}" ]]; then
    rm -rf "${CACHE_ONLY_ROOT}" 2>/dev/null || true
  fi

  if [[ "${CACHE_ONLY}" -ne 1 ]]; then
    color_lock_release_theme_update

    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]]; then
      if [[ ! -e "${THEME_SWITCH_LOCK}" ]]; then
        if ! hyprctl reload config-only >/dev/null 2>&1; then
          print_log -sec "cleanup" -warn "hyprctl" "config reload failed"
        fi
      fi
      if [[ -n "${HYPR_AUTO_RELOAD_PREV}" ]]; then
        hyprctl keyword misc:disable_autoreload "${HYPR_AUTO_RELOAD_PREV}" -q || true
      fi
    fi
  fi

  color_lock_spawn_precache
  color_lock_release_run_lock
  return "${exit_code}"
}

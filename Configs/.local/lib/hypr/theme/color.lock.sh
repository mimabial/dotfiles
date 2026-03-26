#!/usr/bin/env bash

color_lock_init() {
  LOCK_FILE="$(hypr_lock_path color_gen)"
  CACHE_ONLY_LOCK_FILE="$(hypr_lock_path color_cache_only)"
  STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/color.gen.state"
  THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"
  THEME_UPDATE_META="$(hypr_lock_path theme_update_meta)"
  THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"
  CACHE_ONLY="${CACHE_ONLY:-${HYPR_WAL_CACHE_ONLY:-0}}"
  ASYNC_APPS=1
  ASYNC_POST_UPDATES=1
  MODE_OVERRIDE="${HYPR_WAL_MODE_OVERRIDE:-}"
  CACHE_ONLY_ROOT=""
  HYPR_AUTO_RELOAD_PREV=""
  THEME_UPDATE_LOCK_OWNED=0
  THEME_UPDATE_LOCK_FD=""

  mkdir -p "$(dirname "${LOCK_FILE}")" "$(dirname "${STATE_FILE}")"
}

color_lock_acquire_run_lock() {
  if [[ "${CACHE_ONLY}" -eq 1 ]]; then
    exec 200>"${CACHE_ONLY_LOCK_FILE}"
    if ! flock -n 200; then
      print_log -sec "pywal16" -stat "skip" "cache-only: another prewarm process running"
      exit 0
    fi
    return 0
  fi

  exec 200>"${LOCK_FILE}"
  if ! flock -n 200; then
    print_log -sec "pywal16" -stat "wait" "Another process running"
    flock 200
  fi
}

color_lock_acquire_theme_update() {
  local lock_tmp=""

  [[ "${CACHE_ONLY}" -ne 1 ]] || return 0
  [[ "${HYPR_THEME_UPDATE_EXTERNAL_LOCK:-0}" -ne 1 ]] || return 0

  exec {THEME_UPDATE_LOCK_FD}>"${THEME_UPDATE_LOCK}"
  flock "${THEME_UPDATE_LOCK_FD}"
  lock_tmp="${THEME_UPDATE_META}.tmp.$$"
  {
    printf 'pid=%s\n' "$$"
    printf 'started=%s\n' "$(date +%s)"
    printf 'cmd=%s\n' "${BASH_SOURCE[0]##*/}"
  } >"${lock_tmp}" && mv -f "${lock_tmp}" "${THEME_UPDATE_META}"
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

  flock -u 200
  (
    export HYPR_WAL_CACHE_ONLY=1
    export HYPR_WAL_MODE_OVERRIDE="${PRECACHE_MODE}"
    bash "${LIB_DIR}/hypr/theme/color.set.sh" "${PRECACHE_WALLPAPER}" &>/dev/null
  ) &
  disown
}

color_lock_cleanup() {
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
}

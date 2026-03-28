#!/usr/bin/env bash
# shellcheck disable=SC2154,SC1091

source "$(command -v hyprshell)" || exit 1

THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"
THEME_UPDATE_META="$(hypr_lock_path theme_update_meta)"
WAYBAR_WATCH_LOCK="$(hypr_lock_path waybar_watch)"

theme_apply_waybar_reload_mode="direct"
theme_apply_lock_fd=""
theme_apply_lock_owned=0

detect_theme_apply_waybar_reload_mode() {
  local fd
  exec {fd}>"${WAYBAR_WATCH_LOCK}" || return 1
  if flock -n "${fd}"; then
    flock -u "${fd}" 2>/dev/null || true
    exec {fd}>&-
    theme_apply_waybar_reload_mode="direct"
    return 0
  fi
  exec {fd}>&-
  theme_apply_waybar_reload_mode="watcher"
}

detect_theme_apply_waybar_reload_mode || true

theme_apply_create_update_lock() {
  local lock_tmp
  [[ "${theme_apply_lock_owned}" -eq 1 ]] && return 0
  exec {theme_apply_lock_fd}>"${THEME_UPDATE_LOCK}"
  flock "${theme_apply_lock_fd}"
  lock_tmp="${THEME_UPDATE_META}.tmp.$$"
  {
    printf 'pid=%s\n' "$$"
    printf 'started=%s\n' "$(date +%s)"
    printf 'cmd=%s\n' "${BASH_SOURCE[0]##*/}"
    printf 'waybar_reload=%s\n' "${theme_apply_waybar_reload_mode}"
  } >"${lock_tmp}" && mv -f "${lock_tmp}" "${THEME_UPDATE_META}"
  theme_apply_lock_owned=1
}

theme_apply_release_update_lock() {
  [[ "${theme_apply_lock_owned}" -eq 1 ]] || return 0
  rm -f "${THEME_UPDATE_META}"
  flock -u "${theme_apply_lock_fd}" 2>/dev/null || true
  exec {theme_apply_lock_fd}>&-
  theme_apply_lock_fd=""
  theme_apply_lock_owned=0
}

theme_apply_reload_dunst_runtime() {
  [[ -x "${LIB_DIR}/hypr/wal/wal.dunst.sh" ]] || return 0
  "${LIB_DIR}/hypr/wal/wal.dunst.sh" --reload-only >/dev/null 2>&1 || true
}

theme_apply_reload_hypr_config() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] || return 0
  command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl reload config-only >/dev/null 2>&1 || print_log -sec "theme.apply" -warn "hyprctl" "config reload failed"
}

theme_apply_restart_waybar() {
  local waybar_script="${LIB_DIR}/hypr/waybar/waybar.py"
  [[ "${theme_apply_waybar_reload_mode}" == "direct" ]] || return 0
  if [[ -x "${waybar_script}" ]]; then
    "${waybar_script}" --restart-direct >/dev/null 2>&1 || true
  elif command -v hyprshell >/dev/null 2>&1; then
    hyprshell waybar --restart-direct >/dev/null 2>&1 || true
  fi
}

theme_apply_wallpaper() {
  local quiet="${1:-false}"
  local -a wallpaper_args=(
    --wait-lock
    --resume
    --global
    --notify-body "Theme: ${HYPR_THEME}"
  )
  if [[ "${quiet}" == "true" ]]; then
    "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" "${wallpaper_args[@]}" >/dev/null 2>&1
  else
    "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" "${wallpaper_args[@]}"
  fi
}

trap theme_apply_release_update_lock EXIT

quiet=false
while (($#)); do
  case "$1" in
    --quiet) quiet=true ;;
    *)
      echo "Usage: $(basename "$0") [--quiet]" >&2
      exit 1
      ;;
  esac
  shift
done

theme_apply_create_update_lock
HYPR_THEME_UPDATE_EXTERNAL_LOCK=1 "${LIB_DIR}/hypr/theme/color.set.sh" || exit 1
theme_apply_reload_dunst_runtime
theme_apply_wallpaper "${quiet}" || exit 1
theme_apply_reload_hypr_config
hyprshell fonts/font-sync.sh 2>/dev/null || true
theme_apply_restart_waybar

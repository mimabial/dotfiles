#!/usr/bin/env bash
# shellcheck disable=SC2154

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

theme_apply_effects_lib="${LIB_DIR}/hypr/theme/lib/theme.apply.effects.bash"
if [[ ! -r "${theme_apply_effects_lib}" ]]; then
  print_log -sec "theme.apply" -err "source" "missing ${theme_apply_effects_lib}"
  exit 1
fi
# shellcheck source=/dev/null
source "${theme_apply_effects_lib}" || exit 1

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
  local lock_tmp=""
  [[ "${theme_apply_lock_owned}" -eq 1 ]] && return 0
  exec {theme_apply_lock_fd}>"${THEME_UPDATE_LOCK}"
  flock "${theme_apply_lock_fd}"
  lock_tmp="$(mktemp "${THEME_UPDATE_META}.tmp.XXXXXX")" || return 1
  {
    printf 'pid=%s\n' "$$"
    printf 'started=%s\n' "$(date +%s)"
    printf 'cmd=%s\n' "${BASH_SOURCE[0]##*/}"
    printf 'waybar_reload=%s\n' "${theme_apply_waybar_reload_mode}"
  } >"${lock_tmp}" && mv -f "${lock_tmp}" "${THEME_UPDATE_META}"
  theme_apply_lock_owned=1
}

theme_apply_release_update_lock() {
  local exit_code="${1:-$?}"
  [[ "${theme_apply_lock_owned}" -eq 1 ]] || return "${exit_code}"
  rm -f "${THEME_UPDATE_META}"
  flock -u "${theme_apply_lock_fd}" 2>/dev/null || true
  exec {theme_apply_lock_fd}>&-
  theme_apply_lock_fd=""
  theme_apply_lock_owned=0
  return "${exit_code}"
}

theme_apply_reload_dunst_runtime() {
  [[ -x "${LIB_DIR}/hypr/wal/wal.dunst.sh" ]] || return 0
  "${LIB_DIR}/hypr/wal/wal.dunst.sh" --reload-only >/dev/null 2>&1 || true
}

theme_apply_run_color_generation() {
  local source_path="${1:-}"

  if [[ -n "${source_path}" ]]; then
    HYPR_THEME_UPDATE_EXTERNAL_LOCK=1 "${LIB_DIR}/hypr/theme/color-sync.sh" "${source_path}" || return 1
  else
    HYPR_THEME_UPDATE_EXTERNAL_LOCK=1 "${LIB_DIR}/hypr/theme/color-sync.sh" || return 1
  fi
}

theme_apply_sync_static_desktop_state() {
  local desktop_sync_script="${LIB_DIR}/hypr/theme/desktop.sync.sh"
  [[ -x "${desktop_sync_script}" ]] || return 0
  THEME_DESKTOP_SYNC_LOG_DCONF=0 "${desktop_sync_script}" --static-only >/dev/null 2>&1 \
    || print_log -sec "theme.apply" -warn "desktop" "static sync failed"
}

theme_apply_sync_runtime_desktop_state() {
  local quiet="${1:-false}"
  local desktop_sync_script="${LIB_DIR}/hypr/theme/desktop.sync.sh"
  [[ -x "${desktop_sync_script}" ]] || return 0

  if [[ "${quiet}" == "true" ]]; then
    THEME_DESKTOP_SYNC_LOG_DCONF=0 "${desktop_sync_script}" --runtime-only >/dev/null 2>&1 \
      || print_log -sec "theme.apply" -warn "desktop" "runtime sync failed"
  else
    "${desktop_sync_script}" --runtime-only \
      || print_log -sec "theme.apply" -warn "desktop" "runtime sync failed"
  fi
}

theme_apply_refresh_kvantum() {
  [[ -x "${LIB_DIR}/hypr/wal/wal.kvantum.sh" ]] || return 0
  "${LIB_DIR}/hypr/wal/wal.kvantum.sh" >/dev/null 2>&1 || print_log -sec "theme.apply" -warn "kvantum" "refresh failed"
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
  local skip_colors="${2:-0}"
  local -a wallpaper_args=(
    resume
    --global
    --notify-body "Theme: ${HYPR_THEME}"
  )
  local -a wallpaper_env=(
    "WALLPAPER_SYNC_APPLY=1"
    "WALLPAPER_SKIP_COLORS=${skip_colors}"
  )
  if [[ "${quiet}" == "true" ]]; then
    env "${wallpaper_env[@]}" "${LIB_DIR}/hypr/wallpaper.sh" "${wallpaper_args[@]}" >/dev/null 2>&1
  else
    env "${wallpaper_env[@]}" "${LIB_DIR}/hypr/wallpaper.sh" "${wallpaper_args[@]}"
  fi
}

theme_apply_resolve_current_wallpaper() {
  local wallpaper_link="${HYPR_THEME_DIR}/wall.set"

  if [[ ! -e "${wallpaper_link}" ]]; then
    print_log -sec "theme.apply" -err "wallpaper" "missing ${wallpaper_link}"
    return 1
  fi

  readlink -f -- "${wallpaper_link}" 2>/dev/null \
    || realpath -- "${wallpaper_link}" 2>/dev/null \
    || {
      print_log -sec "theme.apply" -err "wallpaper" "failed to resolve ${wallpaper_link}"
      return 1
    }
}

theme_apply_run_pipeline() {
  local quiet="${1:-false}"
  local wallpaper_path=""

  if [[ "${selected_color_mode}" -eq 0 ]]; then
    theme_apply_run_color_generation || return 1
    theme_apply_sync_static_desktop_state
    theme_apply_refresh_kvantum
    theme_apply_reload_dunst_runtime
    theme_apply_wallpaper "${quiet}" 1 || return 1
    return 0
  fi

  theme_apply_wallpaper "${quiet}" 1 || return 1
  wallpaper_path="$(theme_apply_resolve_current_wallpaper)" || return 1
  theme_apply_run_color_generation "${wallpaper_path}" || return 1
  theme_apply_sync_static_desktop_state
  theme_apply_refresh_kvantum
  theme_apply_reload_dunst_runtime
}

trap 'theme_apply_release_update_lock "$?"' EXIT

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
theme_apply_run_pipeline "${quiet}" || exit 1
theme_apply_reload_hypr_config
theme_apply_sync_runtime_desktop_state "${quiet}"
[[ -x "${LIB_DIR}/hypr/fonts/font-sync.sh" ]] && "${LIB_DIR}/hypr/fonts/font-sync.sh" >/dev/null 2>&1 || true
theme_apply_run_post_effects
theme_apply_restart_waybar

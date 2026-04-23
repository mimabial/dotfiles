#!/usr/bin/env bash
# shellcheck disable=SC2154

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

theme_apply_desktop_sync_lib="${LIB_DIR}/hypr/theme/lib/theme.desktop.sync.bash"
theme_apply_font_sync_lib="${LIB_DIR}/hypr/fonts/font.sync.lib.bash"

if [[ ! -r "${theme_apply_desktop_sync_lib}" ]]; then
  print_log -sec "theme.apply" -err "source" "missing ${theme_apply_desktop_sync_lib}"
  exit 1
fi
# shellcheck source=/dev/null
source "${theme_apply_desktop_sync_lib}" || exit 1

if [[ ! -r "${theme_apply_font_sync_lib}" ]]; then
  print_log -sec "theme.apply" -err "source" "missing ${theme_apply_font_sync_lib}"
  exit 1
fi
# shellcheck source=/dev/null
source "${theme_apply_font_sync_lib}" || exit 1

THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"
THEME_UPDATE_META="$(hypr_lock_path theme_update_meta)"

theme_apply_lock_fd=""
theme_apply_lock_owned=0
theme_apply_desktop_state_prepared=0
theme_apply_runtime_sync_pid=""
theme_apply_font_sync_pid=""
theme_apply_wallpaper_pid=""

theme_apply_acquire_update_lock() {
  local lock_tmp=""
  [[ "${theme_apply_lock_owned}" -eq 1 ]] && return 0
  exec {theme_apply_lock_fd}>"${THEME_UPDATE_LOCK}"
  flock "${theme_apply_lock_fd}"
  lock_tmp="$(mktemp "${THEME_UPDATE_META}.tmp.XXXXXX")" || return 1
  {
    printf 'pid=%s\n' "$$"
    printf 'started=%s\n' "$(date +%s)"
    printf 'cmd=%s\n' "${BASH_SOURCE[0]##*/}"
  } >"${lock_tmp}" && mv -f "${lock_tmp}" "${THEME_UPDATE_META}"
  theme_apply_lock_owned=1
}

theme_apply_release_update_lock() {
  local exit_code="${1:-0}"
  [[ "${theme_apply_lock_owned}" -eq 1 ]] || return "${exit_code}"
  rm -f "${THEME_UPDATE_META}"
  flock -u "${theme_apply_lock_fd}" 2>/dev/null || true
  exec {theme_apply_lock_fd}>&-
  theme_apply_lock_fd=""
  theme_apply_lock_owned=0
  return "${exit_code}"
}

theme_apply_prepare_desktop_state() {
  [[ "${theme_apply_desktop_state_prepared}" -eq 1 ]] && return 0
  theme_desktop_prepare_state || return 1
  theme_apply_desktop_state_prepared=1
}

theme_apply_commit_theme_metadata() {
  local staged_file="${HYPR_THEME_METADATA_FILE:-}"
  local live_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"

  [[ -n "${staged_file}" && -f "${staged_file}" ]] || return 0
  mkdir -p "$(dirname "${live_file}")" || return 1

  if [[ -f "${live_file}" ]] && cmp -s "${staged_file}" "${live_file}"; then
    rm -f -- "${staged_file}"
  else
    mv -f -- "${staged_file}" "${live_file}"
  fi

  HYPR_THEME_METADATA_FILE="${live_file}"
  export HYPR_THEME_METADATA_FILE
}

theme_apply_sync_runtime_desktop_state() {
  local quiet="${1:-false}"

  if [[ "${quiet}" == "true" ]]; then
    if (
      THEME_DESKTOP_SYNC_LOG_DCONF=0 theme_desktop_apply_runtime_resolved && theme_desktop_set_cursor_async
    ) >/dev/null 2>&1; then
      return 0
    fi

    return 1
  fi

  theme_desktop_apply_runtime_resolved && theme_desktop_set_cursor_async
}

theme_apply_wallpaper() {
  local quiet="${1:-false}"
  local skip_colors="${2:-0}"
  local -a wallpaper_args=(
    resume
    --global
    --no-notify
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

theme_apply_sync_nvim_theme() {
  if [[ -x "${HYPR_LIB_DIR}/util/nvim-theme-sync.sh" ]]; then
    "${HYPR_LIB_DIR}/util/nvim-theme-sync.sh" >/dev/null 2>&1 || true
  fi
}

theme_apply_enqueue_wallpaper_thumbs() {
  local -a cache_args=()
  local wall=""
  local queue_script=""
  local cache_script=""

  if [[ ${#thmWall[@]} -eq 0 ]]; then
    get_themes
  fi

  for wall in "${thmWall[@]}"; do
    [[ -n "${wall}" ]] || continue
    [[ -r "${wall}" ]] || continue
    cache_args+=(-w "${wall}")
  done

  queue_script="${LIB_DIR}/hypr/wallpaper/wallcache.daemon.sh"
  cache_script="${LIB_DIR}/hypr/wallpaper/awww-wallcache.sh"
  [[ -x "${queue_script}" || -x "${cache_script}" ]] || return 0
  [[ ${#cache_args[@]} -eq 0 ]] && return 0

  if [[ -x "${queue_script}" ]]; then
    "${queue_script}" --enqueue "${cache_args[@]}" &>/dev/null &
  else
    "${cache_script}" "${cache_args[@]}" &>/dev/null &
  fi
}

theme_apply_sync_backend_wallpaper_links() {
  local file=""
  local base=""

  [[ -d "${WALLPAPER_CURRENT_DIR}" ]] || return 0

  while IFS= read -r -d '' file; do
    base="$(basename "${file}" .png)"
    pkg_installed "${base}" || continue
    "${LIB_DIR}/hypr/wallpaper.sh" link --backend "${base}" >/dev/null 2>&1 || true
  done < <(find -H "${WALLPAPER_CURRENT_DIR}" -maxdepth 1 -type l -name "*.png" -print0)
}

theme_apply_wait_for_pid() {
  local pid="$1"
  local label="$2"

  [[ -n "${pid}" ]] || return 0
  if wait "${pid}"; then
    return 0
  fi

  print_log -sec "theme.apply" -warn "${label}"
  return 1
}

theme_apply_start_common_jobs() {
  local quiet="${1:-false}"
  local desktop_state_ready=0

  theme_apply_acquire_update_lock || return 1
  if theme_apply_prepare_desktop_state >/dev/null 2>&1; then
    desktop_state_ready=1
  fi

  theme_apply_runtime_sync_pid=""
  if [[ "${desktop_state_ready}" -eq 1 ]]; then
    (
      theme_apply_sync_runtime_desktop_state "${quiet}"
    ) &
    theme_apply_runtime_sync_pid="$!"
  fi
}

theme_apply_finish() {
  local quiet="${1:-false}"

  theme_apply_wait_for_pid "${theme_apply_runtime_sync_pid}" "desktop runtime sync failed" || true
  theme_apply_wait_for_pid "${theme_apply_font_sync_pid}" "font sync failed" || true

  theme_apply_sync_nvim_theme
  theme_apply_enqueue_wallpaper_thumbs
  theme_apply_wait_for_pid "${theme_apply_wallpaper_pid}" "wallpaper apply failed" || return 1
  theme_apply_sync_backend_wallpaper_links

  if [[ "${quiet}" == "true" ]]; then
    "${LIB_DIR}/hypr/wallpaper.sh" notify --global --notify-body "Theme: ${HYPR_THEME}" >/dev/null 2>&1 || true
  else
    "${LIB_DIR}/hypr/wallpaper.sh" notify --global --notify-body "Theme: ${HYPR_THEME}" || true
  fi
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

wallpaper_path=""
if [[ "${selected_color_mode}" -eq 0 ]]; then
  :
else
  wallpaper_path="$(theme_apply_resolve_current_wallpaper)" || exit 1
fi

theme_apply_start_common_jobs "${quiet}" || exit 1

if [[ -n "${wallpaper_path}" ]]; then
  env \
    HYPR_THEME_UPDATE_EXTERNAL_LOCK=1 \
    HYPR_THEME_RUNTIME_SYNC_EXTERNAL=1 \
    "${LIB_DIR}/hypr/theme/color-sync.sh" "${wallpaper_path}" || exit 1
else
  env \
    HYPR_THEME_UPDATE_EXTERNAL_LOCK=1 \
    HYPR_THEME_RUNTIME_SYNC_EXTERNAL=1 \
    "${LIB_DIR}/hypr/theme/color-sync.sh" || exit 1
fi

if ! { theme_apply_prepare_desktop_state && theme_desktop_apply_static_resolved_if_needed; } >/dev/null 2>&1; then
  print_log -sec "theme.apply" -warn "desktop" "static sync failed"
fi

theme_apply_commit_theme_metadata || exit 1

theme_apply_font_sync_pid=""
(
  font_sync_apply_waybar_bar_font_include >/dev/null 2>&1
) &
theme_apply_font_sync_pid="$!"

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] && command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload config-only >/dev/null 2>&1 || print_log -sec "theme.apply" -warn "hyprctl" "config reload failed"
fi

theme_apply_wallpaper_pid=""
(
  theme_apply_wallpaper "${quiet}" 1
) &
theme_apply_wallpaper_pid="$!"

theme_apply_finish "${quiet}" || exit 1

#!/usr/bin/env bash
# shellcheck disable=SC1091
# Wallpaper backend adapter for the swww/awww-style runtime wallpaper daemon.

selected_wall="${1:-"${WALLPAPER_CURRENT_DIR:-${HYPR_CACHE_HOME:-$HOME/.cache/hypr}/wallpaper/current}/wall.set"}"

# Use flock for robust locking (releases automatically on exit/crash)
LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck disable=SC1090
source "${LIB_DIR}/hypr/runtime/lock_paths.sh"

SWWW_LOCK="$(hypr_lock_path wallpaper_swww)"
exec 203>"${SWWW_LOCK}"
if ! flock -n 203; then
  echo "Another swww wallpaper operation in progress, skipping..."
  exit 0
fi
trap 'flock -u 203 2>/dev/null' EXIT

# shellcheck disable=SC1091
source "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh"

wait_for_wallpaper_daemon() {
  local attempt=0
  local max_attempts=40

  while (( attempt < max_attempts )); do
    if "${wallpaper_client_cmd}" query >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
    ((attempt++))
  done
  return 1
}

cleanup_stale_wallpaper_socket() {
  local socket_path=""

  [[ "${wallpaper_daemon_cmd}" == "awww-daemon" ]] || return 0
  [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 0
  pgrep -x "${wallpaper_daemon_cmd}" >/dev/null 2>&1 && return 0

  socket_path="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY}-awww-daemon.sock"
  [[ -S "${socket_path}" ]] || return 0
  rm -f -- "${socket_path}"
}

resolve_wallpaper_backend() {
  if command -v awww >/dev/null 2>&1 && command -v awww-daemon >/dev/null 2>&1; then
    wallpaper_client_cmd="awww"
    wallpaper_daemon_cmd="awww-daemon"
    wallpaper_backend_log="awww"
    wallpaper_daemon_args=(--format argb)
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/awww"
    return 0
  fi

  if command -v swww >/dev/null 2>&1 && command -v swww-daemon >/dev/null 2>&1; then
    wallpaper_client_cmd="swww"
    wallpaper_daemon_cmd="swww-daemon"
    wallpaper_backend_log="swww"
    wallpaper_daemon_args=(--format xrgb)
    return 0
  fi

  print_log -sec "wallpaper" -err "backend missing (expected awww or swww)"
  return 1
}

ensure_wallpaper_daemon() {
  "${wallpaper_client_cmd}" query >/dev/null 2>&1 && return 0
  cleanup_stale_wallpaper_socket
  "${wallpaper_daemon_cmd}" "${wallpaper_daemon_args[@]}" 200>&- 201>&- 202>&- 203>&- &
  disown
  wait_for_wallpaper_daemon && return 0
  print_log -sec "${wallpaper_backend_log}" -err "daemon did not become ready"
  return 1
}

resolve_wallpaper_backend || exit 1

#// set defaults
wallpaper_transition_type="${wallpaper_transition_type:-${WALLPAPER_SWWW_TRANSITION_DEFAULT:-fade}}"

# Handle transition
case "${WALLPAPER_SET_FLAG}" in
  p)
    wallpaper_transition_type="${WALLPAPER_SWWW_TRANSITION_PREV:-$wallpaper_transition_type}"
    ;;
  n)
    wallpaper_transition_type="${WALLPAPER_SWWW_TRANSITION_NEXT:-$wallpaper_transition_type}"
    ;;

esac

[[ -z "${selected_wall}" ]] && echo "No input wallpaper" && exit 1
selected_wall="$(readlink -f "${selected_wall}")"

ensure_wallpaper_daemon || exit 1

if file --mime-type -b "${selected_wall}" | grep -q '^video/'; then
  print_log -sec "wallpaper" -stat "converting video" "$selected_wall"
  mkdir -p "${WALLPAPER_VIDEO_DIR}"
  cached_thumb="${WALLPAPER_VIDEO_DIR}/$(${HYPR_HASH_COMMAND:-sha1sum} "${selected_wall}" | cut -d' ' -f1).png"
  extract_thumbnail "${selected_wall}" "${cached_thumb}"
  selected_wall="${cached_thumb}"
fi
[[ -z "${wallFramerate}" ]] && wallFramerate=60
[[ -z "${wallTransDuration}" ]] && wallTransDuration=0.6

# Apply wallpaper through the swww backend.
print_log -sec "wallpaper" -stat "apply" "$selected_wall"

# Resolve the wallpaper path
resolved_wall="$(readlink -f "$selected_wall")"
if [ -z "${resolved_wall}" ] || [ ! -f "${resolved_wall}" ]; then
  print_log -sec "${wallpaper_backend_log}" -err "wallpaper not found: ${selected_wall} -> ${resolved_wall}"
  exit 1
fi

# Get cursor position (fallback to center if unavailable)
cursor_pos="$(hyprctl cursorpos 2>/dev/null | grep -E '^[0-9]' || echo "0,0")"

# Build backend command
wallpaper_cmd=("${wallpaper_client_cmd}" img "${resolved_wall}"
  --transition-bezier .43,1.19,1,.4
  --transition-type "${wallpaper_transition_type}"
  --transition-duration "${wallTransDuration}"
  --transition-fps "${wallFramerate}"
  --invert-y
  --transition-pos "${cursor_pos}")

# Don't run in background during startup to ensure GIF animation loads properly
if [[ "${WALLPAPER_SET_FLAG}" == "start" ]]; then
  "${wallpaper_cmd[@]}"
else
  ( "${wallpaper_cmd[@]}" || print_log -sec "${wallpaper_backend_log}" -err "failed to set wallpaper" ) &
fi

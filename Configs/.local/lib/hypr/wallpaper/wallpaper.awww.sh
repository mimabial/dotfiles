#!/usr/bin/env bash
set -euo pipefail

wallpaper_path="${1:-"${WALLPAPER_CURRENT_DIR:-${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wallpaper/current}/wall.set"}"


# shellcheck disable=SC1090
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/lock_paths.bash"

AWWW_LOCK="$(hypr_lock_path_ensure_parent wallpaper_awww)"
exec {awww_lock_fd}>"${AWWW_LOCK}"
if ! flock -n "${awww_lock_fd}"; then
  if [[ "${WALLPAPER_WAIT_FOR_LOCK:-0}" -eq 1 ]]; then
    echo "Another awww wallpaper operation is already in progress, waiting..."
    flock "${awww_lock_fd}"
  else
    echo "Another awww wallpaper operation in progress, skipping..."
    exit 0
  fi
fi
wallpaper_awww_release_lock() {
  local exit_code="${1:-$?}"
  flock -u "${awww_lock_fd}" 2>/dev/null || true
  return "${exit_code}"
}
trap 'wallpaper_awww_release_lock "$?"' EXIT

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require wallpaper_catalog || exit 1

wallpaper_awww_socket_path() {
  printf '%s\n' "${XDG_RUNTIME_DIR:-/run/user/${UID}}/${WAYLAND_DISPLAY:-}-awww-daemon.sock"
}

wallpaper_awww_wait_until_ready() {
  hypr_wait_for_path 2 "$(wallpaper_awww_socket_path)" && "${wallpaper_client_cmd}" query >/dev/null 2>&1
}

wallpaper_awww_remove_stale_socket() {
  local socket_path=""

  [[ "${wallpaper_daemon_cmd}" == "awww-daemon" ]] || return 0
  [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 0
  pgrep -x "${wallpaper_daemon_cmd}" >/dev/null 2>&1 && return 0

  socket_path="$(wallpaper_awww_socket_path)"
  [[ -S "${socket_path}" ]] || return 0
  rm -f -- "${socket_path}"
}

wallpaper_awww_configure() {
  command -v awww >/dev/null 2>&1 || {
    print_log -sec "wallpaper" -err "backend missing (expected awww)"
    return 1
  }
  command -v awww-daemon >/dev/null 2>&1 || {
    print_log -sec "wallpaper" -err "daemon missing (expected awww-daemon)"
    return 1
  }

  wallpaper_client_cmd="awww"
  wallpaper_daemon_cmd="awww-daemon"
  wallpaper_backend_log="awww"
  wallpaper_daemon_args=(--format argb)
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/awww"
}

wallpaper_awww_ensure_daemon() {
  "${wallpaper_client_cmd}" query >/dev/null 2>&1 && return 0
  wallpaper_awww_remove_stale_socket
  hyprshell app -t service -- "${wallpaper_daemon_cmd}" "${wallpaper_daemon_args[@]}" && wallpaper_awww_wait_until_ready && return 0
  print_log -sec "${wallpaper_backend_log}" -err "daemon did not become ready"
  return 1
}

wallpaper_awww_configure || exit 1

wallpaper_transition_type="${AWWW_TRANSITION:-fade}"
wallpaper_transition_duration="${AWWW_TRANSITION_DURATION:-0.25}"
wallpaper_transition_fps="${AWWW_TRANSITION_FPS:-60}"
wallpaper_transition_bezier="${AWWW_TRANSITION_BEZIER:-.43,1.19,1,.4}"

[[ -z "${wallpaper_path}" ]] && echo "No input wallpaper" && exit 1
wallpaper_path="$(readlink -f "${wallpaper_path}")"

wallpaper_awww_ensure_daemon || exit 1

if file --mime-type -b "${wallpaper_path}" | grep -q '^video/'; then
  print_log -sec "wallpaper" -stat "converting video" "$wallpaper_path"
  mkdir -p "${WALLPAPER_VIDEO_DIR}"
  read -r video_hash _ < <("${HYPR_HASH_COMMAND}" "${wallpaper_path}")
  video_still_path="${WALLPAPER_VIDEO_DIR}/${video_hash}.png"
  extract_thumbnail "${wallpaper_path}" "${video_still_path}"
  wallpaper_path="${video_still_path}"
fi
print_log -sec "wallpaper" -stat "apply" "$wallpaper_path"

image_path="$(readlink -f "$wallpaper_path")"
if [ -z "${image_path}" ] || [ ! -f "${image_path}" ]; then
  print_log -sec "${wallpaper_backend_log}" -err "wallpaper not found: ${wallpaper_path} -> ${image_path}"
  exit 1
fi

cursor_position="$(hyprctl cursorpos 2>/dev/null | grep -E '^[0-9]' || echo "0,0")"

awww_image_command=("${wallpaper_client_cmd}" img "${image_path}"
  --transition-bezier "${wallpaper_transition_bezier}"
  --transition-type "${wallpaper_transition_type}"
  --transition-duration "${wallpaper_transition_duration}"
  --transition-fps "${wallpaper_transition_fps}"
  --invert-y
  --transition-pos "${cursor_position}")

# Run synchronously whenever the caller is using wait-lock semantics.
# That keeps backend submits ordered with the global wallpaper lock, so
# rapid next/previous actions cannot let an older background submit land last.
if [[ "${WALLPAPER_SET_FLAG:-}" == "start" \
  || "${WALLPAPER_SYNC_APPLY:-0}" == "1" \
  || "${WALLPAPER_WAIT_FOR_LOCK:-0}" == "1" ]]; then
  "${awww_image_command[@]}"
else
  ( "${awww_image_command[@]}" || print_log -sec "${wallpaper_backend_log}" -err "failed to set wallpaper" ) &
fi

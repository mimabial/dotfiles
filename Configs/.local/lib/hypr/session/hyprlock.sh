#!/bin/bash

# shellcheck source=/dev/null
if ! source "$(command -v hyprshell)"; then
  echo "Error: hyprshell not found."
  exit 1
fi

ensure_xdg_dirs() {
  [[ -n "${XDG_CONFIG_HOME:-}" ]] || export XDG_CONFIG_HOME="$HOME/.config"
  [[ -n "${XDG_CACHE_HOME:-}" ]] || export XDG_CACHE_HOME="$HOME/.cache"
  [[ -n "${XDG_DATA_HOME:-}" ]] || export XDG_DATA_HOME="$HOME/.local/share"
}

setup_hyprlock_paths() {
  HYPR_CACHE_HOME="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME}/hypr}"
  HYPR_LIB_DIR="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}"
  WALLPAPER_CACHE_DIR="${WALLPAPER_CACHE_DIR:-${HYPR_CACHE_HOME}/wallpaper}"
  WALLPAPER_CURRENT_DIR="${WALLPAPER_CURRENT_DIR:-${WALLPAPER_CACHE_DIR}/current}"
  WALLPAPER_VIDEO_DIR="${WALLPAPER_VIDEO_DIR:-${WALLPAPER_CURRENT_DIR}/thumbnails}"
  WALLPAPER="${WALLPAPER_CURRENT_DIR}/wall.set"
  HYPRLOCK_SCOPE_NAME="${XDG_SESSION_DESKTOP:-unknown}-lockscreen.scope"
  HYPRLOCK_USER_DIR="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME}/hypr}/hyprlock"
  HYPRLOCK_SHARED_DIR="${HYPR_DATA_HOME:-${XDG_DATA_HOME}/hypr}/hyprlock"
}

usage() {
  cat <<EOF
Usage: $(basename "${0}") --[arg]

arguments:
  --background -b    - Converts and ensures background to be a png
  --title            - Returns MPRIS song title
  --artist           - Returns MPRIS artist name
  --source           - Returns MPRIS player icon
  --status           - Returns MPRIS play/pause status icon
  --length           - Returns MPRIS song length (MM:SS)
  --profile          - Generates the profile picture
  --art              - Prints the path to the mpris art
  --select      -S   - Selects the hyprlock layout
  --help       -h    - Displays this help message
EOF
}

source_hyprlock_modules() {
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"
  MAGICK_LIMITS=()
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/session/hyprlock.assets.bash"
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/session/hyprlock.media.bash"
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/session/hyprlock.layout.bash"
  resolve_magick_limits
}

ensure_background_png() {
  if [[ ! -f "${WALLPAPER_CURRENT_DIR}/wall.set.png" ]] || ! file -b "${WALLPAPER_CURRENT_DIR}/wall.set.png" 2>/dev/null | grep -q '^PNG'; then
    fn_background || true
  fi
}

refresh_mpris_fallbacks() {
  local thumb="${HYPR_CACHE_HOME}/landing/mpris"
  set_mpris_blurred_empty "${thumb}.blurred.png"
}

lock_bitwarden_if_running() {
  pgrep -x "bitwarden" >/dev/null || return 0
  bitwarden-desktop --lock &
}

run_default_lock() {
  ensure_background_png
  refresh_mpris_fallbacks
  fn_profile
  check_and_sanitize_process
  lock_bitwarden_if_running
  app2unit.sh -u "${HYPRLOCK_SCOPE_NAME}" -t scope -- hyprlock
}

update_art_cache_if_needed() {
  local lock_file="${TMPDIR:-/tmp}/hyprlock-art.lock"
  local stamp_file="${lock_file}.stamp"
  local lock_fd=""
  local now=0
  local last_spawn=0

  [[ "${1:-}" == "--source" ]] || return 0

  if ! exec {lock_fd}>"${lock_file}"; then
    return 0
  fi
  if ! flock -x "${lock_fd}"; then
    exec {lock_fd}>&-
    return 0
  fi

  now="$(date +%s)"
  if [[ -r "${stamp_file}" ]]; then
    read -r last_spawn <"${stamp_file}" || last_spawn=0
  fi

  if (( now - last_spawn > 2 )); then
    printf '%s\n' "${now}" >"${stamp_file}"
    "${BASH_SOURCE[0]}" --update-art >/dev/null 2>&1 &
  fi

  flock -u "${lock_fd}" 2>/dev/null || true
  exec {lock_fd}>&-
}

handle_hyprlock_action() {
  case "$1" in
    --test)
      layout_test "$2"
      ;;
    --test-preview)
      rofi_test_preview "$2"
      ;;
    select|-S|--select)
      fn_select
      ;;
    background|--background|-b)
      fn_background
      ;;
    profile|--profile)
      fn_profile
      ;;
    --title)
      fn_title
      ;;
    --artist)
      fn_artist
      ;;
    --source)
      fn_source
      ;;
    --status)
      fn_status
      ;;
    --length)
      fn_length
      ;;
    --update-art)
      fn_update_art
      ;;
    art|--art)
      fn_art
      ;;
    help|--help|-h)
      usage
      ;;
  esac
}

parse_and_dispatch_args() {
  local longopts="select,background,profile,title,artist,source,status,length,update-art,art,help,test:,test-preview:"
  local parsed=""

  parsed=$(getopt --options Shb --longoptions "$longopts" --name "$0" -- "$@") || exit 2
  eval set -- "$parsed"

  while true; do
    case "$1" in
      --test|--test-preview)
        handle_hyprlock_action "$1" "$2"
        exit 0
        ;;
      select|-S|--select|background|--background|-b|profile|--profile|--title|--artist|--source|--status|--length|--update-art|art|--art|help|--help|-h)
        handle_hyprlock_action "$1"
        exit 0
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
    shift
  done
}

ensure_xdg_dirs
setup_hyprlock_paths
source_hyprlock_modules

if [[ $# -eq 0 ]]; then
  run_default_lock
  exit 0
fi

update_art_cache_if_needed "${1:-}"
parse_and_dispatch_args "$@"

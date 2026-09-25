#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

queue_art_update() {
  local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" lock fd path last=0
  [[ -d "${dir}" ]] || mkdir -m 700 "${dir}" || return
  lock="${dir}/hyprlock-art.lock"
  exec {fd}>"${lock}" && flock -n "${fd}" || return 0
  read -r last 2>/dev/null <"${lock}.stamp" || last=0
  ((EPOCHSECONDS - last > 2)) || return 0
  printf '%s\n' "${EPOCHSECONDS}" >"${lock}.stamp"
  exec {fd}>&-
  # hyprlock reads a label's pipe until every holder closes it, background work included
  ( for path in /proc/self/fd/*; do fd="${path##*/}"; ((fd < 3)) || exec {fd}>&-; done
    exec "${BASH_SOURCE[0]}" --update-art ) >/dev/null 2>&1 &
}

case "${1:-}" in
  --mpris|--title|--artist|--source|--status|--length)
    source "${LIB_DIR}/hypr/session/hyprlock.media.bash"
    queue_art_update  # most layouts never ask for --source; this self-rate-limits
    "fn_${1#--}" "${2:-}"
    exit
    ;;
esac

# Theme renders can invoke this without hyprshell on PATH.
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system notify wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

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
  --mpris            - Returns MPRIS song title, or fails if nothing is playing
  --title            - Returns MPRIS song title
  --artist           - Returns MPRIS artist name
  --source           - Returns MPRIS player icon
  --status           - Returns MPRIS play/pause status icon
  --length           - Returns MPRIS song length (MM:SS)
  --play-pause       - Toggles playback on the player the lock screen shows
  --next             - Skips to the next track on that player
  --previous         - Skips to the previous track on that player
  --rewind           - Seeks 10 seconds back on that player
  --forward          - Seeks 10 seconds ahead on that player
  --profile          - Generates the profile picture
  --art              - Prints the path to the mpris art
  --select      -S   - Opens the hyprlock layout explorer
  --apply NAME       - Applies the hyprlock layout NAME
  --test NAME        - Locks with layout NAME as a dismissable preview
  --repair           - Repairs the managed hyprlock.conf wrapper
  --help       -h    - Displays this help message
EOF
}

source_hyprlock_modules() {
  MAGICK_LIMITS=()
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/session/hyprlock.assets.bash"
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/session/hyprlock.media.bash"
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/session/hyprlock.layout.bash"
  resolve_magick_limits
}

handle_hyprlock_action() {
  case "$1" in
    --test)
      preview_hyprlock_layout "$2"
      ;;
    --apply)
      fn_apply "$2"
      ;;
    select|-S|--select)
      fn_select
      ;;
    repair|--repair)
      ensure_hyprlock_conf
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
    --play-pause|--next|--previous|--rewind|--forward)
      fn_control "${1#--}"
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
  local longopts="select,repair,background,profile,title,artist,source,status,length,play-pause,next,previous,rewind,forward,update-art,art,help,test:,apply:"
  local parsed=""

  parsed=$(getopt --options Shb --longoptions "$longopts" --name "$0" -- "$@") || exit 2
  eval set -- "$parsed"

  while true; do
    case "$1" in
      --test|--apply)
        handle_hyprlock_action "$1" "$2"
        exit 0
        ;;
      select|-S|--select|repair|--repair|background|--background|-b|profile|--profile|--title|--artist|--source|--status|--length|--play-pause|--next|--previous|--rewind|--forward|--update-art|art|--art|help|--help|-h)
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

[[ $# -gt 0 ]] || set -- --help
parse_and_dispatch_args "$@"

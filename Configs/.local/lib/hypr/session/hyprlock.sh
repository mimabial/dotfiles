#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/xdg.bash"
hypr_init_xdg_env
source "${BASH_SOURCE[0]%/*}/hyprlock/paths.bash"
source "${BASH_SOURCE[0]%/*}/hyprlock/media.bash"
source "${BASH_SOURCE[0]%/*}/hyprlock/artwork.bash"
declare -A HYPRLOCK_PATHS=()
declare -a HYPRLOCK_MAGICK_ARGS=()
hyprlock_paths_into HYPRLOCK_PATHS

case "${1:-}" in
  --mpris) media_reader=hyprlock_active_media_title ;;
  --title) media_reader=hyprlock_media_title ;;
  --artist) media_reader=hyprlock_media_artist ;;
  --source) media_reader=hyprlock_media_player_icon ;;
  --status) media_reader=hyprlock_media_status_icon ;;
  --length) media_reader=hyprlock_media_duration ;;
esac
if [[ -n "${media_reader:-}" ]]; then
  media_player="$(mpris_selected_player)"
  hyprlock_queue_artwork_update HYPRLOCK_PATHS "${media_player}"
  "${media_reader}" "${2:-${media_player}}"
  exit
fi

# Theme renders can invoke this without hyprshell on PATH.
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state system notify wallpaper_catalog || exit 1
hypr_runtime_load_desktop_environment || exit 1

source "${BASH_SOURCE[0]%/*}/hyprlock/process.bash"
source "${BASH_SOURCE[0]%/*}/hyprlock/images.bash"
source "${BASH_SOURCE[0]%/*}/hyprlock/layouts.bash"

hyprlock_paths_into HYPRLOCK_PATHS
hyprlock_init_magick

usage() {
  cat <<EOF
Usage: hyprshell session/hyprlock --[arg]

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

handle_hyprlock_action() {
  case "$1" in
    --test)
      hyprlock_preview_layout HYPRLOCK_PATHS "$2"
      ;;
    --apply)
      hyprlock_apply_layout HYPRLOCK_PATHS "$2"
      ;;
    -S|--select)
      hyprlock_open_layout_selector
      ;;
    --repair)
      hyprlock_ensure_config HYPRLOCK_PATHS
      ;;
    --background|-b)
      hyprlock_render_background HYPRLOCK_PATHS
      ;;
    --profile)
      hyprlock_render_profile HYPRLOCK_PATHS
      ;;
    --play-pause|--next|--previous|--rewind|--forward)
      hyprlock_control_media "${1#--}"
      ;;
    --update-art)
      hyprlock_update_artwork HYPRLOCK_PATHS
      ;;
    --art)
      hyprlock_artwork_path HYPRLOCK_PATHS
      ;;
    --help|-h)
      usage
      ;;
  esac
}

parse_and_dispatch_args() {
  local longopts="select,repair,background,profile,play-pause,next,previous,rewind,forward,update-art,art,help,test:,apply:"
  local parsed=""

  parsed=$(getopt --options Shb --longoptions "$longopts" --name "$0" -- "$@") || exit 2
  eval set -- "$parsed"
  [[ "$1" == -- ]] || handle_hyprlock_action "$1" "${2:-}"
}

[[ $# -gt 0 ]] || set -- --help
parse_and_dispatch_args "$@"

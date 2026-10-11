KNOB_ICON_STEP_PERCENT=5
LEVEL_BAR_PERCENT_PER_DOT=15

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1
}

is_true() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

media_icons_dir() {
  printf '%s/Hypr-Icon/media\n' "${ICONS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}"
}

notify_level() {
  local app="$1" replace_id="$2" percent="$3" label="$4" knob_percent="" bar=""
  knob_percent=$(((percent + KNOB_ICON_STEP_PERCENT / 2) / KNOB_ICON_STEP_PERCENT * KNOB_ICON_STEP_PERCENT))
  ((knob_percent > 100)) && knob_percent=100
  printf -v bar '%*s' "$((percent / LEVEL_BAR_PERCENT_PER_DOT))" ''
  dunstify -a "${app}" -r "${replace_id}" -t "${NOTIFY_OSD_MS}" \
    -e -i "$(media_icons_dir)/knob-${knob_percent}.svg" "${percent}${bar// /.}" "${label}"
}

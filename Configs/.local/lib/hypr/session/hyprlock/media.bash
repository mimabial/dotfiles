MPRIS_SEEK_SECONDS=10
MPRIS_TITLE_MAX_CHARS=40
mpris_player_icon() {
  local player=${1:-default}
  declare -A player_icons=(
    ["default"]=""
    ["spotify"]=""
    ["firefox"]=""
    ["fftab"]=""  # the browser bridge names a player per tab
    ["vlc"]="嗢"
    ["google-chrome"]=""
    ["opera"]=""
    ["brave"]=""
  )
  local key=""

  for key in "${!player_icons[@]}"; do
    if [[ ${player} == "$key"* ]]; then
      echo "${player_icons[$key]}"
      return
    fi
  done
  echo "${player_icons[default]}"
}

# playerctl lists alphabetically, so only the status can pick the player that sounds.
mpris_selected_player() {
  local -a names=() statuses=()
  mapfile -t names < <(playerctl --list-all 2>/dev/null)
  mapfile -t statuses < <(playerctl -a status 2>/dev/null)
  local index="" paused=""
  for index in "${!names[@]}"; do
    case "${statuses[index]:-}" in
      Playing)
        printf '%s' "${names[index]}"
        return
        ;;
      Paused) [[ -n ${paused} ]] || paused="${names[index]}" ;;
    esac
  done
  printf '%s' "${paused:-${names[0]:-}}"
}

mpris_player_status() {
  playerctl -p "${1}" status 2>/dev/null
}

mpris_status_is_active() {
  case "${1:-}" in
    Playing | Paused) return 0 ;;
    *) return 1 ;;
  esac
}

mpris_active_metadata() {
  local player="$1"
  local format="$2"
  local metadata=""
  metadata="$(playerctl -p "${player}" metadata --format $'{{status}}\t'"${format}" 2>/dev/null)" || return 1
  local status="${metadata%%$'\t'*}"
  local value="${metadata#*$'\t'}"
  mpris_status_is_active "${status}" || return 1
  printf '%s\n' "${value}"
}

mpris_artwork_url() {
  local player="$1"
  local art_url=""
  local video_url=""
  local video_id=""
  local youtube_watch_re='youtube\.com/watch\?v=([^&]+)'
  local youtube_short_re='youtu\.be/([^?]+)'

  art_url="$(playerctl -p "${player}" metadata --format '{{mpris:artUrl}}' 2>/dev/null)"
  if [[ -z "${art_url}" ]]; then
    video_url="$(playerctl -p "${player}" metadata --format '{{xesam:url}}' 2>/dev/null)"
    if [[ "${video_url}" =~ ${youtube_watch_re} ]] || [[ "${video_url}" =~ ${youtube_short_re} ]]; then
      video_id="${BASH_REMATCH[1]}"
      art_url="https://img.youtube.com/vi/${video_id}/maxresdefault.jpg"
    fi
  fi

  printf '%s\n' "${art_url}"
}

mpris_fallback_artist() {
  awk -F'=' '/^PRETTY_NAME=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release
}

format_mpris_length() {
  local length=$1
  local microseconds_per_second=1000000
  local seconds=$((length / microseconds_per_second))
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))
  printf "%d:%02d\n" "${minutes}" "${remaining_seconds}"
}

truncate_mpris_title() {
  local value="$1"
  local max_length="${2:-${MPRIS_TITLE_MAX_CHARS}}"

  if ((${#value} > max_length)); then
    printf '%s...\n' "${value:0:max_length}"
  else
    printf '%s\n' "${value}"
  fi
}

hyprlock_media_title() {
  local player=${1:-$(mpris_selected_player)}
  local title=""

  title="$(mpris_active_metadata "${player}" "{{xesam:title}}" || true)"
  if [[ -n "${title}" ]]; then
    truncate_mpris_title "${title}"
  else
    echo "${USER^}"
  fi
}

hyprlock_active_media_title() {
  local player=${1:-$(mpris_selected_player)}
  mpris_status_is_active "$(mpris_player_status "${player}" || true)" || return 1
  hyprlock_media_title "${player}"
}

hyprlock_media_artist() {
  local player=${1:-$(mpris_selected_player)}

  if ! mpris_active_metadata "${player}" "{{xesam:artist}}"; then
    mpris_fallback_artist
  fi
}

hyprlock_media_player_icon() {
  local player=${1:-$(mpris_selected_player)}
  local player_status=""

  player_status="$(mpris_player_status "${player}" || true)"
  if mpris_status_is_active "${player_status}"; then
    mpris_player_icon "${player}"
  fi
}

hyprlock_media_status_icon() {
  local player=${1:-$(mpris_selected_player)}
  local player_status=""

  player_status="$(mpris_player_status "${player}" || true)"
  case "${player_status}" in
    Playing) echo "▶" ;;
    Paused) echo "⏸" ;;
    *) echo "" ;;
  esac
}

hyprlock_control_media() {
  local player=""
  player="$(mpris_selected_player)"
  [[ -n "${player}" ]] || return 0
  case "$1" in
    rewind) playerctl -p "${player}" position "${MPRIS_SEEK_SECONDS}-" ;;
    forward) playerctl -p "${player}" position "${MPRIS_SEEK_SECONDS}+" ;;
    *) playerctl -p "${player}" "$1" ;;
  esac
}

hyprlock_media_duration() {
  local player=${1:-$(mpris_selected_player)}
  local length=""

  length="$(mpris_active_metadata "${player}" "{{mpris:length}}" || true)"
  if [[ -n "${length}" ]]; then
    format_mpris_length "${length}"
  fi
}

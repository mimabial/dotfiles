MPRIS_SEEK_SECONDS=10
MPRIS_TITLE_MAX_CHARS=40
MPRIS_SNAPSHOT_FORMAT=$'{{playerInstance}}\x1f{{status}}\x1f{{xesam:title}}\x1f{{xesam:artist}}\x1f{{mpris:length}}\x1f{{mpris:artUrl}}\x1f{{xesam:url}}'
MPRIS_SNAPSHOT_SHARE_MICROSECONDS=500000
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
  local name="" status="" first="" paused=""
  while IFS=$'\t' read -r name status; do
    [[ -n ${first} ]] || first="${name}"
    case "${status}" in
      Playing)
        printf '%s' "${name}"
        return
        ;;
      Paused) [[ -n ${paused} ]] || paused="${name}" ;;
    esac
  done < <(playerctl -a status --format $'{{playerInstance}}\t{{status}}' 2>/dev/null)
  printf '%s' "${paused:-${first}}"
}

mpris_snapshot_into() {
  local -n snapshot_ref="$1"
  local snapshot_file="$2" lock_fd stamp="" rows="" row="" name="" status="" selected="" paused="" first=""
  local now="${EPOCHREALTIME/./}"
  [[ -d "${snapshot_file%/*}" ]] || mkdir -m 700 "${snapshot_file%/*}" || return 1
  exec {lock_fd}<>"${snapshot_file}"
  flock "${lock_fd}"
  { IFS= read -r stamp || true; IFS= read -r -d '' rows || true; } <"${snapshot_file}"
  if ((now - ${stamp:-0} >= MPRIS_SNAPSHOT_SHARE_MICROSECONDS || now < ${stamp:-0})); then
    rows="$(playerctl -a metadata --format "${MPRIS_SNAPSHOT_FORMAT}" 2>/dev/null)" || true
    printf '%s\n%s\n' "${now}" "${rows}" >"${snapshot_file}"
    snapshot_ref[fresh]=1
  fi
  exec {lock_fd}>&-
  while IFS= read -r row; do
    IFS=$'\x1f' read -r name status _ <<<"${row}"
    [[ -n ${first} ]] || first="${row}"
    case "${status}" in
      Playing)
        selected="${row}"
        break
        ;;
      Paused) [[ -n ${paused} ]] || paused="${row}" ;;
    esac
  done <<<"${rows}"
  IFS=$'\x1f' read -r "snapshot_ref[player]" "snapshot_ref[status]" "snapshot_ref[title]" "snapshot_ref[artist]" \
    "snapshot_ref[length]" "snapshot_ref[art_url]" "snapshot_ref[url]" <<<"${selected:-${paused:-${first}}}"
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

mpris_artwork_url_into() {
  local -n art_url_ref="$1"
  local video_url="$3"
  local youtube_watch_re='youtube\.com/watch\?v=([^&]+)'
  local youtube_short_re='youtu\.be/([^?]+)'

  art_url_ref="$2"
  if [[ -z "${art_url_ref}" ]] && { [[ "${video_url}" =~ ${youtube_watch_re} ]] || [[ "${video_url}" =~ ${youtube_short_re} ]]; }; then
    art_url_ref="https://img.youtube.com/vi/${BASH_REMATCH[1]}/maxresdefault.jpg"
  fi
}

mpris_artwork_url() {
  local art_url="" video_url=""
  IFS=$'\x1f' read -r art_url video_url < <(playerctl -p "$1" metadata --format $'{{mpris:artUrl}}\x1f{{xesam:url}}' 2>/dev/null) || true
  mpris_artwork_url_into art_url "${art_url}" "${video_url}"
  printf '%s\n' "${art_url}"
}

mpris_fallback_artist() {
  local line="" value=""
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == PRETTY_NAME=* ]] || continue
    value="${line#PRETTY_NAME=}"
    value="${value%%=*}"
    printf '%s\n' "${value//\"/}"
    return
  done </etc/os-release
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
  local -n title_media_ref="$1"

  if mpris_status_is_active "${title_media_ref[status]}" && [[ -n "${title_media_ref[title]}" ]]; then
    truncate_mpris_title "${title_media_ref[title]}"
  else
    echo "${USER^}"
  fi
}

hyprlock_active_media_title() {
  local -n active_media_ref="$1"
  mpris_status_is_active "${active_media_ref[status]}" || return 1
  hyprlock_media_title "$1"
}

hyprlock_media_artist() {
  local -n artist_media_ref="$1"

  if mpris_status_is_active "${artist_media_ref[status]}"; then
    printf '%s\n' "${artist_media_ref[artist]}"
  else
    mpris_fallback_artist
  fi
}

hyprlock_media_player_icon() {
  local -n icon_media_ref="$1"

  if mpris_status_is_active "${icon_media_ref[status]}"; then
    mpris_player_icon "${icon_media_ref[player]}"
  fi
}

hyprlock_media_status_icon() {
  local -n status_media_ref="$1"

  case "${status_media_ref[status]}" in
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
  local -n duration_media_ref="$1"

  if mpris_status_is_active "${duration_media_ref[status]}" && [[ -n "${duration_media_ref[length]}" ]]; then
    format_mpris_length "${duration_media_ref[length]}"
  fi
}

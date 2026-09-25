#!/usr/bin/env bash
# Music progress for a hyprlock label: hyprlock.progress.sh PLAYED_HEX REST_HEX
set -uo pipefail

played_color="${1:-ffffff}" remaining_color="${2:-ffffff}" progress_cells=10
progress_cache="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/hyprlock-progress"

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/session/hyprlock.media.bash"
player="$(mpris_default_player)"
[[ -n "${player}" ]] || { rm -f "${progress_cache}"; exit 0; }
IFS=';' read -r status position length track < <(playerctl -p "${player}" metadata \
  --format '{{status}};{{position}};{{mpris:length}};{{mpris:trackid}}' 2>/dev/null)
if [[ ! "${status:-}" =~ ^(Playing|Paused)$ || ! "${position:-}" =~ ^[0-9]+$ || ! "${length:-}" =~ ^[1-9][0-9]*$ ]]; then
  rm -f "${progress_cache}"
  exit 0
fi

# Spotify reports a frozen position; while it stays frozen, count wall time instead.
now_microseconds="$(date +%s%6N)" reported_position="${position}"
read -r last_track last_reported_position last_displayed_position last_update_microseconds 2>/dev/null <"${progress_cache}" || true
if [[ "${track}" == "${last_track:-}" && "${reported_position}" == "${last_reported_position:-}" ]]; then
  position="${last_displayed_position}"
  [[ "${status}" == Playing ]] && position=$((last_displayed_position + now_microseconds - last_update_microseconds))
fi
((position > length)) && position="${length}"
[[ -d "${progress_cache%/*}" ]] || mkdir -p "${progress_cache%/*}"
printf '%s %s %s %s\n' "${track}" "${reported_position}" "${position}" "${now_microseconds}" >"${progress_cache}"

fill_progress_cells() { printf -v "$1" '%*s' "$2" ''; printf -v "$1" '%s' "${!1// /—}"; }
done_cells=$((position * progress_cells / length))
((done_cells == 0)) && [[ "${status}" == Playing ]] && done_cells=1
if ((done_cells >= progress_cells)); then
  fill_progress_cells full $((progress_cells + 1))
  progress_markup="<span foreground=\"#${played_color}\">${full}</span>"
else
  fill_progress_cells head "${done_cells}"
  fill_progress_cells tail $((progress_cells - done_cells))
  progress_markup="<span foreground=\"#${played_color}\">${head}</span><span foreground=\"#${remaining_color}\">⦿</span><span foreground=\"#${remaining_color}\" alpha=\"25%\">${tail}</span>"
fi
format_mpris_timestamp() { printf '%d:%02d' $(($1 / 60000000)) $(($1 / 1000000 % 60)); }
printf '%s %s / %s\n' "${progress_markup}" "$(format_mpris_timestamp "${position}")" "$(format_mpris_timestamp "${length}")"

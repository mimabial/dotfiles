#!/usr/bin/env bash
# Music progress for a hyprlock label: hyprlock.progress.sh PLAYED_HEX REST_HEX
set -uo pipefail

played="${1:-ffffff}" rest="${2:-ffffff}" cells=10
cache="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/hyprlock-progress"

player=spotify
[[ "$(playerctl -p "${player}" status 2>/dev/null)" =~ ^(Playing|Paused)$ ]] || player="$(playerctl -l 2>/dev/null | head -n 1)"
[[ -n "${player}" ]] || { rm -f "${cache}"; exit 0; }
IFS=';' read -r status position length track < <(playerctl -p "${player}" metadata \
  --format '{{status}};{{position}};{{mpris:length}};{{mpris:trackid}}' 2>/dev/null)
if [[ ! "${status:-}" =~ ^(Playing|Paused)$ || ! "${position:-}" =~ ^[0-9]+$ || ! "${length:-}" =~ ^[1-9][0-9]*$ ]]; then
  rm -f "${cache}"
  exit 0
fi

# Spotify reports a frozen position; while it stays frozen, count wall time instead.
now="$(date +%s%6N)" raw="${position}"
read -r last_track last_raw last_shown last_now 2>/dev/null <"${cache}" || true
if [[ "${track}" == "${last_track:-}" && "${raw}" == "${last_raw:-}" ]]; then
  position="${last_shown}"
  [[ "${status}" == Playing ]] && position=$((last_shown + now - last_now))
fi
((position > length)) && position="${length}"
[[ -d "${cache%/*}" ]] || mkdir -p "${cache%/*}"
printf '%s %s %s %s\n' "${track}" "${raw}" "${position}" "${now}" >"${cache}"

dashes() { printf -v "$1" '%*s' "$2" ''; printf -v "$1" '%s' "${!1// /—}"; }
done_cells=$((position * cells / length))
((done_cells == 0)) && [[ "${status}" == Playing ]] && done_cells=1
if ((done_cells >= cells)); then
  dashes full $((cells + 1))
  bar="<span foreground=\"#${played}\">${full}</span>"
else
  dashes head "${done_cells}"
  dashes tail $((cells - done_cells))
  bar="<span foreground=\"#${played}\">${head}</span><span foreground=\"#${rest}\">⦿</span><span foreground=\"#${rest}\" alpha=\"25%\">${tail}</span>"
fi
clock() { printf '%d:%02d' $(($1 / 60000000)) $(($1 / 1000000 % 60)); }
printf '%s %s / %s\n' "${bar}" "$(clock "${position}")" "$(clock "${length}")"

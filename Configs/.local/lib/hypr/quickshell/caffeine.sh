#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/../session/idle.state.sh"

manual_on=0
audio_enabled=1
audio_playing=0
fullscreen_enabled=0
fullscreen_active=0
game_active=0
idle_manual_enabled && manual_on=1
idle_audio_enabled || audio_enabled=0
idle_fullscreen_enabled && fullscreen_enabled=1
if command -v playerctl >/dev/null 2>&1 && playerctl -a status 2>/dev/null | grep -q '^Playing$'; then
  audio_playing=1
fi
window_state_file="$(idle_window_state_file)"
[[ ! -r "${window_state_file}" ]] || read -r fullscreen_active game_active <"${window_state_file}" || true
audio_on=$((audio_enabled && audio_playing))
fullscreen_on=$((fullscreen_enabled && fullscreen_active))
game_on=$((fullscreen_enabled && game_active))

if [[ "${manual_on}" -eq 1 || "${audio_on}" -eq 1 || "${fullscreen_on}" -eq 1 || "${game_on}" -eq 1 ]]; then
  icon="\udb80\udd76"
  header_color="#98c379"
  header_text="Caffeine Mode Active"
  class_name="activated"
  alt_text="activated"
else
  icon="\udb81\udeca"
  header_color="#e06c75"
  header_text="Caffeine Mode Inactive"
  class_name="deactivated"
  alt_text="deactivated"
fi

manual_labels=("Off" "On")
manual_label=${manual_labels[manual_on]}
audio_label=Idle
((audio_on)) && audio_label=Playing
((audio_enabled)) || audio_label=Disabled
audio_status_label=Idle
if ((audio_playing)); then
  audio_status_label=Playing
  ((audio_enabled)) || audio_status_label="Playing (ignored)"
fi
fullscreen_label=Idle
((fullscreen_on)) && fullscreen_label=Active
((fullscreen_enabled)) || fullscreen_label=Disabled
fullscreen_status_label=Idle
if ((fullscreen_active)); then
  fullscreen_status_label=Active
  ((fullscreen_enabled)) || fullscreen_status_label="Active (ignored)"
fi
game_status_label=Idle
if ((game_active)); then
  game_status_label=Active
  ((fullscreen_enabled)) || game_status_label="Active (ignored)"
fi

reasons=()
((manual_on)) && reasons+=(Manual)
((audio_on)) && reasons+=(Audio)
((fullscreen_on)) && reasons+=(Fullscreen)
((game_on)) && reasons+=(Game)
reason_label=None
if ((${#reasons[@]})); then
  printf -v reason_label '%s, ' "${reasons[@]}"
  reason_label="${reason_label%, }"
fi

class_extra=""
((manual_on)) && class_extra+=" manual"
((audio_on)) && class_extra+=" audio"
((fullscreen_on)) && class_extra+=" fullscreen"
((game_on)) && class_extra+=" game"

tooltip="<span foreground='${header_color}'>${icon} ${header_text}</span>\nManual: ${manual_label}\nAudio Toggle: ${audio_label}\nAudio Status: ${audio_status_label}\nFullscreen/Game Toggle: ${fullscreen_label}\nFullscreen Status: ${fullscreen_status_label}\nGame Status: ${game_status_label}\nReason: ${reason_label}"

bools=(false true)
printf '{"text": "%s", "tooltip": "%s", "class": "%s%s", "alt": "%s", "manual": %s, "audioEnabled": %s, "playing": %s, "fullscreenEnabled": %s, "fullscreen": %s, "game": %s, "reason": "%s"}' \
  "${icon}" "${tooltip}" "${class_name}" "${class_extra}" "${alt_text}" \
  "${bools[manual_on]}" "${bools[audio_enabled]}" "${bools[audio_playing]}" \
  "${bools[fullscreen_enabled]}" "${bools[fullscreen_active]}" "${bools[game_active]}" \
  "${reason_label}"

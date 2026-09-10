#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/../session/idle.state.sh"

manual_on=0
audio_enabled=1
audio_playing=0
idle_manual_enabled && manual_on=1
idle_audio_enabled || audio_enabled=0
if command -v playerctl >/dev/null 2>&1 && playerctl -a status 2>/dev/null | grep -q '^Playing$'; then
  audio_playing=1
fi
audio_on=$((audio_enabled && audio_playing))

if [[ "${manual_on}" -eq 1 || "${audio_on}" -eq 1 ]]; then
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

case "${manual_on}${audio_on}" in
  10) reason_label=Manual ;;
  01) reason_label=Audio ;;
  11) reason_label="Manual, Audio" ;;
  *) reason_label=None ;;
esac

class_extra=""
((manual_on)) && class_extra+=" manual"
((audio_on)) && class_extra+=" audio"

tooltip="<span foreground='${header_color}'>${icon} ${header_text}</span>\nManual: ${manual_label}\nAudio Toggle: ${audio_label}\nAudio Status: ${audio_status_label}\nReason: ${reason_label}"

bools=(false true)
printf '{"text": "%s", "tooltip": "%s", "class": "%s%s", "alt": "%s", "manual": %s, "audioEnabled": %s, "playing": %s, "reason": "%s"}' \
  "${icon}" "${tooltip}" "${class_name}" "${class_extra}" "${alt_text}" \
  "${bools[manual_on]}" "${bools[audio_enabled]}" "${bools[audio_playing]}" \
  "${reason_label}"

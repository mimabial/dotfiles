#!/usr/bin/env bash

# Waybar module script for caffeine/keep-awake status
# Outputs JSON for waybar custom module

STATE_DIR="${XDG_STATE_HOME:-}"
if [[ -z "${STATE_DIR}" ]]; then
  STATE_DIR="$HOME/.local/state"
fi
STATE_DIR="${STATE_DIR}/hypr"
KEEP_AWAKE_STATE_FILE="${STATE_DIR}/keep-awake.state"
AUDIO_STATE_FILE="${STATE_DIR}/keep-awake-audio.state"

manual_on=0
audio_on=0
audio_enabled=1

if [[ -f "${KEEP_AWAKE_STATE_FILE}" ]]; then
  manual_on=1
fi

if [[ -f "${AUDIO_STATE_FILE}" ]]; then
  audio_value=$(<"${AUDIO_STATE_FILE}")
  if [[ "${audio_value}" == "0" ]]; then
    audio_enabled=0
  fi
fi

audio_playing=0
if command -v playerctl >/dev/null 2>&1; then
  if playerctl -a status 2>/dev/null | grep -q '^Playing$'; then
    audio_playing=1
  fi
fi

if [[ "${audio_enabled}" -eq 1 && "${audio_playing}" -eq 1 ]]; then
  audio_on=1
fi

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

if [[ "${manual_on}" -eq 1 ]]; then
  manual_label="On"
else
  manual_label="Off"
fi

if [[ "${audio_on}" -eq 1 ]]; then
  audio_label="Playing"
else
  audio_label="Idle"
  if [[ "${audio_enabled}" -eq 0 ]]; then
    audio_label="Disabled"
  fi
fi

audio_status_label="Idle"
if [[ "${audio_playing}" -eq 1 ]]; then
  audio_status_label="Playing"
  if [[ "${audio_enabled}" -eq 0 ]]; then
    audio_status_label="Playing (ignored)"
  fi
fi

reasons=()
if [[ "${manual_on}" -eq 1 ]]; then
  reasons+=("Manual")
fi
if [[ "${audio_on}" -eq 1 ]]; then
  reasons+=("Audio")
fi
if [[ "${#reasons[@]}" -gt 0 ]]; then
  reason_label=""
  for reason in "${reasons[@]}"; do
    if [[ -n "${reason_label}" ]]; then
      reason_label="${reason_label}, "
    fi
    reason_label="${reason_label}${reason}"
  done
else
  reason_label="None"
fi

class_extra=""
if [[ "${manual_on}" -eq 1 ]]; then
  class_extra="${class_extra} manual"
fi
if [[ "${audio_on}" -eq 1 ]]; then
  class_extra="${class_extra} audio"
fi

tooltip="<span foreground='${header_color}'>${icon} ${header_text}</span>\nManual: ${manual_label}\nAudio Toggle: ${audio_label}\nAudio Status: ${audio_status_label}\nReason: ${reason_label}"

printf '{"text": "%s", "tooltip": "%s", "class": "%s%s", "alt": "%s"}' \
  "${icon}" "${tooltip}" "${class_name}" "${class_extra}" "${alt_text}"

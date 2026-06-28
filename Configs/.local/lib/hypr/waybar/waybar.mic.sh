#!/usr/bin/env bash

set -euo pipefail

find_audio_source() {
  local default_source=""

  default_source="$(pactl info 2>/dev/null | sed -n 's/^Default Source: //p' | head -1)"
  if [[ -n "${default_source}" && "${default_source}" != *.monitor ]]; then
    printf '%s\n' "${default_source}"
    return 0
  fi

  pactl list short sources 2>/dev/null | awk '$2 !~ /\.monitor$/ {print $2; exit}'
}

source_volume_pct() {
  pactl get-source-volume "$1" 2>/dev/null | awk 'match($0,/[0-9]+%/){print substr($0,RSTART,RLENGTH-1); exit}'
}

source_is_muted() {
  [[ "$(pactl get-source-mute "$1" 2>/dev/null | awk '{print $2}')" == "yes" ]]
}

main() {
  local source=""
  local volume="0"
  local text=""
  local alt="absent"
  local class_name="absent"
  local tooltip="No microphone"

  source="$(find_audio_source || true)"
  if [[ -n "${source}" ]]; then
    volume="$(source_volume_pct "${source}")"
    volume="${volume:-0}"
    if source_is_muted "${source}"; then
      alt="muted"
      class_name="muted"
      tooltip="Microphone muted"
    else
      text=""
      alt="active"
      class_name="active"
      tooltip="${volume}% microphone"
    fi
  fi

  printf '{"text":"%s","alt":"%s","class":"%s","tooltip":"%s"}\n' \
    "${text}" "${alt}" "${class_name}" "${tooltip}"
}

main "$@"

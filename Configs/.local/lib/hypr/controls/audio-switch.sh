#!/usr/bin/env bash

set -u

scr_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${scr_dir}/lib/control.common.bash"

require_cmd wpctl || {
  echo "wpctl is required"
  exit 1
}
require_cmd pw-dump || {
  echo "pw-dump is required"
  exit 1
}
require_cmd jq || {
  echo "jq is required"
  exit 1
}
require_cmd notify-send || {
  echo "notify-send is required"
  exit 1
}

list_sinks_tsv() {
  pw-dump |
    jq -r '.[] | select(.type=="PipeWire:Interface:Node" and .info?.props?."media.class"=="Audio/Sink") | [.info.props."object.id", (.info.props."node.description" // .info.props."node.name" // "Unknown")] | @tsv'
}

current_sink_id() {
  wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null |
    awk '/^id / { gsub(/,/, "", $2); print $2; exit }'
}

sink_volume_pct() {
  local sink_id="$1"
  wpctl get-volume "${sink_id}" 2>/dev/null | awk '{ printf "%.0f\n", $2 * 100 }'
}

sink_is_muted() {
  local sink_id="$1"
  wpctl get-volume "${sink_id}" 2>/dev/null | grep -q "MUTED"
}

volume_icon_state() {
  local vol="$1"
  local muted="$2"
  if [[ "${muted}" == "true" || "${vol}" -eq 0 ]]; then
    printf 'muted\n'
  elif [[ "${vol}" -le 33 ]]; then
    printf 'low\n'
  elif [[ "${vol}" -le 66 ]]; then
    printf 'medium\n'
  else
    printf 'high\n'
  fi
}

mapfile -t sinks < <(list_sinks_tsv)
if (( ${#sinks[@]} == 0 )); then
  notify-send -u critical "Audio" "No audio devices found"
  exit 1
fi

cur_id="$(current_sink_id)"
cur_idx=-1
for i in "${!sinks[@]}"; do
  sink_id="${sinks[$i]%%$'\t'*}"
  if [[ "${sink_id}" == "${cur_id}" ]]; then
    cur_idx="${i}"
    break
  fi
done

if (( cur_idx < 0 )); then
  next_idx=0
else
  next_idx=$(((cur_idx + 1) % ${#sinks[@]}))
fi

next_line="${sinks[$next_idx]}"
next_id="${next_line%%$'\t'*}"
next_desc="${next_line#*$'\t'}"

if [[ "${next_id}" != "${cur_id}" ]]; then
  wpctl set-default "${next_id}"
fi

next_vol="$(sink_volume_pct "${next_id}")"
if sink_is_muted "${next_id}"; then
  next_muted="true"
else
  next_muted="false"
fi

icon_state="$(volume_icon_state "${next_vol}" "${next_muted}")"
notify-send -i "audio-volume-${icon_state}-symbolic" "Audio Output" "${next_desc}"

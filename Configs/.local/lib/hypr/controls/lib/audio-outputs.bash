get_sink_label() {
  wpctl inspect "$1" 2>/dev/null | awk -F'"' '/node.description = / { print $2; exit }'
}

get_default_sink_id() {
  wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | awk '/^id / { gsub(/,/, "", $2); print $2; exit }'
}

list_sinks_tsv() {
  pw-dump |
    jq -r '.[] | select(.type=="PipeWire:Interface:Node" and .info?.props?."media.class"=="Audio/Sink") | [.info.props."object.id", .info.props."node.name"] | @tsv'
}

next_audio_sink() {
  local current_id="$1"
  local -a sinks=()
  local current_index=-1
  local next_index=0
  local i=0
  local sink_id=""

  mapfile -t sinks < <(list_sinks_tsv)
  (( ${#sinks[@]} == 0 )) && return 1

  for i in "${!sinks[@]}"; do
    sink_id="${sinks[$i]%%$'\t'*}"
    [[ "${sink_id}" == "${current_id}" ]] && { current_index="${i}"; break; }
  done

  if (( current_index < 0 )); then
    next_index=0
  else
    next_index=$(( (current_index + 1) % ${#sinks[@]} ))
  fi
  printf '%s\n' "${sinks[$next_index]}"
}

move_application_streams() {
  local old_sink="$1" new_sink="$2" old_index="" metadata="" streams=""
  local input="" object_id=""
  local -A explicit_targets=()

  [[ -n ${old_sink} && ${old_sink} != "${new_sink}" ]] || return 0
  metadata=$(pw-metadata -n default 2>/dev/null) || return 0
  old_index=$(pactl -f json list sinks 2>/dev/null |
    jq -r --arg name "${old_sink}" 'map(select(.name == $name))[0].index // empty') || return 0
  [[ ${old_index} =~ ^[0-9]+$ ]] || return 0
  streams=$(pactl -f json list sink-inputs 2>/dev/null |
    jq -r --arg sink "${old_index}" '.[]
      | select((.sink | tostring) == $sink)
      | select(.properties."application.name" != null and .properties."application.name" != "EasyEffects")
      | [.index, (.properties."object.id" // "")] | @tsv') || return 0

  while IFS= read -r object_id; do
    explicit_targets["${object_id}"]=1
  done < <(streams_with_explicit_target <<<"${metadata}")

  while IFS=$'\t' read -r input object_id; do
    [[ ${input} =~ ^[0-9]+$ ]] || continue
    [[ -n ${object_id} && -n ${explicit_targets[${object_id}]:-} ]] && continue
    pactl move-sink-input "${input}" "${new_sink}" >/dev/null 2>&1 || true
  done <<<"${streams}"
}

set_default_output() {
  local sink_id="$1"
  local sink_name="$2"
  local sink_label=""
  local old_sink=""

  old_sink=$(pactl get-default-sink 2>/dev/null || true)
  sink_label="$(get_sink_label "${sink_id}")"

  if wpctl set-default "${sink_id}"; then
    move_application_streams "${old_sink}" "${sink_name}"
    dunstify -t "${NOTIFY_OSD_MS}" -i "$(media_icons_dir)/unmuted-speaker.svg" \
      -r "${NOTIFY_ID_VOLUME}" -u low "Activated: ${sink_label:-${sink_name}}"
  else
    dunstify -t "${NOTIFY_OSD_MS}" -r "${NOTIFY_ID_VOLUME}" -u critical \
      -i "dialog-error" "Error activating ${sink_label:-${sink_name}}"
    return 1
  fi
}

toggle_output_to_next_sink() {
  local current_id=""
  local next_line=""
  local next_id=""
  local next_name=""

  require_commands pw-dump jq wpctl pactl dunstify || return 1
  current_id="$(get_default_sink_id)"
  next_line="$(next_audio_sink "${current_id}")" || return 1
  next_id="${next_line%%$'\t'*}"
  next_name="${next_line#*$'\t'}"

  set_default_output "${next_id}" "${next_name}"
}

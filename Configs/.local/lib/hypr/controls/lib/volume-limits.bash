SOFTWARE_VOLUME_LIMITS='{"minimum":-60,"maximum":0,"step":1,"backend":"software"}'

default_sink_api_card_port() {
  local sink=""
  sink="$(pactl get-default-sink 2>/dev/null || true)"
  pactl --format=json list sinks 2>/dev/null | jq -r --arg sink "${sink}" '
    .[] | select(.name == $sink)
    | [(.properties["device.api"] // ""), (.properties["alsa.card"] // ""), (.active_port // "")]
    | @tsv' | head -1
}

mixer_control_for_port() {
  case "${1,,}" in
    *headphone* | *headset*) printf 'Headphone\n' ;;
    *speaker*) printf 'Speaker\n' ;;
    *lineout* | *line-out*) printf 'Line Out\n' ;;
    *) printf 'PCM\n' ;;
  esac
}

playback_volume_caps_line() {
  local mixer_control="$1" caps_pattern="$2" file="$3"
  awk -v wanted="${mixer_control} Playback Volume" -v caps="${caps_pattern}" '
    /Control: name=/ { volume = /Playback Volume/; exact = index($0, "name=\"" wanted "\"") }
    volume && $0 ~ caps {
      if (exact) { print; found = 1; exit }
      if (!fallback) fallback = $0
      volume = 0
    }
    END { if (!found && fallback) print fallback }
  ' "${file}"
}

print_volume_limits() {
  local device_api="" card_index="" active_port="" mixer_control="" codec_file="" capabilities=""
  if ! command -v pactl >/dev/null || ! command -v jq >/dev/null; then
    printf '%s\n' "${SOFTWARE_VOLUME_LIMITS}"
    return
  fi
  IFS=$'\t' read -r device_api card_index active_port < <(default_sink_api_card_port)
  [[ "${device_api}" == "alsa" && "${card_index}" =~ ^[0-9]+$ ]] || { printf '%s\n' "${SOFTWARE_VOLUME_LIMITS}"; return; }
  mixer_control="$(mixer_control_for_port "${active_port}")"
  for codec_file in /proc/asound/card"${card_index}"/codec#*; do
    [[ -r "${codec_file}" ]] || continue
    capabilities="$(playback_volume_caps_line "${mixer_control}" 'Amp-Out caps:' "${codec_file}")"
    [[ -n "${capabilities}" ]] && break
  done
  if [[ "${capabilities}" =~ ofs=0x([[:xdigit:]]+),[[:space:]]+nsteps=0x([[:xdigit:]]+),[[:space:]]+stepsize=0x([[:xdigit:]]+) ]]; then
    local offset=$((16#${BASH_REMATCH[1]})) steps=$((16#${BASH_REMATCH[2]})) step_size=$((16#${BASH_REMATCH[3]}))
    awk -v offset="${offset}" -v steps="${steps}" -v step_size="${step_size}" 'BEGIN { step_db=(step_size+1)/4; printf "{\"minimum\":%.2f,\"maximum\":%.2f,\"step\":%.2f,\"backend\":\"alsa\"}\n", -offset*step_db, (steps-offset)*step_db, step_db }'
    return
  fi
  codec_file="/proc/asound/card${card_index}/usbmixer"
  [[ -r "${codec_file}" ]] && capabilities="$(playback_volume_caps_line "${mixer_control}" 'Volume:.*dBmin=' "${codec_file}")"
  if [[ "${capabilities}" =~ dBmin=(-?[0-9]+),[[:space:]]*dBmax=(-?[0-9]+) ]]; then
    awk -v minimum="${BASH_REMATCH[1]}" -v maximum="${BASH_REMATCH[2]}" 'BEGIN { printf "{\"minimum\":%.2f,\"maximum\":%.2f,\"step\":1,\"backend\":\"alsa\"}\n", minimum/100, maximum/100 }'
  else
    printf '%s\n' "${SOFTWARE_VOLUME_LIMITS}"
  fi
}

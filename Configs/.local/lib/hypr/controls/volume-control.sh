#!/usr/bin/env bash
set -u

print_volume_limits() {
  local sink="" sink_fields="" device_api="" card_index="" active_port="" mixer_control="PCM" codec_file="" capabilities=""
  if ! command -v pactl >/dev/null || ! command -v jq >/dev/null; then
    printf '{"minimum":-60,"maximum":0,"step":1,"backend":"software"}\n'
    return
  fi
  sink="$(pactl get-default-sink 2>/dev/null || true)"
  sink_fields="$(pactl --format=json list sinks 2>/dev/null | jq -r --arg sink "${sink}" '.[] | select(.name == $sink) | [(.properties["device.api"] // ""), (.properties["alsa.card"] // ""), (.active_port // "")] | @tsv' | head -1)"
  IFS=$'\t' read -r device_api card_index active_port <<< "${sink_fields}"
  [[ "${device_api}" == "alsa" && "${card_index}" =~ ^[0-9]+$ ]] || { printf '{"minimum":-60,"maximum":0,"step":1,"backend":"software"}\n'; return; }
  case "${active_port,,}" in *headphone*|*headset*) mixer_control="Headphone" ;; *speaker*) mixer_control="Speaker" ;; *lineout*|*line-out*) mixer_control="Line Out" ;; esac
  for codec_file in /proc/asound/card"${card_index}"/codec#*; do
    [[ -r "${codec_file}" ]] || continue
    capabilities="$(awk -v wanted="${mixer_control} Playback Volume" '/Control: name=/ { volume=/Playback Volume/; exact=index($0, "name=\"" wanted "\"") } volume && /Amp-Out caps:/ { if (exact) { print; found=1; exit } if (!fallback) fallback=$0; volume=0 } END { if (!found && fallback) print fallback }' "${codec_file}")"
    [[ -n "${capabilities}" ]] && break
  done
  if [[ "${capabilities}" =~ ofs=0x([[:xdigit:]]+),[[:space:]]+nsteps=0x([[:xdigit:]]+),[[:space:]]+stepsize=0x([[:xdigit:]]+) ]]; then
    local offset=$((16#${BASH_REMATCH[1]})) steps=$((16#${BASH_REMATCH[2]})) step_size=$((16#${BASH_REMATCH[3]}))
    awk -v offset="${offset}" -v steps="${steps}" -v step_size="${step_size}" 'BEGIN { step_db=(step_size+1)/4; printf "{\"minimum\":%.2f,\"maximum\":%.2f,\"step\":%.2f,\"backend\":\"alsa\"}\n", -offset*step_db, (steps-offset)*step_db, step_db }'
    return
  fi
  codec_file="/proc/asound/card${card_index}/usbmixer"
  [[ -r "${codec_file}" ]] && capabilities="$(awk -v wanted="${mixer_control} Playback Volume" '/Control: name=/ { volume=/Playback Volume/; exact=index($0, "name=\"" wanted "\"") } volume && /Volume:.*dBmin=/ { if (exact) { print; found=1; exit } if (!fallback) fallback=$0; volume=0 } END { if (!found && fallback) print fallback }' "${codec_file}")"
  if [[ "${capabilities}" =~ dBmin=(-?[0-9]+),[[:space:]]*dBmax=(-?[0-9]+) ]]; then
    awk -v minimum="${BASH_REMATCH[1]}" -v maximum="${BASH_REMATCH[2]}" 'BEGIN { printf "{\"minimum\":%.2f,\"maximum\":%.2f,\"step\":1,\"backend\":\"alsa\"}\n", minimum/100, maximum/100 }'
  else
    printf '{"minimum":-60,"maximum":0,"step":1,"backend":"software"}\n'
  fi
}

[[ "${1:-}" == "--limits" ]] && { print_volume_limits; exit; }

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/controls/lib/control.common.bash"

readonly VOLUME_NOTIFY_REPLACE_ID=8
readonly VOLUME_NOTIFY_TIMEOUT_MS=800
readonly VOLUME_DEFAULT_BOOST_LIMIT=150
readonly VOLUME_DEFAULT_STEP=5
readonly VOLUME_BAR_DIVISOR=15
readonly VOLUME_ANGLE_QUANTIZATION_DEG=5

usage() {
  cat <<EOF
Usage: $(basename "$0") -[device] <action> [step]

Devices:
  -i    Input device (default source)
  -o    Output device (default sink)
  -p    Player application
  -t    Toggle to next output device
  -q    Quiet mode (no notifications)

Actions:
  i     Increase volume
  d     Decrease volume
  m     Toggle mute
EOF
}

require_commands() {
  local cmd_name=""
  for cmd_name in "$@"; do
    require_cmd "${cmd_name}" || {
      print_log -sec "volume" -err "missing" "${cmd_name} is required"
      return 1
    }
  done
}

get_default_sink_label() {
  wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node.description = / { print $2; exit }'
}

get_default_sink_id() {
  wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | awk '/^id / { gsub(/,/, "", $2); print $2; exit }'
}

list_sinks_tsv() {
  pw-dump |
    jq -r '.[] | select(.type=="PipeWire:Interface:Node" and .info?.props?."media.class"=="Audio/Sink") | [.info.props."object.id", (.info.props."node.description" // .info.props."node.name" // "Unknown")] | @tsv'
}

audio_sink_id_at_offset() {
  local current_id="$1"
  local offset="$2"
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
    next_index=$(( (current_index + offset) % ${#sinks[@]} ))
  fi
  printf '%s\n' "${sinks[$next_index]}"
}

playerctl_cmd() {
  local player_name="$1"
  shift
  if [[ -n "${player_name}" ]]; then
    playerctl --player="${player_name}" "$@"
  else
    playerctl "$@"
  fi
}

sink_volume_pct() {
  local target="$1"
  wpctl get-volume "${target}" 2>/dev/null | awk '{ printf "%.0f\n", $2 * 100 }'
}

sink_is_muted() {
  local target="$1"
  wpctl get-volume "${target}" 2>/dev/null | grep -q "MUTED"
}

icons_media_dir() {
  printf '%s/Hypr-Icon/media\n' "${ICONS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}"
}

notify_volume() {
  local notify_enabled="$1"
  local volume_pct="$2"
  local label="$3"
  local angle=""
  local icon=""
  local bar=""

  is_true "${notify_enabled}" || return 0
  angle=$(((volume_pct + VOLUME_ANGLE_QUANTIZATION_DEG / 2) / VOLUME_ANGLE_QUANTIZATION_DEG * VOLUME_ANGLE_QUANTIZATION_DEG))
  ((angle > 100)) && angle=100
  icon="$(icons_media_dir)/knob-${angle}.svg"
  printf -v bar '%*s' "$((volume_pct / VOLUME_BAR_DIVISOR))" ''
  bar="${bar// /.}"
  dunstify -a "Volume control" -r "${VOLUME_NOTIFY_REPLACE_ID}" -t "${VOLUME_NOTIFY_TIMEOUT_MS}" \
    -e -i "${icon}" "${volume_pct}${bar}" "${label}"
}

notify_mute() {
  local notify_enabled="$1"
  local muted="$2"
  local device_kind="$3"
  local label="$4"
  local icon_suffix="speaker"
  local prefix="unmuted"

  is_true "${notify_enabled}" || return 0
  [[ "${device_kind}" == "source" ]] && icon_suffix="microphone"
  [[ "${muted}" == "true" ]] && prefix="muted"

  dunstify -a "Volume control" -r "${VOLUME_NOTIFY_REPLACE_ID}" -t "${VOLUME_NOTIFY_TIMEOUT_MS}" \
    -e -i "$(icons_media_dir)/${prefix}-${icon_suffix}.svg" "${prefix}" "${label}"
}

apply_sink_delta() {
  local target="$1"
  local delta="$2"
  local step="$3"
  local boost_enabled="$4"
  local limit=""

  read -r limit < "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/volume-limit" || limit=""
  [[ "${limit}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || limit=""
  [[ -n "${limit}" ]] || { is_true "${boost_enabled}" && limit="$(awk -v value="${VOLUME_BOOST_LIMIT:-${VOLUME_DEFAULT_BOOST_LIMIT}}" 'BEGIN { print value / 100 }')" || limit=1; }
  wpctl set-volume -l "${limit}" "${target}" "${step}%${delta}"
}

apply_source_delta() {
  local target="$1"
  local delta="$2"
  local step="$3"
  [[ -n "${target}" ]] || return 0
  pactl set-source-volume "${target}" "${delta}${step}%"
}

apply_player_delta() {
  local player_name="$1"
  local delta="$2"
  local step="$3"
  local amount="" value=$((10#${step}))
  printf -v amount '%d.%02d' "$((value / 100))" "$((value % 100))"
  playerctl_cmd "${player_name}" volume "${amount}${delta}"
}

toggle_sink_mute() {
  local target="$1"
  wpctl set-mute "${target}" toggle
  sink_is_muted "${target}" && printf 'true\n' || printf 'false\n'
}

toggle_source_mute() {
  local target="$1"
  [[ -n "${target}" ]] || return 0
  pactl set-source-mute "${target}" toggle
  source_is_muted "${target}" && printf 'true\n' || printf 'false\n'
}

toggle_player_mute() {
  local player_name="$1"
  local safe_name="${player_name//\//_}"
  local volume_file=""
  local current_volume=""

  volume_file="${TMPDIR:-/tmp}/${0##*/}_last_volume_${safe_name:-all}"
  current_volume="$(playerctl_cmd "${player_name}" volume | awk '{ printf "%.2f", $0 }')"

  if [[ "${current_volume}" != "0.00" ]]; then
    printf '%s\n' "${current_volume}" >"${volume_file}"
    playerctl_cmd "${player_name}" volume 0
    printf 'true\n'
    return 0
  fi

  if [[ -f "${volume_file}" ]]; then
    playerctl_cmd "${player_name}" volume "$(<"${volume_file}")"
  else
    playerctl_cmd "${player_name}" volume 0.5
  fi
  printf 'false\n'
}

move_application_streams() {
  local old_sink="$1" new_sink="$2" old_index="" metadata="" streams=""
  local input="" object_id="" target=""
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

  while IFS=$'\t' read -r object_id target; do
    [[ ${object_id} =~ ^[0-9]+$ && ${target} != -1 ]] && explicit_targets["${object_id}"]=1
  done < <(sed -n "s/^update: id:\([0-9][0-9]*\) key:'target\.\(object\|node\)' value:'\([^']*\)'.*/\1\t\3/p" <<<"${metadata}")

  while IFS=$'\t' read -r input object_id; do
    [[ ${input} =~ ^[0-9]+$ ]] || continue
    [[ -n ${object_id} && -n ${explicit_targets[${object_id}]:-} ]] && continue
    pactl move-sink-input "${input}" "${new_sink}" >/dev/null 2>&1 || true
  done <<<"${streams}"
}

set_default_output() {
  local sink_id="$1"
  local sink_name="$2"
  local old_sink=""

  old_sink=$(pactl get-default-sink 2>/dev/null || true)

  if wpctl set-default "${sink_id}" && pactl set-default-sink "${sink_name}"; then
    move_application_streams "${old_sink}" "${sink_name}"
    dunstify -t "${VOLUME_NOTIFY_TIMEOUT_MS}" -i "$(icons_media_dir)/unmuted-speaker.svg" \
      -r "${VOLUME_NOTIFY_REPLACE_ID}" -u low "Activated: ${sink_name}"
  else
    dunstify -t "${VOLUME_NOTIFY_TIMEOUT_MS}" -r "${VOLUME_NOTIFY_REPLACE_ID}" -u critical \
      -i "dialog-error" "Error activating ${sink_name}"
    return 1
  fi
}

toggle_output_to_next_sink() {
  local current_id=""
  local next_line=""
  local next_id=""
  local next_desc=""

  require_commands pw-dump jq wpctl pactl dunstify || return 1
  current_id="$(get_default_sink_id)"
  next_line="$(audio_sink_id_at_offset "${current_id}" 1)" || return 1
  next_id="${next_line%%$'\t'*}"
  next_desc="${next_line#*$'\t'}"

  set_default_output "${next_id}" "${next_desc}"
}

run_action() {
  local device_kind="$1"
  local target="$2"
  local player_name="$3"
  local action="$4"
  local step="$5"
  local boost_enabled="$6"
  local notify_enabled="$7"
  local label="$8"
  local delta="-"
  local volume_pct=""
  local muted=""

  [[ "${action}" == "i" ]] && delta="+"

  case "${action}" in
    i | d)
      case "${device_kind}" in
        sink)
          apply_sink_delta "${target}" "${delta}" "${step}" "${boost_enabled}"
          volume_pct="$(sink_volume_pct "${target}")"
          ;;
        source)
          [[ -n "${target}" ]] || return 0
          apply_source_delta "${target}" "${delta}" "${step}"
          volume_pct="$(source_volume_pct "${target}")"
          ;;
        player)
          apply_player_delta "${player_name}" "${delta}" "${step}"
          volume_pct="$(playerctl_cmd "${player_name}" volume | awk '{ printf "%.0f\n", $0 * 100 }')"
          ;;
      esac
      notify_volume "${notify_enabled}" "${volume_pct}" "${label}"
      ;;
    m)
      case "${device_kind}" in
        sink)
          muted="$(toggle_sink_mute "${target}")"
          ;;
        source)
          [[ -n "${target}" ]] || return 0
          muted="$(toggle_source_mute "${target}")"
          ;;
        player)
          muted="$(toggle_player_mute "${player_name}")"
          ;;
      esac
      notify_mute "${notify_enabled}" "${muted}" "${device_kind}" "${label}"
      ;;
  esac
}

require_device_commands() {
  local device_kind="$1"
  local notify_enabled="$2"

  case "${device_kind}" in
    sink) require_commands wpctl || return 1 ;;
    source) require_commands pactl || return 1 ;;
    player) require_commands playerctl || return 1 ;;
  esac
  is_true "${notify_enabled}" || return 0
  require_commands dunstify
}

set_default_command() {
  [[ -n "${1:-}" && -n "${2:-}" ]] || {
    printf 'Usage: %s --set-default ID NAME\n' "${0##*/}" >&2
    return 2
  }
  require_commands wpctl pactl dunstify || return 1
  set_default_output "$1" "$2"
}

parse_args() {
  local -n options_ref="$1"
  shift
  local opt=""
  local OPTIND=1

  while getopts "iop:tq" opt; do
    case "${opt}" in
      i)
        options_ref[device_kind]="source"
        options_ref[target]="$(get_default_source_target || true)"
        options_ref[label]="${options_ref[target]:-No microphone}"
        ;;
      o)
        options_ref[device_kind]="sink"
        options_ref[target]="@DEFAULT_AUDIO_SINK@"
        options_ref[label]="$(get_default_sink_label)"
        ;;
      p)
        options_ref[device_kind]="player"
        options_ref[player_name]="${OPTARG}"
        options_ref[label]="${OPTARG:-all players}"
        ;;
      t) options_ref[toggle_output]=true; return 0 ;;
      q) options_ref[notify]=false ;;
      *) return 2 ;;
    esac
  done

  shift $((OPTIND - 1))
  options_ref[action]="${1:-}"
  options_ref[step]="${2:-${options_ref[step]}}"
}

validate_action() {
  local action="$1"
  local step="$2"

  case "${action}" in
    i | d)
      [[ "${step}" =~ ^[0-9]+$ ]] && return 0
      print_log -sec "volume" -err "step" "Invalid step: ${step}"
      return 2
      ;;
    m) ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main() {
  [[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; return; }
  [[ "${1:-}" == --set-default ]] && { set_default_command "${@:2}"; return; }

  local -A options=(
    [notify]="${VOLUME_NOTIFY:-true}"
    [boost]="${VOLUME_BOOST:-false}"
    [step]="${VOLUME_STEPS:-${VOLUME_DEFAULT_STEP}}"
    [device_kind]="" [target]="" [player_name]="" [label]="" [action]="" [toggle_output]=false
  )

  parse_args options "$@" || {
    usage >&2
    return 2
  }
  [[ "${options[toggle_output]}" == true ]] && { toggle_output_to_next_sink; return; }
  [[ -n "${options[device_kind]}" ]] || {
    usage >&2
    return 2
  }
  require_device_commands "${options[device_kind]}" "${options[notify]}" || return 1
  validate_action "${options[action]}" "${options[step]}" || return 2

  run_action "${options[device_kind]}" "${options[target]}" "${options[player_name]}" "${options[action]}" \
    "${options[step]}" "${options[boost]}" "${options[notify]}" "${options[label]}"
}

main "$@"

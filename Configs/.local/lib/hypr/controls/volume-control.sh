#!/usr/bin/env bash
#
# volume-control.sh — Adjust sink/source/player volume, toggle mute, switch sinks.
#
# Usage:
#   volume-control.sh -o {i|d|m} [step]   # Default sink: increase / decrease / toggle mute
#   volume-control.sh -i {i|d|m} [step]   # Default source (microphone)
#   volume-control.sh -p PLAYER {i|d|m} [step]
#   volume-control.sh -s                  # Select output sink via rofi
#   volume-control.sh -t                  # Toggle to next output sink
#   volume-control.sh -q ...              # Quiet (no notification)
#
# Depends on: wpctl, pactl, pw-dump, jq, dunstify, playerctl (for -p), rofi (for -s)
#
set -u

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/controls/lib/control.common.bash"

readonly VOLUME_NOTIFY_REPLACE_ID=8
readonly VOLUME_NOTIFY_TIMEOUT_MS=800
readonly VOLUME_DEFAULT_BOOST_LIMIT=150
readonly VOLUME_DEFAULT_STEP=5
readonly VOLUME_BAR_DIVISOR=15
readonly VOLUME_ANGLE_QUANTIZATION_DEG=5
readonly WAYBAR_MIC_REFRESH_SIGNAL="RTMIN+18"

usage() {
  cat <<EOF
Usage: $(basename "$0") -[device] <action> [step]

Devices:
  -i    Input device (default source)
  -o    Output device (default sink)
  -p    Player application
  -s    Select output device
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
  wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | grep -oP 'node.description = "\K[^"]+' \
    | head -1
}

get_default_source_target() {
  local default_source=""

  default_source="$(pactl info 2>/dev/null | sed -n 's/^Default Source: //p' | head -1)"
  if [[ -n "${default_source}" && "${default_source}" != *.monitor ]]; then
    printf '%s\n' "${default_source}"
    return 0
  fi
  pactl list short sources 2>/dev/null | awk '$2 !~ /\.monitor$/ {print $2; exit}'
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

source_volume_pct() {
  local target="$1"
  pactl get-source-volume "${target}" 2>/dev/null | grep -o '[0-9]\+%' | head -1 | tr -d '%'
}

source_is_muted() {
  local target="$1"
  [[ "$(pactl get-source-mute "${target}" 2>/dev/null | awk '{print $2}')" == "yes" ]]
}

refresh_waybar_mic() {
  hypr_user_pkill "-${WAYBAR_MIC_REFRESH_SIGNAL}" -x waybar >/dev/null 2>&1 || true
}

clamp_angle() {
  local angle="$1"
  ((angle < 0)) && angle=0
  ((angle > 100)) && angle=100
  printf '%s\n' "${angle}"
}

quantize_angle() {
  local volume_pct="$1"
  local q="${VOLUME_ANGLE_QUANTIZATION_DEG}"
  local angle=$(((volume_pct + (q / 2)) / q * q))
  clamp_angle "${angle}"
}

icons_media_dir() {
  printf '%s/Pywal16-Icon/media\n' "${ICONS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}"
}

notify_volume() {
  local notify_enabled="$1"
  local volume_pct="$2"
  local label="$3"
  local angle=""
  local icon=""
  local bar=""

  is_true "${notify_enabled}" || return 0
  angle="$(quantize_angle "${volume_pct}")"
  icon="$(icons_media_dir)/knob-${angle}.svg"
  bar="$(printf '%*s' $((volume_pct / VOLUME_BAR_DIVISOR)) '' | tr ' ' '.')"
  dunstify -a "Volume control" -r "${VOLUME_NOTIFY_REPLACE_ID}" -t "${VOLUME_NOTIFY_TIMEOUT_MS}" \
    -i "${icon}" "${volume_pct}${bar}" "${label}"
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
    -i "$(icons_media_dir)/${prefix}-${icon_suffix}.svg" "${prefix}" "${label}"
}

apply_sink_delta() {
  local target="$1"
  local delta="$2"
  local step="$3"
  local boost_enabled="$4"
  local boost_limit_decimal=""

  if is_true "${boost_enabled}"; then
    boost_limit_decimal="$(awk -v limit="${VOLUME_BOOST_LIMIT:-${VOLUME_DEFAULT_BOOST_LIMIT}}" 'BEGIN { print limit / 100 }')"
    wpctl set-volume -l "${boost_limit_decimal}" "${target}" "${step}%${delta}"
  else
    wpctl set-volume -l 1.0 "${target}" "${step}%${delta}"
  fi
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
  playerctl_cmd "${player_name}" volume "$(awk -v s="${step}" 'BEGIN { print s / 100 }')${delta}"
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
  local volume_file=""
  local current_volume=""

  volume_file="${TMPDIR:-/tmp}/$(basename "$0")_last_volume_${player_name:-all}"
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

set_output_by_description() {
  local selection="$1"
  local sink_id=""

  sink_id="$(list_sinks_tsv | awk -F'\t' -v sel="${selection}" '$2==sel { print $1; exit }')"
  if [[ -z "${sink_id}" ]]; then
    dunstify -u critical -a "Volume control" -i "dialog-error" "Audio Output" "Unable to resolve: ${selection}"
    return 1
  fi

  if wpctl set-default "${sink_id}"; then
    dunstify -t "${VOLUME_NOTIFY_TIMEOUT_MS}" -i "$(icons_media_dir)/unmuted-speaker.svg" \
      -r "${VOLUME_NOTIFY_REPLACE_ID}" -u low "Activated: ${selection}"
  else
    dunstify -t "${VOLUME_NOTIFY_TIMEOUT_MS}" -r "${VOLUME_NOTIFY_REPLACE_ID}" -u critical \
      -i "dialog-error" "Error activating ${selection}"
    return 1
  fi
}

select_output_via_rofi() {
  local choice=""

  require_cmd rofi || {
    print_log -sec "volume" -err "missing" "rofi is required for output selection"
    return 1
  }

  choice="$(list_sinks_tsv | cut -f2 | awk 'NF' | sort -u | rofi -dmenu -theme "notification" -p "Audio Output")" || return 0
  [[ -n "${choice}" ]] || return 0
  set_output_by_description "${choice}"
}

toggle_output_to_next_sink() {
  local current_id=""
  local next_line=""
  local next_id=""
  local next_desc=""

  current_id="$(get_default_sink_id)"
  next_line="$(audio_sink_id_at_offset "${current_id}" 1)" || return 1
  next_id="${next_line%%$'\t'*}"
  next_desc="${next_line#*$'\t'}"

  if wpctl set-default "${next_id}"; then
    dunstify -t "${VOLUME_NOTIFY_TIMEOUT_MS}" -i "$(icons_media_dir)/unmuted-speaker.svg" \
      -r "${VOLUME_NOTIFY_REPLACE_ID}" -u low "Activated: ${next_desc}"
  else
    dunstify -t "${VOLUME_NOTIFY_TIMEOUT_MS}" -r "${VOLUME_NOTIFY_REPLACE_ID}" -u critical \
      -i "dialog-error" "Error activating ${next_desc}"
    return 1
  fi
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
          refresh_waybar_mic
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
          refresh_waybar_mic
          ;;
        player)
          muted="$(toggle_player_mute "${player_name}")"
          ;;
      esac
      notify_mute "${notify_enabled}" "${muted}" "${device_kind}" "${label}"
      ;;
  esac
}

main() {
  require_commands wpctl pw-dump jq dunstify pactl || return 1

  local notify_enabled="${VOLUME_NOTIFY:-true}"
  local boost_enabled="${VOLUME_BOOST:-false}"
  local default_step="${VOLUME_STEPS:-${VOLUME_DEFAULT_STEP}}"
  local device_kind=""
  local target=""
  local player_name=""
  local label=""
  local action=""
  local step=""
  local opt=""

  while getopts "iop:stq" opt; do
    case "${opt}" in
      i)
        device_kind="source"
        target="$(get_default_source_target || true)"
        label="${target:-No microphone}"
        ;;
      o)
        device_kind="sink"
        target="@DEFAULT_AUDIO_SINK@"
        label="$(get_default_sink_label)"
        ;;
      p)
        device_kind="player"
        player_name="${OPTARG}"
        label="${player_name:-all players}"
        require_cmd playerctl || {
          print_log -sec "volume" -err "missing" "playerctl is required for -p"
          return 1
        }
        ;;
      s)
        select_output_via_rofi
        return $?
        ;;
      t)
        toggle_output_to_next_sink
        return $?
        ;;
      q)
        notify_enabled=false
        ;;
      *)
        usage >&2
        return 2
        ;;
    esac
  done

  shift $((OPTIND - 1))
  [[ -n "${device_kind}" ]] || {
    usage >&2
    return 2
  }

  action="${1:-}"
  step="${2:-${default_step}}"

  case "${action}" in
    i | d)
      [[ "${step}" =~ ^[0-9]+$ ]] || {
        print_log -sec "volume" -err "step" "Invalid step: ${step}"
        return 2
      }
      run_action "${device_kind}" "${target}" "${player_name}" "${action}" "${step}" \
        "${boost_enabled}" "${notify_enabled}" "${label}"
      ;;
    m)
      run_action "${device_kind}" "${target}" "${player_name}" "${action}" "${step}" \
        "${boost_enabled}" "${notify_enabled}" "${label}"
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"

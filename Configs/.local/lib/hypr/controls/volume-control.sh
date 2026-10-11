#!/usr/bin/env bash
set -u

source "${BASH_SOURCE[0]%/*}/lib/volume-limits.bash"

[[ "${1:-}" == "--limits" ]] && { print_volume_limits; exit; }

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/controls/lib/control-feedback.bash"
source "${HYPR_LIB_DIR}/controls/lib/audio-streams.bash"

source "${HYPR_LIB_DIR}/controls/lib/audio-outputs.bash"

readonly VOLUME_DEFAULT_BOOST_LIMIT=150
readonly VOLUME_DEFAULT_STEP=5
readonly PLAYER_UNMUTE_FALLBACK_VOLUME=0.5

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

notify_volume() {
  local notify_enabled="$1"
  local volume_pct="$2"
  local label="$3"

  is_true "${notify_enabled}" || return 0
  notify_level "Volume control" "${NOTIFY_ID_VOLUME}" "${volume_pct}" "${label}"
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

  dunstify -a "Volume control" -r "${NOTIFY_ID_VOLUME}" -t "${NOTIFY_OSD_MS}" \
    -e -i "$(media_icons_dir)/${prefix}-${icon_suffix}.svg" "${prefix}" "${label}"
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
    playerctl_cmd "${player_name}" volume "${PLAYER_UNMUTE_FALLBACK_VOLUME}"
  fi
  printf 'false\n'
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
        options_ref[label]="$(get_sink_label @DEFAULT_AUDIO_SINK@)"
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

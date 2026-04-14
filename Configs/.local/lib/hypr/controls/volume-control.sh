#!/usr/bin/env bash

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
lib_root="$(realpath "${script_dir}/../..")"
xdg_lib="${lib_root}/hypr/core/xdg.sh"

[[ -r "${xdg_lib}" ]] || {
  printf 'missing xdg bootstrap: %s\n' "${xdg_lib}" >&2
  exit 1
}

# shellcheck source=/dev/null
source "${xdg_lib}" || exit 1
hypr_init_xdg_env
export LIB_DIR="${lib_root}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/controls/lib/control.common.bash"

is_notify="${VOLUME_NOTIFY:-true}"
is_volume_boost="${VOLUME_BOOST:-false}"
step_default="${VOLUME_STEPS:-5}"
ICONS_DIR="${ICONS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}"
icodir="${ICONS_DIR}/Pywal16-Icon/media"

device=""
srce=""
target=""
nsink=""

print_usage() {
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
  exit 1
}

require_commands() {
  local cmd_name=""

  for cmd_name in "$@"; do
    require_cmd "${cmd_name}" || {
      echo "${cmd_name} is required"
      exit 1
    }
  done
}

require_commands wpctl pw-dump jq dunstify pactl

get_default_sink() {
  wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null |
    grep -oP 'node.description = "\K[^"]+' |
    head -1
}

get_default_source() {
  get_default_source_target
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
  wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null |
    awk '/^id / { gsub(/,/, "", $2); print $2; exit }'
}

list_sinks_tsv() {
  pw-dump |
    jq -r '.[] | select(.type=="PipeWire:Interface:Node" and .info?.props?."media.class"=="Audio/Sink") | [.info.props."object.id", (.info.props."node.description" // .info.props."node.name" // "Unknown")] | @tsv'
}

playerctl_cmd() {
  if [[ -n "${srce}" ]]; then
    playerctl --player="${srce}" "$@"
  else
    playerctl "$@"
  fi
}

target_volume_pct() {
  local tgt="$1"
  wpctl get-volume "${tgt}" 2>/dev/null | awk '{ printf "%.0f\n", $2 * 100 }'
}

target_is_muted() {
  local tgt="$1"
  wpctl get-volume "${tgt}" 2>/dev/null | grep -q "MUTED"
}

source_volume_pct() {
  local tgt="$1"
  pactl get-source-volume "${tgt}" 2>/dev/null | grep -o '[0-9]\+%' | head -1 | tr -d '%'
}

source_is_muted() {
  local tgt="$1"
  [[ "$(pactl get-source-mute "${tgt}" 2>/dev/null | awk '{print $2}')" == "yes" ]]
}

refresh_waybar_mic() {
  pkill -RTMIN+18 waybar >/dev/null 2>&1 || true
}

notify_vol() {
  local vol="$1"
  is_true "${is_notify}" || return 0

  local angle icon bar
  angle=$((((vol + 2) / 5) * 5))
  ((angle > 100)) && angle=100
  ((angle < 0)) && angle=0
  icon="${icodir}/knob-${angle}.svg"
  bar="$(printf '%*s' $((vol / 15)) '' | tr ' ' '.')"
  dunstify -a "Volume control" -r 8 -t 800 -i "${icon}" "${vol}${bar}" "${nsink}"
}

notify_mute() {
  local muted="$1"
  local icon_suffix="speaker"

  is_true "${is_notify}" || return 0
  [[ "${device}" == "source" ]] && icon_suffix="microphone"

  local prefix=$([[ "${muted}" == "true" ]] && echo "muted" || echo "unmuted")
  dunstify -a "Volume control" -r 8 -t 800 -i "${icodir}/${prefix}-${icon_suffix}.svg" "${prefix}" "${nsink}"
}

set_output_by_description() {
  local selection="$1"
  local sink_id

  sink_id="$(list_sinks_tsv | awk -F'\t' -v sel="${selection}" '$2==sel { print $1; exit }')"
  if [[ -z "${sink_id}" ]]; then
    dunstify -u critical -a "Volume control" -i "dialog-error" "Audio Output" "Unable to resolve: ${selection}"
    return 1
  fi

  if wpctl set-default "${sink_id}"; then
    dunstify -t 800 -i "${icodir}/unmuted-speaker.svg" -r 8 -u low "Activated: ${selection}"
  else
    dunstify -t 800 -r 8 -u critical -i "dialog-error" "Error activating ${selection}"
    return 1
  fi
}

select_output() {
  local selection="${1:-}"
  if [[ -n "${selection}" ]]; then
    set_output_by_description "${selection}"
    return
  fi
  list_sinks_tsv | cut -f2 | awk 'NF' | sort -u
}

toggle_output() {
  local current_id current_index=-1 next_index next_line next_id next_desc
  local -a sinks

  mapfile -t sinks < <(list_sinks_tsv)
  (( ${#sinks[@]} == 0 )) && return 1

  current_id="$(get_default_sink_id)"
  for i in "${!sinks[@]}"; do
    sink_id="${sinks[$i]%%$'\t'*}"
    if [[ "${sink_id}" == "${current_id}" ]]; then
      current_index="${i}"
      break
    fi
  done

  if (( current_index < 0 )); then
    next_index=0
  else
    next_index=$(((current_index + 1) % ${#sinks[@]}))
  fi

  next_line="${sinks[$next_index]}"
  next_id="${next_line%%$'\t'*}"
  next_desc="${next_line#*$'\t'}"
  if wpctl set-default "${next_id}"; then
    dunstify -t 800 -i "${icodir}/unmuted-speaker.svg" -r 8 -u low "Activated: ${next_desc}"
  else
    dunstify -t 800 -r 8 -u critical -i "dialog-error" "Error activating ${next_desc}"
    return 1
  fi
}

change_volume() {
  local action="$1"
  local step="$2"
  local delta="-"

  [[ "${action}" == "i" ]] && delta="+"

  case "${device}" in
    sink)
      if is_true "${is_volume_boost}"; then
        boost_limit_decimal="$(awk -v limit="${VOLUME_BOOST_LIMIT:-150}" 'BEGIN { print limit / 100 }')"
        wpctl set-volume -l "${boost_limit_decimal}" "${target}" "${step}%${delta}"
      else
        wpctl set-volume -l 1.0 "${target}" "${step}%${delta}"
      fi
      vol="$(target_volume_pct "${target}")"
      notify_vol "${vol}"
      ;;
    source)
      [[ -n "${target}" ]] || return 0
      pactl set-source-volume "${target}" "${delta}${step}%"
      vol="$(source_volume_pct "${target}")"
      notify_vol "${vol}"
      refresh_waybar_mic
      ;;
    player)
      playerctl_cmd volume "$(awk -v s="${step}" 'BEGIN { print s / 100 }')${delta}"
      vol="$(playerctl_cmd volume | awk '{ printf "%.0f\n", $0 * 100 }')"
      notify_vol "${vol}"
      ;;
  esac
}

toggle_mute() {
  local muted="false"
  case "${device}" in
    sink)
      wpctl set-mute "${target}" toggle
      if target_is_muted "${target}"; then
        muted="true"
      fi
      notify_mute "${muted}"
      ;;
    source)
      [[ -n "${target}" ]] || return 0
      pactl set-source-mute "${target}" toggle
      if source_is_muted "${target}"; then
        muted="true"
      fi
      notify_mute "${muted}"
      refresh_waybar_mic
      ;;
    player)
      local volume_file current_volume
      volume_file="${TMPDIR:-/tmp}/$(basename "$0")_last_volume_${srce:-all}"
      current_volume="$(playerctl_cmd volume | awk '{ printf "%.2f", $0 }')"
      if [[ "${current_volume}" != "0.00" ]]; then
        printf '%s\n' "${current_volume}" > "${volume_file}"
        playerctl_cmd volume 0
        muted="true"
      else
        if [[ -f "${volume_file}" ]]; then
          playerctl_cmd volume "$(cat "${volume_file}")"
        else
          playerctl_cmd volume 0.5
        fi
      fi
      notify_mute "${muted}"
      ;;
  esac
}

while getopts "iop:stq" opt; do
  case "${opt}" in
    i)
      device="source"
      target="$(get_default_source_target || true)"
      nsink="${target:-No microphone}"
      ;;
    o)
      device="sink"
      target="@DEFAULT_AUDIO_SINK@"
      nsink="$(get_default_sink)"
      ;;
    p)
      device="player"
      srce="${OPTARG}"
      nsink="${srce:-all players}"
      require_cmd playerctl || { echo "playerctl is required for -p"; exit 1; }
      ;;
    s)
      require_cmd rofi || {
        echo "rofi is required for output selection"
        exit 1
      }
      selected_output="$(select_output | rofi -dmenu -theme "notification" -p "Audio Output")" || exit 0
      [[ -z "${selected_output}" ]] && exit 0
      select_output "${selected_output}"
      exit
      ;;
    t)
      toggle_output
      exit
      ;;
    q)
      is_notify=false
      ;;
    *)
      print_usage
      ;;
  esac
done

shift $((OPTIND - 1))

[[ -z "${device}" ]] && print_usage

action="${1:-}"
step="${2:-${step_default}}"

if [[ "${action}" == "i" || "${action}" == "d" ]]; then
  if [[ ! "${step}" =~ ^[0-9]+$ ]]; then
    echo "Invalid step: ${step}"
    exit 1
  fi
  change_volume "${action}" "${step}"
elif [[ "${action}" == "m" ]]; then
  toggle_mute
else
  print_usage
fi

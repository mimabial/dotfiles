#!/usr/bin/env bash

# shellcheck source=/dev/null
if ! source "$(command -v hyprshell)"; then
  echo "[$0] :: Error: hyprshell not found."
  exit 1
fi

DEFAULT_TEMP=6500
DEFAULT_GAMMA=100
DEFAULT_TEMP_STEP=500
DEFAULT_GAMMA_STEP=5
MIN_TEMP=3000
MAX_TEMP=10000
MIN_GAMMA=20
MAX_GAMMA=100

notify="${waybar_temperature_notification:-true}"
action=""
color_mode="temp"
custom_step=""
newTemp=""
newGamma=""
signal_proc=""
temp_step="${DEFAULT_TEMP_STEP}"
gamma_step="${DEFAULT_GAMMA_STEP}"

currentTemp=""
currentGamma=""
toggle_mode=""

declare -A temp_colors=(
  [10000]="#8b0000"
  [8000]="#ff6347"
  [6500]=""
  [5000]="#ffa500"
  [4000]="#ff8c00"
  [3000]="#ff471a"
  [2000]="#d22f2f"
  [1000]="#ad1f2f"
)

declare -A gamma_colors=(
  [90]="#00ff00"
  [70]="#90ee90"
  [50]=""
  [30]="#ffa500"
  [20]="#ff6347"
)

load_state() {
  currentTemp="$(state_get "HYPRSUNSET_TEMP" "${DEFAULT_TEMP}")"
  currentGamma="$(state_get "HYPRSUNSET_GAMMA" "${DEFAULT_GAMMA}")"
  toggle_mode="$(state_get "HYPRSUNSET_ENABLED" "1")"
}

write_sunset_state() {
  state_set "HYPRSUNSET_TEMP" "${currentTemp}" "staterc"
  state_set "HYPRSUNSET_GAMMA" "${currentGamma}" "staterc"
  state_set "HYPRSUNSET_ENABLED" "${toggle_mode}" "staterc"
}

clamp_range() {
  local value="$1"
  local min_value="$2"
  local max_value="$3"

  [ "$value" -lt "$min_value" ] && value=$min_value
  [ "$value" -gt "$max_value" ] && value=$max_value
  echo "$value"
}

validate_int_range() {
  local value="$1"
  local min_value="$2"
  local max_value="$3"
  local error_message="$4"

  if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge "$min_value" ] && [ "$value" -le "$max_value" ]; then
    return 0
  fi

  echo "${error_message}"
  return 1
}

get_running_temp() {
  hyprctl hyprsunset temperature 2>/dev/null || echo "${DEFAULT_TEMP}"
}

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    --cm MODE                   Color mode: 'temp' for temperature, 'gamma' for gamma
    -i, --increase [STEP]       Increase the selected color mode value
    -d, --decrease [STEP]       Decrease the selected color mode value
    -s, --set VALUE             Set specific value for the selected color mode
    -r, --read                  Read current screen temperature and gamma
    -t, --toggle                Toggle hyprsunset (on/off)
    -q, --quiet                 Disable notifications
    -P, --sigproc PROC,SIGNAL   Send signal to process (e.g., --sigproc waybar,19)
    -h, --help                  Show this help message

Examples:
    $(basename "$0") -r                     # Read current values
    $(basename "$0") --cm temp -i           # Increase temperature by 500K
    $(basename "$0") --cm temp -d 1000      # Decrease temperature by 1000K
    $(basename "$0") --cm temp -s 4000      # Set temperature to 4000K
    $(basename "$0") --cm gamma -i          # Increase gamma by 5
    $(basename "$0") --cm gamma -d 10       # Decrease gamma by 10
    $(basename "$0") --cm gamma -s 80       # Set gamma to 80
    $(basename "$0") -t --quiet             # Toggle mode quietly
    $(basename "$0") --sigproc waybar,19    # Send SIGUSR1 to waybar
EOF
}

require_args() {
  if [ "$#" -eq 0 ]; then
    echo "No arguments provided"
    show_help
    exit 1
  fi
}

parse_args() {
  local longopts="cm:,increase:,decrease:,set:,read,toggle,quiet,sigproc:,help"
  local shortopts="i:d:s:rtqP:h"
  local parsed=""

  parsed=$(getopt --options "${shortopts}" --longoptions "${longopts}" --name "$0" -- "$@") || exit 2
  eval set -- "${parsed}"

  while true; do
    case "$1" in
      --cm)
        color_mode="$2"
        shift 2
        ;;
      -i|--increase)
        action="increase"
        custom_step="$2"
        shift 2
        ;;
      -d|--decrease)
        action="decrease"
        custom_step="$2"
        shift 2
        ;;
      -s|--set)
        action="set"
        custom_step="$2"
        shift 2
        ;;
      -r|--read)
        action="read"
        shift
        ;;
      -t|--toggle)
        action="toggle"
        shift
        ;;
      -q|--quiet)
        notify=false
        shift
        ;;
      -P|--sigproc)
        signal_proc="$2"
        shift 2
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      --)
        shift
        return 0
        ;;
      *)
        echo "Invalid option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

validate_color_mode() {
  case "${color_mode}" in
    temp|gamma) return 0 ;;
    *)
      echo "Error: Color mode must be 'temp' or 'gamma'"
      exit 1
      ;;
  esac
}

resolve_set_action() {
  if [ "${color_mode}" = "gamma" ]; then
    validate_int_range "${custom_step}" "${MIN_GAMMA}" "${MAX_GAMMA}" \
      "Error: Gamma value must be an integer between ${MIN_GAMMA} and ${MAX_GAMMA}" || exit 1
    newGamma="$(clamp_range "${custom_step}" "${MIN_GAMMA}" "${MAX_GAMMA}")"
    return 0
  fi

  validate_int_range "${custom_step}" "${MIN_TEMP}" "${MAX_TEMP}" \
    "Error: Temperature must be an integer between ${MIN_TEMP} and ${MAX_TEMP}" || exit 1
  newTemp="$(clamp_range "${custom_step}" "${MIN_TEMP}" "${MAX_TEMP}")"
}

resolve_step_action() {
  if [ -z "${custom_step}" ] || ! [[ "${custom_step}" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  if [ "${color_mode}" = "gamma" ]; then
    validate_int_range "${custom_step}" 1 50 "Error: Gamma step must be between 1 and 50" || exit 1
    gamma_step="${custom_step}"
    return 0
  fi

  validate_int_range "${custom_step}" 1 5000 "Error: Temperature step must be between 1 and 5000" || exit 1
  temp_step="${custom_step}"
}

prepare_action_values() {
  validate_color_mode
  [ -n "${action}" ] || {
    echo "Error: No action specified"
    show_help
    exit 1
  }

  case "${action}" in
    set) resolve_set_action ;;
    increase|decrease) resolve_step_action ;;
  esac
}

apply_action_to_state() {
  case "${action}" in
    increase)
      if [ "${color_mode}" = "gamma" ]; then
        newGamma="$(clamp_range "$((currentGamma + gamma_step))" "${MIN_GAMMA}" "${MAX_GAMMA}")"
        currentGamma="${newGamma}"
      else
        newTemp="$(clamp_range "$((currentTemp + temp_step))" "${MIN_TEMP}" "${MAX_TEMP}")"
        currentTemp="${newTemp}"
      fi
      write_sunset_state
      ;;
    decrease)
      if [ "${color_mode}" = "gamma" ]; then
        newGamma="$(clamp_range "$((currentGamma - gamma_step))" "${MIN_GAMMA}" "${MAX_GAMMA}")"
        currentGamma="${newGamma}"
      else
        newTemp="$(clamp_range "$((currentTemp - temp_step))" "${MIN_TEMP}" "${MAX_TEMP}")"
        currentTemp="${newTemp}"
      fi
      write_sunset_state
      ;;
    set)
      if [ "${color_mode}" = "gamma" ]; then
        currentGamma="${newGamma}"
      else
        currentTemp="${newTemp}"
      fi
      write_sunset_state
      ;;
    toggle)
      toggle_mode=$((1 - toggle_mode))
      write_sunset_state
      ;;
    read) ;;
  esac
}

notification_title() {
  case "${action}" in
    toggle)
      if [ "${toggle_mode}" -eq 1 ]; then
        printf '%s' 'Hyprsunset: ON'
      else
        printf '%s' 'Hyprsunset: OFF'
      fi
      ;;
    *)
      if [ -n "${newTemp}" ]; then
        printf '%s' 'Mode: Temperature'
      elif [ -n "${newGamma}" ]; then
        printf '%s' 'Mode: Gamma'
      fi
      ;;
  esac
}

notification_message() {
  case "${action}" in
    toggle)
      if [ "${toggle_mode}" -eq 0 ]; then
        printf '%s' ''
      fi
      ;;
    *)
      if [ -n "${newTemp}" ]; then
        printf '%sK' "${newTemp}"
      elif [ -n "${newGamma}" ]; then
        printf '%s' "${newGamma}"
      fi
      ;;
  esac
}

send_notification() {
  local title message

  title="$(notification_title)"
  message="$(notification_message)"
  [ -n "${title}" ] || return 0

  if [ -n "${message}" ]; then
    dunstify -a "hyprsunset" -r 19 -t 800 -i redshift "${message}" "${title}"
    return 0
  fi

  dunstify -a "hyprsunset" -r 19 -t 800 -i redshift "${title}"
}

parse_signal_target() {
  local raw="$1"

  case "${raw}" in
    *,*) IFS=',' read -r process signal <<<"${raw}" ;;
    *:*) IFS=':' read -r process signal <<<"${raw}" ;;
    *)
      echo "Error: Invalid sigproc format. Use PROCESS,SIGNAL or PROCESS:SIGNAL"
      return 1
      ;;
  esac

  if ! [[ "${signal}" =~ ^[0-9]+$ ]]; then
    echo "Error: Signal must be a number"
    return 1
  fi
}

send_signal_to_process() {
  local process="" signal=""

  [ -n "${signal_proc}" ] || return 0
  parse_signal_target "${signal_proc}" || return 1

  if pgrep -x "${process}" >/dev/null; then
    pkill -RTMIN+"${signal}" "${process}" 2>/dev/null || echo "Warning: Failed to send signal ${signal} to ${process}"
    return 0
  fi

  echo "Warning: Process '${process}' not found"
}

remove_stale_socket() {
  local socket_path="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.hyprsunset.sock"
  [ -f "${socket_path}" ] || return 0
  rm "${socket_path}"
}

ensure_hyprsunset_process() {
  if pgrep -x "hyprsunset" >/dev/null; then
    return 0
  fi

  remove_stale_socket
  hyprctl --quiet dispatch exec -- hyprsunset
}

runtime_sync_needed() {
  [ "${action}" != "read" ] || [ "${toggle_mode}" -eq 1 ]
}

sync_runtime_for_read() {
  local current_running_temp=""

  [ "${toggle_mode}" -eq 1 ] || return 0
  current_running_temp="$(hyprctl hyprsunset temperature)"
  if [ "${current_running_temp}" != "${currentTemp}" ]; then
    hyprctl --quiet hyprsunset temperature "${currentTemp}"
  fi
}

sync_runtime_for_write() {
  if [ "${toggle_mode}" -eq 0 ]; then
    hyprctl --quiet hyprsunset identity
    hyprctl --quiet hyprsunset gamma "${DEFAULT_GAMMA}"
    return 0
  fi

  if [ "${color_mode}" = "gamma" ] && [ -n "${newGamma}" ]; then
    hyprctl --quiet hyprsunset temperature "${currentTemp}"
    hyprctl --quiet hyprsunset gamma "${newGamma}"
    return 0
  fi

  if [ -n "${newTemp}" ]; then
    hyprctl --quiet hyprsunset temperature "${newTemp}"
    return 0
  fi

  hyprctl --quiet hyprsunset temperature "${currentTemp}"
  hyprctl --quiet hyprsunset gamma "${currentGamma}"
}

sync_runtime_state() {
  runtime_sync_needed || return 0
  ensure_hyprsunset_process

  if [ "${action}" = "read" ]; then
    sync_runtime_for_read
    return 0
  fi

  sync_runtime_for_write
}

render_threshold_color() {
  local value="$1"
  local suffix="$2"
  local -n colors_ref="$3"
  local threshold color

  for threshold in $(printf '%s\n' "${!colors_ref[@]}" | sort -nr); do
    if (( value >= threshold )); then
      color="${colors_ref[$threshold]}"
      if [[ -n "${color}" ]]; then
        printf "<span color='%s'><b>%s%s</b></span>" "${color}" "${value}" "${suffix}"
      else
        printf "<b>%s%s</b>" "${value}" "${suffix}"
      fi
      return 0
    fi
  done
}

get_temp_color() {
  render_threshold_color "$1" "K" temp_colors
}

get_gamma_color() {
  render_threshold_color "$1" "" gamma_colors
}

generate_status() {
  local text_output alt_text tooltip_text
  local current_running_temp temp_colored gamma_colored
  local saved_temp_colored saved_gamma_colored

  current_running_temp="$(get_running_temp)"
  if [ "${toggle_mode}" -eq 1 ]; then
    text_output="󱩌"
    alt_text="active"
    temp_colored="$(get_temp_color "${current_running_temp}")"
    gamma_colored="$(get_gamma_color "${currentGamma}")"
    tooltip_text="󰈈 <b>Hyprsunset Active</b>\n"
    tooltip_text+="󰔄 Temperature: ${temp_colored}\n"
    tooltip_text+="󰍉 Gamma: ${gamma_colored}\n"
    tooltip_text+="\n<i>󰀨 Click to Disable</i>"
  else
    text_output="󱩍"
    alt_text="inactive"
    saved_temp_colored="$(get_temp_color "${currentTemp}")"
    saved_gamma_colored="$(get_gamma_color "${currentGamma}")"
    tooltip_text="<b> Hyprsunset: Inactive</b>\n"
    tooltip_text+="󰔄 Temperature: ${saved_temp_colored}\n"
    tooltip_text+="󰍉 Gamma: ${saved_gamma_colored}\n"
    tooltip_text+="\n<i>󰀨 Click to activate with saved settings</i>"
  fi

  cat <<JSON
{"text":"${text_output}", "alt":"${alt_text}", "tooltip":"${tooltip_text}"}
JSON
}

main() {
  require_args "$@"
  load_state
  parse_args "$@"
  prepare_action_values
  apply_action_to_state
  [ "${notify}" = true ] && send_notification
  send_signal_to_process
  sync_runtime_state
  generate_status
}

main "$@"

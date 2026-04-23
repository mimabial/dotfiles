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
HYPRSUNSET_USER_ID="$(id -u)"

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
  local -n state_ref="$1"

  state_ref[temp]="$(state_get "HYPRSUNSET_TEMP" "${DEFAULT_TEMP}")"
  state_ref[gamma]="$(state_get "HYPRSUNSET_GAMMA" "${DEFAULT_GAMMA}")"
  state_ref[enabled]="$(state_get "HYPRSUNSET_ENABLED" "1")"
}

hyprsunset_matching_pids() {
  pgrep -u "${HYPRSUNSET_USER_ID}" -x "$1" 2>/dev/null || true
}

hyprsunset_process_running() {
  local process="$1"
  local pid=""

  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    return 0
  done < <(hyprsunset_matching_pids "${process}")

  return 1
}

hyprsunset_signal_process() {
  local process="$1"
  local signal="$2"
  local pid=""
  local sent=0
  local failed=0

  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    sent=1
    if ! kill -s "RTMIN+${signal}" "${pid}" 2>/dev/null; then
      failed=1
    fi
  done < <(hyprsunset_matching_pids "${process}")

  [[ "${sent}" -eq 1 ]] || return 1
  [[ "${failed}" -eq 0 ]]
}

write_sunset_state() {
  local -n state_ref="$1"

  state_set "HYPRSUNSET_TEMP" "${state_ref[temp]}" "staterc"
  state_set "HYPRSUNSET_GAMMA" "${state_ref[gamma]}" "staterc"
  state_set "HYPRSUNSET_ENABLED" "${state_ref[enabled]}" "staterc"
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

parse_args() {
  local -n options_ref="$1"
  shift
  local longopts="cm:,increase::,decrease::,set:,read,toggle,quiet,sigproc:,help"
  local shortopts="i::d::s:rtqP:h"
  local parsed=""

  parsed=$(getopt --options "${shortopts}" --longoptions "${longopts}" --name "$0" -- "$@") || return 2
  eval set -- "${parsed}"

  while true; do
    case "$1" in
      --cm)
        options_ref[color_mode]="$2"
        shift 2
        ;;
      -i|--increase)
        options_ref[action]="increase"
        options_ref[custom_step]="$2"
        shift 2
        ;;
      -d|--decrease)
        options_ref[action]="decrease"
        options_ref[custom_step]="$2"
        shift 2
        ;;
      -s|--set)
        options_ref[action]="set"
        options_ref[custom_step]="$2"
        shift 2
        ;;
      -r|--read)
        options_ref[action]="read"
        shift
        ;;
      -t|--toggle)
        options_ref[action]="toggle"
        shift
        ;;
      -q|--quiet)
        options_ref[notify]=false
        shift
        ;;
      -P|--sigproc)
        options_ref[signal_proc]="$2"
        shift 2
        ;;
      -h|--help)
        options_ref[help]=true
        shift
        ;;
      --)
        shift
        return 0
        ;;
      *)
        echo "Invalid option: $1" >&2
        return 1
        ;;
    esac
  done
}

apply_signed_step() {
  local -n options_ref="$1"
  local -n state_ref="$2"
  local direction="$3"

  if [ "${options_ref[color_mode]}" = "gamma" ]; then
    state_ref[new_gamma]="$(clamp_range "$((state_ref[gamma] + (direction * options_ref[gamma_step])))" "${MIN_GAMMA}" "${MAX_GAMMA}")"
    state_ref[gamma]="${state_ref[new_gamma]}"
    return 0
  fi

  state_ref[new_temp]="$(clamp_range "$((state_ref[temp] + (direction * options_ref[temp_step])))" "${MIN_TEMP}" "${MAX_TEMP}")"
  state_ref[temp]="${state_ref[new_temp]}"
}

validate_color_mode() {
  case "$1" in
    temp|gamma) return 0 ;;
    *)
      echo "Error: Color mode must be 'temp' or 'gamma'"
      return 1
      ;;
  esac
}

resolve_set_action() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  if [ "${options_ref[color_mode]}" = "gamma" ]; then
    validate_int_range "${options_ref[custom_step]}" "${MIN_GAMMA}" "${MAX_GAMMA}" \
      "Error: Gamma value must be an integer between ${MIN_GAMMA} and ${MAX_GAMMA}" || return 1
    state_ref[new_gamma]="$(clamp_range "${options_ref[custom_step]}" "${MIN_GAMMA}" "${MAX_GAMMA}")"
    return 0
  fi

  validate_int_range "${options_ref[custom_step]}" "${MIN_TEMP}" "${MAX_TEMP}" \
    "Error: Temperature must be an integer between ${MIN_TEMP} and ${MAX_TEMP}" || return 1
  state_ref[new_temp]="$(clamp_range "${options_ref[custom_step]}" "${MIN_TEMP}" "${MAX_TEMP}")"
}

resolve_step_action() {
  local -n options_ref="$1"

  if [ -z "${options_ref[custom_step]}" ] || ! [[ "${options_ref[custom_step]}" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  if [ "${options_ref[color_mode]}" = "gamma" ]; then
    validate_int_range "${options_ref[custom_step]}" 1 50 "Error: Gamma step must be between 1 and 50" || return 1
    options_ref[gamma_step]="${options_ref[custom_step]}"
    return 0
  fi

  validate_int_range "${options_ref[custom_step]}" 1 5000 "Error: Temperature step must be between 1 and 5000" || return 1
  options_ref[temp_step]="${options_ref[custom_step]}"
}

prepare_action_values() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  validate_color_mode "${options_ref[color_mode]}" || return 1
  [ -n "${options_ref[action]}" ] || {
    echo "Error: No action specified" >&2
    show_help >&2
    return 1
  }

  case "${options_ref[action]}" in
    set) resolve_set_action "${!options_ref}" "${!state_ref}" ;;
    increase|decrease) resolve_step_action "${!options_ref}" ;;
  esac
}

apply_action_to_state() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  case "${options_ref[action]}" in
    increase)
      apply_signed_step "${!options_ref}" "${!state_ref}" 1
      ;;
    decrease)
      apply_signed_step "${!options_ref}" "${!state_ref}" -1
      ;;
    set)
      if [ "${options_ref[color_mode]}" = "gamma" ]; then
        state_ref[gamma]="${state_ref[new_gamma]}"
      else
        state_ref[temp]="${state_ref[new_temp]}"
      fi
      ;;
    toggle)
      state_ref[enabled]=$((1 - state_ref[enabled]))
      ;;
    read)
      return 0
      ;;
  esac

  write_sunset_state "${!state_ref}"
}

send_notification() {
  local -n options_ref="$1"
  local -n state_ref="$2"
  local title="" message="" icon_name
  local -a notify_args

  case "${options_ref[action]}" in
    toggle)
      title="Hyprsunset"
      if [ "${state_ref[enabled]}" -eq 1 ]; then
        message="ON"
      else
        message="OFF"
      fi
      ;;
    *)
      if [ -n "${state_ref[new_temp]}" ]; then
        title="Mode: Temperature"
        message="${state_ref[new_temp]}K"
      elif [ -n "${state_ref[new_gamma]}" ]; then
        title="Mode: Gamma"
        message="${state_ref[new_gamma]}"
      fi
      ;;
  esac
  [ -n "${title}" ] || return 0

  if [ "${state_ref[enabled]}" -eq 1 ]; then
    icon_name="redshift-status-on"
  else
    icon_name="redshift-status-off"
  fi

  notify_args=(-a "hyprsunset" -r 19 -t 800 -i "${icon_name}" "${title}")
  [ -n "${message}" ] && notify_args+=("${message}")

  notify_send_safe "${notify_args[@]}"
}

parse_signal_target() {
  local raw="$1"
  local -n process_ref="$2"
  local -n signal_ref="$3"

  case "${raw}" in
    *,*) IFS=',' read -r process_ref signal_ref <<<"${raw}" ;;
    *:*) IFS=':' read -r process_ref signal_ref <<<"${raw}" ;;
    *)
      echo "Error: Invalid sigproc format. Use PROCESS,SIGNAL or PROCESS:SIGNAL"
      return 1
      ;;
  esac

  if ! [[ "${signal_ref}" =~ ^[0-9]+$ ]]; then
    echo "Error: Signal must be a number"
    return 1
  fi
}

send_signal_to_process() {
  local signal_proc="$1"
  local process="" signal=""

  [ -n "${signal_proc}" ] || return 0
  parse_signal_target "${signal_proc}" process signal || return 1

  if hyprsunset_process_running "${process}"; then
    hyprsunset_signal_process "${process}" "${signal}" || echo "Warning: Failed to send signal ${signal} to ${process}"
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
  if hyprsunset_process_running "hyprsunset"; then
    return 0
  fi

  remove_stale_socket
  hyprctl --quiet dispatch exec -- hyprsunset
}

sync_runtime_for_read() {
  local -n state_ref="$1"
  local current_running_temp=""

  [ "${state_ref[enabled]}" -eq 1 ] || return 0
  current_running_temp="$(hyprctl hyprsunset temperature)"
  if [ "${current_running_temp}" != "${state_ref[temp]}" ]; then
    hyprctl --quiet hyprsunset temperature "${state_ref[temp]}"
  fi
}

sync_runtime_for_write() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  if [ "${state_ref[enabled]}" -eq 0 ]; then
    hyprctl --quiet hyprsunset identity
    hyprctl --quiet hyprsunset gamma "${DEFAULT_GAMMA}"
    return 0
  fi

  if [ "${options_ref[color_mode]}" = "gamma" ] && [ -n "${state_ref[new_gamma]}" ]; then
    hyprctl --quiet hyprsunset temperature "${state_ref[temp]}"
    hyprctl --quiet hyprsunset gamma "${state_ref[new_gamma]}"
    return 0
  fi

  if [ -n "${state_ref[new_temp]}" ]; then
    hyprctl --quiet hyprsunset temperature "${state_ref[new_temp]}"
    return 0
  fi

  hyprctl --quiet hyprsunset temperature "${state_ref[temp]}"
  hyprctl --quiet hyprsunset gamma "${state_ref[gamma]}"
}

sync_runtime_state() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  if [ "${options_ref[action]}" = "read" ] && [ "${state_ref[enabled]}" -ne 1 ]; then
    return 0
  fi
  ensure_hyprsunset_process

  if [ "${options_ref[action]}" = "read" ]; then
    sync_runtime_for_read "${!state_ref}"
    return 0
  fi

  sync_runtime_for_write "${!options_ref}" "${!state_ref}"
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
  local -n state_ref="$1"
  local text_output alt_text tooltip_text
  local current_running_temp temp_colored gamma_colored
  local saved_temp_colored saved_gamma_colored

  current_running_temp="$(hyprctl hyprsunset temperature 2>/dev/null || echo "${DEFAULT_TEMP}")"
  if [ "${state_ref[enabled]}" -eq 1 ]; then
    text_output="󱩌"
    alt_text="active"
    temp_colored="$(get_temp_color "${current_running_temp}")"
    gamma_colored="$(get_gamma_color "${state_ref[gamma]}")"
    tooltip_text="󰈈 <b>Hyprsunset Active</b>\n"
    tooltip_text+="󰔄 Temperature: ${temp_colored}\n"
    tooltip_text+="󰍉 Gamma: ${gamma_colored}\n"
    tooltip_text+="\n<i>󰀨 Click to Disable</i>"
  else
    text_output="󱩍"
    alt_text="inactive"
    saved_temp_colored="$(get_temp_color "${state_ref[temp]}")"
    saved_gamma_colored="$(get_gamma_color "${state_ref[gamma]}")"
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
  local -A options=(
    [notify]="${waybar_temperature_notification:-true}"
    [action]=""
    [color_mode]="temp"
    [custom_step]=""
    [signal_proc]=""
    [temp_step]="${DEFAULT_TEMP_STEP}"
    [gamma_step]="${DEFAULT_GAMMA_STEP}"
    [help]=false
  )
  local -A state=(
    [temp]=""
    [gamma]=""
    [enabled]=""
    [new_temp]=""
    [new_gamma]=""
  )

  if [ "$#" -le 0 ]; then
    echo "No arguments provided" >&2
    show_help >&2
    return 1
  fi
  parse_args options "$@" || return $?
  if [ "${options[help]}" = true ]; then
    show_help
    return 0
  fi

  load_state state
  prepare_action_values options state || return 1
  apply_action_to_state options state
  [ "${options[notify]}" = true ] && send_notification options state
  send_signal_to_process "${options[signal_proc]}"
  sync_runtime_state options state
  generate_status state
}

main "$@"

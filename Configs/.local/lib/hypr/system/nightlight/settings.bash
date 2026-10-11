DEFAULT_TEMPERATURE_KELVIN=6500
DEFAULT_GAMMA_PERCENT=100
DEFAULT_TEMPERATURE_STEP_KELVIN=500
DEFAULT_GAMMA_STEP_PERCENT=5
MIN_TEMPERATURE_KELVIN=3000
MAX_TEMPERATURE_KELVIN=10000
MIN_GAMMA_PERCENT=20
MAX_GAMMA_PERCENT=100
MIN_STEP=1
MAX_TEMPERATURE_STEP_KELVIN=5000
MAX_GAMMA_STEP_PERCENT=50
HYPRSUNSET_SOCKET_WAIT_S=3
HYPRSUNSET_USER_ID="${UID}"

declare -A temperature_colors=(
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

nightlight_load_state() {
  local -n state_ref="$1"

  state_ref[temperature_kelvin]="$(state_get "HYPRSUNSET_TEMP" "${DEFAULT_TEMPERATURE_KELVIN}")"
  state_ref[gamma_percent]="$(state_get "HYPRSUNSET_GAMMA" "${DEFAULT_GAMMA_PERCENT}")"
  state_ref[enabled]="$(state_get "HYPRSUNSET_ENABLED" "1")"
}

nightlight_write_sunset_state() {
  local -n state_ref="$1"

  state_set "HYPRSUNSET_TEMP" "${state_ref[temperature_kelvin]}" "staterc"
  state_set "HYPRSUNSET_GAMMA" "${state_ref[gamma_percent]}" "staterc"
  state_set "HYPRSUNSET_ENABLED" "${state_ref[enabled]}" "staterc"
}

nightlight_validate_int_range() {
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

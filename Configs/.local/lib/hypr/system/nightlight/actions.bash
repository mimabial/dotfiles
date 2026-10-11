nightlight_apply_signed_step() {
  local -n options_ref="$1"
  local -n state_ref="$2"
  local direction="$3"

  if [ "${options_ref[color_mode]}" = "gamma" ]; then
    state_ref[new_gamma_percent]="$(hypr_clamp "$((state_ref[gamma_percent] + (direction * options_ref[gamma_step_percent])))" "${MIN_GAMMA_PERCENT}" "${MAX_GAMMA_PERCENT}")"
    state_ref[gamma_percent]="${state_ref[new_gamma_percent]}"
    return 0
  fi

  state_ref[new_temperature_kelvin]="$(hypr_clamp "$((state_ref[temperature_kelvin] + (direction * options_ref[temperature_step_kelvin])))" "${MIN_TEMPERATURE_KELVIN}" "${MAX_TEMPERATURE_KELVIN}")"
  state_ref[temperature_kelvin]="${state_ref[new_temperature_kelvin]}"
}

nightlight_resolve_set_action() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  if [ "${options_ref[color_mode]}" = "gamma" ]; then
    nightlight_validate_int_range "${options_ref[custom_step]}" "${MIN_GAMMA_PERCENT}" "${MAX_GAMMA_PERCENT}" \
      "Error: Gamma value must be an integer between ${MIN_GAMMA_PERCENT} and ${MAX_GAMMA_PERCENT}" || return 1
    state_ref[new_gamma_percent]="$(hypr_clamp "${options_ref[custom_step]}" "${MIN_GAMMA_PERCENT}" "${MAX_GAMMA_PERCENT}")"
    return 0
  fi

  nightlight_validate_int_range "${options_ref[custom_step]}" "${MIN_TEMPERATURE_KELVIN}" "${MAX_TEMPERATURE_KELVIN}" \
    "Error: Temperature must be an integer between ${MIN_TEMPERATURE_KELVIN} and ${MAX_TEMPERATURE_KELVIN}" || return 1
  state_ref[new_temperature_kelvin]="$(hypr_clamp "${options_ref[custom_step]}" "${MIN_TEMPERATURE_KELVIN}" "${MAX_TEMPERATURE_KELVIN}")"
}

nightlight_resolve_step_action() {
  local -n options_ref="$1"

  [ -n "${options_ref[custom_step]}" ] || return 0

  if [ "${options_ref[color_mode]}" = "gamma" ]; then
    nightlight_validate_int_range "${options_ref[custom_step]}" "${MIN_STEP}" "${MAX_GAMMA_STEP_PERCENT}" \
      "Error: Gamma step must be between ${MIN_STEP} and ${MAX_GAMMA_STEP_PERCENT}" || return 1
    options_ref[gamma_step_percent]="${options_ref[custom_step]}"
    return 0
  fi

  nightlight_validate_int_range "${options_ref[custom_step]}" "${MIN_STEP}" "${MAX_TEMPERATURE_STEP_KELVIN}" \
    "Error: Temperature step must be between ${MIN_STEP} and ${MAX_TEMPERATURE_STEP_KELVIN}" || return 1
  options_ref[temperature_step_kelvin]="${options_ref[custom_step]}"
}

nightlight_prepare_action_values() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  nightlight_validate_color_mode "${options_ref[color_mode]}" || return 1
  [ -n "${options_ref[action]}" ] || {
    echo "Error: No action specified" >&2
    nightlight_show_help >&2
    return 1
  }

  case "${options_ref[action]}" in
    set) nightlight_resolve_set_action "${!options_ref}" "${!state_ref}" ;;
    increase|decrease) nightlight_resolve_step_action "${!options_ref}" ;;
  esac
}

nightlight_apply_action_to_state() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  case "${options_ref[action]}" in
    increase)
      nightlight_apply_signed_step "${!options_ref}" "${!state_ref}" 1
      ;;
    decrease)
      nightlight_apply_signed_step "${!options_ref}" "${!state_ref}" -1
      ;;
    set)
      if [ "${options_ref[color_mode]}" = "gamma" ]; then
        state_ref[gamma_percent]="${state_ref[new_gamma_percent]}"
      else
        state_ref[temperature_kelvin]="${state_ref[new_temperature_kelvin]}"
      fi
      ;;
    toggle)
      state_ref[enabled]=$((1 - state_ref[enabled]))
      ;;
    read)
      return 0
      ;;
  esac

  nightlight_write_sunset_state "${!state_ref}"
}

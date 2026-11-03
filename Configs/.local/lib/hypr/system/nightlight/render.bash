nightlight_send_notification() {
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
      if [ -n "${state_ref[new_temperature_kelvin]}" ]; then
        title="Mode: Temperature"
        message="${state_ref[new_temperature_kelvin]}K"
      elif [ -n "${state_ref[new_gamma_percent]}" ]; then
        title="Mode: Gamma"
        message="${state_ref[new_gamma_percent]}"
      fi
      ;;
  esac
  [ -n "${title}" ] || return 0

  if [ "${state_ref[enabled]}" -eq 1 ]; then
    icon_name="redshift-status-on"
  else
    icon_name="redshift-status-off"
  fi

  notify_args=(-a "hyprsunset" -r "${NOTIFY_ID_HYPRSUNSET}" -t "${NOTIFY_OSD_MS}" -i "${icon_name}" "${title}")
  [ -n "${message}" ] && notify_args+=("${message}")

  notify_send_safe "${notify_args[@]}"
}

nightlight_render_threshold_color_into() {
  local -n colored_ref="$1"
  local value="$2" suffix="$3"
  local -n colors_ref="$4"
  local threshold selected_threshold="" color
  colored_ref=""
  for threshold in "${!colors_ref[@]}"; do
    if ((value >= threshold)) && [[ -z "$selected_threshold" || "$threshold" -gt "$selected_threshold" ]]; then
      selected_threshold="$threshold"
    fi
  done
  [[ -n "$selected_threshold" ]] || return 0
  color="${colors_ref[$selected_threshold]}"
  if [[ -n "$color" ]]; then
    printf -v colored_ref "<span color='%s'><b>%s%s</b></span>" "$color" "$value" "$suffix"
  else
    printf -v colored_ref '<b>%s%s</b>' "$value" "$suffix"
  fi
}

nightlight_get_temp_color_into() {
  nightlight_render_threshold_color_into "$1" "$2" "K" temperature_colors
}

nightlight_get_gamma_color_into() {
  nightlight_render_threshold_color_into "$1" "$2" "" gamma_colors
}

nightlight_generate_status() {
  local -n state_ref="$1"
  local text_output alt_text tooltip_text
  local active_json temperature_kelvin
  local runtime_temperature_kelvin temp_colored gamma_colored
  local saved_temp_colored saved_gamma_colored

  runtime_temperature_kelvin="$(hyprctl hyprsunset temperature 2>/dev/null || echo "${DEFAULT_TEMPERATURE_KELVIN}")"
  if [ "${state_ref[enabled]}" -eq 1 ]; then
    text_output="󱩌"
    alt_text="active"
    active_json=true
    temperature_kelvin="${runtime_temperature_kelvin}"
    nightlight_get_temp_color_into temp_colored "${runtime_temperature_kelvin}"
    nightlight_get_gamma_color_into gamma_colored "${state_ref[gamma_percent]}"
    tooltip_text="󰈈 <b>Hyprsunset Active</b>\n"
    tooltip_text+="󰔄 Temperature: ${temp_colored}\n"
    tooltip_text+="󰍉 Gamma: ${gamma_colored}\n"
    tooltip_text+="\n<i>󰀨 Click to Disable</i>"
  else
    text_output="󱩍"
    alt_text="inactive"
    active_json=false
    temperature_kelvin="${state_ref[temperature_kelvin]}"
    nightlight_get_temp_color_into saved_temp_colored "${state_ref[temperature_kelvin]}"
    nightlight_get_gamma_color_into saved_gamma_colored "${state_ref[gamma_percent]}"
    tooltip_text="<b> Hyprsunset: Inactive</b>\n"
    tooltip_text+="󰔄 Temperature: ${saved_temp_colored}\n"
    tooltip_text+="󰍉 Gamma: ${saved_gamma_colored}\n"
    tooltip_text+="\n<i>󰀨 Click to activate with saved settings</i>"
  fi

  [[ "${temperature_kelvin}" =~ ^[0-9]+$ ]] || temperature_kelvin="${DEFAULT_TEMPERATURE_KELVIN}"

  printf '%s\n' "{\"text\":\"${text_output}\", \"alt\":\"${alt_text}\", \"tooltip\":\"${tooltip_text}\", \"active\":${active_json}, \"temperature\":${temperature_kelvin}, \"gamma\":${state_ref[gamma_percent]}, \"limits\":{\"tempMin\":${MIN_TEMPERATURE_KELVIN},\"tempMax\":${MAX_TEMPERATURE_KELVIN},\"gammaMin\":${MIN_GAMMA_PERCENT},\"gammaMax\":${MAX_GAMMA_PERCENT}}}"
}

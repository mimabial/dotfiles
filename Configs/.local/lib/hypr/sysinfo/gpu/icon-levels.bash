# Levels run high, mid, low; icons run from below low up to at-or-above high.
GPU_UTILIZATION_THRESHOLDS_PERCENT=(90 60 30)
GPU_UTILIZATION_ICONS=("󰾆" "󰾅" "󰓅" "")
GPU_TEMPERATURE_THRESHOLDS_C=(85 65 45)
GPU_TEMPERATURE_ICONS=("" "" "" "")

gpu_metric_is_numeric() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

gpu_level_with_hysteresis() {
  local value="$1" previous_level="$2" high="$3" mid="$4" low="$5" hysteresis_margin="$6"
  local integer_value measured_level=0 next_level
  local -a level_thresholds=(0 "$low" "$mid" "$high")

  if [[ -z "$value" ]] || ! gpu_metric_is_numeric "$value"; then
    [[ "$previous_level" =~ ^[0-3]$ ]] && printf '%s\n' "$previous_level"
    return 0
  fi
  integer_value="${value%%.*}"
  ((integer_value >= low)) && measured_level=1
  ((integer_value >= mid)) && measured_level=2
  ((integer_value >= high)) && measured_level=3
  if [[ ! "$previous_level" =~ ^[0-3]$ || ! "$hysteresis_margin" =~ ^[0-9]+$ ]] || ((hysteresis_margin <= 0)); then
    printf '%s\n' "$measured_level"
    return
  fi

  next_level="$previous_level"
  if ((measured_level > previous_level)); then
    ((integer_value >= level_thresholds[measured_level] + hysteresis_margin)) && next_level="$measured_level"
  elif ((measured_level < previous_level)); then
    ((integer_value < level_thresholds[previous_level] - hysteresis_margin)) && next_level="$measured_level"
  else
    next_level="$measured_level"
  fi
  printf '%s\n' "$next_level"
}

gpu_cached_level_icon() {
  local value="$1" previous_level="$2" hysteresis_margin="$3" state_key="$4"
  local -n levels_ref="$5" icons_ref="$6"
  local icon_level=""

  icon_level=$(gpu_level_with_hysteresis "${value}" "${previous_level}" "${levels_ref[@]}" "${hysteresis_margin}")
  if [[ -n "${icon_level}" ]]; then
    gpu_cache_set "${state_key}" "${icon_level}"
    printf '%s\n' "${icons_ref[icon_level]}"
    return 0
  fi
  printf '%s\n' "${icons_ref[0]}"
}

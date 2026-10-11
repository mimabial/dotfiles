battery_percentage_into() {
  local output_name="$1" battery_path="$2" percentage="" current_amount full_amount key value quantity
  if [[ -r "$battery_path/capacity" ]]; then
    percentage=$(<"$battery_path/capacity")
  fi
  for quantity in energy charge; do
    [[ -z "$percentage" && -r "$battery_path/${quantity}_now" && -r "$battery_path/${quantity}_full" ]] || continue
    current_amount=$(<"$battery_path/${quantity}_now")
    full_amount=$(<"$battery_path/${quantity}_full")
    [[ "$full_amount" =~ ^[0-9]+$ ]] && ((full_amount > 0)) && percentage=$((current_amount * 100 / full_amount))
    break
  done
  if [[ -z "$percentage" && -r "$battery_path/uevent" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" == POWER_SUPPLY_CAPACITY ]] && percentage="$value" && break
    done <"$battery_path/uevent"
  fi
  [[ "$percentage" =~ ^[0-9]+$ ]] || return 1
  printf -v "$output_name" '%s' "$percentage"
}

battery_read_all() {
  local battery_path percentage_value total_percent=0
  battery_percentages=() battery_statuses=()
  for battery_path in /sys/class/power_supply/BAT*; do
    [[ -r "$battery_path/status" ]] || continue
    battery_percentage_into percentage_value "$battery_path" || continue
    battery_percentages+=("$percentage_value")
    battery_statuses+=("$(<"$battery_path/status")")
    total_percent=$((total_percent + percentage_value))
  done
  ((${#battery_percentages[@]})) || return 1
  battery_percent=$((total_percent / ${#battery_percentages[@]}))
}

battery_refresh_state() {
  battery_read_all || return 1
  battery_status="${battery_statuses[-1]}"
  if ((battery_percent >= full_threshold_percent)) && [[ "$battery_status" != Discharging* ]]; then
    battery_status=Full
  fi
}

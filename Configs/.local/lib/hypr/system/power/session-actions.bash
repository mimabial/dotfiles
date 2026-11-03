declare -F hypr_dbus_get >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/dbus.bash" || return 1

power_apply_profile() {
  local state="" profile="" current=""
  power_manager_enabled || return 0
  hypr_gamemode_active && return 0
  state="$(power_source_state)"
  profile="$(power_setting "profiles.$state" balanced)"
  power_valid_profile "$profile" || return 1
  current="$(hypr_power_profile)"
  [[ "$current" == "$profile" ]] && return 0
  local set_status=0
  hypr_set_power_profile "$profile" || set_status=$?
  if ((set_status)) && [[ "$profile" != balanced ]]; then
    hypr_set_power_profile balanced || true
  fi
  return "$set_status"
}

power_perform_action() {
  local action="$1" locked="${2:-}" method=""
  power_valid_action "$action" || return 2
  [[ "$action" == ignore ]] && return 0
  [[ "$locked" == --locked ]] || "${HYPR_LIB_DIR}/session/lid-close.sh" --no-suspend || return
  case "$action" in
    suspend) "${HYPR_LIB_DIR}/session/suspend.sh" --no-lock ;;
    hibernate|suspend-then-hibernate|hybrid-sleep|poweroff)
      case "$action" in
        hibernate) method=Hibernate ;;
        suspend-then-hibernate) method=SuspendThenHibernate ;;
        hybrid-sleep) method=HybridSleep ;;
        poweroff) method=PowerOff ;;
      esac
      hypr_login1_call "$method" boolean:true >/dev/null
      ;;
  esac
}

power_lid_action() {
  local state="" action=""
  [[ "$(power_setting lid.ignoreLidClose false)" == true ]] && { printf 'ignore\n'; return; }
  state="$(power_source_state)"
  action="$(power_setting "lid.$state.action" suspend)"
  power_valid_action "$action" || action=suspend
  printf '%s\n' "$action"
}

power_lid_choice() {
  if power_sleep_held; then
    printf 'keep-running\n'
    return
  fi
  jq -r 'if .lid.ignoreLidClose then empty
    else [.lid.ac.action, .lid.batteryHigh.action, .lid.batteryLow.action] | map(. // "suspend") | unique | select(length == 1)[0] end' \
    "$power_config_path" 2>/dev/null || printf 'suspend\n'
}

power_set_lid_choice() {
  local choice="$1" config=""
  power_require_idle_state || return 1
  if [[ "$choice" == keep-running ]]; then
    idle_set_system 1
    return
  fi
  power_valid_action "$choice" || return 2
  config="$(jq --arg action "$choice" \
    '.lid.ignoreLidClose = false | .lid.ac.action = $action | .lid.batteryHigh.action = $action | .lid.batteryLow.action = $action' \
    "$power_config_path")" || return 1
  printf '%s\n' "$config" >"$power_config_path"
  idle_set_system 0
}

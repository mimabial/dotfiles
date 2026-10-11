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
  [[ "$locked" == --locked ]] || hyprshell session/lid-close.sh --no-suspend || return
  case "$action" in
    suspend) hyprshell session/suspend.sh --no-lock ;;
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
  if ! power_manager_enabled; then
    printf 'suspend\n'
    return
  fi
  [[ "$(power_setting lid.ignoreLidClose false)" == true ]] && { printf 'ignore\n'; return; }
  state="$(power_source_state)"
  action="$(power_setting "lid.$state.action" suspend)"
  power_valid_action "$action" || action=suspend
  printf '%s\n' "$action"
}

MINUTES_PER_DAY=1440

power_idle_plan() {
  local state="" action="" minutes=""
  power_manager_enabled || return 1
  state="$(power_source_state)"
  action="$(power_setting "idle.$state.action" suspend)"
  minutes="$(power_setting "idle.$state.sleepAfterMinutes" 0)"
  power_valid_action "$action" || return 1
  [[ "$minutes" =~ ^[0-9]+$ ]] || return 1
  ((minutes > 0 && minutes <= MINUTES_PER_DAY)) || return 1
  [[ "$action" != ignore ]] || return 1
  printf '%s %s\n' "$minutes" "$action"
}

power_cancel_idle() {
  local pid="" token="" command=""
  [[ -d "$power_runtime_dir" ]] || return 0
  exec {idle_lock}>"$power_runtime_dir/idle.lock"
  flock "$idle_lock"
  [[ -f "$power_runtime_dir/idle.token" ]] && read -r token <"$power_runtime_dir/idle.token"
  [[ -f "$power_runtime_dir/idle.pid" ]] && read -r pid <"$power_runtime_dir/idle.pid"
  rm -f -- "$power_runtime_dir/idle.token" "$power_runtime_dir/idle.pid"
  if [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]]; then
    command="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
    [[ "$command" == *"power-manager.sh idle-wait $token "* ]] && kill "$pid" 2>/dev/null || true
  fi
  exec {idle_lock}>&-
}

power_arm_idle() {
  local minutes="" action="" delay="" token="" daemon_pid=""
  read -r minutes action < <(power_idle_plan) || return 0
  [[ -n "$minutes" && -n "$action" ]] || return 0
  read -r daemon_pid < <(hypr_user_pgrep -x hypridle) || return 0
  mkdir -p "$power_runtime_dir"
  delay=$((minutes * SECONDS_PER_MINUTE - IDLE_ARM_ELAPSED_SECONDS))
  ((delay >= 0)) || delay=0
  power_cancel_idle
  token="${EPOCHREALTIME//[!0-9]/}-$RANDOM"
  exec {idle_lock}>"$power_runtime_dir/idle.lock"
  flock "$idle_lock"
  printf '%s\n' "$token" >"$power_runtime_dir/idle.token"
  ("$0" idle-wait "$token" "$delay" "$action" "$daemon_pid") </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$power_runtime_dir/idle.pid"
  flock -u "$idle_lock"
  exec {idle_lock}>&-
}

power_rearm_idle() {
  [[ -f "$power_runtime_dir/idle.token" ]] || return 0
  power_cancel_idle
  power_arm_idle
}

power_wait_idle() {
  local token="$1" delay_seconds="$2" action="$3" daemon_pid="$4" active="" current_pid="" waiter_pid="" wait_status=124
  [[ "$delay_seconds" =~ ^[0-9]+$ ]] || return 2
  power_valid_action "$action" || return 2
  if ((delay_seconds)); then
    timeout "$delay_seconds" pidwait -p "$daemon_pid" &
    waiter_pid=$!
    trap 'kill "$waiter_pid" 2>/dev/null || true' EXIT
    trap 'exit 0' TERM INT
    wait_status=0
    wait "$waiter_pid" || wait_status=$?
    trap - EXIT TERM INT
  fi
  exec {idle_lock}>"$power_runtime_dir/idle.lock"
  flock "$idle_lock"
  [[ -f "$power_runtime_dir/idle.token" ]] && read -r active <"$power_runtime_dir/idle.token"
  [[ "$active" == "$token" ]] || return 0
  rm -f -- "$power_runtime_dir/idle.token" "$power_runtime_dir/idle.pid"
  exec {idle_lock}>&-
  [[ "$wait_status" == 124 ]] || return 0
  power_manager_enabled || return 0
  read -r current_pid < <(hypr_user_pgrep -x hypridle) || return 0
  [[ "$current_pid" == "$daemon_pid" ]] || return 0
  "$0" perform "$action"
}

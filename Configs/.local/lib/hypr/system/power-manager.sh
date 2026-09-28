#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

config="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/power-manager.json"
runtime="$HYPR_RUNTIME_DIR/power-manager"

enabled() {
  [[ -f "$config" ]] && jq -e '.enabled == true' "$config" >/dev/null 2>&1
}

setting() {
  local key="$1" fallback="$2" value=""
  value="$(jq -r --arg key "$key" 'getpath($key | split(".")) // empty' "$config" 2>/dev/null)" || true
  printf '%s\n' "${value:-$fallback}"
}

state_key() {
  local percentage="" threshold=""
  if ! hypr_on_battery; then
    printf 'ac\n'
    return
  fi
  percentage="$(hypr_dbus_get system org.freedesktop.UPower /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device Percentage 2>/dev/null || true)"
  threshold="$(setting batteryThreshold 20)"
  if [[ "$percentage" =~ ^[0-9]+([.][0-9]+)?$ && "$threshold" =~ ^[0-9]+$ ]]; then
    if awk -v percent="$percentage" -v limit="$threshold" 'BEGIN { exit !(percent > 0 && percent <= limit) }'; then
      printf 'batteryLow\n'
      return
    fi
  fi
  printf 'batteryHigh\n'
}

valid_profile() {
  [[ "$1" == balanced || "$1" == power-saver || "$1" == performance ]]
}

valid_action() {
  case "$1" in
    ignore|suspend|hibernate|suspend-then-hibernate|hybrid-sleep|poweroff) return 0 ;;
    *) return 1 ;;
  esac
}

apply_profile() {
  local state="" profile="" current=""
  enabled || return 0
  hypr_gamemode_active && return 0
  state="$(state_key)"
  profile="$(setting "profiles.$state" balanced)"
  valid_profile "$profile" || return 1
  current="$(hypr_power_profile)"
  [[ "$current" == "$profile" ]] && return 0
  hypr_set_power_profile "$profile" || {
    [[ "$profile" == balanced ]] || hypr_set_power_profile balanced
  }
}

idle_action() {
  local state="" action="" minutes=""
  enabled || return 1
  state="$(state_key)"
  action="$(setting "idle.$state.action" suspend)"
  minutes="$(setting "idle.$state.sleepAfterMinutes" 0)"
  valid_action "$action" || return 1
  [[ "$minutes" =~ ^[0-9]+$ ]] || return 1
  ((minutes > 0 && minutes <= 1440)) || return 1
  [[ "$action" != ignore ]] || return 1
  printf '%s %s\n' "$minutes" "$action"
}

cancel_idle() {
  local pid="" token="" command=""
  [[ -d "$runtime" ]] || return 0
  exec {idle_lock}>"$runtime/idle.lock"
  flock "$idle_lock"
  [[ -f "$runtime/idle.token" ]] && read -r token <"$runtime/idle.token"
  [[ -f "$runtime/idle.pid" ]] && read -r pid <"$runtime/idle.pid"
  rm -f -- "$runtime/idle.token" "$runtime/idle.pid"
  if [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]]; then
    command="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
    [[ "$command" == *"power-manager.sh idle-wait $token "* ]] && kill "$pid" 2>/dev/null || true
  fi
  flock -u "$idle_lock"
}

arm_idle() {
  local minutes="" action="" delay="" token="" daemon_pid=""
  read -r minutes action < <(idle_action) || return 0
  [[ -n "$minutes" && -n "$action" ]] || return 0
  read -r daemon_pid < <(hypr_user_pgrep -x hypridle) || return 0
  mkdir -p "$runtime"
  delay=$((minutes * 60 - 60))
  ((delay >= 0)) || delay=0
  cancel_idle
  token="$(date +%s%N)-$RANDOM"
  exec {idle_lock}>"$runtime/idle.lock"
  flock "$idle_lock"
  printf '%s\n' "$token" >"$runtime/idle.token"
  ("$0" idle-wait "$token" "$delay" "$action" "$daemon_pid") </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$runtime/idle.pid"
  flock -u "$idle_lock"
}

rearm_idle() {
  [[ -f "$runtime/idle.token" ]] || return 0
  cancel_idle
  arm_idle
}

wait_idle() {
  local token="$1" delay="$2" action="$3" daemon_pid="$4" active="" current_pid="" sleeper=""
  [[ "$delay" =~ ^[0-9]+$ ]] || return 2
  valid_action "$action" || return 2
  sleep "$delay" &
  sleeper=$!
  trap "kill $sleeper 2>/dev/null || true" EXIT TERM INT
  wait "$sleeper" || return 0
  trap - EXIT TERM INT
  exec {idle_lock}>"$runtime/idle.lock"
  flock "$idle_lock"
  [[ -f "$runtime/idle.token" ]] && read -r active <"$runtime/idle.token"
  [[ "$active" == "$token" ]] || return 0
  rm -f -- "$runtime/idle.token" "$runtime/idle.pid"
  flock -u "$idle_lock"
  enabled || return 0
  read -r current_pid < <(hypr_user_pgrep -x hypridle) || return 0
  [[ "$current_pid" == "$daemon_pid" ]] || return 0
  "$0" perform "$action"
}

perform_action() {
  local action="$1" locked="${2:-}" method=""
  valid_action "$action" || return 2
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
      dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 \
        "org.freedesktop.login1.Manager.$method" boolean:true >/dev/null
      ;;
  esac
}

lid_action() {
  local state="" action=""
  if ! enabled; then
    printf 'suspend\n'
    return
  fi
  [[ "$(setting lid.ignoreLidClose false)" == true ]] && { printf 'ignore\n'; return; }
  state="$(state_key)"
  action="$(setting "lid.$state.action" suspend)"
  valid_action "$action" || action=suspend
  printf '%s\n' "$action"
}

case "${1:-}" in
  state) state_key ;;
  enabled) enabled ;;
  apply-profile) apply_profile ;;
  idle-plan) idle_action ;;
  idle-arm) arm_idle ;;
  idle-rearm) rearm_idle ;;
  idle-cancel) cancel_idle ;;
  idle-legacy) enabled || hyprshell session/suspend.sh ;;
  idle-wait) wait_idle "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
  lid-action) lid_action ;;
  perform) perform_action "${2:-}" "${3:-}" ;;
  -h|--help) printf 'Usage: hyprshell system/power-manager <state|enabled|apply-profile|idle-plan|idle-arm|idle-rearm|idle-cancel|idle-legacy|lid-action|perform ACTION [--locked]>\n' ;;
  *) exit 2 ;;
esac

#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

set -uo pipefail
export LC_ALL=C

action=${1:-}
address=${2:-}

if (( $# != 2 )) \
  || [[ $action != pair && $action != connect && $action != disconnect && $action != forget ]] \
  || [[ ! $address =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
  echo "Usage: bluetooth-device-action <pair|connect|disconnect|forget> <address>" >&2
  exit 1
fi

active_control_pid=
active_output_file=

cleanup_control_output_file() {
  [[ -z $active_output_file ]] || rm -f -- "$active_output_file"
}

cancel_active_control() {
  trap - INT TERM
  if [[ -n $active_control_pid ]]; then
    kill -TERM "$active_control_pid" >/dev/null 2>&1 || true
    wait "$active_control_pid" >/dev/null 2>&1 || true
  fi
  exit 130
}

trap cleanup_control_output_file EXIT
trap cancel_active_control INT TERM

strip_terminal_codes() {
  sed $'s/\033\[[0-9;?]*[ -\/]*[@-~]//g'
}

TIMEOUT_EXIT_STATUS=124
TIMEOUT_KILLED_EXIT_STATUS=137
declare -rA BLUETOOTHCTL_TIMEOUT_S=([pair]=20 [connect]=20 [disconnect]=10 [remove]=10 [trust]=5)

source "${BASH_SOURCE[0]%/*}/lib/device-action-errors.bash"

requested_state_already_holds() {
  local phase=$1 lower=$2

  case $phase in
    connect) [[ $lower == *alreadyconnected* || $lower == *already\ connected* ]] ;;
    pair) [[ $lower == *alreadyexists* || $lower == *already\ paired* ]] ;;
    disconnect) [[ $lower == *notconnected* || $lower == *not\ connected* ]] ;;
    remove) [[ $lower == *doesnotexist* || $lower == *not\ available* ]] ;;
    *) false ;;
  esac
}

run_bluetoothctl_action() {
  local phase=$1
  local output status lower failed=false
  active_output_file=$(mktemp) || {
    echo "Could not start the Bluetooth operation." >&2
    return 1
  }
  timeout --kill-after=2s "${BLUETOOTHCTL_TIMEOUT_S[$phase]}s" bluetoothctl "$phase" "$address" >"$active_output_file" 2>&1 &
  active_control_pid=$!
  status=0
  wait "$active_control_pid" || status=$?
  active_control_pid=

  output=$(strip_terminal_codes <"$active_output_file")
  rm -f -- "$active_output_file"
  active_output_file=
  lower=${output,,}

  requested_state_already_holds "$phase" "$lower" && return 0

  (( status == 0 )) || failed=true
  if [[ $lower == *org.bluez.error* || $lower == *"failed to "*
      || $lower == *"not available"* || $lower == error:* ]]; then
    failed=true
  fi

  if [[ $failed == true ]]; then
    bluetoothctl_failure_message "$phase" "$status" "$output" >&2
    return 1
  fi
}

ensure_bluetooth_adapter_powered() {
  local state
  state=$(hypr_daemon_call bluetoothctl show 2>/dev/null | strip_terminal_codes) || state=
  [[ $state == *"Powered: yes"* ]] && return 0

  if ! "${BASH_SOURCE[0]%/*}/power.sh" on >/dev/null 2>&1; then
    echo "The Bluetooth adapter could not be powered on." >&2
    return 1
  fi
}

ensure_bluetooth_device_not_blocked() {
  local info
  info=$(hypr_daemon_call bluetoothctl info "$address" 2>/dev/null | strip_terminal_codes) || return 0
  if [[ $info == *"Blocked: yes"* ]]; then
    echo "This device is blocked. Unblock it before trying again." >&2
    return 1
  fi
}

run_optional_bluetoothctl_action() {
  run_bluetoothctl_action "$1" >/dev/null 2>&1 || true
}

case "$action" in
  pair)
    ensure_bluetooth_adapter_powered || exit 1
    ensure_bluetooth_device_not_blocked || exit 1
    run_bluetoothctl_action pair || exit 1
    run_optional_bluetoothctl_action trust
    run_bluetoothctl_action connect || exit 1
    ;;
  connect)
    ensure_bluetooth_adapter_powered || exit 1
    ensure_bluetooth_device_not_blocked || exit 1
    run_bluetoothctl_action connect || exit 1
    run_optional_bluetoothctl_action trust
    ;;
  disconnect)
    run_bluetoothctl_action disconnect || exit 1
    ;;
  forget)
    run_optional_bluetoothctl_action disconnect
    run_bluetoothctl_action remove || exit 1
    ;;
esac

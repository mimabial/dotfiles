bluetoothctl_timeout_message() {
  local phase=$1
  case "$phase" in
    pair) echo "Pairing timed out. Put the device in pairing mode and try again." ;;
    connect) echo "Connection timed out. Make sure the device is nearby and awake." ;;
    disconnect) echo "Disconnecting the device timed out." ;;
    remove) echo "Forgetting the device timed out." ;;
    *) echo "The Bluetooth operation timed out." ;;
  esac
}

bluetoothctl_known_error_message() {
  case "${1,,}" in
    *authenticationrejected*|*authentication\ rejected*)
      echo "Pairing was rejected by the device. Confirm the code and try again."
      ;;
    *authenticationfailed*|*authentication\ failed*)
      echo "Pairing failed authentication. Remove the device's old pairing and try again."
      ;;
    *authenticationtimeout*|*authentication\ timeout*)
      echo "Pairing timed out. Put the device in pairing mode and try again."
      ;;
    *authenticationcanceled*|*authenticationcancelled*|*authentication\ canceled*|*authentication\ cancelled*)
      echo "Pairing was cancelled."
      ;;
    *blocked*)
      echo "This device is blocked. Unblock it before trying again."
      ;;
    *notready*|*not\ ready*)
      echo "The Bluetooth adapter is not ready. Turn Bluetooth on and try again."
      ;;
    *inprogress*|*in\ progress*)
      echo "Another Bluetooth operation is already in progress."
      ;;
    *profile-unavailable*|*profile\ unavailable*)
      echo "The device's Bluetooth service is unavailable. Reconnect or repair the device."
      ;;
    *connectionattemptfailed*|*page-timeout*|*connection\ attempt\ failed*)
      echo "The device did not respond. Make sure it is nearby, awake, and not connected elsewhere."
      ;;
    *notavailable*|*not\ available*)
      echo "The device is unavailable. Make sure it is nearby and in pairing mode."
      ;;
    *) return 1 ;;
  esac
}

bluetoothctl_generic_failure_message() {
  local phase=$1
  local detail=$2
  case "$phase" in
    pair) printf 'Could not pair with the device%s\n' "${detail:+: $detail}" ;;
    connect) printf 'Could not connect to the device%s\n' "${detail:+: $detail}" ;;
    disconnect) printf 'Could not disconnect the device%s\n' "${detail:+: $detail}" ;;
    remove) printf 'Could not forget the device%s\n' "${detail:+: $detail}" ;;
    *) printf 'The Bluetooth operation failed%s\n' "${detail:+: $detail}" ;;
  esac
}

bluetoothctl_failure_message() {
  local phase=$1
  local status=$2
  local output=$3
  local detail

  if (( status == TIMEOUT_EXIT_STATUS || status == TIMEOUT_KILLED_EXIT_STATUS )); then
    bluetoothctl_timeout_message "$phase"
    return
  fi
  bluetoothctl_known_error_message "$output" && return
  detail=$(printf '%s\n' "$output" | awk 'NF { line=$0 } END { print line }')
  bluetoothctl_generic_failure_message "$phase" "$detail"
}

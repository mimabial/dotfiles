#!/usr/bin/env bash

brightness_helper_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${brightness_helper_dir}/control.common.bash"

normalize_brightness_mode() {
  case "${1:-auto}" in
    0 | false | FALSE | no | NO | off | OFF | disabled | DISABLED | never | NEVER)
      printf '%s\n' off
      ;;
    *)
      printf '%s\n' auto
      ;;
  esac
}

brightnessctl_supported() {
  require_cmd brightnessctl || return 1
  brightnessctl info >/dev/null 2>&1
}

brightness_control_enabled() {
  brightnessctl_supported
}

brightness_idle_enabled() {
  local mode
  mode="$(normalize_brightness_mode "${HYPR_IDLE_DIM:-auto}")"
  [[ "${mode}" != off ]] || return 1
  brightnessctl_supported
}

brightness_unavailable_reason() {
  if ! require_cmd brightnessctl; then
    printf '%s\n' "brightnessctl is not installed"
    return
  fi
  printf '%s\n' "no writable brightness device detected"
}

#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/controls/lib/control-feedback.bash"

brightness_idle_enabled() {
  case "${HYPR_IDLE_DIM:-auto}" in
    0 | false | FALSE | no | NO | off | OFF | disabled | DISABLED | never | NEVER) return 1 ;;
  esac
  require_cmd brightnessctl && brightnessctl -m >/dev/null 2>&1
}

brightness_unavailable_reason() {
  if ! require_cmd brightnessctl; then
    printf '%s\n' "brightnessctl is not installed"
    return
  fi
  printf '%s\n' "no writable brightness device detected"
}

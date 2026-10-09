#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/notify.bash" || exit 1

hypr_help_guard "Usage: hyprshell controls/touchpad-toggle
Turn every touchpad off, or back on; the choice survives config reloads and restarts." "$@"

disabled_touchpads="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/touchpads-disabled.lua"
if [[ -f "${disabled_touchpads}" ]]; then enabled=true state=on; else enabled=false state=off; fi

device_configs=()
while IFS= read -r touchpad; do
  device_configs+=("hl.device({name = $(hypr_lua_quote "${touchpad}"), enabled = ${enabled}})")
done < <(hyprctl devices -j | jq -r '.mice[].name | select(endswith("touchpad"))')

if ${enabled}; then
  rm -f -- "${disabled_touchpads}"
else
  printf '%s\n' "${device_configs[@]}" >"${disabled_touchpads}"
fi
hypr_lua_apply "$(IFS=';'; printf '%s' "${device_configs[*]}")" >/dev/null
send_ephemeral_notif "hypr-touchpad" -t "${NOTIFY_MS}" -i input-touchpad "Touchpad ${state}"

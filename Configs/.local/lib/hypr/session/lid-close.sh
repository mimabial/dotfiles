#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell session/lid-close [--no-suspend]
Lock the screen, wait for it to map, then suspend. Bound to the lid switch, so it
must not depend on hypridle: caffeine stops that daemon and would skip the lock." "$@"

suspend=1
[[ "${1:-}" == "--no-suspend" ]] && suspend=0

mkdir -p "${HYPR_RUNTIME_DIR}"
exec {close_fd}>"${HYPR_RUNTIME_DIR}/lid-close.lock"
flock -n "${close_fd}" || exit 0
log="$(mktemp "${HYPR_RUNTIME_DIR}/lid-lock.XXXXXX")"
had_lock=0 ready=0
hypr_user_pgrep -x hyprlock >/dev/null 2>&1 && had_lock=1
hyprlock --immediate-render --no-fade-in {close_fd}>&- >"${log}" 2>&1 &
lock_pid=$!
for _ in {1..100}; do
  grep -q 'onLockLocked called' "${log}" && { ready=1; break; }
  ((had_lock)) && grep -q 'onLockFinished called' "${log}" && { ready=1; break; }
  kill -0 "${lock_pid}" 2>/dev/null || break
  sleep 0.05
done
rm -f -- "${log}"
((ready)) || { notify_send_safe -u critical 'Suspend cancelled' 'Hyprland did not confirm the screen lock'; exit 1; }

[[ "${suspend}" -eq 1 ]] || exit 0
if ! exec {inhibitor_fd}<"${HYPR_RUNTIME_DIR}/lid-inhibitor" || flock -n "${inhibitor_fd}"; then
  notify_send_safe -u critical 'Suspend cancelled' 'Lid inhibitor is not running'
  exit 1
fi
exec hyprshell session/suspend.sh --no-lock

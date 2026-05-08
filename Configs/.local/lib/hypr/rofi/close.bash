#!/usr/bin/env bash
# Sourced module; strict mode is owned by the caller.

rofi_close_user_uid() {
  printf '%s\n' "${UID:-$(id -u)}"
}

rofi_wait_for_exit() {
  local attempts="${1:-80}"
  local delay="${2:-0.03}"
  local user_uid=""

  user_uid="$(rofi_close_user_uid)" || return 1
  [[ "${attempts}" =~ ^[0-9]+$ ]] || attempts=80

  while ((attempts > 0)); do
    pgrep -u "${user_uid}" -x rofi >/dev/null 2>&1 || return 0
    sleep "${delay}"
    attempts=$((attempts - 1))
  done

  pgrep -u "${user_uid}" -x rofi >/dev/null 2>&1 && return 1
  return 0
}

rofi_close_running() {
  local user_uid=""

  user_uid="$(rofi_close_user_uid)" || return 1
  pkill -u "${user_uid}" -x rofi >/dev/null 2>&1 || return 0
  rofi_wait_for_exit "$@" || true
}

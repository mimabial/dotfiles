#!/usr/bin/env bash

source "${BASH_SOURCE[0]%/*}/../core/processes.bash"

ROFI_EXIT_WAIT_S=2
ROFI_CLOSED=0
ROFI_NOT_RUNNING=1
ROFI_STILL_RUNNING=2

rofi_close_running() {
  local wait_status=0

  pkill -u "${UID}" -x rofi >/dev/null 2>&1 || return "${ROFI_NOT_RUNNING}"
  timeout "${ROFI_EXIT_WAIT_S}" pidwait -u "${UID}" -x rofi || wait_status=$?
  ((wait_status == 0 || wait_status == PROCPS_NO_MATCH_STATUS)) && return "${ROFI_CLOSED}"
  return "${ROFI_STILL_RUNNING}"
}

rofi_ensure_closed() {
  rofi_close_running || (($? == ROFI_NOT_RUNNING))
}

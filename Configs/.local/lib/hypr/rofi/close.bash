#!/usr/bin/env bash

ROFI_EXIT_WAIT_S=2

rofi_close_running() {
  pkill -u "${UID}" -x rofi >/dev/null 2>&1 || return 0
  timeout "${ROFI_EXIT_WAIT_S}" pidwait -u "${UID}" -x rofi || true
}

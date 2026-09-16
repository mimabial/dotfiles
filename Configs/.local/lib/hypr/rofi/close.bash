#!/usr/bin/env bash
# Sourced module; strict mode is owned by the caller.

rofi_close_running() {
  pkill -u "${UID}" -x rofi >/dev/null 2>&1 || return 0
  timeout 2 pidwait -u "${UID}" -x rofi || true
}

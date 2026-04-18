#!/usr/bin/env bash

waybar_common_have_command() {
  command -v "$1" >/dev/null 2>&1
}

waybar_common_notify() {
  local icon="$1"
  local title="$2"
  local message="$3"
  local urgency="${4:-normal}"
  local timeout="${5:-5000}"

  dunstify -t "${timeout}" -i "${icon}" "${title}" "${message}" -u "${urgency}"
}

#!/usr/bin/env bash

set -euo pipefail

active_window_json="$(hyprctl -j activewindow 2>/dev/null)" || exit 1
read -r active_class active_address < <(
  jq -r '[.class // "", .address // ""] | @tsv' <<<"${active_window_json}"
)

if [[ -z "${active_class}" ]]; then
  exit 0
fi

if [[ "${active_class}" == "Steam" ]] && [[ -n "${active_address}" ]]; then
  hyprctl dispatch closewindow "address:${active_address}"
else
  hyprctl dispatch killactive ""
fi

#!/usr/bin/env bash

active_window_json="$(hyprctl -j activewindow 2>/dev/null)" || exit 1
active_class="$(jq -r '.class // empty' <<<"${active_window_json}")"
active_address="$(jq -r '.address // empty' <<<"${active_window_json}")"

if [[ -z "${active_class}" ]]; then
  exit 0
fi

if [[ "${active_class}" == "Steam" ]] && [[ -n "${active_address}" ]]; then
  hyprctl dispatch closewindow "address:${active_address}"
else
  hyprctl dispatch killactive ""
fi

#!/usr/bin/env bash

set -euo pipefail

state_file="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/gaps-toggle.state"
mkdir -p "$(dirname "${state_file}")"

gaps_out="$(hyprctl -j getoption general:gaps_out | jq -r '.int')"
gaps_in="$(hyprctl -j getoption general:gaps_in | jq -r '.int')"

if [[ "${gaps_out}" == "0" && "${gaps_in}" == "0" ]]; then
  if [[ -f "${state_file}" ]]; then
    # shellcheck disable=SC1090
    source "${state_file}"
  fi
  restore_out="${restore_out:-6}"
  restore_in="${restore_in:-3}"
  hyprctl -q --batch "\
    keyword general:gaps_in ${restore_in};\
    keyword general:gaps_out ${restore_out};\
  "
  notify-send "Workspace gaps enabled" "in=${restore_in}, out=${restore_out}" 2>/dev/null || true
else
  printf "restore_in=%s\nrestore_out=%s\n" "${gaps_in}" "${gaps_out}" >"${state_file}"
  hyprctl -q --batch "\
    keyword general:gaps_in 0;\
    keyword general:gaps_out 0;\
  "
  notify-send "Workspace gaps disabled" "in=0, out=0" 2>/dev/null || true
fi

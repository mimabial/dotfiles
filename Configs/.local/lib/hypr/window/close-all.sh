#!/usr/bin/env bash

set -euo pipefail

CORE_COMMON="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh"
# shellcheck source=/dev/null
source "${CORE_COMMON}" || exit 1

hypr_help_guard "Usage: hyprshell window/close-all
Close every window on the focused Hyprland instance." "$@"

clients_json="$(hyprctl clients -j)"
addrs_text="$(
  jq -r '.[] | .address // empty | select(length > 0)' <<<"${clients_json}"
)"

if [[ -z "${addrs_text}" ]]; then
  exit 0
fi

mapfile -t addrs <<<"${addrs_text}"

declare -a close_dispatchers=()
for addr in "${addrs[@]}"; do
  close_dispatchers+=("hl.dsp.window.close({window=$(hypr_lua_quote "address:${addr}")})")
done

hypr_lua_batch "${close_dispatchers[@]}" >/dev/null 2>&1 || true

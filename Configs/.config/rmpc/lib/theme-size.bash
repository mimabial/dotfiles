#!/usr/bin/env bash

rmpc_theme_for_size() {
  local helper="${XDG_DATA_HOME:-$HOME/.local/share}/rmpc/bin/rmpc-onresize"

  "${helper}" --print "${1:-}" "${2:-}"
}

rmpc_terminal_size() {
  local size=""

  size="$(stty size 2>/dev/null || true)"
  [[ "${size}" =~ ^[0-9]+[[:space:]][0-9]+$ ]] || return 1
  printf '%s\n' "${size}"
}

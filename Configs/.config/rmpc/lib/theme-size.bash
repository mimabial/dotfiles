#!/usr/bin/env bash

RMPC_WIDE_MIN_COLUMNS=100
RMPC_TALL_MIN_ROWS=24

rmpc_theme_for_size_into() {
  local -n theme_ref="$1"
  local columns="$2" rows="$3"

  if ((columns < RMPC_WIDE_MIN_COLUMNS && rows < RMPC_TALL_MIN_ROWS)); then
    theme_ref="hypr-small"
  elif ((columns < RMPC_WIDE_MIN_COLUMNS)); then
    theme_ref="hypr"
  elif ((rows < RMPC_TALL_MIN_ROWS)); then
    theme_ref="hypr-wide"
  else
    theme_ref="hypr-big"
  fi
}

rmpc_terminal_size() {
  local size=""

  size="$(stty size 2>/dev/null || true)"
  [[ "${size}" =~ ^[1-9][0-9]*[[:space:]][1-9][0-9]*$ ]] || return 1
  printf '%s\n' "${size}"
}

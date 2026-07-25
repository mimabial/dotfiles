#!/usr/bin/env bash

rmpc_theme_for_size() {
  local columns="${1:-}"
  local rows="${2:-}"

  [[ "${columns}" =~ ^[0-9]+$ && "${rows}" =~ ^[0-9]+$ ]] || return 2

  if ((columns < 90 && rows < 30)); then
    printf '%s\n' "pywal16-small"
  elif ((columns < 90 || rows < 30)); then
    printf '%s\n' "pywal16"
  else
    printf '%s\n' "pywal16-big"
  fi
}

rmpc_terminal_size() {
  local size=""

  size="$(stty size 2>/dev/null || true)"
  [[ "${size}" =~ ^[0-9]+[[:space:]][0-9]+$ ]] || return 1
  printf '%s\n' "${size}"
}

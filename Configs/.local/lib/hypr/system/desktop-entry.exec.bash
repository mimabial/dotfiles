#!/usr/bin/env bash

HYPR_SYSTEM_DIR="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system"

desktop_entry_exec_query() {
  local mode="$1"
  shift
  DESKTOP_ENTRY_REPLY=()
  mapfile -d '' -t DESKTOP_ENTRY_REPLY < <(python3 "$HYPR_SYSTEM_DIR/desktop-entry.py" "$mode" "$@")
  [[ "${DESKTOP_ENTRY_REPLY[0]:-}" == ok ]] && return 0
  printf '%s\n' "${DESKTOP_ENTRY_REPLY[1]:-Desktop entry resolution failed}" >&2
  return 1
}

desktop_entry_exec_tokenize_spec() {
  desktop_entry_exec_query tokenize "$1" || return
  DESKTOP_ENTRY_EXECUTABLE="${DESKTOP_ENTRY_REPLY[1]}"
  DESKTOP_ENTRY_ARGV=("${DESKTOP_ENTRY_REPLY[@]:2}")
}

desktop_entry_exec_resolve() {
  desktop_entry_exec_query resolve "$@" || return
  DESKTOP_ENTRY_WORKDIR="${DESKTOP_ENTRY_REPLY[1]}"
  DESKTOP_ENTRY_EXECUTABLE="${DESKTOP_ENTRY_REPLY[2]}"
  DESKTOP_ENTRY_ARGV=("${DESKTOP_ENTRY_REPLY[@]:3}")
}

#!/usr/bin/env bash

HYPR_SYSTEM_DIR="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system"

desktop_entry_exec_query_into() {
  local -n reply_ref="$1"
  local mode="$2"
  shift 2
  mapfile -d '' -t reply_ref < <(python3 "$HYPR_SYSTEM_DIR/desktop-entry.py" "$mode" "$@")
  [[ "${reply_ref[0]:-}" == ok ]] && return 0
  printf '%s\n' "${reply_ref[1]:-Desktop entry resolution failed}" >&2
  return 1
}

desktop_entry_exec_tokenize_spec_into() {
  local -n spec_argv_ref="$1"
  local -a tokenize_reply=()
  desktop_entry_exec_query_into tokenize_reply tokenize "$2" || return
  spec_argv_ref=("${tokenize_reply[@]:1}")
}

desktop_entry_exec_resolve_into() {
  local -n entry_argv_ref="$1" entry_workdir_ref="$2"
  local -a resolve_reply=()
  shift 2
  desktop_entry_exec_query_into resolve_reply resolve "$@" || return
  entry_workdir_ref="${resolve_reply[1]}"
  entry_argv_ref=("${resolve_reply[@]:2}")
}

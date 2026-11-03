#!/usr/bin/env bash

hypr_ensure_runtime_dir_into() {
  local -n runtime_dir_ref="$1"
  local subdir="${2:-}"

  runtime_dir_ref="${XDG_RUNTIME_DIR:-/run/user/${UID}}"
  if [[ -z "${runtime_dir_ref}" ]] || { [[ ! -d "${runtime_dir_ref}" ]] && ! mkdir -p "${runtime_dir_ref}" 2>/dev/null; }; then
    runtime_dir_ref="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/runtime"
    [[ -d "${runtime_dir_ref}" ]] || mkdir -p "${runtime_dir_ref}" || return 1
  fi

  [[ -n "${subdir}" ]] || return 0
  runtime_dir_ref+="/${subdir#/}"
  [[ -d "${runtime_dir_ref}" ]] || mkdir -p "${runtime_dir_ref}" || return 1
}

hypr_ensure_runtime_subdir() {
  local runtime_dir=""

  hypr_ensure_runtime_dir_into runtime_dir "${1:-}" || return 1
  printf '%s\n' "${runtime_dir}"
}

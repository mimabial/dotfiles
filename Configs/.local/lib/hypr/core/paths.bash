#!/usr/bin/env bash

hypr_runtime_root_dir() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/${UID}}"
  local fallback_dir=""

  if [[ -n "${runtime_dir}" ]] && { [[ -d "$runtime_dir" ]] || mkdir -p "$runtime_dir" 2>/dev/null; }; then
    printf '%s\n' "${runtime_dir}"
    return 0
  fi

  fallback_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/runtime"
  [[ -d "$fallback_dir" ]] || mkdir -p "$fallback_dir" || return 1
  printf '%s\n' "${fallback_dir}"
}

hypr_runtime_subdir() {
  local subdir="${1:-}"
  local runtime_root=""
  local target_dir=""

  runtime_root="$(hypr_runtime_root_dir)" || return 1
  if [[ -z "${subdir}" ]]; then
    printf '%s\n' "${runtime_root}"
    return 0
  fi

  target_dir="${runtime_root}/${subdir#/}"
  mkdir -p "${target_dir}" || return 1
  printf '%s\n' "${target_dir}"
}

#!/usr/bin/env bash

hypr_lock_manifest_file() {
  local lib_root="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}"
  printf '%s\n' "${lib_root}/runtime/lock_names.conf"
}

hypr_lock_runtime_dir() {
  printf '%s\n' "${XDG_RUNTIME_DIR:-/tmp}"
}

hypr_load_lock_manifest() {
  local manifest="${1:-$(hypr_lock_manifest_file)}"
  [[ -r "${manifest}" ]]
}

hypr_lock_template() {
  local key="$1"
  local manifest="${2:-$(hypr_lock_manifest_file)}"
  local template=""

  hypr_load_lock_manifest "${manifest}" || return 1
  template="$(awk -F= -v key="${key}" '
    $0 !~ /^[[:space:]]*#/ && $1 == key {
      print $2
      exit
    }
  ' "${manifest}")"
  [[ -n "${template}" ]] || return 1
  printf '%s\n' "${template}"
}

hypr_lock_path() {
  local key="$1"
  local template runtime_dir uid rendered

  template="$(hypr_lock_template "${key}")" || return 1
  runtime_dir="$(hypr_lock_runtime_dir)"
  uid="${UID:-$(id -u)}"
  rendered="${template//\{uid\}/${uid}}"

  printf '%s\n' "${runtime_dir}/${rendered}"
}

#!/usr/bin/env bash

hypr_hash_cache_command() {
  local candidate="${HYPR_HASH_COMMAND:-xxh64sum}"

  if command -v "${candidate}" >/dev/null 2>&1; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  for candidate in md5sum sha256sum; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

hypr_hash_cache_digest_files() {
  local hash_command=""

  hash_command="$(hypr_hash_cache_command)" || return 1
  cat "$@" 2>/dev/null | "${hash_command}" | awk '{print $1}'
}

hypr_hash_cache_digest_strings() {
  local hash_command=""

  hash_command="$(hypr_hash_cache_command)" || return 1
  printf '%s\n' "$@" | "${hash_command}" | awk '{print $1}'
}

hypr_hash_cache_is_current() {
  local hash_file="$1"
  local expected_hash="$2"
  local current_hash=""

  [[ -f "${hash_file}" ]] || return 1
  current_hash="$(cat "${hash_file}" 2>/dev/null || true)"
  [[ "${current_hash}" == "${expected_hash}" ]]
}

hypr_hash_cache_store() {
  local hash_file="$1"
  local value="$2"

  mkdir -p "$(dirname "${hash_file}")"
  printf '%s\n' "${value}" > "${hash_file}"
}

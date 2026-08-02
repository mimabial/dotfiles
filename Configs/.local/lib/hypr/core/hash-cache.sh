#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

_hypr_hash_cache_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F hypr_runtime_subdir >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_hypr_hash_cache_dir}/common.sh" || return 1 2>/dev/null || exit 1
fi
unset _hypr_hash_cache_dir

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

hypr_hash_cache_runtime_file() {
  local filename="$1"
  local runtime_dir=""

  [[ -n "${filename}" ]] || return 1
  runtime_dir="$(hypr_runtime_subdir hypr)" || return 1
  printf '%s/%s\n' "${runtime_dir}" "${filename}"
}

hypr_hash_cache_is_current() {
  local hash_file="$1"
  local expected_hash="$2"
  local current_hash=""

  # Honor --regen: callers that exported FORCE_COLOR_REGEN=1 want a forced
  # re-run, so report cache stale even if the hash matches.
  [[ "${FORCE_COLOR_REGEN:-0}" -eq 1 ]] && return 1
  [[ -f "${hash_file}" ]] || return 1
  current_hash="$(cat "${hash_file}" 2>/dev/null || true)"
  [[ "${current_hash}" == "${expected_hash}" ]]
}

hypr_hash_cache_store() {
  local hash_file="$1"
  local value="$2"

  # Honor --no-cache: callers that exported HYPR_WAL_CACHE_ENABLE=0 want no
  # cache writes (so the next plain run still recomputes).
  [[ "${HYPR_WAL_CACHE_ENABLE:-1}" -eq 0 ]] && return 0
  mkdir -p "$(dirname "${hash_file}")"
  printf '%s\n' "${value}" > "${hash_file}"
}

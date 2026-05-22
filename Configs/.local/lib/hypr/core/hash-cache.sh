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

hypr_hash_cache_file() {
  local filename="$1"
  local cache_root=""

  [[ -n "${filename}" ]] || return 1
  cache_root="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
  printf '%s/hash-cache/%s\n' "${cache_root}" "${filename}"
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

hypr_hash_cache_metadata_value() {
  local state_file="$1"
  local key="$2"

  [[ -f "${state_file}" && -n "${key}" ]] || return 1
  awk -F= -v key="${key}" '$1 == key {print substr($0, index($0, "=") + 1); exit}' "${state_file}"
}

hypr_hash_cache_metadata_matches() {
  local state_file="$1"
  shift

  local entry=""
  local key=""
  local expected=""
  local actual=""

  [[ -f "${state_file}" ]] || return 1

  for entry in "$@"; do
    key="${entry%%=*}"
    expected="${entry#*=}"
    actual="$(hypr_hash_cache_metadata_value "${state_file}" "${key}")" || return 1
    [[ "${actual}" == "${expected}" ]] || return 1
  done
}

hypr_hash_cache_metadata_store() {
  local state_file="$1"
  shift

  local state_dir=""
  local tmp_file=""
  local entry=""

  state_dir="$(dirname "${state_file}")"
  mkdir -p "${state_dir}" || return 1
  tmp_file="$(mktemp "${state_file}.XXXXXX")" || return 1

  {
    for entry in "$@"; do
      printf '%s\n' "${entry}"
    done
  } > "${tmp_file}"

  mv -f "${tmp_file}" "${state_file}"
}

hypr_hash_cache_output_is_fresh() {
  local output_file="$1"
  shift

  local input_file=""

  [[ -f "${output_file}" ]] || return 1

  for input_file in "$@"; do
    [[ -f "${input_file}" && "${input_file}" -nt "${output_file}" ]] && return 1
  done
}

hypr_hash_cache_outputs_current() {
  local hash_file="$1"
  local expected_hash="$2"
  local state_file="$3"
  shift 3

  # Mirror is_current's --regen honor so the mtime path below doesn't
  # silently keep stale outputs after a forced re-run.
  [[ "${FORCE_COLOR_REGEN:-0}" -eq 1 ]] && return 1

  local section="outputs"
  local item=""
  local -a outputs=()
  local -a inputs=()
  local -a metadata=()

  while (($#)); do
    case "$1" in
      --outputs) section="outputs" ;;
      --inputs) section="inputs" ;;
      --metadata) section="metadata" ;;
      *)
        case "${section}" in
          outputs) outputs+=("$1") ;;
          inputs) inputs+=("$1") ;;
          metadata) metadata+=("$1") ;;
        esac
        ;;
    esac
    shift
  done

  [[ ${#outputs[@]} -gt 0 ]] || return 1

  for item in "${outputs[@]}"; do
    hypr_hash_cache_output_is_fresh "${item}" "${inputs[@]}" || return 1
  done

  hypr_hash_cache_metadata_matches "${state_file}" "${metadata[@]}" || return 1
  hypr_hash_cache_is_current "${hash_file}" "${expected_hash}"
}

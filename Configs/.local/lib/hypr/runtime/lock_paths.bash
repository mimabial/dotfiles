#!/usr/bin/env bash

if ! declare -F hypr_ensure_runtime_dir_into >/dev/null 2>&1; then
  _hypr_lock_source_dir="${BASH_SOURCE[0]%/*}"
  [[ "${_hypr_lock_source_dir}" != "${BASH_SOURCE[0]}" ]] || _hypr_lock_source_dir=.
  # shellcheck source=/dev/null
  source "${_hypr_lock_source_dir}/../core/paths.bash" || return 1 2>/dev/null || exit 1
  unset _hypr_lock_source_dir
fi

hypr_lock_path_into() {
  local -n lock_path_ref="$1"
  local operation="$2"

  [[ -n "${operation}" ]] || return 1
  hypr_ensure_runtime_dir_into lock_path_ref || return 1
  lock_path_ref+="/${operation//_/-}.lock"
}

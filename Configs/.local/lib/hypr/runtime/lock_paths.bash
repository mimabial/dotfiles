#!/usr/bin/env bash

if ! declare -F hypr_ensure_runtime_root_dir >/dev/null 2>&1; then
  _hypr_lock_source_dir="${BASH_SOURCE[0]%/*}"
  [[ "${_hypr_lock_source_dir}" != "${BASH_SOURCE[0]}" ]] || _hypr_lock_source_dir=.
  # shellcheck source=/dev/null
  source "${_hypr_lock_source_dir}/../core/paths.bash" || return 1 2>/dev/null || exit 1
  unset _hypr_lock_source_dir
fi

hypr_lock_path_ensure_parent() {
  local operation="$1"
  local runtime_parent_dir=""

  [[ -n "${operation}" ]] || return 1
  runtime_parent_dir="$(hypr_ensure_runtime_root_dir)" || return 1
  printf '%s/%s.lock\n' "${runtime_parent_dir}" "${operation//_/-}"
}

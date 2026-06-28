#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"
# shellcheck source=/dev/null
source "${script_dir}/../core/common.sh"

hypr_help_guard "Usage: hyprshell service/show-managed-split [path...]
Show the managed/generated/per-host split for config paths (all when none given)." "$@"

manifest_path="$(hypr_service_manifest_path)"

current_domain=""
found=0

while IFS='|' read -r domain layer kind mode backup rel_path; do
  found=1
  if [[ "${domain}" != "${current_domain}" ]]; then
    [[ -n "${current_domain}" ]] && printf '\n'
    printf '%s\n' "${domain}"
    current_domain="${domain}"
  fi
  printf '  %-6s %-4s %-9s %-7s %s\n' "${layer}" "${kind}" "${mode}" "${backup}" "${rel_path}"
done < <(hypr_service_manifest_entries "${manifest_path}" "$@")

[[ "${found}" -eq 1 ]] || hypr_service_die "No manifest entries matched: $*"

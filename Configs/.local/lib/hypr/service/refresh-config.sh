#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

case "${1:-}" in
  -h|--help|help)
    hypr_service_usage_refresh_config
    exit 0
    ;;
esac

hypr_service_parse_refresh_args "$@"

if [[ "${#hypr_service_cli_args[@]}" -ne 1 ]]; then
  hypr_service_usage_refresh_config
  exit 1
fi

rel_path="${hypr_service_cli_args[0]}"
hypr_service_is_safe_relpath "${rel_path}" || hypr_service_die "Invalid config path: ${rel_path}"

hypr_service_init
hypr_service_apply_cli_env
hypr_service_refresh_config "${rel_path}" "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}"
hypr_service_maybe_report_backup_root

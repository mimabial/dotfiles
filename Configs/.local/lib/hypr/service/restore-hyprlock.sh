#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

case "${1:-}" in
  -h | --help)
    printf 'Usage: hyprshell service/restore-hyprlock.sh [--dry-run] [--quiet] [--diff|--no-diff] [--backup-label <name>]\n'
    exit 0
    ;;
esac

hypr_service_parse_refresh_args "$@"
[[ "${#hypr_service_cli_args[@]}" -eq 0 ]] || hypr_service_die "restore-hyprlock.sh does not take positional arguments."
[[ -n "${hypr_service_cli_backup_label}" ]] || hypr_service_cli_backup_label="restore-hyprlock"

hypr_service_init
hypr_service_apply_cli_env
hypr_service_restore_manifest_domains "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}" hyprlock
hypr_service_maybe_report_backup_root

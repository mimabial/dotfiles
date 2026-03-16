#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

case "${1:-}" in
  -h | --help)
    printf 'Usage: hyprshell service/refresh-hypridle.sh [--dry-run] [--quiet] [--diff|--no-diff] [--backup-label <name>]\n'
    exit 0
    ;;
esac

hypr_service_parse_refresh_args "$@"
[[ "${#hypr_service_cli_args[@]}" -eq 0 ]] || hypr_service_die "refresh-hypridle.sh does not take positional arguments."

hypr_service_init
hypr_service_apply_cli_env
hypr_service_refresh_manifest_domains "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}" hypridle
if [[ "${hypr_service_cli_dry_run}" -eq 0 ]]; then
  systemctl --user restart hyprland-hypridle.service >/dev/null 2>&1 || true
fi

hypr_service_maybe_report_backup_root

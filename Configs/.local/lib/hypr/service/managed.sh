#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell service/managed.sh --mode <refresh|restore> [options] <domain> [domain...]

Modes:
  refresh   honor manifest modes (preserve/overwrite/sync/trash)
  restore   overwrite managed targets from stock defaults, backing up first

Options:
  -n, --dry-run          preview without changing files
  -q, --quiet            suppress per-entry status lines
  --diff                 show unified diffs for changed managed files
  --no-diff              skip file diffs (default)
  --backup-label <name>  override backup folder suffix

Domains:
  hypr-config
  hypr-state
  hyprlock
  hypridle
  waybar
  rofi
USAGE
}

mode=""
declare -a forwarded_args=()
hypr_service_parse_mode_cli usage mode forwarded_args "$@"
hypr_service_validate_mode "${mode}" || {
  usage
  exit 1
}

hypr_service_parse_refresh_args "${forwarded_args[@]}"
[[ "${#hypr_service_cli_args[@]}" -gt 0 ]] || {
  usage
  exit 1
}

if [[ "${mode}" == "restore" && -z "${hypr_service_cli_backup_label}" ]]; then
  hypr_service_cli_backup_label="restore"
fi

hypr_service_init
hypr_service_apply_cli_env

case "${mode}" in
  refresh)
    hypr_service_refresh_manifest_domains "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}" "${hypr_service_cli_args[@]}"
    ;;
  restore)
    hypr_service_restore_manifest_domains "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}" "${hypr_service_cli_args[@]}"
    ;;
esac

hypr_service_maybe_report_backup_root

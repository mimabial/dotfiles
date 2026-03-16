#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell service/restore-managed.sh [options] <domain> [domain...]

Options:
  -n, --dry-run          preview without changing files
  -q, --quiet            suppress per-entry status lines
  --diff                 show unified diffs for changed managed files
  --no-diff              skip file diffs
  --backup-label <name>  override backup folder suffix

Restore semantics:
  - overwrite managed config/state from stock defaults
  - always back up changed existing targets before replacement
  - populate missing targets from stock defaults

Domains:
  hypr-config
  hypr-state
  hyprlock
  hypridle
  waybar
  rofi

Use hyprshell service/show-managed-split.sh to inspect managed targets.
USAGE
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

[[ "$#" -gt 0 ]] || {
  usage
  exit 1
}

hypr_service_parse_refresh_args "$@"
[[ "${#hypr_service_cli_args[@]}" -gt 0 ]] || {
  usage
  exit 1
}

if [[ -z "${hypr_service_cli_backup_label}" ]]; then
  hypr_service_cli_backup_label="restore"
fi

hypr_service_init
hypr_service_apply_cli_env
hypr_service_restore_manifest_domains "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}" "${hypr_service_cli_args[@]}"
hypr_service_maybe_report_backup_root

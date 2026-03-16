#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell service/refresh-managed.sh [options] <domain> [domain...]

Options:
  -n, --dry-run          preview without changing files
  -q, --quiet            suppress per-entry status lines
  --diff                 show unified diffs for changed managed files
  --no-diff              skip file diffs (default)
  --backup-label <name>  override backup folder suffix

Entries honor the manifest mode:
  preserve  - populate only when missing
  overwrite - replace managed files from template
  sync      - mirror managed directories from template
  trash     - remove target (backing it up first when configured)

Use restore-managed.sh when you want a destructive reset to stock defaults.

Backups are written under ~/.config/cfg_backups/<timestamp>_refresh/.

Domains:
  hypr-config
  hypr-state
  hyprlock
  hypridle
  waybar
  rofi

Use hyprshell service/show-managed-split.sh to inspect layer, mode, and backup policy.
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

hypr_service_init
hypr_service_apply_cli_env
hypr_service_refresh_manifest_domains "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}" "${hypr_service_cli_args[@]}"
hypr_service_maybe_report_backup_root

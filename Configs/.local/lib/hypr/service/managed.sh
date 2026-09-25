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
  rofi
USAGE
}

mode=""
declare -a forwarded_args=() cli_args=()
declare -A cli_options=()

hypr_service_parse_mode_cli usage mode forwarded_args "$@"
hypr_service_validate_mode "${mode}" || {
  usage
  exit 1
}

hypr_service_parse_refresh_args cli_options cli_args "${forwarded_args[@]}"
[[ "${#cli_args[@]}" -gt 0 ]] || {
  usage
  exit 1
}

if [[ "${mode}" == "restore" && -z "${cli_options[backup_label]}" ]]; then
  cli_options[backup_label]="restore"
fi

hypr_service_init
hypr_service_apply_cli_env "${cli_options[dry_run]}" "${cli_options[backup_label]}"

hypr_service_apply_manifest_domains "${mode}" "${cli_options[show_diff]}" "${cli_options[quiet]}" "${cli_args[@]}"

hypr_service_maybe_report_backup_root

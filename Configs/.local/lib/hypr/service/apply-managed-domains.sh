#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/managed/init.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell service/apply-managed-domains.sh --mode <refresh|restore> [options] <domain> [domain...]

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
  hyprlock
  hypridle
  rofi
USAGE
}

declare -a forwarded_args=() domains=()
declare -A run_options=()

managed_parse_mode_into run_options forwarded_args usage "$@"
managed_mode_is_valid "${run_options[mode]}" || {
  usage
  exit 1
}

managed_parse_options_into run_options domains "${forwarded_args[@]}"
[[ "${#domains[@]}" -gt 0 ]] || {
  usage
  exit 1
}

if [[ "${run_options[mode]}" == "restore" && -z "${run_options[backup_label]}" ]]; then
  run_options[backup_label]="restore"
fi

run_options[backup_label]="${run_options[backup_label]:-${domains[0]}}"
managed_visit_domains managed_apply_domain_entry run_options "${domains[@]}"
managed_print_backups run_options

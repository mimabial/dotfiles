#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/managed/init.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell service/apply-config.sh --mode <refresh|restore> [options] <relative-path-under-config>

Modes:
  refresh   overwrite a changed target from stock defaults, backing it up first
  restore   overwrite the target from ~/.local/share/hypr/default/

Options:
  -n, --dry-run          preview without changing files
  -q, --quiet            suppress per-entry status lines
  --diff                 show unified diffs for changed files
  --no-diff              skip file diffs
  --backup-label <name>  override backup folder suffix
USAGE
}

declare -a forwarded_args=() config_paths=()
declare -A run_options=()

managed_parse_mode_into run_options forwarded_args usage "$@"
managed_mode_is_valid "${run_options[mode]}" || {
  usage
  exit 2
}

managed_parse_options_into run_options config_paths "${forwarded_args[@]}"
[[ "${#config_paths[@]}" -eq 1 ]] || {
  usage
  exit 2
}

relative_path="${config_paths[0]}"

if [[ "${run_options[mode]}" == "restore" && -z "${run_options[backup_label]}" ]]; then
  run_options[backup_label]="restore-config"
fi

run_options[backup_label]="${run_options[backup_label]:-refresh}"
managed_apply_config run_options "${relative_path}"
managed_print_backups run_options

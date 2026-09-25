#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell service/config.sh --mode <refresh|restore> [options] <relative-path-under-config>

Modes:
  refresh   honor preserve semantics for a managed config file
  restore   overwrite the target from ~/.local/share/hypr/default/

Options:
  -n, --dry-run          preview without changing files
  -q, --quiet            suppress per-entry status lines
  --diff                 show unified diffs for changed files
  --no-diff              skip file diffs
  --backup-label <name>  override backup folder suffix
USAGE
}

mode=""
declare -a forwarded_args=() cli_args=()
declare -A cli_options=()

hypr_service_parse_mode_cli usage mode forwarded_args "$@"
hypr_service_validate_mode "${mode}" || {
  usage
  exit 2
}

hypr_service_parse_refresh_args cli_options cli_args "${forwarded_args[@]}"
[[ "${#cli_args[@]}" -eq 1 ]] || {
  usage
  exit 2
}

rel_path="${cli_args[0]}"
hypr_service_is_safe_relpath "${rel_path}" || hypr_service_die "Invalid config path: ${rel_path}"

if [[ "${mode}" == "restore" && -z "${cli_options[backup_label]}" ]]; then
  cli_options[backup_label]="restore-config"
fi

hypr_service_init
hypr_service_apply_cli_env "${cli_options[dry_run]}" "${cli_options[backup_label]}"

case "${mode}" in
  refresh)
    hypr_service_refresh_config "${rel_path}" "${cli_options[show_diff]}" "${cli_options[quiet]}"
    ;;
  restore)
    hypr_service_restore_config "${rel_path}" "${cli_options[show_diff]}" "${cli_options[quiet]}"
    ;;
esac

hypr_service_maybe_report_backup_root

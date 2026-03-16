#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell service/restore-config.sh [options] <relative-path-under-config>

Options:
  -n, --dry-run          preview without changing files
  -q, --quiet            suppress per-entry status lines
  --diff                 show unified diffs for changed files
  --no-diff              skip file diffs
  --backup-label <name>  override backup folder suffix

This restores one managed config file from ~/.local/share/hypr/default/.
USAGE
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

hypr_service_parse_refresh_args "$@"

[[ "${#hypr_service_cli_args[@]}" -eq 1 ]] || {
  usage
  exit 1
}

rel_path="${hypr_service_cli_args[0]}"
hypr_service_is_safe_relpath "${rel_path}" || hypr_service_die "Invalid config path: ${rel_path}"

if [[ -z "${hypr_service_cli_backup_label}" ]]; then
  hypr_service_cli_backup_label="restore-config"
fi

hypr_service_init
hypr_service_apply_cli_env

source_path="$(hypr_service_template_path "${rel_path}")"
target_path="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"
hypr_service_apply_file_mode "${source_path}" "${target_path}" "${rel_path}" overwrite always "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}"
hypr_service_maybe_report_backup_root

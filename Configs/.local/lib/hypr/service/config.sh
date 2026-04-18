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
declare -a forwarded_args=()

while (($#)); do
  case "$1" in
    --mode)
      shift
      [[ "$#" -gt 0 ]] || hypr_service_die "Missing value for --mode"
      mode="$1"
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    *)
      forwarded_args+=("$1")
      ;;
  esac
  shift
done

case "${mode}" in
  refresh | restore) ;;
  *)
    usage
    exit 1
    ;;
esac

hypr_service_parse_refresh_args "${forwarded_args[@]}"
[[ "${#hypr_service_cli_args[@]}" -eq 1 ]] || {
  usage
  exit 1
}

rel_path="${hypr_service_cli_args[0]}"
hypr_service_is_safe_relpath "${rel_path}" || hypr_service_die "Invalid config path: ${rel_path}"

if [[ "${mode}" == "restore" && -z "${hypr_service_cli_backup_label}" ]]; then
  hypr_service_cli_backup_label="restore-config"
fi

hypr_service_init
hypr_service_apply_cli_env

case "${mode}" in
  refresh)
    hypr_service_refresh_config "${rel_path}" "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}"
    ;;
  restore)
    source_path="$(hypr_service_template_path "${rel_path}")"
    target_path="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"
    hypr_service_apply_file_mode "${source_path}" "${target_path}" "${rel_path}" overwrite always "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}"
    ;;
esac

hypr_service_maybe_report_backup_root

#!/usr/bin/env bash
# Unified refresh/restore handler for a single domain with post-actions.
# Replaces the individual refresh-<domain>.sh and restore-<domain>.sh scripts.
#
# Usage:
#   hyprshell service/domain.sh refresh <domain> [options]
#   hyprshell service/domain.sh restore <domain> [options]
#
# Domains: hypr-config, hypr-state, hyprlock, hypridle, waybar, rofi
#
# Options:
#   -n, --dry-run          preview without changing files
#   -q, --quiet            suppress per-entry status lines
#   --diff / --no-diff     show/hide unified diffs
#   --backup-label <name>  override backup folder suffix

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell service/domain.sh <refresh|restore> <domain> [options]

Actions:
  refresh   populate managed files (preserve mode by default)
  restore   overwrite managed files from stock defaults (backs up first)

Domains:
  hypr-config   hypr-state   hyprlock   hypridle   waybar   rofi

Options:
  -n, --dry-run          preview without changing files
  -q, --quiet            suppress per-entry status lines
  --diff / --no-diff     show/hide unified diffs
  --backup-label <name>  override backup folder suffix
USAGE
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

[[ "$#" -ge 2 ]] || { usage; exit 1; }

action="$1"; shift
domain="$1"; shift

case "${action}" in
  refresh|restore) ;;
  -h|--help|help) usage; exit 0 ;;
  *) printf 'Unknown action: %s\n' "${action}" >&2; usage; exit 1 ;;
esac

case "${domain}" in
  hypr-config|hypr-state|hyprlock|hypridle|waybar|rofi) ;;
  -h|--help|help) usage; exit 0 ;;
  *) hypr_service_die "Unknown domain: ${domain}" ;;
esac

declare -a hypr_service_cli_args=()
hypr_service_cli_show_diff=0
hypr_service_cli_quiet=0
hypr_service_cli_dry_run=0
hypr_service_cli_backup_label=""

hypr_service_parse_refresh_args "$@"
[[ "${#hypr_service_cli_args[@]}" -eq 0 ]] || hypr_service_die "domain.sh does not take extra positional arguments."

if [[ "${action}" == "restore" ]]; then
  [[ -n "${hypr_service_cli_backup_label}" ]] || hypr_service_cli_backup_label="restore-${domain}"
fi

hypr_service_init
hypr_service_apply_cli_env

case "${action}" in
  refresh) hypr_service_refresh_manifest_domains "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}" "${domain}" ;;
  restore) hypr_service_restore_manifest_domains "${hypr_service_cli_show_diff}" "${hypr_service_cli_quiet}" "${domain}" ;;
esac

case "${domain}" in
  hypr-config|hypr-state)
    [[ "${hypr_service_cli_dry_run}" -ne 0 ]] || hyprctl reload >/dev/null 2>&1 || true
    ;;
  hypridle)
    [[ "${hypr_service_cli_dry_run}" -ne 0 ]] || systemctl --user restart hyprland-hypridle.service >/dev/null 2>&1 || true
    ;;
  rofi)
    [[ "${hypr_service_cli_dry_run}" -ne 0 ]] || pkill -x rofi >/dev/null 2>&1 || true
    ;;
  waybar)
    if [[ "${hypr_service_cli_dry_run}" -eq 0 ]]; then
      hyprshell waybar/waybar.py --update
    else
      [[ "${hypr_service_cli_quiet}" -eq 1 ]] || printf 'Dry run skipped: waybar wrapper rebuild\n'
    fi
    ;;
esac

hypr_service_maybe_report_backup_root

#!/usr/bin/env bash

set -euo pipefail

[[ -f /etc/arch-release ]] || exit 0

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_runtime_require system || exit 1

# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/packages/update-queries.bash"

update_cache_ttl_seconds="${HYPR_UPDATE_CACHE_TTL:-$((6 * 60 * 60))}"

hypr_help_guard "Usage: hyprshell system/package-updates [up [all|pacman|aur|flatpak]|--run-upgrade [source]|--refresh]
Report pending updates as bar JSON; 'up' opens an upgrade terminal.
Repeat calls inside ${update_cache_ttl_seconds}s reuse the cached report; --refresh forces a re-check." "$@"

update_runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
update_cache_path="${update_runtime_dir}/update_status.json"
update_database_dir=""
update_aur_helper=""
declare -a system_update_errors=()

source "${BASH_SOURCE[0]%/*}/packages/update-cache.bash"

if [[ "${1:-}" == "up" || "${1:-}" == "--run-upgrade" ]]; then
  case "${2:-all}" in
    all | pacman | aur | flatpak) ;;
    *) echo "Unknown update source: ${2}" >&2; exit 2 ;;
  esac
fi

if [[ "${1:-}" == "up" ]]; then
  updates_require_cached_report || exit 1
  exec hyprshell launch/terminal-present.sh --hypr-profile dialog --app-id "org.tui.SystemUpdate" --title "System Update" -- hyprshell system/package-updates.sh --run-upgrade "${2:-all}"
fi

if [[ "${1:-}" != "--refresh" && "${1:-}" != "--run-upgrade" ]] && [[ -s "${update_cache_path}" ]] \
  && ((EPOCHSECONDS - $(stat -c %Y "${update_cache_path}" 2>/dev/null || echo 0) < update_cache_ttl_seconds)) \
  && jq -e . >/dev/null 2>&1 <"${update_cache_path}"; then
  cat "${update_cache_path}"
  exit 0
fi

update_aur_helper="$(get_aur_helper 2>/dev/null || true)"

if [[ "${1:-}" == "--run-upgrade" ]]; then
  hypr_runtime_require state || exit 1
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/session/idle/state.bash"
  source "${HYPR_LIB_DIR}/session/idle/controller.bash"
  source "${BASH_SOURCE[0]%/*}/packages/upgrade.bash"
  upgrade_acquire_lock || exit 1
  upgrade_run "${2:-all}"
  exit $?
fi

source "${BASH_SOURCE[0]%/*}/packages/update-render.bash"
source "${BASH_SOURCE[0]%/*}/packages/update-report.bash"
updates_collect_report

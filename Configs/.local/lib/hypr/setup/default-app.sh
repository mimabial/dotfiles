#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_runtime_require state
source "${BASH_SOURCE[0]%/*}/default-apps/applications.bash"

default_app_usage() {
  printf 'Usage: hyprshell setup/default-app.sh agent|browser|terminal|editor [NAME]\n'
}

application_role="${1:-}"
selection="${2:-}"
if [[ -z "${selection}" ]]; then
  case "${application_role}" in
    -h | --help | help) default_app_usage ;;
    *) default_app_read "${application_role}" || { default_app_usage >&2; exit 2; } ;;
  esac
  exit 0
fi

declare -A application=()
default_app_lookup application "${application_role}" "${selection}" || { default_app_usage >&2; exit 2; }
if ! command -v "${application[command]}" >/dev/null 2>&1; then
  dunstify -u critical -i dialog-error "${application[display_name]} is not installed" "Install it before making it the default"
  exit 1
fi

source "${BASH_SOURCE[0]%/*}/default-apps/preferences.bash"
default_app_apply application
dunstify -t "${NOTIFY_MS}" -i preferences-system "Default ${application_role}" "${application[display_name]} is now the default ${application_role}"

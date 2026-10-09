#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell setup/migrate [--list]
Run the one-time migrations in setup/_migrations/ that this host has not run yet." "$@"

case "${1:-}" in
  "") list_only=false ;;
  --list) list_only=true ;;
  *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

migrations_dir="${BASH_SOURCE[0]%/*}/_migrations"
done_list="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/migrations-done"
mkdir -p "${done_list%/*}"
touch "${done_list}"

for migration in "${migrations_dir}"/*.sh; do
  [[ -f "${migration}" ]] || continue
  name="${migration##*/}"
  if grep -qxF -- "${name}" "${done_list}"; then status="done"; else status="pending"; fi
  if ${list_only}; then
    printf '%-8s %s\n' "${status}" "${name}"
    continue
  fi
  [[ "${status}" == pending ]] || continue
  printf 'Running migration %s\n' "${name}"
  bash "${migration}"
  printf '%s\n' "${name}" >>"${done_list}"
done

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

migration_directory="${BASH_SOURCE[0]%/*}/_migrations"
completed_migrations_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/migrations-done"
declare -A completed_migrations=()
if [[ -f "${completed_migrations_file}" ]]; then
  while IFS= read -r migration_name || [[ -n "${migration_name}" ]]; do
    [[ -z "${migration_name}" ]] || completed_migrations["${migration_name}"]=1
  done <"${completed_migrations_file}"
fi

for migration_script in "${migration_directory}"/*.sh; do
  [[ -f "${migration_script}" ]] || continue
  migration_name="${migration_script##*/}"
  if [[ -n "${completed_migrations[${migration_name}]:-}" ]]; then migration_status=done; else migration_status=pending; fi
  if ${list_only}; then
    printf '%-8s %s\n' "${migration_status}" "${migration_name}"
    continue
  fi
  [[ "${migration_status}" == pending ]] || continue
  printf 'Running migration %s\n' "${migration_name}"
  bash "${migration_script}"
  [[ -d "${completed_migrations_file%/*}" ]] || mkdir -p "${completed_migrations_file%/*}"
  printf '%s\n' "${migration_name}" >>"${completed_migrations_file}"
done

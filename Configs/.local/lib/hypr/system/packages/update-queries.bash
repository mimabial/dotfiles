#!/usr/bin/env bash
updates_query_repository() {
  local db="${1:-}"
  [[ -n "${db}" ]] || return 2
  env CHECKUPDATES_DB="${db}" checkupdates
}

updates_query_aur() {
  local helper="${1:-}"
  [[ -n "${helper}" ]] || return 2
  "${helper}" -Qua
}

updates_query_flatpak() {
  flatpak remote-ls --updates --columns=application,version,branch
}

updates_count_lines() {
  awk 'NF { count++ } END { print count + 0 }'
}

package_capture_updates() {
  set +e
  "$@"
  local rc=$?
  set -e
  case "${rc}" in
    0 | 1 | 2) return 0 ;;
    *) return "${rc}" ;;
  esac
}

package_list_updates() (
  local helper=""
  local temp_db=""
  trap '[[ -z "$temp_db" ]] || rm -rf -- "$temp_db"' EXIT

  if package_command_exists checkupdates; then
    temp_db="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pm-checkupdates.XXXXXX")"
    package_capture_updates updates_query_repository "${temp_db}" |
      awk 'NF { print "pacman\t" $0 }'
  fi

  if helper="$(package_aur_helper)"; then
    package_capture_updates updates_query_aur "${helper}" | awk 'NF { print "aur\t" $0 }'
  fi

  if package_command_exists flatpak; then
    package_capture_updates updates_query_flatpak |
      awk 'NF { print "flatpak\t" $0 }'
  fi
)

package_count_updates() {
  package_list_updates | updates_count_lines
}


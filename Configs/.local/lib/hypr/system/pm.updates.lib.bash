#!/usr/bin/env bash
pm_updates_repo_cmd() {
  local db="${1:-}"
  [[ -n "${db}" ]] || return 2
  env CHECKUPDATES_DB="${db}" checkupdates
}

pm_updates_aur_cmd() {
  local helper="${1:-}"
  [[ -n "${helper}" ]] || return 2
  "${helper}" -Qua
}

pm_updates_flatpak_cmd() {
  flatpak remote-ls --updates --columns=application,version,branch
}

pm_updates_count() {
  awk 'NF { count++ } END { print count + 0 }'
}

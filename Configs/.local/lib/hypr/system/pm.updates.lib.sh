#!/usr/bin/env bash
# Shared package-update queries for pm.sh (count/list-updates CLI) and
# system.update.sh (waybar widget). Each runs one source's query and writes its
# raw update lines to stdout; callers own exit-handling, labelling and format.
# checkupdates exits 2 when there are no updates -- both callers already treat
# 1/2 as "no updates", so these pass the exit code through unchanged.

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

# Count non-blank update lines from stdin. Serves the CLI (pipe the combined
# list in) and the widget (here-string a single source's captured list).
pm_updates_count() {
  awk 'NF { count++ } END { print count + 0 }'
}

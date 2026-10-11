STALE_UPDATE_DATABASE_AGE_MIN=10

updates_collect_report() {
# Quickshell SIGKILLs this provider on reload, so the traps below never run and
# each death leaks an 8.7M pacman db copy until $XDG_RUNTIME_DIR is full.
find "${XDG_RUNTIME_DIR:-/tmp}" -maxdepth 1 -type d -name 'checkupdates_db_*' -mmin "+${STALE_UPDATE_DATABASE_AGE_MIN}" \
  -exec rm -rf {} + 2>/dev/null || true
update_database_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-"/tmp"}/checkupdates_db_XXXXXX")
trap 'updates_remove_check_database "$?"' EXIT
trap 'updates_handle_signal 130' INT
trap 'updates_handle_signal 143' TERM

updates_capture_query_into repo_update_lines pacman updates_query_repository "$update_database_dir"
repo_update_count=$(updates_count_lines <<<"$repo_update_lines")

if [[ -n "${update_aur_helper}" ]]; then
  updates_capture_query_into aur_update_lines aur updates_query_aur "${update_aur_helper}"
  aur_update_count=$(updates_count_lines <<<"$aur_update_lines")
else
  aur_update_lines=""
  aur_update_count=0
fi

if pkg_installed flatpak; then
  updates_capture_query_into flatpak_update_lines flatpak updates_query_flatpak
  flatpak_update_count=$(updates_count_lines <<<"$flatpak_update_lines")
else
  flatpak_update_count=0
  flatpak_update_lines=""
fi

total_update_count=$((repo_update_count + aur_update_count + flatpak_update_count))

flatpak_updates="$(updates_format_flatpak_lines)"
if [[ "${#system_update_errors[@]}" -gt 0 && "$total_update_count" -eq 0 ]]; then
  updates_write_bar_report "" "$(updates_build_tooltip)" "error"
elif [[ "${#system_update_errors[@]}" -gt 0 ]]; then
  updates_write_bar_report "" "$(updates_build_tooltip)" "warning"
elif [ "$total_update_count" -eq 0 ]; then
  updates_write_bar_report "" " Packages are up to date" "up-to-date"
else
  updates_write_bar_report "" "$(updates_build_tooltip)" "updates"
fi
}

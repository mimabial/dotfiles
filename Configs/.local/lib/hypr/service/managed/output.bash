managed_fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

managed_print_status() {
  local -n output_run_ref="$1"
  local format="$2"
  shift 2
  # shellcheck disable=SC2059 # Callers pass constant format strings plus data args.
  [[ "${output_run_ref[quiet]}" -eq 1 ]] || printf -- "${format}" "$@"
}

managed_print_diff() {
  local -n diff_run_ref="$1"
  local relative_path="$2" before_path="$3" after_path="$4"
  [[ "${diff_run_ref[show_diff]}" -eq 1 ]] || return 0
  printf 'Changes for %s:\n' "${relative_path}"
  diff -u "${before_path}" "${after_path}" || true
}

managed_print_backups() {
  local -n backup_run_ref="$1"
  [[ "${backup_run_ref[dry_run]}" -eq 0 && -n "${backup_run_ref[backup_root]}" ]] || return 0
  printf 'Backups: %s\n' "${backup_run_ref[backup_root]}"
}

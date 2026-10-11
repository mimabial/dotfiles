managed_preserve_path() {
  local -n preserved_path_ref="$1" preserve_run_ref="$2"
  if [[ "${preserved_path_ref[target_exists]}" -eq 1 ]]; then
    managed_print_status "$2" 'Preserved: %s\n' "${preserved_path_ref[display]}"
  elif [[ "${preserve_run_ref[dry_run]}" -eq 1 ]]; then
    managed_print_status "$2" 'Would populate: %s\n' "${preserved_path_ref[display]}"
  else
    mkdir -p "${preserved_path_ref[target]%/*}"
    cp -a "${preserved_path_ref[source]}" "${preserved_path_ref[target]}"
    managed_print_status "$2" 'Populated: %s\n' "${preserved_path_ref[display]}"
  fi
}

managed_trash_path() {
  local -n trashed_path_ref="$1" trash_run_ref="$2"
  if [[ "${trashed_path_ref[target_exists]}" -eq 0 ]]; then
    managed_print_status "$2" 'Missing: %s\n' "${trashed_path_ref[display]}"
    return 0
  fi
  if [[ "${trash_run_ref[dry_run]}" -eq 1 ]]; then
    managed_backup_policy_is_enabled "${trashed_path_ref[backup_policy]}" "${trashed_path_ref[kind]}" &&
      managed_print_status "$2" 'Would back up: %s\n' "${trashed_path_ref[display]}"
    managed_print_status "$2" 'Would trash: %s\n' "${trashed_path_ref[display]}"
    return 0
  fi
  if managed_backup_policy_is_enabled "${trashed_path_ref[backup_policy]}" "${trashed_path_ref[kind]}"; then
    managed_back_up_path_into "$1" "$2"
  fi
  rm -rf "${trashed_path_ref[target]}"
  managed_print_status "$2" 'Trashed: %s\n' "${trashed_path_ref[display]}"
}

managed_overwrite_file() {
  local -n overwritten_path_ref="$1" overwrite_run_ref="$2"
  if [[ "${overwritten_path_ref[target_exists]}" -eq 1 ]] && cmp -s "${overwritten_path_ref[source]}" "${overwritten_path_ref[target]}"; then
    managed_print_status "$2" 'Unchanged: %s\n' "${overwritten_path_ref[display]}"
    return 0
  fi
  if [[ "${overwrite_run_ref[dry_run]}" -eq 1 ]]; then
    if [[ "${overwritten_path_ref[target_exists]}" -eq 0 ]]; then
      managed_print_status "$2" 'Would populate: %s\n' "${overwritten_path_ref[display]}"
      return 0
    fi
    if managed_backup_policy_is_enabled "${overwritten_path_ref[backup_policy]}" file; then
      managed_print_status "$2" 'Would back up: %s\n' "${overwritten_path_ref[display]}"
    fi
    managed_print_status "$2" 'Would overwrite: %s\n' "${overwritten_path_ref[display]}"
    managed_print_diff "$2" "${overwritten_path_ref[relative_path]}" "${overwritten_path_ref[target]}" "${overwritten_path_ref[source]}"
    return 0
  fi
  if [[ "${overwritten_path_ref[target_exists]}" -eq 1 ]] && managed_backup_policy_is_enabled "${overwritten_path_ref[backup_policy]}" file; then
    managed_back_up_path_into "$1" "$2"
  fi
  mkdir -p "${overwritten_path_ref[target]%/*}"
  cp -a "${overwritten_path_ref[source]}" "${overwritten_path_ref[target]}"
  if [[ "${overwritten_path_ref[target_exists]}" -eq 1 ]]; then
    managed_print_status "$2" 'Overwritten: %s\n' "${overwritten_path_ref[display]}"
  else
    managed_print_status "$2" 'Populated: %s\n' "${overwritten_path_ref[display]}"
  fi
  if [[ -n "${overwritten_path_ref[backup_path]}" && -f "${overwritten_path_ref[backup_path]}" ]]; then
    managed_print_diff "$2" "${overwritten_path_ref[relative_path]}" "${overwritten_path_ref[backup_path]}" "${overwritten_path_ref[target]}"
  fi
  return 0
}

managed_sync_tree() {
  local -n synced_path_ref="$1" sync_run_ref="$2"
  local sync_plan=""
  sync_plan="$(rsync -ani --delete "${synced_path_ref[source]}/" "${synced_path_ref[target]}/")" ||
    managed_fail "Failed to compare directory ${synced_path_ref[source]} -> ${synced_path_ref[target]}"
  if [[ -z "${sync_plan}" ]]; then
    managed_print_status "$2" 'Unchanged: %s\n' "${synced_path_ref[display]}"
    return 0
  fi
  if [[ "${sync_run_ref[dry_run]}" -eq 1 ]]; then
    if [[ "${synced_path_ref[target_exists]}" -eq 1 ]] && managed_backup_policy_is_enabled "${synced_path_ref[backup_policy]}" tree; then
      managed_print_status "$2" 'Would back up: %s\n' "${synced_path_ref[display]}"
    fi
    managed_print_status "$2" 'Would sync: %s\n' "${synced_path_ref[display]}"
    managed_print_status "$2" '%s\n' "${sync_plan}"
    return 0
  fi
  if [[ "${synced_path_ref[target_exists]}" -eq 1 ]] && managed_backup_policy_is_enabled "${synced_path_ref[backup_policy]}" tree; then
    managed_back_up_path_into "$1" "$2"
  fi
  mkdir -p "${synced_path_ref[target]}"
  rsync -a --delete "${synced_path_ref[source]}/" "${synced_path_ref[target]}/" || managed_fail "Failed to sync directory ${synced_path_ref[relative_path]}"
  managed_print_status "$2" 'Synced: %s\n' "${synced_path_ref[display]}"
}

managed_apply_path() {
  local -n applied_path_ref="$1"
  if [[ "${applied_path_ref[operation]}" != trash ]]; then
    case "${applied_path_ref[kind]}" in
      file) [[ -f "${applied_path_ref[source]}" ]] || managed_fail "No template found for ${applied_path_ref[relative_path]}: ${applied_path_ref[source]}" ;;
      tree) [[ -d "${applied_path_ref[source]}" ]] || managed_fail "No template directory found for ${applied_path_ref[relative_path]}: ${applied_path_ref[source]}" ;;
    esac
  fi
  case "${applied_path_ref[kind]}:${applied_path_ref[operation]}" in
    file:preserve | tree:preserve) managed_preserve_path "$1" "$2" ;;
    file:trash | tree:trash) managed_trash_path "$1" "$2" ;;
    file:overwrite) managed_overwrite_file "$1" "$2" ;;
    tree:sync) managed_sync_tree "$1" "$2" ;;
    *) managed_fail "Unsupported ${applied_path_ref[kind]} mode: ${applied_path_ref[operation]} (${applied_path_ref[relative_path]})" ;;
  esac
}

managed_apply_config() {
  local -n config_run_ref="$1"
  local relative_path="$2"
  managed_relative_path_is_valid "${relative_path}" || managed_fail "Invalid config path: ${relative_path}"
  local -A config_path=([layer]=config [kind]=file [relative_path]="${relative_path}" [operation]=overwrite [backup_policy]=changed)
  [[ "${config_run_ref[mode]}" != restore ]] || config_path[backup_policy]=always
  managed_resolve_paths_into config_path
  managed_apply_path config_path "$1"
}

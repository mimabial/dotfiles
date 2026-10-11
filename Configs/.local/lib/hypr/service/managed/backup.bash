managed_backup_policy_is_enabled() {
  local backup_policy="$1" kind="$2"
  case "${backup_policy}" in
    always | changed) return 0 ;;
    never) return 1 ;;
    *) managed_fail "Unsupported backup policy for ${kind}: ${backup_policy}" ;;
  esac
}

managed_back_up_path_into() {
  local -n backup_path_ref="$1" backup_run_ref="$2"
  local label="${backup_run_ref[backup_label]}" target_suffix="${backup_path_ref[target]}"
  [[ -e "${target_suffix}" || -L "${target_suffix}" ]] || return 1
  if [[ -z "${backup_run_ref[backup_root]}" ]]; then
    label="${label//[^A-Za-z0-9._-]/-}"
    backup_run_ref[backup_root]="${XDG_CONFIG_HOME:-$HOME/.config}/cfg_backups/$(date +%Y%m%d_%H%M%S)_${label}"
  fi
  case "${target_suffix}" in
    "${HOME}") target_suffix=/ ;;
    "${HOME}/"*) target_suffix="${target_suffix#"${HOME}"}" ;;
  esac
  backup_path_ref[backup_path]="${backup_run_ref[backup_root]}${target_suffix}"
  mkdir -p "${backup_path_ref[backup_path]%/*}"
  rm -rf "${backup_path_ref[backup_path]}"
  cp -a "${backup_path_ref[target]}" "${backup_path_ref[backup_path]}"
}

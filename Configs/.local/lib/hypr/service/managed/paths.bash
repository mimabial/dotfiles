managed_relative_path_is_valid() {
  local relative_path="$1"
  [[ -n "${relative_path}" && "${relative_path}" != /* && "${relative_path}" != *".."* ]]
}

managed_resolve_paths_into() {
  local -n resolved_path_ref="$1"
  [[ "${resolved_path_ref[layer]}" == config ]] || managed_fail "Unsupported layer: ${resolved_path_ref[layer]}"
  resolved_path_ref[source]="${XDG_DATA_HOME:-$HOME/.local/share}/hypr/default/${resolved_path_ref[relative_path]}"
  resolved_path_ref[target]="${XDG_CONFIG_HOME:-$HOME/.config}/${resolved_path_ref[relative_path]}"
  resolved_path_ref[display]="${resolved_path_ref[target]}"
  resolved_path_ref[target_exists]=0
  resolved_path_ref[backup_path]=""
  case "${resolved_path_ref[kind]}" in
    file)
      [[ -e "${resolved_path_ref[target]}" || -L "${resolved_path_ref[target]}" ]] && resolved_path_ref[target_exists]=1
      ;;
    tree)
      [[ -d "${resolved_path_ref[target]}" ]] && resolved_path_ref[target_exists]=1
      resolved_path_ref[display]+=/
      ;;
  esac
  return 0
}

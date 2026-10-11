package_error() {
  printf '%s: %s\n' "${0##*/}" "$1" >&2
  exit 1
}

package_require_arguments() {
  (($# > 0)) || package_error "missing argument"
}

package_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

package_parse_arguments() {
  while (($# > 0)); do
    case "$1" in
      --pm)
        (($# >= 2)) || package_error "missing value for --pm"
        requested_package_manager="$2"
        shift 2
        ;;
      --noconfirm | --no-confirm)
        skip_confirmation=1
        shift
        ;;
      -h | --help | help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        package_error "unknown flag: $1"
        ;;
      *)
        break
        ;;
    esac
  done

  (($# > 0)) || {
    usage
    exit 0
  }
  package_command="$1"
  shift
  package_arguments=("$@")
}

package_dispatch() {
  case "${package_command}" in
    add)
      skip_confirmation=1
      package_install_repository "${package_arguments[@]}"
      ;;
    aur-add)
      skip_confirmation=1
      package_install_aur "${package_arguments[@]}"
      ;;
    install | install-repo | i)
      if ((${#package_arguments[@]} == 0)); then package_pick_repository_install; else package_install_repository "${package_arguments[@]}"; fi
      ;;
    install-aur)
      if ((${#package_arguments[@]} == 0)); then package_pick_aur_install; else package_install_aur "${package_arguments[@]}"; fi
      ;;
    remove | r)
      if ((${#package_arguments[@]} == 0)); then package_pick_removal; else package_remove "${package_arguments[@]}"; fi
      ;;
    upgrade | u) package_upgrade_all ;;
    fetch | f) package_fetch_metadata ;;
    info | n) package_show_info "${package_arguments[@]}" ;;
    list | l) package_list "${package_arguments[@]}" ;;
    la) package_list all ;;
    li) package_list installed ;;
    query | pq) package_is_installed "${package_arguments[@]}" ;;
    file-query | fq) package_query_file_owner "${package_arguments[@]}" ;;
    count-updates | cu) package_count_updates ;;
    list-updates | lu) package_list_updates ;;
    clean-cache) package_clean_cache ;;
    remove-orphans) package_remove_orphans ;;
    which) package_selected_manager ;;
    which-aur) package_aur_helper || package_error "no AUR helper found; install yay or paru" ;;
    help | h | -h | --help) usage ;;
    *) package_error "unknown command: ${package_command}" ;;
  esac
}


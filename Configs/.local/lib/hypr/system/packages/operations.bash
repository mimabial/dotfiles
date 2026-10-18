package_aur_helper() {
  [[ "${requested_package_manager}" == pacman ]] && return 1

  if [[ -n "${requested_package_manager}" && "${requested_package_manager}" != pacman ]]; then
    package_command_exists "${requested_package_manager}" || package_error "package manager not found: ${requested_package_manager}"
    printf '%s\n' "${requested_package_manager}"
    return 0
  fi
  if package_command_exists yay; then
    printf 'yay\n'
  elif package_command_exists paru; then
    printf 'paru\n'
  else
    return 1
  fi
}

package_selected_manager() {
  local helper=""
  if [[ -n "${requested_package_manager}" ]]; then
    package_command_exists "${requested_package_manager}" || package_error "package manager not found: ${requested_package_manager}"
    printf '%s\n' "${requested_package_manager}"
  elif helper="$(package_aur_helper)"; then
    printf '%s\n' "${helper}"
  else
    printf 'pacman\n'
  fi
}

package_confirmation_flags_into() {
  local out_name="$1"
  local -n out_ref="${out_name}"
  out_ref=()
  ((skip_confirmation == 1)) && out_ref+=(--noconfirm)
  return 0
}

package_run_pacman() {
  if [[ -t 0 && -t 1 ]] && package_command_exists sudo; then
    sudo pacman "$@"
  elif package_command_exists pkexec; then
    pkexec pacman "$@"
  elif package_command_exists sudo; then
    sudo pacman "$@"
  else
    package_error "neither sudo nor pkexec is available"
  fi
}

package_install_repository() {
  package_require_arguments "$@"
  local -a flags=(--needed)
  ((skip_confirmation == 1)) && flags+=(--noconfirm)
  package_run_pacman -S "${flags[@]}" -- "$@"
}

package_install_aur() {
  package_require_arguments "$@"
  local helper=""
  local -a flags=(--aur --needed)
  helper="$(package_aur_helper)" || package_error "no AUR helper found; install yay or paru"
  ((skip_confirmation == 1)) && flags+=(--noconfirm)
  "${helper}" -S "${flags[@]}" -- "$@"
}

package_remove() {
  package_require_arguments "$@"
  local -a flags=()
  package_confirmation_flags_into flags
  package_run_pacman -Rns "${flags[@]}" -- "$@"
}

package_upgrade() {
  local update_source="${1:-all}" helper=""
  local -a flags=()
  package_confirmation_flags_into flags

  case "${update_source}" in
    all | pacman)
      if [[ "${update_source}" == all ]] && helper="$(package_aur_helper)"; then
        "${helper}" -Syu "${flags[@]}" || return
      else
        package_run_pacman -Syu "${flags[@]}" || return
      fi
      ;;
    aur)
      helper="$(package_aur_helper)" || package_error "no AUR helper found; install yay or paru"
      "${helper}" -Sua "${flags[@]}" || return
      ;;
    flatpak)
      package_command_exists flatpak || package_error "flatpak is not installed"
      ;;
    *) package_error "unknown update source: ${update_source}" ;;
  esac

  if [[ "${update_source}" == flatpak ]] || { [[ "${update_source}" == all ]] && package_command_exists flatpak; }; then
    flags=()
    ((skip_confirmation == 1)) && flags+=(-y)
    flatpak update "${flags[@]}" || return
  fi
  [[ "${update_source}" == flatpak ]] || package_review_orphans
}

package_fetch_metadata() {
  local helper=""
  if helper="$(package_aur_helper)"; then
    "${helper}" -Sy
  else
    package_run_pacman -Sy
  fi
  if package_command_exists flatpak; then flatpak update --appstream; fi
}

package_show_info() {
  package_require_arguments "$@"
  local helper=""
  if helper="$(package_aur_helper)"; then
    "${helper}" -Si --color=auto "$1"
  else
    pacman -Si --color=auto "$1"
  fi
}

package_list() {
  case "${1:-}" in
    all) pacman -Sl --color=never ;;
    installed) pacman -Q --color=never ;;
    *) package_error "expected list scope: all or installed" ;;
  esac
}

package_is_installed() {
  package_require_arguments "$@"
  if pacman -Q "$1" >/dev/null 2>&1; then
    printf 'Installed\n'
    return 0
  fi
  printf 'Not installed\n'
  return 1
}

package_query_file_owner() {
  package_require_arguments "$@"
  pacman -F -- "$1"
}

package_clean_cache() {
  local helper=""
  if helper="$(package_aur_helper)"; then
    "${helper}" -Sc
  else
    package_run_pacman -Sc
  fi
}

package_review_orphans() {
  local -a orphans=()
  local reply=""

  mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
  ((${#orphans[@]})) || return 0

  printf '\nOrphaned packages (%s):\n' "${#orphans[@]}"
  printf '  %s\n' "${orphans[@]}"
  if ((skip_confirmation == 0)); then
    [[ -t 0 ]] || return 0
    read -r -p "Remove them? [y/N] " reply || return 0
    [[ "${reply}" =~ ^[Yy] ]] || return 0
  fi
  package_remove "${orphans[@]}"
}

package_remove_orphans() {
  local -a orphans=()
  mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
  ((${#orphans[@]} == 0)) && {
    printf 'No orphaned packages.\n'
    return 0
  }
  package_remove "${orphans[@]}"
}


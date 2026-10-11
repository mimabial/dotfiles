package_pick_with_preview() {
  local preview="$1"
  local color="$2"
  shift 2
  package_command_exists fzf || package_error "fzf is not installed"
  fzf \
    --multi \
    --preview="${preview}" \
    --preview-window=down:65%:wrap \
    --bind=alt-p:toggle-preview \
    --bind=alt-j:preview-down,alt-k:preview-up \
    --bind=alt-d:preview-half-page-down,alt-u:preview-half-page-up \
    --color="pointer:${color},marker:${color}" \
    "$@"
}

package_aur_names() {
  case "$1" in
    yay) yay -Pc | awk '{ print $1 }' ;;
    paru) paru -Slq aur ;;
  esac
}

package_pick_repository_install() {
  local -a selected=()
  mapfile -t selected < <(pacman -Slq | package_pick_with_preview 'pacman -Sii -- {1}' green)
  ((${#selected[@]} == 0)) && return 0
  skip_confirmation=1
  package_install_repository "${selected[@]}"
}

package_pick_aur_install() {
  local helper=""
  local -a selected=()
  helper="$(package_aur_helper)" || package_error "no AUR helper found; install yay or paru"
  mapfile -t selected < <(
    package_aur_names "${helper}" |
      package_pick_with_preview \
        "${helper} -Sii --aur -- {1}" \
        green \
        --bind="alt-b:change-preview:${helper} -Gp -- {1} | tail -n +5" \
        --bind="alt-B:change-preview:${helper} -Sii --aur -- {1}"
  )
  ((${#selected[@]} == 0)) && return 0
  skip_confirmation=1
  package_install_aur "${selected[@]}"
}

package_pick_removal() {
  local -a selected=()
  mapfile -t selected < <(pacman -Qqe | package_pick_with_preview 'pacman -Qi -- {1}' red)
  ((${#selected[@]} == 0)) && return 0
  package_remove "${selected[@]}"
}


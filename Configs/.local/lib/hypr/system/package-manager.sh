#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'HELP'
Usage: package-manager.sh [--pm yay|paru|pacman] [--noconfirm] <command> [args...]

Commands:
  add <pkg...>             Install repo packages with pacman, --needed --noconfirm
  aur-add <pkg...>         Install AUR packages with yay/paru, --needed --noconfirm
  install, i [pkg...]      Install repo packages; fzf selector when empty
  install-repo [pkg...]    Alias for install
  install-aur [pkg...]     Install AUR packages; fzf selector when empty
  remove, r [pkg...]       Remove packages; fzf selector when empty
  upgrade, u [source]      Upgrade all (default), pacman, aur, or flatpak
  fetch, f                 Refresh package metadata
  info, n <pkg>            Show package information
  list, l all|installed    List repo or installed packages
  la, li                   Shortcuts for list all / installed
  query, pq <pkg>          Check whether a package is installed
  file-query, fq <file>    Query the package owning a file
  count-updates, cu        Count pending repo/AUR/Flatpak updates
  list-updates, lu         List pending repo/AUR/Flatpak updates
  clean-cache              Clean package caches
  remove-orphans           Remove orphaned packages
  which                    Print selected package manager
  which-aur                Print preferred AUR helper
HELP
}

skip_confirmation=0 requested_package_manager="" package_command=""
package_arguments=()
source "${BASH_SOURCE[0]%/*}/packages/command.bash"
source "${BASH_SOURCE[0]%/*}/packages/operations.bash"
source "${BASH_SOURCE[0]%/*}/packages/update-queries.bash"

package_parse_arguments "$@"
case "$package_command" in
  install | install-repo | i | install-aur | remove | r)
    ((${#package_arguments[@]})) || source "${BASH_SOURCE[0]%/*}/packages/picker.bash"
    ;;
esac
package_dispatch

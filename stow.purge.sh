#!/usr/bin/env bash

set -euo pipefail

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

packages=(
  alacritty
  cava
  fastfetch
  gtk
  hypr
  hypr-lib
  hypr-share
  kde
  kitty
  kvantum
  rmpc
  rofi
  share
  scripts
  systemd
  starship
  swaync
  tmux
  uwsm
  wal
  waybar
  wlogout
  zsh
)

purge_package_targets() {
  local pkg="$1"
  local pkg_dir="$dotfiles_dir/$pkg"
  local removed=0
  local verbose="${STOW_VERBOSE:-1}"

  [[ -d "$pkg_dir" ]] || return 0

  if [[ "$verbose" -ne 0 ]]; then
    echo "Purging targets for ${pkg}..."
  fi

  purge_children() {
    local rel_root="$1"
    local pkg_root="$pkg_dir/$rel_root"
    local target_root="$HOME/$rel_root"
    local path=""
    local rel=""
    local target=""

    [[ -d "$pkg_root" ]] || return 0

    while IFS= read -r -d '' path; do
      rel="${path#"$pkg_root"/}"
      target="$target_root/$rel"

      if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$verbose" -ne 0 ]]; then
          if [[ -d "$target" && ! -L "$target" ]]; then
            echo "Removing dir: $target"
          else
            echo "Removing: $target"
          fi
        fi
        rm -rf -- "$target"
        removed=$((removed + 1))
      fi
    done < <(find "$pkg_root" -mindepth 1 -maxdepth 1 -print0)
  }

  purge_children ".config"
  purge_children ".local/bin"
  purge_children ".local/lib"
  purge_children ".local/libexec"
  purge_children ".local/share"
  purge_children ".local/state"
  purge_children ".cache"
  purge_children ".icons"
  purge_children ".themes"

  if [[ "$verbose" -ne 0 ]]; then
    echo "Removed ${removed} paths for ${pkg}."
  fi
}

for pkg in "${packages[@]}"; do
  purge_package_targets "$pkg"
done

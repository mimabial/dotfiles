#!/usr/bin/env bash

set -euo pipefail

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

packages=(
  alacritty
  cava
  fastfetch
  hypr
  hypr-lib
  hypr-share
  kde
  kitty
  kvantum
  rmpc
  rofi
  scripts
  starship
  swaync
  tmux
  wal
  waybar
  wlogout
  zsh
)

tmux_package="tmux"
packages_no_tmux=()
for pkg in "${packages[@]}"; do
  [[ "$pkg" == "$tmux_package" ]] && continue
  packages_no_tmux+=("$pkg")
done

stow --dir="$dotfiles_dir" --target="$HOME" "${packages_no_tmux[@]}"

tmux_config_dir="$HOME/.config/tmux"
mkdir -p "$tmux_config_dir" "$tmux_config_dir/plugins"
stow --dir="$dotfiles_dir" --target="$HOME" --no-folding "$tmux_package"

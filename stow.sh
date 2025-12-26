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

stow --dir="$dotfiles_dir" --target="$HOME" "${packages[@]}"

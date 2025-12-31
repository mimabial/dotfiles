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

systemd_units=(
  auto-theme.service
  elephant.service
  hypr-config.service
  hypr-ipc.service
  hyprland-hypridle.service
  hyprland-keep-awake.service
  inhibit-idle-on-audio.service
  zsh-zcompdump-clean.timer
)

enable_user_units() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not found; skipping user unit enablement."
    return 0
  fi

  if ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "systemd user instance not available; run:"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user preset ${systemd_units[*]}"
    echo "  systemctl --user start ${systemd_units[*]}"
    return 0
  fi

  systemctl --user daemon-reload

  if ! systemctl --user preset "${systemd_units[@]}"; then
    echo "Failed to apply user unit presets."
    return 0
  fi

  if systemctl --user -q is-active graphical-session.target >/dev/null 2>&1; then
    if ! systemctl --user start "${systemd_units[@]}"; then
      echo "Some user units failed to start; check systemctl --user status."
    fi
    return 0
  fi

  if ! systemctl --user start zsh-zcompdump-clean.timer; then
    echo "Timer failed to start; check systemctl --user status."
  fi
  echo "graphical-session.target not active; graphical units will start on next login."
}

enable_user_units

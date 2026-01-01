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

stow_backup_root="${STOW_BACKUP_ROOT:-}"
if [[ -z "$stow_backup_root" ]]; then
  stow_backup_root="$HOME/.local/state/dotfiles-stow-backup"
fi
stow_backup_dir=""

link_points_to_expected() {
  local target="$1"
  local expected="$2"
  local resolved_target=""
  local resolved_expected=""

  resolved_target="$(readlink -f "$target" 2>/dev/null || true)"
  resolved_expected="$(readlink -f "$expected" 2>/dev/null || true)"

  [[ -n "$resolved_target" ]] && [[ -n "$resolved_expected" ]] && [[ "$resolved_target" == "$resolved_expected" ]]
}

ensure_backup_dir() {
  if [[ -z "$stow_backup_dir" ]]; then
    stow_backup_dir="$stow_backup_root/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$stow_backup_dir"
    echo "Backing up conflicting paths to $stow_backup_dir"
  fi
}

backup_target_path() {
  local target="$1"
  local rel="$2"
  local dest=""

  ensure_backup_dir

  dest="$stow_backup_dir/$rel"
  mkdir -p "$(dirname "$dest")"
  mv "$target" "$dest"
}

override_stow_targets() {
  local pkg="$1"
  local pkg_dir="$dotfiles_dir/$pkg"

  [[ -d "$pkg_dir" ]] || return 0

  local path=""
  local rel=""
  local target=""
  while IFS= read -r -d '' path; do
    rel="${path#"$pkg_dir"/}"
    target="$HOME/$rel"

    if [[ -L "$target" ]] && link_points_to_expected "$target" "$path"; then
      continue
    fi

    if [[ -e "$target" || -L "$target" ]]; then
      backup_target_path "$target" "$rel"
    fi
  done < <(find "$pkg_dir" -mindepth 1 \( -type f -o -type l \) -print0)
}

for pkg in "${packages[@]}"; do
  override_stow_targets "$pkg"
done

stow --restow --dir="$dotfiles_dir" --target="$HOME" "${packages_no_tmux[@]}"

tmux_config_dir="$HOME/.config/tmux"
mkdir -p "$tmux_config_dir" "$tmux_config_dir/plugins"
stow --restow --dir="$dotfiles_dir" --target="$HOME" --no-folding "$tmux_package"

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

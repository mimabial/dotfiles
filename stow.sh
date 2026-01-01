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

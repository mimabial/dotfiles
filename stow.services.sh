#!/usr/bin/env bash

set -euo pipefail

systemd_units=(
  auto-theme.service
  elephant.service
  hypr-config.service
  hypr-ipc.service
  hyprland-hypridle.service
  hyprland-idle-manager.service
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

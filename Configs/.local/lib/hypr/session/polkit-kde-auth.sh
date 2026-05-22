#!/usr/bin/env bash
#
# polkit-kde-auth.sh — Start the first available polkit authentication agent.
#
# Usage:
#   polkit-kde-auth.sh
#
# Depends on: any installed polkit authentication agent
#

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1

candidates=(
  # Hyprland-native (preferred under Hyprland)
  /usr/libexec/hyprpolkitagent
  /usr/lib/hyprpolkitagent
  /usr/lib/hyprpolkitagent/hyprpolkitagent

  # KDE (Arch)
  /usr/lib/polkit-kde-authentication-agent-1
  # KDE (Debian/Ubuntu)
  /usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1
  /usr/libexec/polkit-kde-authentication-agent-1

  # GNOME
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
  /usr/libexec/polkit-gnome-authentication-agent-1
  /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1
  /usr/lib/polkit-gnome-authentication-agent-1
  /usr/bin/polkit-gnome-authentication-agent-1

  # MATE / LXQt / XFCE / Cinnamon / Deepin
  /usr/libexec/polkit-mate-authentication-agent-1
  /usr/bin/lxqt-policykit-agent
  /usr/libexec/xfce-polkit
  /usr/lib/cinnamon-polkit-agent
  /usr/lib/polkit-1-dde/dde-polkit-agent
)

for agent in "${candidates[@]}"; do
  if [[ -f "${agent}" && -x "${agent}" ]]; then
    exec "${agent}"
  fi
done

printf 'polkit-kde-auth: no polkit authentication agent found on this system\n' >&2
exit 1

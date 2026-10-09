#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell setup/hide-launcher-entries
Hide system clutter from the app launcher; the apps stay launchable and keep their file associations." "$@"

launcher_clutter=(avahi-discover bssh bvnc cmake-gui cups 'jconsole-*' 'jshell-*' lstopo nm-connection-editor nvim qv4l2 qvidcap vim)
user_applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

mkdir -p "${user_applications}"
for desktop_id in "${launcher_clutter[@]}"; do
  for entry in /usr/share/applications/${desktop_id}.desktop; do
    [[ -f "${entry}" ]] || continue
    sed '/^NoDisplay=/d; /^\[Desktop Entry\]$/a NoDisplay=true' "${entry}" >"${user_applications}/${entry##*/}"
  done
done

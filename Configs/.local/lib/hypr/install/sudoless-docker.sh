#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_help_guard 'Usage: hyprshell install/sudoless-docker.sh
Toggle membership of the current user in the root-equivalent docker group.' "$@"

configured=false
getent group docker >/dev/null 2>&1 && id -nG "${USER}" | tr ' ' '\n' | grep -qx docker && configured=true

if ${configured}; then
  printf 'WARNING: removing %s from the docker group disables passwordless Docker after the next login.\n\n' "${USER}"
  gum confirm 'Disable sudoless Docker?' || exit 0
  sudo gpasswd -d "${USER}" docker
  printf 'Sudoless Docker is disabled after you log out and back in.\n'
  exit 0
fi

command -v docker >/dev/null 2>&1 || hyprshell pm add docker
printf 'WARNING: the docker group grants passwordless root-equivalent access to every process running as your user.\n\n'
gum confirm 'Enable sudoless Docker?' || exit 0
sudo usermod -aG docker "${USER}"
printf 'Sudoless Docker is enabled after you log out and back in.\n'

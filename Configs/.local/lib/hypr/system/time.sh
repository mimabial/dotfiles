#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/time
Restart the system time-sync daemon to resync the clock." "$@"

echo "Updating time..."
case "$(hypr_init_system)" in
  systemd)
    sudo systemctl restart systemd-timesyncd
    ;;
  runit)
    for svc in ntpd chronyd chrony openntpd; do
      if [[ -d "/etc/runit/sv/${svc}" || -d "/run/runit/service/${svc}" ]]; then
        sudo sv restart "${svc}"
        exit $?
      fi
    done
    echo "No known time-sync service (ntpd/chrony/openntpd) found under runit" >&2
    exit 1
    ;;
  *)
    echo "No supported service manager to restart time sync" >&2
    exit 1
    ;;
esac

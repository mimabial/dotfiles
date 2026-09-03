#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

usage() {
  printf 'Usage: hyprshell install/passwordless-sudo.sh [MINUTES|--disable]\n'
}

minutes=15
explicit_minutes=false
case "${1:-}" in
  "") ;;
  --disable) disable=true ;;
  -h | --help) usage; exit 0 ;;
  *) minutes="$1"; explicit_minutes=true ;;
esac
[[ "${minutes}" =~ ^[1-9][0-9]*$ ]] || { usage >&2; exit 2; }
[[ "${USER}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || { printf 'Unsafe user name\n' >&2; exit 1; }

sudoers_file="/etc/sudoers.d/99-hypr-nopasswd-${USER}"
timer_name="hypr-nopasswd-expire-${USER}"

disable_rule() {
  sudo rm -f -- "${sudoers_file}"
  sudo systemctl stop "${timer_name}.timer" "${timer_name}.service" >/dev/null 2>&1 || true
  printf 'Passwordless sudo is disabled.\n'
}

if [[ "${disable:-false}" == true ]]; then
  disable_rule
  exit 0
fi

if sudo test -f "${sudoers_file}" && ! ${explicit_minutes}; then
  disable_rule
  exit 0
fi

# Deliberately systemd-only: the expiry must survive this shell and a reboot.
# A detached `sleep N && rm` satisfies neither, and a passwordless-sudo rule that
# outlives its timer is worse than not offering the feature.
command -v systemd-run >/dev/null 2>&1 || {
  printf 'Automatic expiry requires systemd-run; refusing to enable a permanent rule.\n' >&2
  exit 1
}

printf 'WARNING: for %s minutes, every process running as %s can execute commands as root without a password.\n\n' "${minutes}" "${USER}"
gum confirm "Enable passwordless sudo for ${minutes} minutes?" || exit 0

temp_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/hypr-sudoers.XXXXXX")"
trap 'rm -f -- "${temp_file}"' EXIT
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "${USER}" >"${temp_file}"
visudo -cf "${temp_file}" >/dev/null
sudo install -m 0440 "${temp_file}" "${sudoers_file}"
sudo systemctl stop "${timer_name}.timer" "${timer_name}.service" >/dev/null 2>&1 || true
sudo systemd-run --quiet --unit="${timer_name}" --on-active="${minutes}m" \
  --timer-property=AccuracySec=1s /usr/bin/rm -f -- "${sudoers_file}"
printf 'Passwordless sudo is enabled for %s minutes; run this action again to disable it early.\n' "${minutes}"

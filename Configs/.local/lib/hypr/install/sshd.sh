#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

usage() {
  printf 'Usage: hyprshell install/sshd.sh [--key PUBLIC_KEY | --gh-keys USERNAME]\n'
}

valid_key() {
  ssh-keygen -lf /dev/stdin <<<"$1" >/dev/null 2>&1
}

authorize_key() {
  local key="$1"
  local authorized_keys="${HOME}/.ssh/authorized_keys"

  valid_key "${key}" || { printf 'Invalid SSH public key\n' >&2; return 1; }
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  touch "${authorized_keys}"
  chmod 600 "${authorized_keys}"
  grep -qxF -- "${key}" "${authorized_keys}" || printf '%s\n' "${key}" >>"${authorized_keys}"
}

authorize_github_keys() {
  local username="$1"
  local keys=""
  local key=""
  local added=0

  [[ "${username}" =~ ^[A-Za-z0-9-]+$ ]] || { printf 'Invalid GitHub username\n' >&2; return 1; }
  keys="$(curl -fsSL "https://github.com/${username}.keys")"
  [[ -n "${keys}" ]] || { printf 'No SSH keys found for %s\n' "${username}" >&2; return 1; }
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    authorize_key "${key}" && ((added += 1))
  done <<<"${keys}"
  ((added > 0))
}

key=""
github_user=""
while (($#)); do
  case "$1" in
    --key) key="${2:-}"; shift 2 ;;
    --gh-keys) github_user="${2:-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -z "${key}" || -z "${github_user}" ]] || { printf 'Choose --key or --gh-keys, not both\n' >&2; exit 2; }

if [[ -z "${key}${github_user}" ]]; then
  case "$(gum choose 'Grab key from GitHub' 'Paste key manually' --header 'Authorize an SSH key')" in
    'Grab key from GitHub') github_user="$(gum input --prompt 'GitHub username> ')" ;;
    'Paste key manually') key="$(gum input --prompt 'Public key> ')" ;;
    *) exit 0 ;;
  esac
fi

printf 'Installing and starting OpenSSH server...\n'
hyprshell pm add openssh
sudo sshd -t
case "$(hypr_init_system)" in
  systemd) sudo systemctl enable --now sshd.service ;;
  runit)
    [[ -d /etc/runit/sv/sshd ]] || { printf 'runit sshd service not found\n' >&2; exit 1; }
    sudo ln -snf /etc/runit/sv/sshd /run/runit/service/sshd
    sudo sv up sshd
    ;;
  *) printf 'Unsupported init system; start sshd manually\n' >&2; exit 1 ;;
esac

if command -v ufw >/dev/null 2>&1; then
  sudo ufw limit 22/tcp comment hypr-sshd >/dev/null
  sudo ufw reload >/dev/null
fi

if [[ -n "${github_user}" ]]; then
  authorize_github_keys "${github_user}"
else
  authorize_key "${key}"
fi
printf 'SSHD is running; connect with: ssh %s@%s\n' "${USER}" "$(hostname)"

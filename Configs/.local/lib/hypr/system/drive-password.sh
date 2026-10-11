#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell system/drive-password
Change the LUKS passphrase on an encrypted drive (prompts when several exist)." "$@"

LUKS_ITER_TIME_MS=2000

mapfile -t encrypted_drives < <(blkid -t TYPE=crypto_LUKS -o device)

if ((${#encrypted_drives[@]})); then
  if ((${#encrypted_drives[@]} == 1)); then
    drive_to_change="${encrypted_drives[0]}"
  else
    drive_to_change="$(hyprshell drive-select "${encrypted_drives[@]}")"
  fi

  if [[ -n $drive_to_change ]]; then
    echo "Changing full-disk encryption password for $drive_to_change"
    sudo cryptsetup luksChangeKey --pbkdf argon2id --iter-time "${LUKS_ITER_TIME_MS}" "$drive_to_change"
  else
    echo "No drive selected."
  fi
else
  echo "No encrypted drives available."
  exit 1
fi

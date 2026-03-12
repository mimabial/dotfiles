#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ntfs-repair-mount.sh [DEVICE|UUID|LABEL] [MOUNTPOINT]

Defaults:
  DEVICE     UUID=F474B7AA74B76DCC (VIRAL_OS)
  MOUNTPOINT /run/media/$USER/<LABEL-or-device-name>

What it does:
  1) Unmounts DEVICE if currently mounted
  2) Runs ntfsfix as root (via pkexec)
  3) Mounts with ntfs3 force + user uid/gid ownership
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd findmnt
need_cmd pkexec
need_cmd ntfsfix
need_cmd mount
need_cmd blkid

default_uuid="F474B7AA74B76DCC"

resolve_device() {
  local input="${1:-}"
  local resolved=""

  if [[ -z "${input}" ]]; then
    resolved="$(blkid -U "${default_uuid}" 2>/dev/null || true)"
    if [[ -z "${resolved}" ]]; then
      resolved="$(blkid -L "VIRAL_OS" 2>/dev/null || true)"
    fi
    echo "${resolved}"
    return 0
  fi

  if [[ "${input}" == /dev/* ]]; then
    echo "${input}"
    return 0
  fi

  if [[ "${input}" == UUID=* ]]; then
    echo "$(blkid -U "${input#UUID=}" 2>/dev/null || true)"
    return 0
  fi

  if [[ "${input}" == LABEL=* ]]; then
    echo "$(blkid -L "${input#LABEL=}" 2>/dev/null || true)"
    return 0
  fi

  if [[ "${input}" == *-* ]]; then
    resolved="$(blkid -U "${input}" 2>/dev/null || true)"
    if [[ -n "${resolved}" ]]; then
      echo "${resolved}"
      return 0
    fi
  fi

  echo "$(blkid -L "${input}" 2>/dev/null || true)"
}

device="$(resolve_device "${1:-}")"
if [[ ! -b "${device}" ]]; then
  echo "Device not found. Try one of:" >&2
  echo "  ntfs-repair-mount.sh /dev/sdb1" >&2
  echo "  ntfs-repair-mount.sh UUID=${default_uuid}" >&2
  echo "  ntfs-repair-mount.sh LABEL=VIRAL_OS" >&2
  exit 1
fi

fstype="$(blkid -o value -s TYPE "${device}" 2>/dev/null || true)"
if [[ -z "${fstype}" ]]; then
  fstype="$(lsblk -no FSTYPE "${device}" 2>/dev/null || true)"
fi
if [[ "${fstype}" != "ntfs" ]]; then
  echo "Refusing to run ntfs-repair-mount on non-NTFS device: ${device} (TYPE=${fstype:-unknown})" >&2
  exit 1
fi

label="$(blkid -o value -s LABEL "${device}" 2>/dev/null || true)"
if [[ -z "${label}" ]]; then
  label="$(basename "${device}")"
fi

mountpoint="${2:-/run/media/${USER}/${label}}"
uid="$(id -u)"
gid="$(id -g)"
mount_opts="uid=${uid},gid=${gid},iocharset=utf8,force"

if findmnt -rn -S "${device}" >/dev/null 2>&1; then
  current_target="$(findmnt -rn -S "${device}" -o TARGET | head -n1)"
  echo "Unmounting ${device} from ${current_target}..."
  if command -v udisksctl >/dev/null 2>&1; then
    if ! udisksctl unmount -b "${device}" >/dev/null 2>&1; then
      echo "UDisks unmount failed. Checking blockers on ${current_target}..."
      if command -v fuser >/dev/null 2>&1; then
        fuser -vm "${current_target}" || true
      fi
      pkexec umount "${device}"
    fi
  else
    pkexec umount "${device}"
  fi
fi

echo "Running ntfsfix on ${device} (polkit auth may prompt)..."
if ! pkexec ntfsfix "${device}"; then
  echo "ntfsfix failed on ${device}." >&2
  echo "If this keeps happening, run Windows chkdsk on this disk: chkdsk /f <drive-letter>" >&2
  exit 1
fi

echo "Mounting ${device} at ${mountpoint} with ntfs3 force..."
pkexec sh -c 'mkdir -p "$2" && mount -t ntfs3 -o "$3" "$1" "$2"' sh "${device}" "${mountpoint}" "${mount_opts}"

if findmnt -rn -S "${device}" >/dev/null 2>&1; then
  echo "Mounted successfully:"
  findmnt -rn -S "${device}" -o SOURCE,TARGET,FSTYPE,OPTIONS
else
  echo "Mount verification failed for ${device}" >&2
  exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell system/removable COMMAND [ARGS...]

Removable-drive operations behind the bar's drives popup, and the suspend hook.

  --unmount-all  Unmount removable volumes before sleep (unless unmountOnSuspend is false);
                 fail on the first that refuses
  --probe-support  List GVFS backends and attached USB device classes
  --mount-read-only DEVICE REMOUNT  Mount DEVICE read-only, unmounting it first when REMOUNT is 1
  --unlock DEVICE READ_ONLY  Unlock DEVICE with the passphrase read from stdin, then mount it
                 (read-only when READ_ONLY is 1)
  --lock DEVICE [MOUNTED_FS]  Unmount MOUNTED_FS when given, then lock DEVICE
  --eject STEP...  Run eject steps in order: trash FS IDENTITY | unmount FS | lock DEVICE | power-off DEVICE
  --run-hook PROGRESS DEVICE MOUNTPOINT COMMAND  Run a drive's on-connect COMMAND with DEVICE,
                 MOUNTPOINT and PROGRESS as arguments, then append its exit status to PROGRESS
  --unmount-network MOUNTPOINT  Unmount a FUSE, GVFS or kernel network mount
  --blockers PATH...  List "PID COMMAND" for the processes holding the mounts under PATH
USAGE
}

DRIVE_FILESYSTEM="${BASH_SOURCE[0]%/*}/drive-filesystem.sh"

mount_read_only() {
  local device="$1" remount="$2"
  [[ "$remount" != 1 ]] || udisksctl unmount --no-user-interaction -b "$device" >/dev/null
  udisksctl mount --no-user-interaction -o ro -b "$device" >/dev/null
}

unlock() {
  local device="$1" read_only="$2" passphrase unlocked
  local key="${XDG_RUNTIME_DIR:-/dev/shm}/removable-drives.$$.key"
  local -a mount_options=()
  [[ "$read_only" != 1 ]] || mount_options=(-o ro)
  trap 'rm -f "$key"' EXIT
  umask 077
  IFS= read -r passphrase
  printf %s "$passphrase" >"$key"
  unset passphrase
  unlocked="$(udisksctl unlock --no-user-interaction -b "$device" --key-file "$key")"
  unlocked="${unlocked##* as }"
  udisksctl mount --no-user-interaction -b "${unlocked%.}" "${mount_options[@]}" >/dev/null
}

lock() {
  local device="$1" mounted_fs="${2:-}"
  [[ -z "$mounted_fs" ]] || udisksctl unmount --no-user-interaction -b "$mounted_fs" >/dev/null
  udisksctl lock --no-user-interaction -b "$device" >/dev/null
}

eject() {
  while (($#)); do
    case "$1" in
      trash) "$DRIVE_FILESYSTEM" trash "$2" "$3" || true; shift 3 ;;
      unmount) udisksctl unmount --no-user-interaction -b "$2"; shift 2 ;;
      lock) udisksctl lock --no-user-interaction -b "$2"; shift 2 ;;
      power-off) udisksctl power-off --no-user-interaction -b "$2" || true; shift 2 ;;
      *) printf 'Unknown eject step: %s\n' "$1" >&2; return 2 ;;
    esac
  done
}

run_hook() {
  local progress="$1" device="$2" mountpoint="$3" command="$4" status=0
  mkdir -p "${progress%/*}" && : >"$progress" || return
  bash -c "$command" removable-drives "$device" "$mountpoint" "$progress" || status=$?
  echo "exit=$status" >>"$progress"
}

unmount_network() {
  fusermount3 -u "$1" 2>/dev/null || gio mount -u "$1" 2>/dev/null || umount "$1"
}

blockers() {
  local -a pids
  read -r -a pids < <(fuser -m "$@" 2>/dev/null) || true
  ((${#pids[@]})) || return 0
  local IFS=,
  ps -o pid=,comm= -p "${pids[*]}" || true
}

probe_support() {
  local mount_file mount_name device vendor class_file classes product
  for mount_file in /usr/share/gvfs/mounts/*.mount; do
    [[ -e "$mount_file" ]] || continue
    mount_name="${mount_file##*/}"
    printf 'backend %s\n' "${mount_name%.mount}"
  done
  for device in /sys/bus/usb/devices/*/; do
    [[ -r "$device/idVendor" ]] || continue
    vendor="$( < "$device/idVendor" )"
    [[ "$vendor" == 1d6b ]] && continue
    classes=""
    for class_file in "$device"*:*/bInterfaceClass; do
      [[ -r "$class_file" ]] && classes+=",$( < "$class_file" )"
    done
    product=""
    [[ ! -r "$device/product" ]] || product="$( < "$device/product" )"
    printf 'usb %s%s %s\n' "$vendor" "$classes" "$product"
  done
}

suspend_targets() {
  lsblk -J -o NAME,PATH,TYPE,RM,HOTPLUG,MOUNTPOINTS | jq -r '
    .blockdevices[]
    | select(.type == "disk" and (.rm == true or .hotplug == true))
    | select(([.. | objects | .mountpoints? // [] | .[]?]
        | any(. == "/" or . == "/boot" or . == "/boot/efi" or . == "/efi" or . == "/home" or . == "/var" or . == "/usr" or . == "/nix" or . == "/nix/store" or . == "[SWAP]")) | not)
    | [.. | objects | select(.path? and ((.mountpoints // []) | any(. != null and . != ""))) | .path]
    | reverse[]'
}

case "${1:-}" in
  -h | --help) usage ;;
  --probe-support) probe_support ;;
  --mount-read-only) mount_read_only "$2" "$3" ;;
  --unlock) unlock "$2" "$3" ;;
  --lock) lock "$2" "${3:-}" ;;
  --eject) shift; eject "$@" ;;
  --run-hook) run_hook "$2" "$3" "$4" "$5" ;;
  --unmount-network) unmount_network "$2" ;;
  --blockers) shift; blockers "$@" ;;
  --unmount-all)
    ! jq -e '.unmountOnSuspend == false' "$HOME/.local/state/hypr/removable-drives.json" >/dev/null 2>&1 || exit 0
    targets="$(suspend_targets)"
    [[ -n "$targets" ]] || exit 0
    mapfile -t mounted_nodes <<<"$targets"
    for node in "${mounted_nodes[@]}"; do
      udisksctl unmount --no-user-interaction -b "$node" >/dev/null || {
        printf 'Could not unmount %s before sleep\n' "$node" >&2
        exit 1
      }
    done
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

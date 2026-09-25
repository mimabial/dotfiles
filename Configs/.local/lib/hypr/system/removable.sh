#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell system/removable --unmount-all|--probe-support

  --unmount-all  Unmount removable volumes before sleep (unless unmountOnSuspend is false);
                 fail on the first that refuses
  --probe-support  List GVFS backends and attached USB device classes
USAGE
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

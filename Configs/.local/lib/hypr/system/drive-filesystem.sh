#!/usr/bin/env bash
set -euo pipefail

action="${1:-}" device="${2:-}" identity="${3:-}" type="${4:-}" label="${5:-}" zero="${6:-0}"
[[ "$device" == /dev/* && -b "$device" ]] || { echo 'Drive is no longer present' >&2; exit 1; }
if [[ "$action" == health ]]; then
  raw="$(busctl call org.freedesktop.UDisks2 /org/freedesktop/UDisks2/Manager org.freedesktop.UDisks2.Manager ResolveDevice 'a{sv}a{sv}' 1 path s "$device" 0)"
  object="/${raw#*/}"; object="${object%?}"
  raw="$(busctl get-property org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Block Drive)"
  drive="/${raw#*/}"; drive="${drive%?}"
  [[ "$drive" == /org/freedesktop/UDisks2/drives/* ]] || exit 1
  busctl --timeout=30 call org.freedesktop.UDisks2 "$drive" org.freedesktop.UDisks2.Drive.Ata SmartUpdate 'a{sv}' 1 nowakeup b true >/dev/null 2>&1 || true
  busctl --timeout=30 call org.freedesktop.UDisks2 "$drive" org.freedesktop.UDisks2.NVMe.Controller SmartUpdate 'a{sv}' 0 >/dev/null 2>&1 || true
  for spec in 'Ata SmartUpdated' 'Ata SmartFailing' 'Ata SmartTemperature' 'Ata SmartPowerOnSeconds' 'Ata SmartNumBadSectors' 'NVMe.Controller SmartUpdated' 'NVMe.Controller SmartCriticalWarning' 'NVMe.Controller SmartTemperature' 'NVMe.Controller SmartPowerOnHours'; do
    read -r interface property <<<"$spec"
    [[ "$interface" == Ata ]] && interface=org.freedesktop.UDisks2.Drive.Ata || interface=org.freedesktop.UDisks2.NVMe.Controller
    value="$(busctl get-property org.freedesktop.UDisks2 "$drive" "$interface" "$property" 2>/dev/null)" || continue
    printf '%s %s\n' "$property" "$value"
  done
  exit
fi
disk="$device"
while :; do
  parent="$(lsblk -dn -o PKNAME "$disk" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" || exit 1
  [[ -n "$parent" ]] || break
  disk="/dev/$parent"
done
read -r removable hotplug < <(lsblk -dn -o RM,HOTPLUG "$disk")
[[ "$removable" == 1 || "$hotplug" == 1 ]] || { echo 'Only removable drives can be changed here' >&2; exit 1; }
mount_tree="$(lsblk -J -o NAME,MOUNTPOINTS "$disk")" || { echo 'Could not verify drive mounts' >&2; exit 1; }
if jq -e '[.. | objects | .mountpoints? // [] | .[]?] | any(. == "/" or . == "/boot" or . == "/boot/efi" or . == "/efi" or . == "/home" or . == "/var" or . == "/usr" or . == "/nix" or . == "/nix/store" or . == "[SWAP]")' <<<"$mount_tree" >/dev/null; then
  echo 'Refusing to change a system drive' >&2; exit 1
fi
case "$identity" in
  uuid:*) current="$(lsblk -dn -o UUID "$device" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"; [[ -n "$current" && "$current" == "${identity#uuid:}" ]] ;;
  serial:*) current="$(lsblk -dn -o SERIAL "$disk" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"; [[ -n "$current" && "$current" == "${identity#serial:}" ]] ;;
  *) false ;;
esac || { echo 'Drive identity changed; rescan before trying again' >&2; exit 1; }

raw="$(busctl call org.freedesktop.UDisks2 /org/freedesktop/UDisks2/Manager org.freedesktop.UDisks2.Manager ResolveDevice 'a{sv}a{sv}' 1 path s "$device" 0)"
object="/${raw#*/}"; object="${object%?}"
[[ "$object" == /org/freedesktop/UDisks2/block_devices/* ]] || { echo 'udisks cannot find this drive' >&2; exit 1; }

if [[ "$action" == trash ]]; then
  mountpoint="$(lsblk -dn -o MOUNTPOINT "$device" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$mountpoint" ]] || { echo 'Mount the volume before emptying its trash' >&2; exit 1; }
  trash="$mountpoint/.Trash-$(id -u)"
  [[ -d "$trash" && ! -L "$trash" ]] || exit 0
  for directory in "$trash/files" "$trash/info"; do
    [[ -d "$directory" && ! -L "$directory" ]] || continue
    find "$directory" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  done
  exit
fi

if [[ "$action" == format ]]; then
  [[ "$type" == exfat || "$type" == vfat || "$type" == ntfs || "$type" == ext4 || "$type" == btrfs ]] || exit 2
  [[ "$zero" == 0 || "$zero" == 1 ]] || exit 2
  target_type="$(lsblk -dn -o TYPE "$device" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ "$target_type" == disk || "$target_type" == part ]] || { echo 'Lock or detach the volume before formatting' >&2; exit 1; }
  mount_tree="$(lsblk -J -o NAME,TYPE,MOUNTPOINTS "$device")" || { echo 'Could not verify volume mounts' >&2; exit 1; }
  if jq -e '[.. | objects | .mountpoints? // [] | .[]?] | any(. != null and . != "")' <<<"$mount_tree" >/dev/null; then
    echo 'Unmount all volumes before formatting' >&2; exit 1
  fi
  layers="$(jq -r '[.blockdevices[] | .children[]? | .. | objects | .type? // empty] | any(. != "part")' <<<"$mount_tree")" || exit 1
  [[ "$layers" != true ]] || { echo 'Lock or detach active volume layers before formatting' >&2; exit 1; }
  count=1; set -- take-ownership b true
  if [[ -n "$label" ]]; then count=$((count + 1)); set -- "$@" label s "$label"; fi
  if [[ "$zero" == 1 && "$device" != "$disk" ]]; then count=$((count + 1)); set -- "$@" erase s zero; fi
  if [[ "$device" == "$disk" ]]; then
    [[ "$type" == ext4 || "$type" == btrfs ]] && partition_type='' || partition_type=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7
    if [[ "$zero" == 1 ]]; then
      busctl --timeout=86400 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Block Format 'sa{sv}' empty 1 erase s zero
    fi
    busctl --timeout=120 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Block Format 'sa{sv}' gpt 0
    busctl --timeout=86400 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.PartitionTable CreatePartitionAndFormat 'ttssa{sv}sa{sv}' 1048576 0 "$partition_type" '' 0 "$type" "$count" "$@"
    exit
  fi
  busctl --timeout=86400 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Block Format 'sa{sv}' "$type" "$count" "$@"
  exit
fi

if [[ "$action" == ntfsfix ]]; then
  [[ "$(lsblk -dn -o FSTYPE "$device" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" == ntfs ]] || { echo 'This is not an NTFS volume' >&2; exit 1; }
  [[ -z "$(lsblk -dn -o MOUNTPOINT "$device" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" ]] || { echo 'Unmount before repairing NTFS' >&2; exit 1; }
  verdict="$(busctl --timeout=86400 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Filesystem Check 'a{sv}' 0)" || verdict='b false'
  if [[ "$verdict" != 'b true' ]]; then
    repair="$(busctl --timeout=86400 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Filesystem Repair 'a{sv}' 0)"
    [[ "$repair" == 'b true' ]] || { echo 'NTFS repair did not finish cleanly' >&2; exit 1; }
  fi
  exit
fi

[[ "$action" == label || "$action" == check || "$action" == repair ]] || exit 2
mount_options="$(findmnt -frn -o OPTIONS -S "$device" || true)"
[[ -z "$mount_options" ]] || udisksctl unmount --no-user-interaction -b "$device" >/dev/null
remount=(udisksctl mount --no-user-interaction -b "$device")
[[ ",$mount_options," == *,ro,* ]] && remount+=(-o ro)
result=0
case "$action" in
  label) busctl --timeout=120 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Filesystem SetLabel 'sa{sv}' "$label" 0 || result=$? ;;
  check) busctl --timeout=86400 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Filesystem Check 'a{sv}' 0 || result=$? ;;
  repair) busctl --timeout=86400 call org.freedesktop.UDisks2 "$object" org.freedesktop.UDisks2.Filesystem Repair 'a{sv}' 0 || result=$? ;;
esac
if [[ -n "$mount_options" ]] && ! "${remount[@]}" >/dev/null; then
  echo 'Filesystem action completed, but the volume could not be remounted' >&2
  [[ "$result" == 0 ]] && result=75
fi
exit "$result"

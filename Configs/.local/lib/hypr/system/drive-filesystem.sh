#!/usr/bin/env bash
set -euo pipefail

udisks() { gdbus call --system --dest org.freedesktop.UDisks2 --timeout "$1" --object-path "$2" --method "org.freedesktop.$3" "${@:4}"; }
quote() { local text="${1//\\/\\\\}"; printf "'%s'" "${text//\'/\\\'}"; }
object_path() { local path="/${1#*/}"; printf '%s' "${path%%\'*}"; }

action="${1:-}" device="${2:-}" identity="${3:-}" type="${4:-}" label="${5:-}" zero="${6:-0}"
[[ "$device" == /dev/* && -b "$device" ]] || { echo 'Drive is no longer present' >&2; exit 1; }
object="$(object_path "$(udisks 25 /org/freedesktop/UDisks2/Manager UDisks2.Manager.ResolveDevice "{'path': <$(quote "$device")>}" '{}')")"
[[ "$object" == /org/freedesktop/UDisks2/block_devices/* ]] || { echo 'udisks cannot find this drive' >&2; exit 1; }
if [[ "$action" == health ]]; then
  drive="$(object_path "$(udisks 25 "$object" DBus.Properties.Get org.freedesktop.UDisks2.Block Drive)")"
  [[ "$drive" == /org/freedesktop/UDisks2/drives/* ]] || exit 1
  udisks 30 "$drive" UDisks2.Drive.Ata.SmartUpdate "{'nowakeup': <true>}" >/dev/null 2>&1 || true
  udisks 30 "$drive" UDisks2.NVMe.Controller.SmartUpdate '{}' >/dev/null 2>&1 || true
  udisks 25 "$drive" DBus.Properties.GetAll org.freedesktop.UDisks2.Drive.Ata 2>/dev/null || true
  udisks 25 "$drive" DBus.Properties.GetAll org.freedesktop.UDisks2.NVMe.Controller 2>/dev/null || true
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
  options="'take-ownership': <true>"
  if [[ -n "$label" ]]; then options+=", 'label': <$(quote "$label")>"; fi
  if [[ "$zero" == 1 && "$device" != "$disk" ]]; then options+=", 'erase': <'zero'>"; fi
  if [[ "$device" == "$disk" ]]; then
    [[ "$type" == ext4 || "$type" == btrfs ]] && partition_type='' || partition_type=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7
    if [[ "$zero" == 1 ]]; then
      udisks 86400 "$object" UDisks2.Block.Format "'empty'" "{'erase': <'zero'>}"
    fi
    udisks 120 "$object" UDisks2.Block.Format "'gpt'" '{}'
    udisks 86400 "$object" UDisks2.PartitionTable.CreatePartitionAndFormat 1048576 0 "'$partition_type'" "''" '{}' "'$type'" "{$options}"
    exit
  fi
  udisks 86400 "$object" UDisks2.Block.Format "'$type'" "{$options}"
  exit
fi

if [[ "$action" == ntfsfix ]]; then
  [[ "$(lsblk -dn -o FSTYPE "$device" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" == ntfs ]] || { echo 'This is not an NTFS volume' >&2; exit 1; }
  [[ -z "$(lsblk -dn -o MOUNTPOINT "$device" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" ]] || { echo 'Unmount before repairing NTFS' >&2; exit 1; }
  verdict="$(udisks 86400 "$object" UDisks2.Filesystem.Check '{}')" || verdict='(false,)'
  if [[ "$verdict" != '(true,)' ]]; then
    repair="$(udisks 86400 "$object" UDisks2.Filesystem.Repair '{}')"
    [[ "$repair" == '(true,)' ]] || { echo 'NTFS repair did not finish cleanly' >&2; exit 1; }
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
  label) udisks 120 "$object" UDisks2.Filesystem.SetLabel "$(quote "$label")" '{}' || result=$? ;;
  check) udisks 86400 "$object" UDisks2.Filesystem.Check '{}' || result=$? ;;
  repair) udisks 86400 "$object" UDisks2.Filesystem.Repair '{}' || result=$? ;;
esac
if [[ -n "$mount_options" ]] && ! "${remount[@]}" >/dev/null; then
  echo 'Filesystem action completed, but the volume could not be remounted' >&2
  [[ "$result" == 0 ]] && result=75
fi
exit "$result"

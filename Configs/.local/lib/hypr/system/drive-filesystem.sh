#!/usr/bin/env bash
set -euo pipefail

QUERY_TIMEOUT_SECONDS=25
SMART_TIMEOUT_SECONDS=30
METADATA_WRITE_TIMEOUT_SECONDS=120
FULL_DEVICE_TIMEOUT_SECONDS=86400
ALIGNED_PARTITION_OFFSET_BYTES=$((1024 * 1024))
PARTITION_SIZE_TO_END=0
MICROSOFT_BASIC_DATA_TYPE=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7
EX_TEMPFAIL=75

udisks() {
  local timeout_seconds="$1" dbus_object="$2" method="$3"
  gdbus call --system --dest org.freedesktop.UDisks2 --timeout "$timeout_seconds" --object-path "$dbus_object" --method "org.freedesktop.$method" "${@:4}"
}
lsblk_field_into() {
  local -n field_ref="$1"
  field_ref="$(lsblk -dn -o "$2" "$3")" || return
  field_ref="${field_ref#"${field_ref%%[![:space:]]*}"}"
  field_ref="${field_ref%"${field_ref##*[![:space:]]}"}"
}
quote() { local text="${1//\\/\\\\}"; printf "'%s'" "${text//\'/\\\'}"; }
object_path() { local path="/${1#*/}"; printf '%s' "${path%%\'*}"; }

action="${1:-}" device="${2:-}" identity="${3:-}" type="${4:-}" label="${5:-}" zero_fill="${6:-0}"
[[ "$device" == /dev/* && -b "$device" ]] || { echo 'Drive is no longer present' >&2; exit 1; }
object="$(object_path "$(udisks "$QUERY_TIMEOUT_SECONDS" /org/freedesktop/UDisks2/Manager UDisks2.Manager.ResolveDevice "{'path': <$(quote "$device")>}" '{}')")"
[[ "$object" == /org/freedesktop/UDisks2/block_devices/* ]] || { echo 'udisks cannot find this drive' >&2; exit 1; }
if [[ "$action" == health ]]; then
  drive="$(object_path "$(udisks "$QUERY_TIMEOUT_SECONDS" "$object" DBus.Properties.Get org.freedesktop.UDisks2.Block Drive)")"
  [[ "$drive" == /org/freedesktop/UDisks2/drives/* ]] || exit 1
  udisks "$SMART_TIMEOUT_SECONDS" "$drive" UDisks2.Drive.Ata.SmartUpdate "{'nowakeup': <true>}" >/dev/null 2>&1 || true
  udisks "$SMART_TIMEOUT_SECONDS" "$drive" UDisks2.NVMe.Controller.SmartUpdate '{}' >/dev/null 2>&1 || true
  udisks "$QUERY_TIMEOUT_SECONDS" "$drive" DBus.Properties.GetAll org.freedesktop.UDisks2.Drive.Ata 2>/dev/null || true
  udisks "$QUERY_TIMEOUT_SECONDS" "$drive" DBus.Properties.GetAll org.freedesktop.UDisks2.NVMe.Controller 2>/dev/null || true
  exit
fi
disk="$device"
while :; do
  lsblk_field_into parent PKNAME "$disk" || exit 1
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
  uuid:*) lsblk_field_into current UUID "$device"; [[ -n "$current" && "$current" == "${identity#uuid:}" ]] ;;
  serial:*) lsblk_field_into current SERIAL "$disk"; [[ -n "$current" && "$current" == "${identity#serial:}" ]] ;;
  *) false ;;
esac || { echo 'Drive identity changed; rescan before trying again' >&2; exit 1; }

if [[ "$action" == trash ]]; then
  lsblk_field_into mountpoint MOUNTPOINT "$device"
  [[ -n "$mountpoint" ]] || { echo 'Mount the volume before emptying its trash' >&2; exit 1; }
  trash="$mountpoint/.Trash-${UID}"
  [[ -d "$trash" && ! -L "$trash" ]] || exit 0
  for directory in "$trash/files" "$trash/info"; do
    [[ -d "$directory" && ! -L "$directory" ]] || continue
    find "$directory" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  done
  exit
fi

if [[ "$action" == format ]]; then
  [[ "$type" == exfat || "$type" == vfat || "$type" == ntfs || "$type" == ext4 || "$type" == btrfs ]] || exit 2
  [[ "$zero_fill" == 0 || "$zero_fill" == 1 ]] || exit 2
  lsblk_field_into target_type TYPE "$device"
  [[ "$target_type" == disk || "$target_type" == part ]] || { echo 'Lock or detach the volume before formatting' >&2; exit 1; }
  mount_tree="$(lsblk -J -o NAME,TYPE,MOUNTPOINTS "$device")" || { echo 'Could not verify volume mounts' >&2; exit 1; }
  if jq -e '[.. | objects | .mountpoints? // [] | .[]?] | any(. != null and . != "")' <<<"$mount_tree" >/dev/null; then
    echo 'Unmount all volumes before formatting' >&2; exit 1
  fi
  layers="$(jq -r '[.blockdevices[] | .children[]? | .. | objects | .type? // empty] | any(. != "part")' <<<"$mount_tree")" || exit 1
  [[ "$layers" != true ]] || { echo 'Lock or detach active volume layers before formatting' >&2; exit 1; }
  options="'take-ownership': <true>"
  if [[ -n "$label" ]]; then options+=", 'label': <$(quote "$label")>"; fi
  if [[ "$zero_fill" == 1 && "$device" != "$disk" ]]; then options+=", 'erase': <'zero'>"; fi
  if [[ "$device" == "$disk" ]]; then
    [[ "$type" == ext4 || "$type" == btrfs ]] && partition_type='' || partition_type="$MICROSOFT_BASIC_DATA_TYPE"
    if [[ "$zero_fill" == 1 ]]; then
      udisks "$FULL_DEVICE_TIMEOUT_SECONDS" "$object" UDisks2.Block.Format "'empty'" "{'erase': <'zero'>}"
    fi
    udisks "$METADATA_WRITE_TIMEOUT_SECONDS" "$object" UDisks2.Block.Format "'gpt'" '{}'
    udisks "$FULL_DEVICE_TIMEOUT_SECONDS" "$object" UDisks2.PartitionTable.CreatePartitionAndFormat "$ALIGNED_PARTITION_OFFSET_BYTES" "$PARTITION_SIZE_TO_END" "'$partition_type'" "''" '{}' "'$type'" "{$options}"
    exit
  fi
  udisks "$FULL_DEVICE_TIMEOUT_SECONDS" "$object" UDisks2.Block.Format "'$type'" "{$options}"
  exit
fi

if [[ "$action" == ntfsfix ]]; then
  lsblk_field_into filesystem_type FSTYPE "$device" && [[ "$filesystem_type" == ntfs ]] || { echo 'This is not an NTFS volume' >&2; exit 1; }
  lsblk_field_into mountpoint MOUNTPOINT "$device" && [[ -z "$mountpoint" ]] || { echo 'Unmount before repairing NTFS' >&2; exit 1; }
  verdict="$(udisks "$FULL_DEVICE_TIMEOUT_SECONDS" "$object" UDisks2.Filesystem.Check '{}')" || verdict='(false,)'
  if [[ "$verdict" != '(true,)' ]]; then
    repair="$(udisks "$FULL_DEVICE_TIMEOUT_SECONDS" "$object" UDisks2.Filesystem.Repair '{}')"
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
  label) udisks "$METADATA_WRITE_TIMEOUT_SECONDS" "$object" UDisks2.Filesystem.SetLabel "$(quote "$label")" '{}' || result=$? ;;
  check) udisks "$FULL_DEVICE_TIMEOUT_SECONDS" "$object" UDisks2.Filesystem.Check '{}' || result=$? ;;
  repair) udisks "$FULL_DEVICE_TIMEOUT_SECONDS" "$object" UDisks2.Filesystem.Repair '{}' || result=$? ;;
esac
if [[ -n "$mount_options" ]] && ! "${remount[@]}" >/dev/null; then
  echo 'Filesystem action completed, but the volume could not be remounted' >&2
  [[ "$result" == 0 ]] && result="$EX_TEMPFAIL"
fi
exit "$result"

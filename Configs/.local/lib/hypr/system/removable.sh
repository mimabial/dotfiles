#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell system/removable [option]

  --report        JSON: {"devices":[{path,name,title,label,size,fstype,mountpoint,mounted}],
                         "mounted":n,"count":n}
  --bar           Bar JSON: text, class, tooltip
  --mount DEV     Mount a device with udisksctl (polkit, no root)
  --unmount DEV   Unmount it
  --eject DEV     Unmount, then power the drive down so it is safe to pull
  --browse DEV    Open the mountpoint in the file manager
  --automount on|off|toggle   udiskie's automount, persisted to its config

Devices are the hotplug or removable partitions lsblk reports, which is the
same set udiskie acts on.
USAGE
}

UDISKIE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/udiskie/config.yml"

# udiskie has no runtime toggle, so the setting is persisted and the daemon
# restarted. Notifications belong to Quickshell's event service.
udiskie_option() {
  local key="$1" fallback="$2"
  [[ -f "${UDISKIE_CONFIG}" ]] || {
    printf '%s' "${fallback}"
    return
  }
  local value
  value="$(sed -n "s/^[[:space:]]*${key}:[[:space:]]*\([a-z]*\).*/\1/p" "${UDISKIE_CONFIG}" | head -1)"
  printf '%s' "${value:-${fallback}}"
}

udiskie_write() {
  local automount="$1"
  mkdir -p "$(dirname "${UDISKIE_CONFIG}")"
  cat >"${UDISKIE_CONFIG}" <<EOF
# AUTO-GENERATED — do not edit.
# Rewritten in full by: hyprshell system/removable --automount
# Only the keys below are managed; anything else added here is lost.
program_options:
  automount: ${automount}
  notify: false
EOF
  pkill -x udiskie >/dev/null 2>&1 || true
  hyprshell app -t service udiskie --smart-tray >/dev/null 2>&1 || true
}

resolve_flag() {
  case "$1" in
    on | true) printf 'true' ;;
    off | false) printf 'false' ;;
    toggle | "") [[ "$2" == "true" ]] && printf 'false' || printf 'true' ;;
    *) return 1 ;;
  esac
}

devices_json() {
  # a whole disk with a filesystem and no partitions counts too, which is how
  # most usb sticks and sd cards arrive
  lsblk -J -o PATH,NAME,LABEL,SIZE,FSTYPE,MOUNTPOINT,RM,HOTPLUG,TYPE 2>/dev/null | jq -c '
    def flatten: [ .[] | . , (.children // [] | flatten[]) ];
    [ .blockdevices | flatten[]
      | select((.rm == true or .hotplug == true) and .fstype != null and .type != "loop")
      | {
          path: .path,
          name: .name,
          label: (.label // ""),
          size: (.size // ""),
          fstype: (.fstype // ""),
          mountpoint: (.mountpoint // ""),
          mounted: (.mountpoint != null),
          title: (if (.label // "") == "" then .name else .label end)
        }
    ]'
}

case "${1:---report}" in
  -h | --help)
    usage
    exit 0
    ;;
  --report)
    devices_json | jq \
      --argjson automount "$(udiskie_option automount true)" \
      --argjson notify "$(udiskie_option notify true)" '{
      devices: .,
      mounted: (map(select(.mounted)) | length),
      count: length,
      automount: $automount,
      notify: $notify
    }'
    ;;
  --bar)
    devices_json | jq -r '
      (map(select(.mounted)) | length) as $mounted |
      length as $count |
      {
        text: (if $count == 0 then "" else "󰕓" end),
        alt: "󱊞",
        class: (if $count == 0 then "empty" elif $mounted > 0 then "mounted" else "present" end),
        tooltip: (if $count == 0 then "No removable media"
                  else (map("\(.title) \(.size) \(if .mounted then "— " + .mountpoint else "— not mounted" end)") | join("\n"))
                  end)
      } | @json'
    ;;
  --browse)
    [[ -n "${2:-}" ]] || {
      usage >&2
      exit 1
    }
    mountpoint="$(lsblk -no MOUNTPOINT "$2" 2>/dev/null | head -1)"
    [[ -n "${mountpoint}" ]] || {
      udisksctl mount -b "$2" --no-user-interaction >/dev/null
      mountpoint="$(lsblk -no MOUNTPOINT "$2" 2>/dev/null | head -1)"
    }
    [[ -n "${mountpoint}" ]] || exit 1
    xdg-open "${mountpoint}" >/dev/null 2>&1 &
    ;;
  --automount)
    current="$(udiskie_option automount true)"
    next="$(resolve_flag "${2:-toggle}" "${current}")" || {
      usage >&2
      exit 1
    }
    udiskie_write "${next}"
    ;;
  --mount)
    [[ -n "${2:-}" ]] || {
      usage >&2
      exit 1
    }
    udisksctl mount -b "$2" --no-user-interaction >/dev/null
    ;;
  --unmount)
    [[ -n "${2:-}" ]] || {
      usage >&2
      exit 1
    }
    udisksctl unmount -b "$2" --no-user-interaction >/dev/null
    ;;
  --eject)
    [[ -n "${2:-}" ]] || {
      usage >&2
      exit 1
    }
    parent="$(lsblk -no PKNAME "$2" 2>/dev/null | head -1)"
    disk="/dev/${parent:-$(basename "$2")}"
    if quickshell ipc call removable-drives eject "${disk}" >/dev/null 2>&1; then
      exit 0
    fi
    system_mount="$(lsblk -J -o MOUNTPOINTS "${disk}" 2>/dev/null | jq -r '[.. | objects | .mountpoints? // [] | .[]?] | any(. == "/" or . == "/boot" or . == "/boot/efi" or . == "/efi" or . == "/home" or . == "/var" or . == "/usr" or . == "[SWAP]")')"
    [[ "${system_mount}" != "true" ]] || {
      printf 'Refusing to eject the system drive: %s\n' "${disk}" >&2
      exit 1
    }
    mapfile -t mounted_nodes < <(lsblk -J -o PATH,MOUNTPOINT "${disk}" 2>/dev/null | jq -r '.. | objects | select(.mountpoint? != null) | .path' | tac)
    for node in "${mounted_nodes[@]}"; do
      udisksctl unmount -b "${node}" --no-user-interaction >/dev/null
    done
    udisksctl power-off -b "${disk}" --no-user-interaction >/dev/null
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

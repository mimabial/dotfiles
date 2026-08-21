#!/usr/bin/env bash
#
# removable.sh — Removable media state and actions, the udiskie tray job.
#
# Usage: removable.sh [--report|--waybar|--mount DEV|--unmount DEV|--eject DEV]
# Depends on: lsblk, jq, udisksctl
#
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell system/removable [option]

  --report        JSON: {"devices":[{path,name,title,label,size,fstype,mountpoint,mounted}],
                         "mounted":n,"count":n}
  --waybar        Bar JSON: text, class, tooltip
  --mount DEV     Mount a device with udisksctl (polkit, no root)
  --unmount DEV   Unmount it
  --eject DEV     Unmount, then power the drive down so it is safe to pull
  --browse DEV    Open the mountpoint in the file manager
  --automount on|off|toggle   udiskie's automount, persisted to its config
  --notify on|off|toggle      udiskie's mount notifications

Devices are the hotplug or removable partitions lsblk reports, which is the
same set udiskie acts on.
USAGE
}

UDISKIE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/udiskie/config.yml"

# udiskie has no runtime toggle, so the setting is persisted and the daemon
# restarted. Only these two keys are managed, so the file is rewritten whole.
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
  local automount="$1" notify="$2"
  mkdir -p "$(dirname "${UDISKIE_CONFIG}")"
  cat >"${UDISKIE_CONFIG}" <<EOF
# AUTO-GENERATED — do not edit.
# Rewritten in full by: hyprshell system/removable --automount|--notify
# Only the two keys below are managed; anything else added here is lost.
program_options:
  automount: ${automount}
  notify: ${notify}
EOF
  local unit
  unit="$(systemctl --user list-units --plain --no-legend 'app-Hyprland-udiskie@*.service' 2>/dev/null | awk 'NR==1{print $1}')"
  if [[ -n "${unit}" ]]; then
    systemctl --user restart "${unit}" >/dev/null 2>&1 || true
  else
    pkill -x udiskie >/dev/null 2>&1 || true
    hyprshell app -t service udiskie --smart-tray >/dev/null 2>&1 || true
  fi
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
  --waybar)
    devices_json | jq -r '
      (map(select(.mounted)) | length) as $mounted |
      length as $count |
      {
        text: (if $count == 0 then "" else "" end),
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
    udiskie_write "${next}" "$(udiskie_option notify true)"
    ;;
  --notify)
    current="$(udiskie_option notify true)"
    next="$(resolve_flag "${2:-toggle}" "${current}")" || {
      usage >&2
      exit 1
    }
    udiskie_write "$(udiskie_option automount true)" "${next}"
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
    udisksctl unmount -b "$2" --no-user-interaction >/dev/null 2>&1 || true
    # power-off takes the parent disk, not the partition
    parent="$(lsblk -no PKNAME "$2" 2>/dev/null | head -1)"
    udisksctl power-off -b "/dev/${parent:-$(basename "$2")}" --no-user-interaction >/dev/null
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

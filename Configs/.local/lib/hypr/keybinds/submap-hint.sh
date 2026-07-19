#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1

hypr_help_guard "Usage: hyprshell keybinds/submap-hint [--show NAME|--dismiss]
Show a keybind hint notification while a Hyprland submap is active.

With no arguments, watch submap events on socket2 and show the hint on entry,
dismiss it on exit." "$@"

SUBMAP_HINT_NOTIF_ID=9042

SUBMAP_HINT_SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"

hint_body() {
  local name="$1"
  python3 "${HYPR_LIB_DIR}/keybinds/lib/keybinds_hint.py" --format hint --submap "${name}" 2>/dev/null
}

show_hint() {
  local name="$1"
  local body=""

  body="$(hint_body "${name}")" || return 0
  [[ -n "${body}" ]] || return 0

  dunstify -u critical -a "Submap" -r "${SUBMAP_HINT_NOTIF_ID}" -t 0 \
    -h string:x-dunst-stack-tag:submap-hint \
    -- "${name^}:" "${body}" || true
}

dismiss_hint() {
  dunstify -C "${SUBMAP_HINT_NOTIF_ID}" 2>/dev/null || true
}

watch_submaps() {
  local socket_path="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
  local event=""

  [[ -S "${socket_path}" ]] || return 1
  command -v nc >/dev/null 2>&1 || return 1

  while IFS= read -r event; do
    case "${event}" in
      submap\>\>?*) "${SUBMAP_HINT_SELF}" --show "${event#submap>>}" || true ;;
      submap\>\>) "${SUBMAP_HINT_SELF}" --dismiss || true ;;
    esac
  done < <(nc -U "${socket_path}")
}

case "${1:-}" in
  --show)
    [[ -n "${2:-}" ]] || {
      printf 'submap-hint: --show needs a submap name\n' >&2
      exit 2
    }
    show_hint "$2"
    exit 0
    ;;
  --dismiss)
    dismiss_hint
    exit 0
    ;;
  "") ;;
  *)
    printf 'submap-hint: unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
esac

exec {hint_lock_fd}>"$(hypr_runtime_subdir hypr)/submap-hint.lock"
flock -n "${hint_lock_fd}" || exit 0

trap dismiss_hint EXIT

while true; do
  watch_submaps || true
  sleep 1
done

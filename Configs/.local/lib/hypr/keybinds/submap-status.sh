#!/usr/bin/env bash
set -uo pipefail

source "$(command -v hyprshell)" || exit 1

hypr_help_guard "Usage: hyprshell keybinds/submap-status
Emit the active Hyprland submap for a Waybar custom module (one line per change).

Prints the current submap on startup, then follows submap events, so a bar that
starts while a submap is active still shows it." "$@"

NO_SUBMAP="default"

# Waybar hides a custom module only when its rendered text is empty, and the
# module's format is static, so the glyph has to travel in "text".
SUBMAP_GLYPH="󰇘"
SUBMAP_GLYPH_ALT=""

alt_mode=false
[[ "${1:-}" == "--alt" || "${1:-}" == "-A" ]] && alt_mode=true

emit() {
  local name="${1:-}"
  local text="${SUBMAP_GLYPH}"
  "${alt_mode}" && text="${SUBMAP_GLYPH_ALT}"
  [[ "${name}" == "${NO_SUBMAP}" ]] && name=""
  if [[ -z "${name}" ]]; then
    printf '{"text":"","tooltip":"","class":""}\n'
  else
    "${alt_mode}" && text="${SUBMAP_GLYPH_ALT} ${name}"
    printf '{"text":"%s","tooltip":"submap: %s","class":"active","alt":"%s"}\n' \
      "${text}" "${name}" "${name}"
  fi
}

emit "$(hyprctl submap 2>/dev/null)"

socket_path="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
[[ -S "${socket_path}" ]] || exit 0
command -v nc >/dev/null 2>&1 || exit 0

while true; do
  while IFS= read -r event; do
    case "${event}" in
      submap\>\>*) emit "${event#submap>>}" ;;
    esac
  done < <(nc -U "${socket_path}" 2>/dev/null)
  sleep 1
  emit "$(hyprctl submap 2>/dev/null)"
done

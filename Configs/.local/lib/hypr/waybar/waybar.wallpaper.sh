#!/usr/bin/env bash

set -euo pipefail

waybar_wallpaper_usage() {
  cat <<'EOF'
Usage: waybar.wallpaper.sh [action] [wallpaper args...]

Actions:
  next        Rotate to the next wallpaper
  previous    Rotate to the previous wallpaper
  prev        Alias for previous
  random      Pick a random wallpaper
  select      Open the wallpaper selector
  resume      Reapply the current wallpaper
  start       Apply the current wallpaper to the backend

Any extra arguments are forwarded to `hyprshell wallpaper`.
Set `WAYBAR_WALLPAPER_FOREGROUND=1` to skip detaching.
EOF
}

waybar_wallpaper_map_args() {
  local action="${1:-}"

  case "${action}" in
    next)
      shift
      wallpaper_args=(-n "$@")
      ;;
    previous | prev)
      shift
      wallpaper_args=(-p "$@")
      ;;
    random)
      shift
      wallpaper_args=(-r "$@")
      ;;
    select)
      shift
      wallpaper_args=(--select "$@")
      ;;
    resume)
      shift
      wallpaper_args=(--resume "$@")
      ;;
    start)
      shift
      wallpaper_args=(--start "$@")
      ;;
    -h | --help | help)
      waybar_wallpaper_usage
      exit 0
      ;;
    *)
      wallpaper_args=("$@")
      ;;
  esac
}

hyprshell_bin="$(command -v hyprshell)"
[[ -n "${hyprshell_bin}" ]] || {
  printf 'Error: hyprshell not found in PATH\n' >&2
  exit 1
}

declare -a wallpaper_args=()
waybar_wallpaper_map_args "$@"

declare -a command_args=("${hyprshell_bin}" wallpaper "${wallpaper_args[@]}")

if [[ "${WAYBAR_WALLPAPER_FOREGROUND:-0}" == "1" ]]; then
  exec "${command_args[@]}"
fi

setsid -f "${command_args[@]}" >/dev/null 2>&1

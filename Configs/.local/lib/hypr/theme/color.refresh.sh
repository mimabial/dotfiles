#!/usr/bin/env bash

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: hyprshell color.refresh.sh [wallpaper]

Force a full color regeneration and reapply themed outputs.

Arguments:
  wallpaper    Optional wallpaper path to regenerate from.

Notes:
  - Bypasses the wal cache for this run.
  - If no wallpaper is provided, the current resolved wallpaper/theme source is used.
EOF
  exit 0
fi

source "$(command -v hyprshell)" || exit 1

export FORCE_COLOR_REGEN=1
export HYPR_WAL_CACHE_ENABLE=0

exec "${LIB_DIR}/hypr/theme/color.set.sh" "$@"

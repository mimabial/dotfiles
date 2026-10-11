#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

usage="Usage: hyprshell system/drive-info /dev/drive"
hypr_help_guard "${usage}
Print the size and model for a drive or partition." "$@"

(( $# )) || { echo "${usage}"; exit 1; }
drive=$1

read -r size root_drive < <(lsblk -dno SIZE,PKNAME "$drive" 2>/dev/null) || true
if [[ -n "$root_drive" ]]; then
  root_drive="/dev/$root_drive"
else
  root_drive="$drive"
fi

model=$(lsblk -dno MODEL "$root_drive" 2>/dev/null)

display="$drive"
[[ -n "$size" ]] && display="$display ($size)"
[[ -n "$model" ]] && display="$display - $model"

printf '%s\n' "$display"

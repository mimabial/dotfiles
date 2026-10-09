#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init cava theme

render_link_output "${XDG_CONFIG_HOME:-$HOME/.config}/cava/themes/hypr"

render_begin

render_read_palette
red="${c[1]}" green="${c[2]}" yellow="${c[3]}" blue="${c[4]}" magenta="${c[5]}" cyan="${c[6]}"
gradient=("${red}" "${green}" "${yellow}" "${blue}" "${magenta}" "${cyan}" "${magenta}" "${cyan}")
{
  printf '[color]\ngradient = 1\ngradient_count = %d\n' "${#gradient[@]}"
  for i in "${!gradient[@]}"; do
    printf "gradient_color_%d = '%s'\n" "$((i + 1))" "${gradient[i]}"
  done
} >"${tmp}"

render_commit "${tmp}" "${hash}"
trap - EXIT

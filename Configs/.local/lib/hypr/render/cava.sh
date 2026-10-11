#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" cava theme

render_link_output render_job "${XDG_CONFIG_HOME:-$HOME/.config}/cava/themes/hypr"

render_output_is_current render_job && exit 0
render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT

render_read_palette_into render_job
red="${render_job[color1]}" green="${render_job[color2]}" yellow="${render_job[color3]}" blue="${render_job[color4]}" magenta="${render_job[color5]}" cyan="${render_job[color6]}"
gradient=("${red}" "${green}" "${yellow}" "${blue}" "${magenta}" "${cyan}" "${magenta}" "${cyan}")
{
  printf '[color]\ngradient = 1\ngradient_count = %d\n' "${#gradient[@]}"
  for i in "${!gradient[@]}"; do
    printf "gradient_color_%d = '%s'\n" "$((i + 1))" "${gradient[i]}"
  done
} >"${render_job[staged_file]}"

render_commit_staged_output render_job
trap - EXIT

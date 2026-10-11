#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" zathura colors
render_link_output render_job "${XDG_CONFIG_HOME:-$HOME/.config}/zathura/colors"

render_output_is_current render_job && exit 0
render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT

render_read_palette_into render_job
red="${render_job[color1]}" green="${render_job[color2]}" yellow="${render_job[color3]}" accent="${render_job[color4]}" bar_fg="${render_job[color7]}" bar_bg="${render_job[color8]}"
cat >"${render_job[staged_file]}" <<EOF
set default-bg                  "${render_job[background_color]}"
set default-fg                  "${render_job[foreground_color]}"
set render-loading-bg           "${render_job[background_color]}"
set render-loading-fg           "${render_job[foreground_color]}"
set recolor-lightcolor          "${render_job[background_color]}"
set recolor-darkcolor           "${render_job[foreground_color]}"

set statusbar-bg                "${bar_bg}"
set statusbar-fg                "${bar_fg}"
set inputbar-bg                 "${bar_bg}"
set inputbar-fg                 "${bar_fg}"
set notification-bg             "${bar_bg}"
set notification-fg             "${bar_fg}"
set notification-error-bg       "${red}"
set notification-error-fg       "${bar_fg}"
set notification-warning-bg     "${yellow}"
set notification-warning-fg     "${bar_bg}"

set completion-bg               "${bar_bg}"
set completion-fg               "${accent}"
set completion-group-bg         "${bar_bg}"
set completion-group-fg         "${accent}"
set completion-highlight-bg     "${accent}"
set completion-highlight-fg     "${bar_bg}"

set index-bg                    "${bar_bg}"
set index-fg                    "${bar_fg}"
set index-active-bg             "${accent}"
set index-active-fg             "${bar_bg}"

set highlight-color             "${yellow}"
set highlight-active-color      "${green}"
EOF

render_commit_staged_output render_job
trap - EXIT

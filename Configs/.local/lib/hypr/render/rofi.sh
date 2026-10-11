#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" rofi colors.rasi

render_output_is_current render_job && exit 0
render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT

if [[ -n "${render_job[pack_override]}" ]]; then
  render_write_pack_override render_job
else
  read -r background_color foreground_color error_color active_color selected_color surface_color accent_color border_color < <(
    jq -r '"\(.bg) \(.fg) \(.colors[1]) \(.colors[2]) \(.colors[4]) \(.colors[8]) \(.colors[11]) \(.colors[12])"' "${render_job[palette_file]}"
  )
  cat > "${render_job[staged_file]}" <<EOF
* {
    background:          ${background_color};
    background-alpha:    ${surface_color}59;
    foreground:          ${foreground_color};
    border:              ${border_color};
    accent:              ${accent_color};
    selected-background: ${selected_color};
    selected-foreground: ${background_color};
    separator:           ${surface_color};
    urgent:              ${error_color};
    active:              ${active_color};
}
EOF
fi

render_commit_staged_output render_job
trap - EXIT

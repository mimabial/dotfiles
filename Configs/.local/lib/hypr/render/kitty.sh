#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" kitty colors.conf

render_output_is_current render_job && exit 0
render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT

if [[ -n "${render_job[pack_override]}" ]]; then
  render_write_pack_override render_job
else
  jq -r '
    "background " + .bg,
    "foreground " + .fg,
    (.colors | to_entries[] | "color\(.key) " + .value)
  ' "${render_job[palette_file]}" > "${render_job[staged_file]}"
fi

render_commit_staged_output render_job
trap - EXIT

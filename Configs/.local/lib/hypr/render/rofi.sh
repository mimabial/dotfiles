#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" rofi colors.rasi quickshell.theme
popup_adapter="${BASH_SOURCE[0]%/*}/../rofi/lib/popup_style.py"
popup_rasi="$(render_palette_roles render_job | python3 "${popup_adapter}" render)"
render_fold_stdin_into_input_digest render_job < <(printf '%s' "${popup_rasi}")

render_output_is_current render_job && exit 0
render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT
printf '%s\n' "${popup_rasi}" >"${render_job[staged_file]}"
render_commit_staged_output render_job
trap - EXIT

#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" alacritty colors.toml

render_output_is_current render_job && exit 0
render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT

if [[ -n "${render_job[pack_override]}" ]]; then
  render_write_pack_override render_job
else
  jq -r '
    def pair($name; $value): $name + " = \"" + $value + "\"";
    ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"] as $names
    | . as $palette
    | (["[colors.primary]", pair("background"; .bg), pair("foreground"; .fg), "",
        "[colors.cursor]", pair("text"; .bg), pair("cursor"; .fg), "",
        "[colors.selection]", pair("text"; .fg), pair("background"; .colors[4]), "",
        "[colors.normal]"]
       + ([range(0; 8)] | map(pair($names[.]; $palette.colors[.])))
       + ["", "[colors.bright]"]
       + ([range(0; 8)] | map(pair($names[.]; $palette.colors[. + 8]))))
    | .[]
  ' "${render_job[palette_file]}" > "${render_job[staged_file]}"
fi

render_commit_staged_output render_job
trap - EXIT

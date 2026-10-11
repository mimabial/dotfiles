#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" hyprlock colors.conf
LOCK_SCREEN_RADIUS_SCALE=2

font_name="$("${BASH_SOURCE[0]%/*}/../fonts/font-get.sh" bar 2>/dev/null || true)"
# Doubled: lock screen panels dwarf a window, so the theme's radius reads as square.
corner_radius="$(sed -nE 's/.*runtime\.config\("decoration\.rounding", *([0-9]+)\).*/\1/p' \
  "${RENDER_CONFIG_DIR}/themes/theme.lua" 2>/dev/null | head -n1 || true)"
corner_radius="$((${corner_radius:-0} * LOCK_SCREEN_RADIUS_SCALE))"
layout_dirs=("${RENDER_CONFIG_DIR}/hyprlock"
  "${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/hyprlock")
tones="$(grep -rhoE --include='*.conf' '\$tone\.c[1-6]\.[0-9]+\.[0-9]+' "${layout_dirs[@]}" 2>/dev/null | sort -u | tr '\n' ' ' || true)"
placeholders="$(grep -rhoE --include='*.conf' '<span size="\$ph\.[0-9]+\.[0-9]+\.[0-9a-f]+">.*</span>' "${layout_dirs[@]}" 2>/dev/null | sort -u || true)"
render_fold_stdin_into_input_digest render_job < <(
  cat "${BASH_SOURCE[0]%/*}/_hyprlock_colors.py" "${BASH_SOURCE[0]%/*}/_common.py"
  printf 'font:%s\nrounding:%s\ntones:%s\nplaceholders:%s\n' "${font_name}" "${corner_radius}" "${tones}" "${placeholders}"
)
render_output_is_current render_job && exit 0
render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT

python3 "${BASH_SOURCE[0]%/*}/_hyprlock_colors.py" "${render_job[palette_file]}" \
  "${font_name}" "${corner_radius}" "${tones}" "${placeholders}" >"${render_job[staged_file]}"

render_commit_staged_output render_job
trap - EXIT

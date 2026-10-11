#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" quickshell theme.json quickshell.theme

theme_metadata_file="${RENDER_CONFIG_DIR}/themes/theme.meta"
read_theme_metric_number() {
  awk -F= -v key="$1" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { gsub(/[[:space:]]/, "", $2); print $2; exit }
  ' "${theme_metadata_file}" 2>/dev/null || true
}
rounding="$(read_theme_metric_number rounding)"
[[ "${rounding}" =~ ^[0-9]+([.][0-9]+)?$ ]] || rounding=0
border="$(read_theme_metric_number border_size)"
[[ "${border}" =~ ^[0-9]+([.][0-9]+)?$ ]] || border=0

render_fold_stdin_into_input_digest render_job < <(printf 'rounding:%s\nborder:%s\n' "${rounding}" "${border}")
render_output_is_current render_job && exit 0

render_stage_output_into render_job
trap 'rm -f -- "${render_job[staged_file]}"' EXIT

palette_roles_json=""
# A pack override is a flat {role: "#hex"} object. Unreadable or malformed packs
# fall through to the palette-derived defaults rather than failing the render.
if [[ -n "${render_job[pack_override]}" ]]; then
  palette_roles_json="$(jq -ce 'with_entries(select(.value | type == "string"))' "${render_job[pack_override]}" 2>/dev/null || true)"
fi

if [[ -z "${palette_roles_json}" ]]; then
  palette_roles_json="$(jq -c "${RENDER_PALETTE_ROLES_JQ} + {background: .bg, foreground: .fg}\
    ${RENDER_PALETTE_NUMBERED_JQ}" "${render_job[palette_file]}")"
fi

[[ "$(jq -r 'length' <<<"${palette_roles_json}")" -gt 0 ]] || {
  echo "render/quickshell: empty palette" >&2
  exit 1
}

jq -n --argjson palette "${palette_roles_json}" --argjson rounding "${rounding}" --argjson border "${border}" \
  '{rounding: $rounding, borderSize: $border, palette: $palette}' > "${render_job[staged_file]}"

render_commit_staged_output render_job
trap - EXIT

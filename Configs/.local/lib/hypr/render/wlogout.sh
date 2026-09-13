#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init wlogout colors.css

render_begin

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
else
  jq -r "${RENDER_PALETTE_ROLES_JQ} ${RENDER_PALETTE_NUMBERED_JQ} | to_entries
    | map(\"@define-color \(.key) \(.value);\") | .[]" "${PALETTE}" > "${tmp}"
fi

render_commit "${tmp}" "${hash}"
trap - EXIT

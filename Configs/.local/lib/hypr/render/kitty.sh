#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init kitty colors.conf

render_begin

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
else
  jq -r '
    "background " + .bg,
    "foreground " + .fg,
    (.colors | to_entries[] | "color\(.key) " + .value)
  ' "${PALETTE}" > "${tmp}"
fi

render_commit "${tmp}" "${hash}"
trap - EXIT

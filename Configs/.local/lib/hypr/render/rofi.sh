#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init rofi colors.rasi

hash="$(render_input_hash)"
render_should_skip "${hash}" && exit 0

tmp="$(render_temp)"
trap 'rm -f "${tmp}"' EXIT

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
else
  read -r bg fg c1 c2 c4 c8 c11 c12 < <(
    jq -r '"\(.bg) \(.fg) \(.colors[1]) \(.colors[2]) \(.colors[4]) \(.colors[8]) \(.colors[11]) \(.colors[12])"' "${PALETTE}"
  )
  cat > "${tmp}" <<EOF
* {
    background:          ${bg};
    background-alpha:    ${c8}59;
    foreground:          ${fg};
    border:              ${c12};
    accent:              ${c11};
    selected-background: ${c4};
    selected-foreground: ${bg};
    separator:           ${c8};
    urgent:              ${c1};
    active:              ${c2};
}
EOF
fi

render_commit "${tmp}" "${hash}"
trap - EXIT

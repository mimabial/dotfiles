#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init wlogout colors.css

hash="$(render_input_hash)"
render_should_skip "${hash}" && exit 0

tmp="$(render_temp)"
trap 'rm -f "${tmp}"' EXIT

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
else
  # Role names and derivation match render/quickshell.sh so both bars and the
  # logout menu resolve @accent, @bg and friends to the same colours.
  jq -r '
    .colors as $c | {
      bg: .bg, fg: .fg, br: $c[5],
      alt_bg: $c[6], alt_fg: $c[3], alt_br: $c[11],
      fg_selected: $c[4],
      act_bg: $c[8], act_fg: $c[7], act_br: $c[13],
      hvr_bg: .bg, hvr_fg: .fg, hvr_br: $c[12],
      accent: $c[12], info: $c[6], warning: $c[3], error: $c[1], success: $c[2]
    } + ([range(0; 16)] | map({key: ("c" + tostring), value: $c[.]}) | from_entries)
    | to_entries | map("@define-color \(.key) \(.value);") | .[]
  ' "${PALETTE}" > "${tmp}"
fi

render_commit "${tmp}" "${hash}"
trap - EXIT

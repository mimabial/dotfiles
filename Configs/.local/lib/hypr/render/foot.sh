#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init foot colors.ini

render_begin

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
else
  render_read_palette
  bg="${bg#\#}" fg="${fg#\#}" c=("${c[@]#\#}")
  {
    printf '[colors-dark]\nbackground=%s\nforeground=%s\ncursor=%s %s\n' "${bg}" "${fg}" "${bg}" "${fg}"
    for i in {0..7}; do
      printf 'regular%d=%s\nbright%d=%s\n' "${i}" "${c[i]}" "${i}" "${c[i + 8]}"
    done
  } > "${tmp}"
fi

render_commit "${tmp}" "${hash}"
trap - EXIT

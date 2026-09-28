#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init alacritty colors.toml

render_begin

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
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
  ' "${PALETTE}" > "${tmp}"
fi

render_commit "${tmp}" "${hash}"
trap - EXIT

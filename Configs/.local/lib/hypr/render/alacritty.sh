#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init alacritty colors.toml

render_begin

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
else
  render_read_palette
  cat > "${tmp}" <<EOF
[colors.primary]
background = "${bg}"
foreground = "${fg}"

[colors.cursor]
text   = "${bg}"
cursor = "${fg}"

[colors.search.matches]
foreground = "${c[0]}"
background = "${c[15]}"

[colors.footer_bar]
foreground = "${c[8]}"
background = "${c[7]}"

[colors.normal]
black   = "${c[0]}"
red     = "${c[1]}"
green   = "${c[2]}"
yellow  = "${c[3]}"
blue    = "${c[4]}"
magenta = "${c[5]}"
cyan    = "${c[6]}"
white   = "${c[7]}"

[colors.bright]
black   = "${c[8]}"
red     = "${c[9]}"
green   = "${c[10]}"
yellow  = "${c[11]}"
blue    = "${c[12]}"
magenta = "${c[13]}"
cyan    = "${c[14]}"
white   = "${c[15]}"
EOF
fi

render_commit "${tmp}" "${hash}"
trap - EXIT

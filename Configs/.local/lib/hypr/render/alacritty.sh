#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init alacritty colors.toml

hash="$(render_input_hash)"
render_should_skip "${hash}" && exit 0

tmp="$(render_temp)"
trap 'rm -f "${tmp}"' EXIT

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
else
  mapfile -t C < <(jq -r '.bg, .fg, (.colors[])' "${PALETTE}")
  bg="${C[0]}" fg="${C[1]}"
  c=("${C[@]:2}")
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

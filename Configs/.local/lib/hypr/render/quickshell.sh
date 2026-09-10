#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init quickshell theme.json quickshell.theme

theme_meta="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}/themes/theme.meta"
meta_number() {
  awk -F= -v key="$1" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { gsub(/[[:space:]]/, "", $2); print $2; exit }
  ' "${theme_meta}" 2>/dev/null || true
}
rounding="$(meta_number rounding)"
[[ "${rounding}" =~ ^[0-9]+([.][0-9]+)?$ ]] || rounding=0
border="$(meta_number border_size)"
[[ "${border}" =~ ^[0-9]+([.][0-9]+)?$ ]] || border=0

hash="$(
  {
    render_input_hash
    printf 'rounding:%s\nborder:%s\n' "${rounding}" "${border}"
  } | { xxh64sum 2>/dev/null || md5sum; } | awk '{print $1}'
)"
render_should_skip "${hash}" && exit 0

tmp="$(render_temp)"
trap 'rm -f "${tmp}"' EXIT

palette=""
# A pack override is a flat {role: "#hex"} object. Unreadable or malformed packs
# fall through to the palette-derived defaults rather than failing the render.
if [[ -n "${PACK_OVERRIDE}" ]]; then
  palette="$(jq -ce 'with_entries(select(.value | type == "string"))' "${PACK_OVERRIDE}" 2>/dev/null || true)"
fi

if [[ -z "${palette}" ]]; then
  palette="$(jq -c '
    .colors as $c | {
      bg: .bg, fg: .fg, br: $c[5],
      alt_bg: $c[6], alt_fg: $c[3], alt_br: $c[11],
      fg_selected: $c[4],
      act_bg: $c[8], act_fg: $c[7], act_br: $c[13],
      hvr_bg: .bg, hvr_fg: .fg, hvr_br: $c[12],
      accent: $c[12], info: $c[6], warning: $c[3], error: $c[1], success: $c[2],
      background: .bg, foreground: .fg
    } + ([range(0; 16)] | map({key: ("c" + tostring), value: $c[.]}) | from_entries)
  ' "${PALETTE}")"
fi

[[ "$(jq -r 'length' <<<"${palette}")" -gt 0 ]] || {
  echo "render/quickshell: empty palette" >&2
  exit 1
}

jq -n --argjson palette "${palette}" --argjson rounding "${rounding}" --argjson border "${border}" \
  '{rounding: $rounding, borderSize: $border, palette: $palette}' > "${tmp}"

render_commit "${tmp}" "${hash}"
trap - EXIT

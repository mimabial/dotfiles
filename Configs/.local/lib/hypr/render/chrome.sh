#!/usr/bin/env bash
# Renderer: chromium theme (manifest.json + ntp background image).
# Output: ~/.cache/hypr/render/chrome/Pywal16-chrome-theme/{manifest.json,images/}
# User loads this directory as an unpacked extension in Chrome.

set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init chrome manifest.json nonexistent.theme

THEME_DIR="${OUT_DIR}/Pywal16-chrome-theme"
IMG_DIR="${THEME_DIR}/images"
IMG_FILE="${IMG_DIR}/theme_ntp_background_norepeat.png"
MANIFEST="${THEME_DIR}/manifest.json"
OUT_FILE="${MANIFEST}"

WALL="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wal.set.png"

hash="$(
  {
    cat "${PALETTE}"
    [[ -f "${WALL}" ]] && md5sum "${WALL}"
    cat "${BASH_SOURCE[0]}"
  } | { xxh64sum 2>/dev/null || md5sum; } | awk '{print $1}'
)"
render_should_skip "${hash}" && exit 0

rgb() {
  local h="${1#\#}"
  printf '%d, %d, %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

mapfile -t C < <(jq -r '.bg, .fg, (.colors[])' "${PALETTE}")
c=("${C[@]:2}")
background="$(rgb "${c[0]}")"
foreground="$(rgb "${c[15]}")"
accent="$(rgb "${c[4]}")"
secondary="$(rgb "${c[8]}")"

staging="$(mktemp -d "${OUT_DIR}/.staging.XXXXXX")"
trap 'rm -rf -- "${staging}"' EXIT
mkdir -p "${staging}/images"
[[ -f "${WALL}" ]] && cp -f "${WALL}" "${staging}/images/theme_ntp_background_norepeat.png"

cat > "${staging}/manifest.json" <<EOF
{
  "manifest_version": 3,
  "version": "1.0",
  "name": "Pywal16 Theme",
  "theme": {
    "images": { "theme_ntp_background": "images/theme_ntp_background_norepeat.png" },
    "colors": {
      "frame": [${background}],
      "frame_inactive": [${background}],
      "toolbar": [${accent}],
      "ntp_text": [${foreground}],
      "ntp_link": [${accent}],
      "ntp_section": [${secondary}],
      "button_background": [${foreground}],
      "toolbar_button_icon": [${foreground}],
      "toolbar_text": [${foreground}],
      "omnibox_background": [${background}],
      "omnibox_text": [${foreground}]
    },
    "properties": { "ntp_background_alignment": "bottom" }
  }
}
EOF

rm -rf -- "${THEME_DIR}"
mv -f "${staging}" "${THEME_DIR}"
trap - EXIT
render-cache store chrome "${hash}"

#!/usr/bin/env bash
# Generate Chrome theme from pywal16 colors
# Based on https://github.com/metafates/ChromiumPywal

# Source pywal16 colors
if ! source "${HOME}/.cache/wal/colors-shell.sh" 2>/dev/null; then
  echo "[chrome] Error: pywal16 colors not found"
  exit 1
fi

THEME_NAME="Wallust"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
THEME_DIR="${CACHE_DIR}/${THEME_NAME}-chrome-theme"

# Hex to RGB converter
hexToRgb() {
  local hex="${1#\#}"
  printf "%d, %d, %d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Clean and recreate theme directory
rm -rf "${THEME_DIR}"
mkdir -p "${THEME_DIR}/images"

# Copy wallpaper if available
if [ -f "${CACHE_DIR}/wal.set.png" ]; then
  cp "${CACHE_DIR}/wal.set.png" "${THEME_DIR}/images/theme_ntp_background_norepeat.png" 2>/dev/null
fi

# Convert colors
background=$(hexToRgb "${color0}")
foreground=$(hexToRgb "${color15}")
accent=$(hexToRgb "${color4}")
secondary=$(hexToRgb "${color8}")

# Generate manifest.json
cat >"${THEME_DIR}/manifest.json" <<EOF
{
  "manifest_version": 3,
  "version": "1.0",
  "name": "${THEME_NAME} Theme",
  "theme": {
    "images": {
      "theme_ntp_background": "images/theme_ntp_background_norepeat.png"
    },
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
    "properties": {
      "ntp_background_alignment": "bottom"
    }
  }
}
EOF

echo "[chrome] Theme generated at ${THEME_DIR}"

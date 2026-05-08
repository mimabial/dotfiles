#!/usr/bin/env bash
# Generate Chrome theme from pywal16 colors
# Based on https://github.com/metafates/ChromiumPywal
#
# Subsystem inputs (sourced from ${WAL_COLORS_FILE} below):
#   color0, color4, color8, color15
: "${color0-}" "${color4-}" "${color8-}" "${color15-}"

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/core/hash-cache.sh" || exit 1
if [[ -r "${LIB_DIR}/hypr/theme/phase-d.sh" ]]; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/hypr/theme/phase-d.sh" || exit 1
  theme_phase_d_init "${HYPR_THEME_PHASE_D_LOCK_KEY:-theme_phase_d_chrome}"
fi

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
WAL_COLORS_FILE="${WAL_CACHE}/colors-shell.sh"
WALLPAPER_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wal.set.png"
THEME_NAME="Pywal16"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
THEME_DIR="${CACHE_DIR}/${THEME_NAME}-chrome-theme"
THEME_IMAGE_DIR="${THEME_DIR}/images"
THEME_IMAGE_FILE="${THEME_IMAGE_DIR}/theme_ntp_background_norepeat.png"
MANIFEST_FILE="${THEME_DIR}/manifest.json"
STATE_FILE="${THEME_DIR}/.hypr-theme-state"
HASH_FILE="$(hypr_hash_cache_file "wal-chrome.hash")" || exit 1
STAGING_DIR=""

# Source pywal16 colors
# shellcheck source=/dev/null
source "${WAL_COLORS_FILE}" 2>/dev/null || {
  echo "[chrome] Error: pywal16 colors not found"
  exit 1
}

# Hex to RGB converter
hex_to_rgb() {
  local hex="${1#\#}"
  printf "%d, %d, %d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

chrome_wallpaper_present() {
  [[ -f "${WALLPAPER_CACHE_FILE}" ]]
}

chrome_expected_hash() {
  if chrome_wallpaper_present; then
    hypr_hash_cache_digest_files "${WAL_COLORS_FILE}" "${WALLPAPER_CACHE_FILE}"
  else
    hypr_hash_cache_digest_files "${WAL_COLORS_FILE}"
  fi
}

chrome_outputs_current() {
  local expected_hash="$1"
  local wallpaper_present=0
  local -a outputs=("${MANIFEST_FILE}")
  local -a metadata=()

  if chrome_wallpaper_present; then
    wallpaper_present=1
    outputs+=("${THEME_IMAGE_FILE}")
  fi

  metadata+=("wallpaper_present=${wallpaper_present}")

  hypr_hash_cache_outputs_current \
    "${HASH_FILE}" "${expected_hash}" "${STATE_FILE}" \
    --outputs "${outputs[@]}" \
    --metadata "${metadata[@]}" || return 1

  if [[ "${wallpaper_present}" -eq 0 && -e "${THEME_IMAGE_FILE}" ]]; then
    return 1
  fi
}

chrome_record_outputs() {
  local expected_hash="$1"
  local wallpaper_present="$2"

  hypr_hash_cache_store "${HASH_FILE}" "${expected_hash}"
  hypr_hash_cache_metadata_store "${STATE_FILE}" \
    "wallpaper_present=${wallpaper_present}" \
    "input_hash=${expected_hash}"
}

expected_hash="$(chrome_expected_hash)"
if chrome_outputs_current "${expected_hash}"; then
  exit 0
fi

# Clean and recreate theme directory
STAGING_DIR="$(mktemp -d "${CACHE_DIR}/${THEME_NAME}-chrome-theme.tmp.XXXXXXXX")" || exit 1
trap '[[ -n "${STAGING_DIR}" && -d "${STAGING_DIR}" ]] && rm -rf -- "${STAGING_DIR}"' EXIT
THEME_IMAGE_DIR="${STAGING_DIR}/images"
THEME_IMAGE_FILE="${THEME_IMAGE_DIR}/theme_ntp_background_norepeat.png"
MANIFEST_FILE="${STAGING_DIR}/manifest.json"
mkdir -p "${THEME_IMAGE_DIR}"

# Copy wallpaper if available
wallpaper_present=0
if chrome_wallpaper_present; then
  cp "${WALLPAPER_CACHE_FILE}" "${THEME_IMAGE_FILE}" 2>/dev/null
  wallpaper_present=1
fi

# Convert colors
background=$(hex_to_rgb "${color0}")
foreground=$(hex_to_rgb "${color15}")
accent=$(hex_to_rgb "${color4}")
secondary=$(hex_to_rgb "${color8}")

# Generate manifest.json
cat >"${MANIFEST_FILE}" <<EOF
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

if declare -F theme_phase_d_promote_dir >/dev/null 2>&1; then
  theme_phase_d_promote_dir "${STAGING_DIR}" "${THEME_DIR}" || exit 1
  STAGING_DIR=""
  theme_phase_d_run_locked_if_current chrome_record_outputs "${expected_hash}" "${wallpaper_present}" || exit 1
else
  rm -rf "${THEME_DIR}"
  mv -f "${STAGING_DIR}" "${THEME_DIR}"
  STAGING_DIR=""
  chrome_record_outputs "${expected_hash}" "${wallpaper_present}"
fi

echo "[chrome] Theme generated at ${THEME_DIR}"

#!/usr/bin/env bash
# wal.gimp.sh - Apply pywal16 colors to GIMP 3.x
#
# Generates @define-color overrides for GIMP's gimp.css, mapping the pywal16
# palette onto the named colors that gimp-dark.css / gimp-light.css define.
# The gimp.css file is loaded last in GIMP's theme.css import chain, so our
# @define-color entries take precedence.
#
# GIMP must be restarted (or Edit > Preferences > Theme > reload) to pick up
# the new colors. There is no runtime reload signal.

set -euo pipefail

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
HASH_FILE="${XDG_RUNTIME_DIR:-/tmp}/wal-gimp-hash"

# Find the most recent GIMP 3.x config directory
find_gimp_config_dir() {
  local gimp_base="${XDG_CONFIG_HOME:-$HOME/.config}/GIMP"
  local best=""

  [[ -d "${gimp_base}" ]] || return 1

  local dir
  for dir in "${gimp_base}"/3.*; do
    [[ -d "${dir}" ]] || continue
    best="${dir}"
  done

  [[ -n "${best}" ]] && printf '%s' "${best}" && return 0
  return 1
}

GIMP_DIR="$(find_gimp_config_dir)" || exit 0
GIMP_CSS="${GIMP_DIR}/gimp.css"

# --- Color math helpers ---

hex_to_dec() { printf '%d' "0x${1}"; }

# Clamp an integer to 0-255.
clamp() {
  local v="$1"
  (( v < 0 )) && v=0
  (( v > 255 )) && v=255
  printf '%d' "${v}"
}

# Parse #RRGGBB into decimal R G B (space-separated).
parse_hex() {
  local hex="${1#\#}"
  printf '%d %d %d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Shift each channel by a signed offset, clamped to 0-255.
shift_color() {
  local hex="$1" offset="$2"
  local r g b
  read -r r g b <<< "$(parse_hex "${hex}")"
  r="$(clamp $(( r + offset )))"
  g="$(clamp $(( g + offset )))"
  b="$(clamp $(( b + offset )))"
  printf 'rgb(%d,%d,%d)' "${r}" "${g}" "${b}"
}

# Convert #RRGGBB to rgb(R,G,B).
hex_to_rgb() {
  local r g b
  read -r r g b <<< "$(parse_hex "$1")"
  printf 'rgb(%d,%d,%d)' "${r}" "${g}" "${b}"
}

# Convert #RRGGBB to rgba(R,G,B,A) where A is 0.0-1.0.
hex_to_rgba() {
  local r g b
  read -r r g b <<< "$(parse_hex "$1")"
  printf 'rgba(%d,%d,%d,%s)' "${r}" "${g}" "${b}" "${2}"
}

# Blend two hex colors. $3 is the weight of $2 (0-100).
blend() {
  local r1 g1 b1 r2 g2 b2 w
  read -r r1 g1 b1 <<< "$(parse_hex "$1")"
  read -r r2 g2 b2 <<< "$(parse_hex "$2")"
  w="$3"
  local r=$(( (r1 * (100 - w) + r2 * w) / 100 ))
  local g=$(( (g1 * (100 - w) + g2 * w) / 100 ))
  local b=$(( (b1 * (100 - w) + b2 * w) / 100 ))
  printf 'rgb(%d,%d,%d)' "$(clamp ${r})" "$(clamp ${g})" "$(clamp ${b})"
}

# Compute perceived luminance (0-255) of a hex color.
luminance() {
  local r g b
  read -r r g b <<< "$(parse_hex "$1")"
  # Approximate: 0.299R + 0.587G + 0.114B
  printf '%d' $(( (r * 299 + g * 587 + b * 114) / 1000 ))
}

# --- Main ---

[[ -f "${WAL_CACHE}/colors-shell.sh" ]] || exit 0
# shellcheck disable=SC1090
source "${WAL_CACHE}/colors-shell.sh"

# Detect dark vs light based on background luminance.
bg_lum="$(luminance "${background}")"
if (( bg_lum < 128 )); then
  is_dark=1
else
  is_dark=0
fi

# Build the GIMP @define-color palette from pywal colors.
#
# GIMP's Default theme defines these named colors (see gimp-dark.css):
#   fg-color, bg-color, border-color, dimmed-fg-color, disabled-fg-color,
#   disabled-button-color, hover-color, widget-bg-color, selected-color,
#   extreme-bg-color, extreme-selected-color, strong-border-color,
#   stronger-border-color, edge-border-color, scrollbar-slider-color,
#   scrollbar-trough-color, ruler-color

bg_rgb="$(hex_to_rgb "${background}")"
fg_rgb="$(hex_to_rgb "${foreground}")"

if (( is_dark )); then
  widget_bg="$(shift_color "${background}" -18)"
  extreme_bg="$(shift_color "${background}" -24)"
  hover="$(shift_color "${background}" 40)"
  selected="$(shift_color "${background}" -30)"
  extreme_selected="$(shift_color "${background}" -5)"
  border="$(shift_color "${background}" -34)"
  strong_border="$(shift_color "${background}" -20)"
  stronger_border="$(shift_color "${background}" 15)"
  edge_border="$(shift_color "${background}" -34)"
  dimmed_fg="$(blend "${foreground}" "${background}" 40)"
  disabled_fg="$(blend "${foreground}" "${background}" 45)"
  disabled_button="$(blend "${foreground}" "${background}" 60)"
  scrollbar_slider="$(blend "${foreground}" "${background}" 30)"
else
  widget_bg="$(shift_color "${background}" 18)"
  extreme_bg="$(shift_color "${background}" 24)"
  hover="$(shift_color "${background}" -40)"
  selected="$(shift_color "${background}" 30)"
  extreme_selected="$(shift_color "${background}" 5)"
  border="$(shift_color "${background}" 34)"
  strong_border="$(shift_color "${background}" 20)"
  stronger_border="$(shift_color "${background}" -15)"
  edge_border="$(shift_color "${background}" 34)"
  dimmed_fg="$(blend "${foreground}" "${background}" 40)"
  disabled_fg="$(blend "${foreground}" "${background}" 45)"
  disabled_button="$(blend "${foreground}" "${background}" 60)"
  scrollbar_slider="$(blend "${foreground}" "${background}" 30)"
fi

scrollbar_trough="${bg_rgb}"
ruler="$(hex_to_rgba "${background}" "0.3")"

# Build hash of inputs to skip no-op writes.
input_hash="$(printf '%s\n' "${background}" "${foreground}" "${color0:-}" "${color4:-}" "${color8:-}" | md5sum | cut -d' ' -f1)"
if [[ -f "${HASH_FILE}" && "$(cat "${HASH_FILE}" 2>/dev/null)" == "${input_hash}" ]]; then
  exit 0
fi

# Write gimp.css with @define-color overrides.
tmp_css="$(mktemp "${GIMP_DIR}/.gimp.css.XXXXXX")"
trap 'rm -f "${tmp_css}" 2>/dev/null' EXIT

cat > "${tmp_css}" <<CSS
/* Auto-generated by wal.gimp.sh — do not edit manually.
 * Source: pywal16 colors from ${WAL_CACHE}/colors-shell.sh
 */

@define-color fg-color               ${fg_rgb};
@define-color bg-color               ${bg_rgb};
@define-color border-color           ${border};
@define-color dimmed-fg-color        ${dimmed_fg};
@define-color disabled-fg-color      ${disabled_fg};
@define-color disabled-button-color  ${disabled_button};
@define-color hover-color            ${hover};
@define-color widget-bg-color        ${widget_bg};
@define-color selected-color         ${selected};
@define-color extreme-bg-color       ${extreme_bg};
@define-color extreme-selected-color ${extreme_selected};
@define-color strong-border-color    ${strong_border};
@define-color stronger-border-color  ${stronger_border};
@define-color edge-border-color      ${edge_border};
@define-color scrollbar-slider-color ${scrollbar_slider};
@define-color scrollbar-trough-color ${scrollbar_trough};
@define-color ruler-color            ${ruler};
CSS

mv "${tmp_css}" "${GIMP_CSS}"
trap - EXIT

echo "${input_hash}" > "${HASH_FILE}"
echo "[gimp] Generated gimp.css"

#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/fonts/lib/font-packages.bash" || exit 1

hypr_help_guard "Usage: hyprshell fonts/find-unused
Audit installed and local fonts not referenced by your config, then optionally remove them." "$@"

MIN_ALIAS_LENGTH=4
FAMILY_SUMMARY_LIMIT=3
FONT_EXT_REGEX='\.(ttf|otf|ttc|otb|pfa|pfb|woff2?)$'
LOCAL_FONT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
SEARCH_ROOTS=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
  "${XDG_CONFIG_HOME:-$HOME/.config}/rofi"
  "${XDG_DATA_HOME:-$HOME/.local/share}/rofi"
  "${XDG_DATA_HOME:-$HOME/.local/share}/hypr"
  "${XDG_CONFIG_HOME:-$HOME/.config}/dunst"
  "${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
  "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty"
  "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig"
  "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0"
  "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0"
  "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  "${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
  "${XDG_CONFIG_HOME:-$HOME/.config}/swappy"
  "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}"
)
SEARCH_GLOBS=(
  '!**/.git/**'
  '!**/plugins/**'
  '!**/chromium/**'
  '!**/GIMP/**'
  '!**/libreoffice/**'
  '!**/__pycache__/**'
  '!**/tags.xml'
)
GSETTINGS_FONT_KEYS=(
  "org.gnome.desktop.interface font-name"
  "org.gnome.desktop.interface document-font-name"
  "org.gnome.desktop.interface monospace-font-name"
  "org.gnome.desktop.wm.preferences titlebar-font"
)
SKIP_PACKAGES_REGEX='^(fontconfig|lib32-fontconfig|libfontenc|libxfont2|xorg-fonts-encodings)$'
declare -ga ACTIVE_SEARCH_ROOTS=() RG_ARGS=() LIVE_FONT_REFS=() INSTALLED_FONT_PACKAGES=() LOCAL_FONT_FAMILIES=()
declare -gA PACKAGE_FAMILY_CACHE=() PACKAGE_FONT_FILES=()
declare -ga FONT_REFERENCE_LINES=()
declare -gA LOCAL_FAMILY_FILES=()
declare -gA LOCAL_FILE_FAMILIES=()
declare -ga ACTIVE_PACKAGES=() INSTALLED_CONFIG_PACKAGES=() FALLBACK_PACKAGES=()
declare -ga UNUSED_PACKAGES=() REQUIRED_PACKAGES=()
declare -gA PACKAGE_MATCHES=() PACKAGE_MATCH_FAMILIES=()
declare -ga LOCAL_ACTIVE_FAMILIES=() LOCAL_INSTALLED_CONFIG_FAMILIES=()
declare -ga LOCAL_FALLBACK_FAMILIES=() LOCAL_UNUSED_FAMILIES=()
declare -gA LOCAL_MATCHES=() UNUSED_LOCAL_FAMILY_MAP=()
declare -g FONT_REFERENCE_CONTENT_FILE="" FONT_REFERENCE_CASEFOLDED_TEXT=""

main() {
  local -a removable_local_files=()
  local required_tool=""
  for required_tool in pacman rg fc-scan; do
    require_cmd "${required_tool}" || return 1
  done

  collect_search_roots_into ACTIVE_SEARCH_ROOTS
  build_rg_args_into RG_ARGS
  collect_live_font_refs_into LIVE_FONT_REFS
  collect_installed_font_packages_into INSTALLED_FONT_PACKAGES PACKAGE_FONT_FILES
  print_header
  collect_local_font_families_into LOCAL_FONT_FAMILIES LOCAL_FAMILY_FILES LOCAL_FILE_FAMILIES
  FONT_REFERENCE_CONTENT_FILE="$(mktemp)"
  trap 'rm -f -- "${FONT_REFERENCE_CONTENT_FILE}"' EXIT
  collect_font_reference_lines

  classify_packages
  classify_local_families

  print_package_section "ACTIVE PACKAGE FONT REFERENCES:" \
    "No active package font references found." "✓" ACTIVE_PACKAGES
  print_package_section "INSTALLED THEME/TEMPLATE PACKAGE REFERENCES:" \
    "No package fonts are kept only by installed themes/templates." "•" INSTALLED_CONFIG_PACKAGES
  print_package_section "FALLBACK-ONLY FONT REFERENCES:" \
    "No fallback-only font references found." "•" FALLBACK_PACKAGES

  report_unused_packages
  offer_unused_package_removal
  report_local_families removable_local_files
  offer_unused_local_file_removal removable_local_files
  report_required_packages
  print_notes
}

source "${BASH_SOURCE[0]%/*}/lib/font-inventory.bash"
source "${BASH_SOURCE[0]%/*}/lib/font-references.bash"
source "${BASH_SOURCE[0]%/*}/lib/font-audit-report.bash"
source "${BASH_SOURCE[0]%/*}/lib/font-removal.bash"

main "$@"

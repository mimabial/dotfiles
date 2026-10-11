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
declare -gA PACKAGE_FAMILY_CACHE=()
declare -gA LOCAL_FAMILY_FILES=()
declare -gA LOCAL_FILE_FAMILIES=()
declare -ga ACTIVE_PACKAGES=() INSTALLED_CONFIG_PACKAGES=() FALLBACK_PACKAGES=()
declare -ga UNUSED_PACKAGES=() REQUIRED_PACKAGES=()
declare -gA PACKAGE_MATCHES=() PACKAGE_MATCH_FAMILIES=()
declare -ga LOCAL_ACTIVE_FAMILIES=() LOCAL_INSTALLED_CONFIG_FAMILIES=()
declare -ga LOCAL_FALLBACK_FAMILIES=() LOCAL_UNUSED_FAMILIES=()
declare -gA LOCAL_MATCHES=() UNUSED_LOCAL_FAMILY_MAP=()
declare -ga LOCAL_REMOVABLE_FAMILIES=() LOCAL_KEPT_PROVIDER_FAMILIES=()
declare -gA LOCAL_REMOVABLE_FILE_COUNTS=() LOCAL_PROVIDER_FILE_COUNTS=()
declare -ga REMOVABLE_LOCAL_FILES=()

main() {
  require_cmd pacman
  require_cmd rg
  require_cmd fc-scan

  collect_search_roots
  build_rg_args
  collect_live_font_refs
  collect_installed_font_packages
  print_header
  collect_local_font_families

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
  report_local_families
  offer_unused_local_file_removal
  report_required_packages
  print_notes
}

source "${BASH_SOURCE[0]%/*}/lib/font-inventory.bash"
source "${BASH_SOURCE[0]%/*}/lib/font-references.bash"
source "${BASH_SOURCE[0]%/*}/lib/font-audit-report.bash"
source "${BASH_SOURCE[0]%/*}/lib/font-removal.bash"

main "$@"

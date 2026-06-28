#!/usr/bin/env bash
# Non-interactive Nerd Font removal helpers.

set -euo pipefail

# shellcheck source=/home/rifle/.local/bin/hyprshell
source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/core/notify.sh"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/fonts/font-nerd.common.bash"

used_fonts=()

detect_used_fonts() {
  used_fonts=()
  local config_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local kitty_conf="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
  local font_ref font_line var font_name

  if [[ -d "${config_dir}" ]]; then
    while IFS= read -r font_ref; do
      font_name=$(echo "$font_ref" | sed -E 's/.*[fF]ont[_-]?[fF]amily[[:space:]]*[:=][[:space:]]*"?([^",;]+)"?.*/\1/; s/.*[fF]ont[[:space:]]*[:=][[:space:]]*"?([^",;]+)"?.*/\1/')
      [[ -n "${font_name}" ]] && used_fonts+=("${font_name}")
    done < <(grep -rh -E '([fF]ont[_-]?[fF]amily|[fF]ont)[[:space:]]*[:=]' "${config_dir}" 2>/dev/null | grep -v '^[[:space:]]*#')

    while IFS= read -r var; do
      font_name=$(echo "$var" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
      [[ -n "${font_name}" ]] && used_fonts+=("${font_name}")
    done < <(grep -rh '^\$MONOSPACE_FONT=' "${config_dir}" 2>/dev/null)
  fi

  if [[ -f "${kitty_conf}" ]]; then
    while IFS= read -r font_line; do
      font_name=$(echo "$font_line" | sed -E 's/^[[:space:]]*font_family[[:space:]]+//')
      [[ -n "${font_name}" ]] && used_fonts+=("${font_name}")
    done < <(grep -E '^[[:space:]]*font_family' "${kitty_conf}")
  fi

  if [[ ${#used_fonts[@]} -gt 0 ]]; then
    mapfile -t used_fonts < <(printf '%s\n' "${used_fonts[@]}" | sort -u)
  fi
}

font_package_family_names() {
  local pkg="$1"
  local font_file font_name

  while IFS= read -r font_file; do
    [[ -f "${font_file}" ]] || continue
    font_name=$(fc-query "${font_file}" 2>/dev/null | awk -F'"' '/^[[:space:]]*family:/{print $2; exit}')
    [[ -n "${font_name}" ]] && printf '%s\n' "${font_name}"
  done < <(pacman -Ql "${pkg}" 2>/dev/null | grep -E '\.(ttf|otf)$' | awk '{print $2}')
}

is_font_in_use() {
  local pkg="$1"
  local font_name used_font

  [[ ${#used_fonts[@]} -eq 0 ]] && return 1

  while IFS= read -r font_name; do
    [[ -n "${font_name}" ]] || continue
    for used_font in "${used_fonts[@]}"; do
      if [[ "${font_name}" == "${used_font}" ]]; then
        return 0
      fi
    done
  done < <(font_package_family_names "${pkg}")

  return 1
}

list_unused_nerd_fonts() {
  local pkg
  detect_used_fonts
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    if ! is_font_in_use "${pkg}"; then
      printf '%s\n' "${pkg}"
    fi
  done < <(list_installed_nerd_fonts)
}

remove_nerd_font_packages() {
  local -a packages=("$@")
  local package_label=""

  if [[ "${#packages[@]}" -eq 0 ]]; then
    echo "No font packages specified." >&2
    return 1
  fi

  package_label="$(font_packages_label "${packages[@]}")"

  if hyprshell pm --noconfirm remove "${packages[@]}"; then
    echo
    echo "Refreshing font cache..."
    refresh_font_cache
    notify_send_safe -a "Font Manager" -i "preferences-desktop-font" "Removed Nerd Font" "${package_label}"
    echo -e "\033[1;32m✓ Removed: ${package_label}\033[0m"
    return 0
  fi

  notify_send_safe -u critical -a "Font Manager" -i "preferences-desktop-font" "Failed to remove Nerd Font" "${package_label}"
  echo -e "\033[1;31m✗ Removal failed.\033[0m" >&2
  return 1
}

usage() {
  cat <<'HELP'
Usage: hyprshell fonts/font-nerd-remove.sh <mode> [packages...]

Modes:
  --list-installed     List installed Nerd Font packages
  --list-unused        List installed Nerd Font packages not detected in config
  --packages <pkg...>  Remove one or more Nerd Font packages
HELP
}

case "${1:-}" in
  --list-installed)
    list_installed_nerd_fonts
    ;;
  --list-unused)
    list_unused_nerd_fonts
    ;;
  --packages)
    shift
    remove_nerd_font_packages "$@"
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    echo "Unknown mode: $1" >&2
    echo >&2
    usage >&2
    exit 2
    ;;
esac

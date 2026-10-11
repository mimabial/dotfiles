#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/fonts/lib/font-packages.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/fonts/lib/font-consumers.bash"

used_fonts=()

detect_used_fonts() {
  local kitty_conf="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
  local kind variable font_name

  used_fonts=()
  for kind in mono bar bar-icon menu terminal; do
    used_fonts+=("$(font_sync_resolve_font_value "${kind}")")
  done
  for variable in FONT DOCUMENT_FONT; do
    font_name="$(hypr_config_value_from_layers "${variable}" 2>/dev/null || true)"
    [[ -n "${font_name}" ]] && used_fonts+=("${font_name}")
  done
  if [[ -f "${kitty_conf}" ]]; then
    while IFS= read -r font_name; do
      [[ -n "${font_name}" ]] && used_fonts+=("${font_name}")
    done < <(sed -nE 's/^[[:space:]]*font_family[[:space:]]+//p' "${kitty_conf}")
  fi

  mapfile -t used_fonts < <(printf '%s\n' "${used_fonts[@]}" | sort -u)
}

font_package_family_names() {
  local font_file

  pacman -Qlq "$1" 2>/dev/null | grep -E '\.(ttf|otf)$' | while IFS= read -r font_file; do
    [[ -f "${font_file}" ]] && fc-scan --format '%{family}\n' "${font_file}" 2>/dev/null
  done | unique_family_names
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
    change_nerd_font_packages remove "$@"
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

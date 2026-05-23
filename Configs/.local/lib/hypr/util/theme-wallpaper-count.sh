#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
if ! source "$(command -v hyprshell)"; then
  echo "[$0] :: Error: hyprshell not found."
  exit 1
fi

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/wallpaper/lib/common.bash"

show_help() {
  cat <<'HELP'
Usage: theme-wallpaper-count.sh [OPTIONS]

Options:
    --json        Output counts as JSON
    --help, -h    Show this help message
HELP
}

count_theme_wallpapers() {
  local theme_dir="${1}"
  local source_dir=""
  local count=0
  local ext
  local first_match=1
  local -a find_args=()
  local -a supported_files=()

  wallpaper_supported_files_array supported_files

  if [[ -d "${theme_dir}/wallpapers" ]]; then
    source_dir="${theme_dir}/wallpapers"
  elif [[ -d "${theme_dir}/wallpaper" ]]; then
    source_dir="${theme_dir}/wallpaper"
  else
    printf '0\n'
    return 0
  fi

  find_args=("${source_dir}" -maxdepth 1 -type f "(")
  for ext in "${supported_files[@]}"; do
    [[ -n "${ext}" ]] || continue
    if [[ "${first_match}" -eq 0 ]]; then
      find_args+=(-o)
    fi
    first_match=0
    find_args+=(-iname "*.${ext}")
  done
  find_args+=(")")

  count="$(
    find -L "${find_args[@]}" | wc -l
  )"
  printf '%s\n' "${count//[[:space:]]/}"
}

print_table() {
  local theme_dir theme_name count total=0 theme_count=0
  local -a rows=()

  while IFS= read -r -d '' theme_dir; do
    theme_name="$(basename "${theme_dir}")"
    count="$(count_theme_wallpapers "${theme_dir}")"
    rows+=("${theme_name}\t${count}")
    total=$((total + count))
    theme_count=$((theme_count + 1))
  done < <(find -L "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  printf 'Theme\tWallpapers\n'
  printf '%b\n' "${rows[@]}" | column -t -s $'\t'
  printf '\n'
  printf 'Themes: %d\n' "${theme_count}"
  printf 'Wallpapers: %d\n' "${total}"
}

print_json() {
  local theme_dir theme_name count total=0
  local first=1

  printf '{\n'
  printf '  "themes": [\n'

  while IFS= read -r -d '' theme_dir; do
    theme_name="$(basename "${theme_dir}")"
    count="$(count_theme_wallpapers "${theme_dir}")"
    total=$((total + count))

    if [[ "${first}" -eq 0 ]]; then
      printf ',\n'
    fi
    first=0

    printf '    {"theme": "%s", "wallpapers": %d}' \
      "$(printf '%s' "${theme_name}" | sed 's/"/\\"/g')" \
      "${count}"
  done < <(find -L "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  printf '\n'
  printf '  ],\n'
  printf '  "total_themes": %d,\n' \
    "$(find -L "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  printf '  "total_wallpapers": %d\n' "${total}"
  printf '}\n'
}

main() {
  case "${1:-}" in
    --json)
      print_json
      ;;
    -h | --help)
      show_help
      ;;
    "")
      print_table
      ;;
    *)
      echo "Invalid option: $1"
      echo "Try '$(basename "$0") --help' for more information."
      exit 1
      ;;
  esac
}

main "$@"

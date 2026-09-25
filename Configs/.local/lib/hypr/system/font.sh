#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/font resolve <layout-file>
Download and install fonts referenced by a Hyprland layout file." "$@"

font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
landing_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/landing/fonts"
mkdir -p "$font_dir" "$landing_dir"

install_font_file() {
  local name="$1" downloaded_file="$2" staging_dir="$3"
  case "${downloaded_file}" in
    *.tar.gz | *.tar.xz | *.zip)
      mkdir -p "${staging_dir}/${name}"
      case "${downloaded_file}" in
        *.tar.gz) tar -xzf "${downloaded_file}" -C "${staging_dir}/${name}" || return 1 ;;
        *.tar.xz) tar -xJf "${downloaded_file}" -C "${staging_dir}/${name}" || return 1 ;;
        *.zip) unzip -q "${downloaded_file}" -d "${staging_dir}/${name}" || return 1 ;;
      esac
      cp -rn "${staging_dir}/${name}" "${font_dir}"
      ;;
    *.ttf | *.otf)
      mkdir -p "${font_dir}/hypr"
      cp -f "${downloaded_file}" "${font_dir}/hypr/${name}.${downloaded_file##*.}"
      ;;
    *) printf '[font] Unsupported file format: %s\n' "${downloaded_file}" >&2; return 1 ;;
  esac
}

download_and_install_font() {
  local name="$1" url="$2" staging_dir filename result=0
  staging_dir="$(mktemp -d "${landing_dir}/font.XXXXXX")" || return 1
  filename="${url%%\?*}"
  filename="${filename##*/}"
  if [[ -z "${filename}" ]] || ! curl -fLsS -o "${staging_dir}/${filename}" "${url}" \
    || ! install_font_file "${name}" "${staging_dir}/${filename}" "${staging_dir}"; then
    result=1
  fi
  rm -rf "${staging_dir}"
  ((result == 0)) || return 1
  dunstify -t 3000 -i preferences-desktop-font Font "${name} Installed successfully"
}

resolve() {
  local layout_path="${1}"
  local name=""
  local url=""

  layout_path="$(printf "%s" "${layout_path}")"
  layout_path="$(realpath "${layout_path}")"
  if [[ ! -f "${layout_path}" ]]; then
    echo "[font] Layout file not found: ${layout_path}"
    return 1
  fi
  # shellcheck disable=SC2016
  while IFS='=' read -r _ font; do
    name=$(echo "$font" | awk -F'|' '{print $1}' | xargs)
    url=$(echo "$font" | awk -F'|' '{print $2}' | xargs)
    if ! fc-list | grep -q "${name}"; then
      download_and_install_font "$name" "$url" || return 1
      fc-cache -f "${font_dir}" || return 1
    fi
  done < <(grep -Eo '^\s*\$resolve\.font\s*=\s*[^|]+\s*\|\s*[^ ]+' "${layout_path}")
}

"${@}"

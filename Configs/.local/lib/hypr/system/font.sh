#!/usr/bin/env bash
# Script to resolve fonts

set -euo pipefail

font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
landing_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/landing/fonts"
mkdir -p "$font_dir" "$landing_dir"

download_and_extract() {
  local name="${1}"
  local url="${2}"
  local temp_dir="${landing_dir}/${name}"
  local domain=""
  local file=""
  local install_status=0

  extract_archive_file() {
    local archive_file="$1"
    local extract_dir="$2"
    local required_cmd=""

    case "${archive_file}" in
      *.tar.gz)
        required_cmd="tar"
        ;;
      *.zip)
        required_cmd="unzip"
        ;;
      *.tar.xz)
        required_cmd="tar"
        ;;
      *)
        echo "[font] Unsupported file format: ${archive_file}"
        return 1
        ;;
    esac

    if ! command -v "${required_cmd}" >/dev/null; then
      echo "[font] ${required_cmd} is not installed"
      return 1
    fi

    case "${archive_file}" in
      *.tar.gz) tar -xzf "${archive_file}" -C "${extract_dir}" ;;
      *.zip) unzip -q "${archive_file}" -d "${extract_dir}" ;;
      *.tar.xz) tar -xJf "${archive_file}" -C "${extract_dir}" ;;
    esac
  }

  install_downloaded_file() {
    local downloaded_file="$1"

    case "${downloaded_file}" in
      *.tar.gz | *.zip | *.tar.xz)
        extract_archive_file "${downloaded_file}" "${temp_dir}/${name}" || return 1
        if ! cp -rn "${temp_dir}/${name}" "${font_dir}"; then
          echo "[font] Failed to extract ${downloaded_file}"
          dunstify -t 5000 -i "preferences-desktop-font" "Font" "Failed to extract ${downloaded_file}"
          return 1
        fi
        dunstify -t 3000 -i "preferences-desktop-font" "Font" "${name} Installed successfully"
        return 0
        ;;
      *.ttf | *.otf)
        mkdir -p "${font_dir}/hypr"
        mv "${downloaded_file}" "${font_dir}/hypr/${name}.ttf"
        echo "[font] ${name} installed successfully. Please restart hyprlock to apply changes."
        dunstify -t 3000 -i "preferences-desktop-font" "Font" "${name} Installed successfully"
        return 2
        ;;
      *)
        echo "[font] Unsupported file format: ${downloaded_file}"
        return 1
        ;;
    esac
  }

  # Extract domain name using parameter expansion
  domain=${url#*://}   # Remove everything up to '://'
  domain=${domain%%/*} # Remove everything after the first '/'
  # Ping the extracted domain
  if ! ping -c 1 "$domain" &>/dev/null; then
    echo "[font] Ping to $domain failed"
    exit 1
  fi

  mkdir -p "${temp_dir}"
  if cd "${temp_dir}"; then
    curl -s -O -L "${url}" || return 1
  else
    return 1
  fi

  while IFS= read -r file; do
    install_downloaded_file "${file}"
    install_status=$?
    if [[ "${install_status}" -eq 2 ]]; then
      break
    fi
    if [[ "${install_status}" -ne 0 ]]; then
      rm -rf "${temp_dir}"
      return 1
    fi
  done < <(find "${temp_dir}" -type f)

  rm -rf "$temp_dir"
  echo "[font] $name installed successfully. Please restart hyprlock to apply changes."
  return 0
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
      download_and_extract "$name" "$url" || return 1
      fc-cache -f "${font_dir}/${name}" || return 1
    fi
  done < <(grep -Eo '^\s*\$resolve\.font\s*=\s*[^|]+\s*\|\s*[^ ]+' "${layout_path}")
}

"${@}"

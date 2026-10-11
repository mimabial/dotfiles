#!/usr/bin/env bash

nerd_font_display_name_from_package() {
  local package_name="$1"
  local display="${package_name}"
  local -a words=()

  [[ "${display}" == ttf-* || "${display}" == otf-* ]] && display="${display:4}"
  if [[ "${display}" == *-nerdfonts ]]; then
    display="${display%-nerdfonts}"
  else
    display="${display%-nerd}"
  fi
  read -ra words <<<"${display//-/ }"
  display="${words[*]^}"
  printf '%s\n' "${display:-${package_name}}"
}

nerd_font_metadata_display_name() {
  local description="$1"

  if [[ "${description}" =~ ^Patched[[:space:]]font[[:space:]](.+)[[:space:]]from[[:space:]]nerd[[:space:]]fonts[[:space:]]library$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

nerd_font_populate_metadata_labels() {
  local out_map_name="$1"
  shift
  local -a packages=("$@")
  local package_name=""
  local description=""
  local label=""

  local -n metadata_label_map_ref="${out_map_name}"

  [[ "${#packages[@]}" -gt 0 ]] || return 0

  while IFS=$'\t' read -r package_name description; do
    [[ -n "${package_name}" ]] || continue
    label="$(nerd_font_metadata_display_name "${description}" || true)"
    [[ -n "${label}" ]] || continue
    # shellcheck disable=SC2034 # Nameref output assigned for the caller.
    metadata_label_map_ref["${package_name}"]="${label}"
  done < <(
    pacman -Si -- "${packages[@]}" 2>/dev/null |
      awk '
        /^Name[[:space:]]*:/ {
          sub(/^[^:]+:[[:space:]]*/, "", $0)
          name=$0
          next
        }
        /^Description[[:space:]]*:/ {
          sub(/^[^:]+:[[:space:]]*/, "", $0)
          if (name != "") printf "%s\t%s\n", name, $0
          name=""
        }
      '
  )
}

nerd_font_menu_build() {
  local mode="$1"
  local out_labels_name="$2"
  local out_map_name="$3"
  local package_list=""
  local package_name=""
  local label=""
  local -a packages=()
  local -A seen_labels=()
  local -A metadata_labels=()

  local -n font_menu_labels_ref="${out_labels_name}"
  local -n font_menu_package_map_ref="${out_map_name}"
  font_menu_labels_ref=()
  font_menu_package_map_ref=()

  case "${mode}" in
    installable)
      package_list="$(hyprshell fonts/font-nerd-install.sh --list-installable 2>/dev/null || true)"
      ;;
    installed)
      package_list="$(hyprshell fonts/font-nerd-remove.sh --list-installed 2>/dev/null || true)"
      ;;
    unused)
      package_list="$(hyprshell fonts/font-nerd-remove.sh --list-unused 2>/dev/null || true)"
      ;;
    *)
      return 1
      ;;
  esac

  mapfile -t packages < <(printf '%s\n' "${package_list}" | sed '/^$/d')
  nerd_font_populate_metadata_labels metadata_labels "${packages[@]}"

  while IFS= read -r package_name; do
    [[ -n "${package_name}" ]] || continue
    label="${metadata_labels["${package_name}"]:-}"
    [[ -n "${label}" ]] || label="$(nerd_font_display_name_from_package "${package_name}")"
    if [[ -n "${seen_labels["${label}"]:-}" ]]; then
      label="${label} [${package_name}]"
    fi
    seen_labels["${label}"]=1
    font_menu_labels_ref+=("${label}")
    # shellcheck disable=SC2034 # Associative-array output assigned for the caller.
    font_menu_package_map_ref["${label}"]="${package_name}"
  done <<<"${package_list}"
}

#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Theme file resolution, @import walking, fullscreen detection, icon theme, launcher style.
# External deps: rofi_resolve_asset, rofi_resolve_theme (core/rofi.sh); get_hypr_conf (core/common).

rofi_normalize_launcher_style() {
  local style_ref="${1:-style_1}"
  [[ -z "${style_ref}" ]] && style_ref="style_1"
  if [[ "${style_ref}" =~ ^[0-9]+$ ]]; then
    printf 'style_%s\n' "${style_ref}"
    return 0
  fi
  printf '%s\n' "${style_ref}"
}

rofi_theme_preview_asset() {
  local theme_ref="$1"
  local base_name="${theme_ref##*/}"
  local asset_path=""

  base_name="${base_name%.rasi}"
  for asset_path in \
    "$(rofi_resolve_asset "${base_name}.png" 2>/dev/null || true)" \
    "$(rofi_resolve_asset "theme_${base_name}.png" 2>/dev/null || true)"; do
    [[ -f "${asset_path}" ]] || continue
    printf '%s\n' "${asset_path}"
    return 0
  done

  return 1
}

rofi_resolve_import_ref() {
  local import_ref="$1"
  local base_dir="$2"
  local resolved=""

  import_ref="${import_ref%\"}"
  import_ref="${import_ref#\"}"
  import_ref="${import_ref%\'}"
  import_ref="${import_ref#\'}"

  [[ -n "${import_ref}" ]] || return 1

  if [[ "${import_ref}" == ~/* ]]; then
    resolved="${HOME}/${import_ref#~/}"
  elif [[ "${import_ref}" == /* ]]; then
    resolved="${import_ref}"
  elif [[ "${import_ref}" == *"/"* ]]; then
    resolved="${base_dir}/${import_ref}"
  else
    resolved="$(rofi_resolve_theme "${import_ref}" 2>/dev/null || true)"
  fi

  [[ -f "${resolved}" ]] || return 1
  printf '%s\n' "${resolved}"
}

rofi_theme_effective_files() {
  local theme_file="$1"
  local visited_name="${2:-_rofi_theme_visited}"
  local base_dir import_ref import_file

  [[ -f "${theme_file}" ]] || return 1

  declare -n _rofi_seen="${visited_name}"
  if [[ -n "${_rofi_seen["${theme_file}"]:-}" ]]; then
    return 0
  fi
  _rofi_seen["${theme_file}"]=1

  base_dir="$(dirname "${theme_file}")"
  while IFS= read -r import_ref; do
    import_file="$(rofi_resolve_import_ref "${import_ref}" "${base_dir}" 2>/dev/null || true)"
    [[ -n "${import_file}" ]] || continue
    rofi_theme_effective_files "${import_file}" "${visited_name}"
  done < <(
    sed -nE 's/^[[:space:]]*@(theme|import)[[:space:]]+"([^"]+)".*/\2/p; s/^[[:space:]]*@(theme|import)[[:space:]]+'\''([^'\'']+)'\''.*/\2/p' "${theme_file}"
  )

  printf '%s\n' "${theme_file}"
}

rofi_theme_is_fullscreen() {
  local theme_ref="$1"
  local theme_file="" file="" fullscreen_value=""
  local -A _rofi_theme_visited=()

  theme_file="$(rofi_resolve_theme "${theme_ref}" 2>/dev/null || true)"
  [[ -f "${theme_file}" ]] || return 1

  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    local file_value=""
    file_value="$(awk '
      BEGIN { IGNORECASE = 1 }
      /^[[:space:]]*fullscreen[[:space:]]*:/ {
        if (match($0, /(true|false)/)) {
          value = substr($0, RSTART, RLENGTH)
        }
      }
      END { print value }
    ' "${file}" 2>/dev/null || true)"
    [[ -n "${file_value}" ]] && fullscreen_value="${file_value}"
  done < <(rofi_theme_effective_files "${theme_file}" "_rofi_theme_visited")

  [[ "${fullscreen_value}" == "true" ]]
}

rofi_icon_theme_override() {
  local icon_theme
  icon_theme="$(get_hypr_conf "ICON_THEME")"
  printf 'configuration {icon-theme: "%s";}\n' "${icon_theme}"
}

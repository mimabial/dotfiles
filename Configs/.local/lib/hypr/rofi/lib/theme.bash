#!/usr/bin/env bash
rofi_normalize_launcher_style() {
  local style_ref="${1:-sidebar}"
  if [[ "${style_ref}" =~ ^[0-9]+$ ]]; then
    style_ref="style_${style_ref}"
  fi
  case "${style_ref}" in
    style_1) style_ref=sidebar ;;
    style_11) style_ref="split" ;;
  esac
  printf '%s\n' "${style_ref}"
}

rofi_theme_preview_asset() {
  local theme_ref="$1"
  local base_name="${theme_ref##*/}"
  local asset_path=""

  base_name="${base_name%.rasi}"
  rofi_resolve_file_into asset_path asset "${base_name}.png" \
    || rofi_resolve_file_into asset_path asset "theme_${base_name}.png" \
    || return 1
  printf '%s\n' "${asset_path}"
}

rofi_resolve_import_ref_into() {
  local -n import_file_ref="$1"
  local import_ref="$2"
  local base_dir="$3"

  import_file_ref=""
  import_ref="${import_ref%\"}"
  import_ref="${import_ref#\"}"
  import_ref="${import_ref%\'}"
  import_ref="${import_ref#\'}"

  [[ -n "${import_ref}" ]] || return 1

  if [[ "${import_ref}" == "~/"* ]]; then
    import_file_ref="${HOME}/${import_ref#"~/"}"
  elif [[ "${import_ref}" == /* ]]; then
    import_file_ref="${import_ref}"
  elif [[ "${import_ref}" == *"/"* ]]; then
    import_file_ref="${base_dir}/${import_ref}"
  else
    rofi_resolve_file_into import_file_ref theme "${import_ref}" || true
  fi

  [[ -f "${import_file_ref}" ]] || {
    import_file_ref=""
    return 1
  }
}

rofi_theme_effective_files() {
  local theme_file="$1"
  local visited_name="${2:-_rofi_theme_visited}"
  local base_dir line import_file
  local double_quoted_import='^[[:space:]]*@(theme|import)[[:space:]]+"([^"]+)"'
  local single_quoted_import="^[[:space:]]*@(theme|import)[[:space:]]+'([^']+)'"

  [[ -f "${theme_file}" ]] || return 1

  declare -n _rofi_seen="${visited_name}"
  if [[ -n "${_rofi_seen["${theme_file}"]:-}" ]]; then
    return 0
  fi
  _rofi_seen["${theme_file}"]=1

  base_dir="${theme_file%/*}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ${double_quoted_import} || "${line}" =~ ${single_quoted_import} ]] || continue
    rofi_resolve_import_ref_into import_file "${BASH_REMATCH[2]}" "${base_dir}" || continue
    rofi_theme_effective_files "${import_file}" "${visited_name}"
  done <"${theme_file}"

  printf '%s\n' "${theme_file}"
}

rofi_theme_is_fullscreen() {
  local theme_ref="$1"
  local theme_file="" file="" line="" fullscreen_value="" nocasematch_restore=-u
  local fullscreen_key='^[[:space:]]*fullscreen[[:space:]]*:'
  local -A _rofi_theme_visited=()

  rofi_resolve_file_into theme_file theme "${theme_ref}" || true
  [[ -f "${theme_file}" ]] || return 1

  shopt -q nocasematch && nocasematch_restore=-s
  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    shopt -s nocasematch
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ "${line}" =~ ${fullscreen_key} && "${line}" =~ (true|false) ]] && fullscreen_value="${BASH_REMATCH[1]}"
    done <"${file}"
    shopt "${nocasematch_restore}" nocasematch
  done < <(rofi_theme_effective_files "${theme_file}" "_rofi_theme_visited")

  [[ "${fullscreen_value}" == "true" ]]
}

rofi_icon_theme_override() {
  local icon_theme
  icon_theme="$(hypr_theme_variable "ICON_THEME")"
  printf 'configuration {icon-theme: "%s";}\n' "${icon_theme}"
}

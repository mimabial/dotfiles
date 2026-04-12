#!/usr/bin/env bash
# wal.kvantum.sh - Kvantum theme generation with pywal colors

source "$(command -v hyprshell)" || exit 1

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
hash_file="${XDG_RUNTIME_DIR:-/tmp}/wal-kvantum-hash"
PYWAL_KVANTUM_DIR="${HOME}/.config/Kvantum/pywal16"

declare -F export_hypr_config >/dev/null && export_hypr_config
selected_color_mode="${selected_color_mode:-1}"

resolve_theme_kvantum_dir() {
  if [[ -z "${HYPR_THEME_DIR}" && -n "${HYPR_THEME}" ]]; then
    HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  fi
  THEME_KVANTUM_DIR="${HYPR_THEME_DIR}/kvantum"
}

theme_inputs_changed() {
  local input_files=(
    "${THEME_KVANTUM_DIR}/kvconfig.theme"
    "${THEME_KVANTUM_DIR}/kvantum.theme"
    "${THEME_KVANTUM_DIR}/colors.map"
  )
  local input_hash=""
  local combined_hash=""
  local kvconfig_output="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  local svg_output="${PYWAL_KVANTUM_DIR}/pywal16.svg"
  local input_file=""

  input_hash=$(cat "${input_files[@]}" "${WAL_CACHE}/colors-shell.sh" 2>/dev/null | md5sum | cut -d' ' -f1)
  combined_hash="${input_hash}-${selected_color_mode}"

  [[ ! -f "${kvconfig_output}" ]] && return 0
  if [[ -f "${THEME_KVANTUM_DIR}/kvantum.theme" && ! -f "${svg_output}" ]]; then
    return 0
  fi

  for input_file in "${THEME_KVANTUM_DIR}/kvconfig.theme" "${THEME_KVANTUM_DIR}/colors.map" "${WAL_CACHE}/colors-shell.sh"; do
    [[ -f "${input_file}" && "${input_file}" -nt "${kvconfig_output}" ]] && return 0
  done

  if [[ -f "${THEME_KVANTUM_DIR}/kvantum.theme" && -f "${svg_output}" ]]; then
    for input_file in "${THEME_KVANTUM_DIR}/kvantum.theme" "${THEME_KVANTUM_DIR}/colors.map" "${WAL_CACHE}/colors-shell.sh"; do
      [[ -f "${input_file}" && "${input_file}" -nt "${svg_output}" ]] && return 0
    done
  fi

  [[ ! -f "$hash_file" || "$(cat "$hash_file" 2>/dev/null)" != "$combined_hash" ]]
}

copy_theme_files() {
  mkdir -p "${PYWAL_KVANTUM_DIR}"
  [[ -f "${THEME_KVANTUM_DIR}/kvconfig.theme" ]] && cp -f "${THEME_KVANTUM_DIR}/kvconfig.theme" "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  [[ -f "${THEME_KVANTUM_DIR}/kvantum.theme" ]] && cp -f "${THEME_KVANTUM_DIR}/kvantum.theme" "${PYWAL_KVANTUM_DIR}/pywal16.svg"
}

load_wal_colors() {
  [[ -f "${WAL_CACHE}/colors-shell.sh" ]] && source "${WAL_CACHE}/colors-shell.sh"
}

build_color_map_replacements() {
  local color_map="${THEME_KVANTUM_DIR}/colors.map"
  local hex_color=""
  local pywal_var=""
  local pywal_value=""

  SED_ARGS=()
  [[ -f "${color_map}" ]] || return 0

  while IFS='=' read -r hex_color pywal_var || [[ -n "${hex_color}" ]]; do
    [[ "${hex_color}" =~ ^#.*$ && ! "${hex_color}" =~ ^#[0-9A-Fa-f]{6}$ ]] && continue
    [[ -n "${hex_color}" && -n "${pywal_var}" ]] || continue

    pywal_value="${!pywal_var}"
    [[ -n "${pywal_value}" ]] || continue
    pywal_value="$(sed_escape_replacement "${pywal_value}")"
    SED_ARGS+=(-e "s|${hex_color}|${pywal_value}|gi")
  done <"${color_map}"
}

apply_color_map_replacements() {
  [[ "${selected_color_mode}" -ne 0 ]] || return 0
  [[ ${#SED_ARGS[@]} -gt 0 ]] || return 0

  [[ -f "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig" ]] && sed -i "${SED_ARGS[@]}" "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  [[ -f "${PYWAL_KVANTUM_DIR}/pywal16.svg" ]] && sed -i "${SED_ARGS[@]}" "${PYWAL_KVANTUM_DIR}/pywal16.svg"
}

fix_svg_selection_colors() {
  local svg="${PYWAL_KVANTUM_DIR}/pywal16.svg"
  local color4_svg=""

  [[ -f "${svg}" && -n "${color4}" ]] || return 0
  color4_svg="$(sed_escape_replacement "${color4}")"

  sed -i -E "
    /id=\"itemview-(toggled|pressed)/,/<\\/g>|<\\/(rect|path)>/ {
      s|fill:#[0-9a-fA-F]{6}|fill:${color4_svg}|g
    }
    /id=\"tbutton-(toggled|pressed)/,/<\\/g>|<\\/(rect|path)>/ {
      s|fill:#[0-9a-fA-F]{6}|fill:${color4_svg}|g
    }
    /id=\"button-(toggled|pressed)(-|\\\")/,/<\\/g>|<\\/(rect|path)>/ {
      s|fill:#[0-9a-fA-F]{6}|fill:${color4_svg}|g
    }
  " "${svg}"
}

load_theme_mode_highlight_colors() {
  local theme_kvconfig="${THEME_KVANTUM_DIR}/kvconfig.theme"
  local kv_highlight=""
  local kv_text=""

  [[ "${selected_color_mode}" -eq 0 && -f "${theme_kvconfig}" ]] || return 0
  kv_highlight=$(grep '^highlight\.color=' "${theme_kvconfig}" | cut -d= -f2)
  kv_text=$(grep '^text\.color=' "${theme_kvconfig}" | cut -d= -f2)
  [[ -n "${kv_highlight}" ]] && color4="${kv_highlight}"
  [[ -n "${kv_text}" ]] && foreground="${kv_text}"
}

update_highlight_colors() {
  local kvconfig="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  local color4_kv=""
  local foreground_kv=""

  [[ -f "${kvconfig}" && -n "${color4}" ]] || return 0
  load_theme_mode_highlight_colors

  color4_kv="$(sed_escape_replacement "${color4}")"
  sed -i "s|^highlight\\.color=.*|highlight.color=${color4_kv}|" "${kvconfig}"
  sed -i "s|^inactive\\.highlight\\.color=.*|inactive.highlight.color=${color4_kv}|" "${kvconfig}"

  if [[ -n "${foreground}" ]]; then
    foreground_kv="$(sed_escape_replacement "${foreground}")"
    sed -i "s|^highlight\\.text\\.color=.*|highlight.text.color=${foreground_kv}|" "${kvconfig}"
  fi

  if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file "${kvconfig}" --group '%General' --key 'reduce_menu_opacity' 0 2>/dev/null
  fi
}

store_current_hash() {
  local input_files=(
    "${THEME_KVANTUM_DIR}/kvconfig.theme"
    "${THEME_KVANTUM_DIR}/kvantum.theme"
    "${THEME_KVANTUM_DIR}/colors.map"
  )
  local input_hash=""

  input_hash=$(cat "${input_files[@]}" "${WAL_CACHE}/colors-shell.sh" 2>/dev/null | md5sum | cut -d' ' -f1)
  echo "${input_hash}-${selected_color_mode}" > "$hash_file"
}

resolve_theme_kvantum_dir
[[ -d "${THEME_KVANTUM_DIR}" ]] || exit 0
theme_inputs_changed || exit 0

copy_theme_files
load_wal_colors
build_color_map_replacements
apply_color_map_replacements
fix_svg_selection_colors
update_highlight_colors
store_current_hash

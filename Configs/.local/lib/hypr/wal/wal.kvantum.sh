#!/usr/bin/env bash
# wal.kvantum.sh - Kvantum theme generation with pywal colors

source "$(command -v hyprshell)" || exit 1

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
hash_file="${XDG_RUNTIME_DIR:-/tmp}/wal-kvantum-hash"
PYWAL_KVANTUM_DIR="${HOME}/.config/Kvantum/pywal16"
KVANTUM_TEMPLATE_DIR="${HYPR_CONFIG_HOME}/themes/Tokyo Night/kvantum"

declare -F export_hypr_config >/dev/null && export_hypr_config
selected_color_mode="${selected_color_mode:-1}"
declare -a SVG_TEMPLATE_SED_ARGS=()

normalize_kvantum_color() {
  local raw="${1%%;*}"

  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"

  if [[ "${raw}" =~ ^#?[0-9A-Fa-f]{8}$ ]]; then
    raw="${raw#\#}"
    printf '#%s\n' "${raw:0:6}"
    return 0
  fi

  if [[ "${raw}" =~ ^#?[0-9A-Fa-f]{6}$ ]]; then
    printf '#%s\n' "${raw#\#}"
    return 0
  fi

  printf '%s\n' "${raw}"
}

resolve_kvantum_svg_source() {
  if [[ -f "${THEME_KVANTUM_DIR}/kvantum.theme" ]]; then
    printf '%s\n' "${THEME_KVANTUM_DIR}/kvantum.theme"
  elif [[ -f "${KVANTUM_TEMPLATE_DIR}/kvantum.theme" ]]; then
    printf '%s\n' "${KVANTUM_TEMPLATE_DIR}/kvantum.theme"
  fi
}

resolve_theme_kvantum_dir() {
  if [[ -n "${HYPR_THEME}" ]]; then
    HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  fi
  THEME_KVANTUM_DIR="${HYPR_THEME_DIR}/kvantum"
}

theme_inputs_changed() {
  local template_kvconfig="${KVANTUM_TEMPLATE_DIR}/kvconfig.theme"
  local svg_source=""
  local input_files=(
    "${THEME_KVANTUM_DIR}/kvconfig.theme"
    "${THEME_KVANTUM_DIR}/colors.map"
    "${template_kvconfig}"
  )
  local input_hash=""
  local combined_hash=""
  local kvconfig_output="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  local svg_output="${PYWAL_KVANTUM_DIR}/pywal16.svg"
  local input_file=""

  svg_source="$(resolve_kvantum_svg_source)"
  [[ -n "${svg_source}" ]] && input_files+=("${svg_source}")

  input_hash=$(cat "${input_files[@]}" "${WAL_CACHE}/colors-shell.sh" 2>/dev/null | md5sum | cut -d' ' -f1)
  combined_hash="${input_hash}-${selected_color_mode}"

  [[ ! -f "${kvconfig_output}" ]] && return 0
  if [[ -n "${svg_source}" && ! -f "${svg_output}" ]]; then
    return 0
  fi

  for input_file in "${THEME_KVANTUM_DIR}/kvconfig.theme" "${THEME_KVANTUM_DIR}/colors.map" "${template_kvconfig}" "${WAL_CACHE}/colors-shell.sh"; do
    [[ -f "${input_file}" && "${input_file}" -nt "${kvconfig_output}" ]] && return 0
  done

  if [[ -n "${svg_source}" && -f "${svg_output}" ]]; then
    for input_file in "${svg_source}" "${THEME_KVANTUM_DIR}/colors.map" "${template_kvconfig}" "${WAL_CACHE}/colors-shell.sh"; do
      [[ -f "${input_file}" && "${input_file}" -nt "${svg_output}" ]] && return 0
    done
  fi

  [[ ! -f "$hash_file" || "$(cat "$hash_file" 2>/dev/null)" != "$combined_hash" ]]
}

copy_theme_files() {
  local svg_source=""

  mkdir -p "${PYWAL_KVANTUM_DIR}"
  if [[ -f "${THEME_KVANTUM_DIR}/kvconfig.theme" ]]; then
    sed -E '/^[[:space:]]*#/! s/[[:space:]]*;.*$//' \
      "${THEME_KVANTUM_DIR}/kvconfig.theme" > "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  fi

  svg_source="$(resolve_kvantum_svg_source)"
  [[ -n "${svg_source}" ]] && cp -f "${svg_source}" "${PYWAL_KVANTUM_DIR}/pywal16.svg"
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

load_kvconfig_colors() {
  local kvconfig_file="$1"
  local map_name="$2"
  local line=""
  local key=""
  local value=""
  local normalized=""
  local -n map_ref="${map_name}"

  map_ref=()
  [[ -f "${kvconfig_file}" ]] || return 1

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "${key}" == *.color ]] || continue

    normalized="$(normalize_kvantum_color "${value}")"
    [[ "${normalized}" =~ ^#[0-9A-Fa-f]{6}$ ]] || continue
    map_ref["${key}"]="${normalized}"
  done < "${kvconfig_file}"
}

resolve_template_svg_fallback_color() {
  local source_color="${1,,}"
  local active_map_name="$2"
  local -n active_map_ref="${active_map_name}"

  case "${source_color}" in
    "#7aa2f7"|"#2ac3de"|"#73daca"|"#b4f9f8"|"#cba6f7"|"#89b4fa"|"#94e2d5"|"#b4befe")
      printf '%s\n' "${active_map_ref[highlight.color]:-}"
      ;;
    "#c0caf5"|"#cdd6f4"|"#dce0e8"|"#f5e0dc")
      printf '%s\n' "${active_map_ref[text.color]:-${active_map_ref[button.text.color]:-}}"
      ;;
    "#1a1b26"|"#24283b")
      printf '%s\n' "${active_map_ref[window.color]:-}"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

build_template_svg_replacements() {
  local template_kvconfig="${KVANTUM_TEMPLATE_DIR}/kvconfig.theme"
  local active_kvconfig="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  local active_svg="${PYWAL_KVANTUM_DIR}/pywal16.svg"
  local source_color=""
  local target_color=""
  local target_color_rep=""
  local key=""
  local -a svg_colors=()
  declare -A template_colors
  declare -A active_colors
  declare -A svg_color_map

  SVG_TEMPLATE_SED_ARGS=()

  [[ -f "${template_kvconfig}" && -f "${active_kvconfig}" && -f "${active_svg}" ]] || return 0
  load_kvconfig_colors "${template_kvconfig}" template_colors || return 0
  load_kvconfig_colors "${active_kvconfig}" active_colors || return 0

  for key in "${!template_colors[@]}"; do
    source_color="${template_colors[${key}],,}"
    target_color="${active_colors[${key}]:-}"
    [[ "${target_color}" =~ ^#[0-9A-Fa-f]{6}$ ]] || continue
    svg_color_map["${source_color}"]="${target_color}"
  done

  readarray -t svg_colors < <(grep -oiE '#[0-9a-f]{6}' "${active_svg}" | tr '[:upper:]' '[:lower:]' | sort -u)
  for source_color in "${svg_colors[@]}"; do
    [[ -n "${svg_color_map[${source_color}]:-}" ]] && continue
    target_color="$(resolve_template_svg_fallback_color "${source_color}" active_colors)"
    [[ "${target_color}" =~ ^#[0-9A-Fa-f]{6}$ ]] || continue
    svg_color_map["${source_color}"]="${target_color}"
  done

  for source_color in "${!svg_color_map[@]}"; do
    target_color_rep="$(sed_escape_replacement "${svg_color_map[${source_color}]}" )"
    SVG_TEMPLATE_SED_ARGS+=(-e "s|${source_color}|${target_color_rep}|gi")
  done
}

apply_template_svg_replacements() {
  local svg="${PYWAL_KVANTUM_DIR}/pywal16.svg"

  [[ -f "${svg}" ]] || return 0
  [[ ${#SVG_TEMPLATE_SED_ARGS[@]} -gt 0 ]] || return 0
  sed -i "${SVG_TEMPLATE_SED_ARGS[@]}" "${svg}"
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
  kv_highlight="$(normalize_kvantum_color "${kv_highlight}")"
  kv_text="$(normalize_kvantum_color "${kv_text}")"
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
  local template_kvconfig="${KVANTUM_TEMPLATE_DIR}/kvconfig.theme"
  local svg_source=""
  local input_files=(
    "${THEME_KVANTUM_DIR}/kvconfig.theme"
    "${THEME_KVANTUM_DIR}/colors.map"
    "${template_kvconfig}"
  )
  local input_hash=""

  svg_source="$(resolve_kvantum_svg_source)"
  [[ -n "${svg_source}" ]] && input_files+=("${svg_source}")

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
build_template_svg_replacements
apply_template_svg_replacements
fix_svg_selection_colors
update_highlight_colors
store_current_hash

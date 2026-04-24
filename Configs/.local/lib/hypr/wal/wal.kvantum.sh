#!/usr/bin/env bash
# wal.kvantum.sh - Kvantum output generation
#
# Maintainable model:
#   - theme mode: copy the theme's Kvantum assets as-is
#   - wallpaper mode: copy the same assets, then apply the theme-owned
#     color substitutions from colors.map
#
# No structural SVG repair, no template fallback, no highlight overrides.

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/core/hash-cache.sh" || exit 1

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
hash_file="$(hypr_hash_cache_file "wal-kvantum.hash")" || exit 1
PYWAL_KVANTUM_DIR="${HOME}/.config/Kvantum/pywal16"
KVANTUM_OUTPUT_STATE_FILE="${PYWAL_KVANTUM_DIR}/.hypr-theme-state"

declare -F export_hypr_config >/dev/null && export_hypr_config
selected_color_mode="${selected_color_mode:-1}"
declare -ga SED_ARGS=()
kvantum_expected_hash=""

resolve_theme_kvantum_dir() {
  if [[ -n "${HYPR_THEME}" ]]; then
    HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  fi
  THEME_KVANTUM_DIR="${HYPR_THEME_DIR}/kvantum"
}

kvantum_theme_kvconfig() {
  printf '%s\n' "${THEME_KVANTUM_DIR}/kvconfig.theme"
}

kvantum_theme_svg() {
  printf '%s\n' "${THEME_KVANTUM_DIR}/kvantum.theme"
}

kvantum_build_expected_hash() {
  local -a input_files=(
    "$(kvantum_theme_kvconfig)"
    "$(kvantum_theme_svg)"
    "${THEME_KVANTUM_DIR}/colors.map"
  )

  if [[ "${selected_color_mode}" -ne 0 ]]; then
    input_files+=("${WAL_CACHE}/colors-shell.sh")
  fi

  printf '%s-%s\n' "$(hypr_hash_cache_digest_files "${input_files[@]}")" "${selected_color_mode}"
}

kvantum_outputs_need_refresh() {
  local kvconfig_output="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  local svg_output="${PYWAL_KVANTUM_DIR}/pywal16.svg"
  local -a outputs=("${kvconfig_output}" "${svg_output}")
  local -a inputs=(
    "$(kvantum_theme_kvconfig)"
    "$(kvantum_theme_svg)"
    "${THEME_KVANTUM_DIR}/colors.map"
  )
  local -a metadata=()

  if [[ "${selected_color_mode}" -ne 0 ]]; then
    inputs+=("${WAL_CACHE}/colors-shell.sh")
  fi

  kvantum_expected_hash="$(kvantum_build_expected_hash)"
  metadata=(
    "theme=${HYPR_THEME}"
    "mode=${selected_color_mode}"
    "input_hash=${kvantum_expected_hash}"
  )

  ! hypr_hash_cache_outputs_current \
    "${hash_file}" "${kvantum_expected_hash}" "${KVANTUM_OUTPUT_STATE_FILE}" \
    "${outputs[@]}" \
    --inputs "${inputs[@]}" \
    --metadata "${metadata[@]}"
}

copy_theme_files() {
  mkdir -p "${PYWAL_KVANTUM_DIR}"

  sed -E '/^[[:space:]]*#/! s/[[:space:]]*;.*$//' \
    "$(kvantum_theme_kvconfig)" > "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  cp -f "$(kvantum_theme_svg)" "${PYWAL_KVANTUM_DIR}/pywal16.svg"
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
  [[ "${selected_color_mode}" -ne 0 ]] || return 0
  [[ -f "${color_map}" ]] || return 0

  while IFS='=' read -r hex_color pywal_var || [[ -n "${hex_color}" ]]; do
    [[ "${hex_color}" =~ ^#.*$ && ! "${hex_color}" =~ ^#[0-9A-Fa-f]{6}$ ]] && continue
    [[ -n "${hex_color}" && -n "${pywal_var}" ]] || continue

    pywal_value="${!pywal_var}"
    [[ -n "${pywal_value}" ]] || continue
    pywal_value="$(sed_escape_replacement "${pywal_value}")"
    SED_ARGS+=(-e "s|${hex_color}|${pywal_value}|gi")
  done < "${color_map}"
}

apply_color_map_replacements() {
  [[ ${#SED_ARGS[@]} -gt 0 ]] || return 0

  sed -i "${SED_ARGS[@]}" "${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  sed -i "${SED_ARGS[@]}" "${PYWAL_KVANTUM_DIR}/pywal16.svg"
}

record_kvantum_outputs() {
  [[ -n "${kvantum_expected_hash}" ]] || kvantum_expected_hash="$(kvantum_build_expected_hash)"
  hypr_hash_cache_store "${hash_file}" "${kvantum_expected_hash}"
  hypr_hash_cache_metadata_store \
    "${KVANTUM_OUTPUT_STATE_FILE}" \
    "theme=${HYPR_THEME}" \
    "mode=${selected_color_mode}" \
    "input_hash=${kvantum_expected_hash}"
}

resolve_theme_kvantum_dir

if [[ ! -f "$(kvantum_theme_kvconfig)" || ! -f "$(kvantum_theme_svg)" ]]; then
  print_log -sec "theme" -err "kvantum" "missing kvantum assets for ${HYPR_THEME:-unknown theme}"
  exit 1
fi

kvantum_outputs_need_refresh || exit 0
copy_theme_files
load_wal_colors
build_color_map_replacements
apply_color_map_replacements
record_kvantum_outputs

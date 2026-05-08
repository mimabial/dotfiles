#!/usr/bin/env bash
# wal.kvantum.sh - Kvantum output generation
#
# Maintainable model:
#   - theme mode: copy the theme's Kvantum assets as-is
#   - wallpaper mode: copy the same assets, then apply the theme-owned
#     color substitutions from colors.map
#
# No structural SVG repair, no template fallback, no theme policy overrides.

set -euo pipefail

# shellcheck source=/dev/null
source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/core/hash-cache.sh" || exit 1
if [[ -r "${LIB_DIR}/hypr/theme/phase-d.sh" ]]; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/hypr/theme/phase-d.sh" || exit 1
  theme_phase_d_init "${HYPR_THEME_PHASE_D_LOCK_KEY:-theme_phase_d_qt}"
fi

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
hash_file="$(hypr_hash_cache_file "wal-kvantum.hash")" || exit 1
PYWAL_KVANTUM_DIR="${HOME}/.config/Kvantum/pywal16"
KVANTUM_OUTPUT_STATE_FILE="${PYWAL_KVANTUM_DIR}/.hypr-theme-state"

declare -F export_hypr_config >/dev/null && export_hypr_config
selected_color_mode="${selected_color_mode:-1}"
declare -ga SED_ARGS=()
kvantum_expected_hash=""
kvantum_tmp_dir=""
kvantum_tmp_kvconfig=""
kvantum_tmp_svg=""

cleanup_kvantum_tmp() {
  [[ -n "${kvantum_tmp_dir}" ]] || return 0
  [[ -d "${kvantum_tmp_dir}" ]] || return 0
  rm -rf -- "${kvantum_tmp_dir}" || true
}
trap cleanup_kvantum_tmp EXIT

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
  mkdir -p "${PYWAL_KVANTUM_DIR}" || return 1
  kvantum_tmp_dir="$(mktemp -d "${PYWAL_KVANTUM_DIR}/.kvantum.XXXXXX")" || return 1
  kvantum_tmp_kvconfig="${kvantum_tmp_dir}/pywal16.kvconfig"
  kvantum_tmp_svg="${kvantum_tmp_dir}/pywal16.svg"

  sed -E '/^[[:space:]]*#/! s/[[:space:]]*;.*$//' \
    "$(kvantum_theme_kvconfig)" > "${kvantum_tmp_kvconfig}" || return 1
  cp -f "$(kvantum_theme_svg)" "${kvantum_tmp_svg}" || return 1
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

  sed -i "${SED_ARGS[@]}" "${kvantum_tmp_kvconfig}"
  sed -i "${SED_ARGS[@]}" "${kvantum_tmp_svg}"
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

install_kvantum_outputs() {
  local rc=0
  local target_kvconfig="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  local target_svg="${PYWAL_KVANTUM_DIR}/pywal16.svg"

  [[ -n "${kvantum_tmp_dir}" && -d "${kvantum_tmp_dir}" ]] || return 1

  if declare -F theme_phase_d_acquire_lock >/dev/null 2>&1; then
    theme_phase_d_acquire_lock || return 1
    if ! theme_phase_d_current_generation; then
      rm -rf -- "${kvantum_tmp_dir}"
      theme_phase_d_release_lock
      return 0
    fi
  fi

  if [[ ! -f "${target_kvconfig}" ]] || ! cmp -s "${kvantum_tmp_kvconfig}" "${target_kvconfig}"; then
    mv -f -- "${kvantum_tmp_kvconfig}" "${target_kvconfig}" || rc=$?
  else
    rm -f -- "${kvantum_tmp_kvconfig}" || rc=$?
  fi

  if [[ "${rc}" -eq 0 ]]; then
    if [[ ! -f "${target_svg}" ]] || ! cmp -s "${kvantum_tmp_svg}" "${target_svg}"; then
      mv -f -- "${kvantum_tmp_svg}" "${target_svg}" || rc=$?
    else
      rm -f -- "${kvantum_tmp_svg}" || rc=$?
    fi
  fi

  if [[ "${rc}" -eq 0 ]]; then
    record_kvantum_outputs || rc=$?
  fi

  rm -rf -- "${kvantum_tmp_dir}" 2>/dev/null || true
  if declare -F theme_phase_d_release_lock >/dev/null 2>&1; then
    theme_phase_d_release_lock
  fi
  return "${rc}"
}

resolve_theme_kvantum_dir

if [[ ! -f "$(kvantum_theme_kvconfig)" || ! -f "$(kvantum_theme_svg)" ]]; then
  print_log -sec "theme" -err "kvantum" "missing kvantum assets for ${HYPR_THEME:-unknown theme}"
  exit 1
fi

if declare -F theme_phase_d_current_generation >/dev/null 2>&1; then
  theme_phase_d_current_generation || exit 0
fi

kvantum_outputs_need_refresh || exit 0
copy_theme_files || exit 1
load_wal_colors
build_color_map_replacements || exit 1
apply_color_map_replacements || exit 1
install_kvantum_outputs || exit 1

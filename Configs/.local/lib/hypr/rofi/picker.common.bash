#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

rofi_picker_bootstrap() {
  pkill -u "$USER" rofi && exit 0

  local hyprshell_path=""
  hyprshell_path="$(command -v hyprshell)" || return 1

  # shellcheck source=/dev/null
  source "${hyprshell_path}" || return 1
  # shellcheck source=/dev/null
  source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash" || return 1
}

rofi_picker_hypr_dir_vars() {
  local out_config_name="$1"
  local out_cache_name="$2"
  local _picker_config_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local _picker_cache_dir="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"

  printf -v "${out_config_name}" '%s' "${_picker_config_dir}"
  printf -v "${out_cache_name}" '%s' "${_picker_cache_dir}"
}

rofi_picker_prepare_data_file() {
  local target_file="$1"
  local cleanup_fn="${2:-}"

  rofi_picker_ensure_data_file "${target_file}" || return 1
  [[ -n "${cleanup_fn}" ]] || return 0
  "${cleanup_fn}" "${target_file}"
}

rofi_picker_recent_category_entry() {
  local recent_file="$1"
  local icon="$2"
  local label="$3"
  local unit_label="$4"
  local recent_count=0

  [[ -f "${recent_file}" && -s "${recent_file}" ]] || return 1

  recent_count="$(wc -l <"${recent_file}" 2>/dev/null || echo 0)"
  [[ "${recent_count}" =~ ^[0-9]+$ ]] || recent_count=0
  ((recent_count > 0)) || return 1

  printf '%s\n' "${icon} ${label} (${recent_count} ${unit_label})	:cat:recent:"
}

rofi_picker_build_recent_first_file() {
  local target_file="$1"
  local recent_file="$2"
  local data_file="$3"

  awk '!seen[$0]++' "${recent_file}" "${data_file}" >"${target_file}"
}

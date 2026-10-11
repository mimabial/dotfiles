#!/usr/bin/env bash

source "${BASH_SOURCE[0]%/*}/close.bash"

PICKER_CATEGORY_TAG=":cat:"
PICKER_BACK_TAG=":b:a:c:k:"
PICKER_BACK_ENTRY="◀ Back	${PICKER_BACK_TAG}"

rofi_picker_category_entry() {
  local label="$1"
  local category="$2"
  printf '%s\t%s%s:\n' "${label}" "${PICKER_CATEGORY_TAG}" "${category}"
}

rofi_picker_selected_category() {
  [[ "$1" =~ ${PICKER_CATEGORY_TAG}([a-z]+):$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

rofi_picker_is_back() {
  [[ "$1" == *"${PICKER_BACK_TAG}" ]]
}

rofi_picker_help_requested() {
  local arg=""
  for arg in "$@"; do
    [[ "${arg}" == -h || "${arg}" == --help ]] && return 0
  done
  return 1
}

rofi_picker_toggle_off_if_open() {
  rofi_picker_help_requested "$@" && return 0
  rofi_close_running && exit 0
  (($? == ROFI_NOT_RUNNING)) || exit 1
}

rofi_picker_load_environment() {
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || return 1
  hypr_runtime_load_shell_environment || return 1
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/rofi/rofi.lib.bash" || return 1
}

rofi_picker_paths_into() {
  local -n picker_paths_ref="$1"
  local picker_name="$2"
  picker_paths_ref[config_dir]="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  picker_paths_ref[cache_dir]="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
  picker_paths_ref[data_file]="${picker_paths_ref[config_dir]}/${picker_name}.db"
  picker_paths_ref[recent_file]="${picker_paths_ref[cache_dir]}/landing/show_${picker_name}.recent"
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

  rofi_picker_category_entry "${icon} ${label} (${recent_count} ${unit_label})" recent
}

rofi_picker_build_recent_first_file() {
  local target_file="$1"
  local recent_file="$2"
  local data_file="$3"

  awk '!seen[$0]++' "${recent_file}" "${data_file}" >"${target_file}"
}

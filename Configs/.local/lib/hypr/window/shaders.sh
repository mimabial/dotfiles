#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state rofi || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/window/stateful-choice.common.bash"

shaders_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/shaders"
shaders_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/shaders"
shaders_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/shaders.lua"
shaders_cache_dir="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/shaders"
compiled_shader_file="${shaders_cache_dir}/compiled.cache.glsl"

show_help() {
  cat <<HELP
Usage: $0 [OPTIONS]

Options:
    --select | -S       Select a shader from the available options
    --set NAME          Set a shader without opening the selector
    --list              List selectable shaders as name, icon and description
    --reload | -r       Reload the current shader
    --quiet  | -q       Suppress success notifications
    --help   | -h       Show this help message
HELP
}

normalize_shader_name() {
  local name="${1:-neutral}"
  name="${name%.frag}"

  case "${name}" in
    "")
      printf 'neutral\n'
      ;;
    *)
      printf '%s\n' "${name}"
      ;;
  esac
}

resolve_shader_path() {
  local name
  name="$(normalize_shader_name "${1:-neutral}")"
  name="${name%.frag}"
  hypr_stateful_choice_resolve_path "${name}" "frag" "${shaders_user_dir}" "${shaders_shared_dir}"
}

resolve_shader_inc_path() {
  local name="${1:-}"
  local candidate
  for candidate in \
    "${shaders_user_dir}/${name}.inc" \
    "${shaders_shared_dir}/${name}.inc"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

list_shader_names() {
  hypr_stateful_choice_list_names "frag" "${shaders_user_dir}" "${shaders_shared_dir}" "neutral"
}

# Same shape as util/workflows.sh --list, so one parser serves every pipeline.
# Shaders carry no icon or description, so those fields are empty rather than
# absent. "neutral" is prepended on the same condition select_shader uses.
list_shaders() {
  local name=""
  {
    if resolve_shader_path neutral >/dev/null 2>&1; then
      printf 'neutral\n'
    fi
    list_shader_names
  } | sed '/^$/d' | while IFS= read -r name; do
    printf '%s\t\t\n' "${name}"
  done
}

select_shader() {
  local shader_items=""
  local selected_shader=""

  shader_items="$(list_shader_names)"
  if resolve_shader_path neutral >/dev/null 2>&1; then
    shader_items=$(printf 'neutral\n%s\n' "${shader_items}" | sed '/^$/d')
  fi

  [[ -n "${shader_items}" ]] || {
    send_ephemeral_notif "hypr-shader-error" -t 3000 -i "preferences-desktop-display" "Error" "No shader files found in ${shaders_user_dir} or ${shaders_shared_dir}"
    exit 1
  }

  hypr_stateful_choice_select \
    "Select shader" \
    "🎨 Select shader..." \
    "clipboard" \
    "${ROFI_SHADER_SCALE:-}" \
    "${ROFI_SHADER_FONT:-${ROFI_FONT:-}}" \
    "$(normalize_shader_name "$(state_get "HYPR_SHADER" "neutral")")" \
    "${shader_items}" \
    selected_shader

  [[ -n "${selected_shader}" ]] || exit 0
  selected_shader="$(normalize_shader_name "${selected_shader}")"

  hypr_stateful_choice_apply "HYPR_SHADER" "${selected_shader}" "hypr-shader" "Shader selected" write_shader_state
}

reload_shader() {
  local shader_name
  shader_name="$(normalize_shader_name "$(state_get "HYPR_SHADER" "neutral")")"
  hypr_stateful_choice_apply "HYPR_SHADER" "${shader_name}" "hypr-shader" "Shader reloaded" write_shader_state
}

set_shader() {
  local shader_name
  shader_name="$(normalize_shader_name "${1:-}")"

  resolve_shader_path "${shader_name}" >/dev/null 2>&1 || {
    echo "Error: unknown shader '${shader_name}'" >&2
    return 1
  }

  hypr_stateful_choice_apply "HYPR_SHADER" "${shader_name}" "hypr-shader" "Shader selected" write_shader_state
}

concat_shader_files() {
  local files=("$@")
  local version_directive=""
  local main_frag_file="${files[-1]}"

  mkdir -p "${shaders_cache_dir}"

  if [[ -f "${main_frag_file}" ]]; then
    version_directive=$(grep -E '^\s*#version\s+' "${main_frag_file}" | head -n1)
    if [[ -z "${version_directive}" ]]; then
      print_log -y "Warning" " No #version directive found in ${main_frag_file}"
      version_directive="#version 300 es"
    fi
  fi

  printf '%s\n\n' "${version_directive}" >"${compiled_shader_file}"

  local shader_file
  for shader_file in "${files[@]}"; do
    if [[ -f "${shader_file}" ]]; then
      print_log -g "Processing shader" " file: ${shader_file}"
      sed '/^\s*#version\s/d' "${shader_file}" >>"${compiled_shader_file}"
      printf '\n' >>"${compiled_shader_file}"
    fi
  done
}

parse_includes_and_update() {
  local selected_shader
  selected_shader="$(normalize_shader_name "${1}")"
  local resolved_shader_path
  local source_var inc_file
  local files=()

  resolved_shader_path="$(resolve_shader_path "${selected_shader}")" || {
    print_log -r "Error" " Shader ${selected_shader} not found"
    return 1
  }

  source_var="$(grep -iE '^\s*//\s*!source\s*=\s*.*' "${resolved_shader_path}" 2>/dev/null | head -n1 | sed -E 's/^\s*\/\/\s*!source\s*=\s*//I' | xargs || true)"
  if [[ -n "${source_var}" ]]; then
    # shellcheck disable=SC2088  # tilde here is a literal match prefix, not expansion
    if [[ "${source_var}" == "~/"* ]]; then
      source_var="${HOME}/${source_var#"~/"}"
    elif [[ "${source_var}" != /* ]]; then
      source_var="$(dirname "${resolved_shader_path}")/${source_var}"
    fi
    if [[ -f "${source_var}" ]]; then
      files+=("${source_var}")
      print_log -g "Found source include" " ${source_var}"
    else
      print_log -y "Warning" " Source file not found: ${source_var}"
    fi
  fi

  inc_file="$(resolve_shader_inc_path "${selected_shader}" || true)"
  if [[ -n "${inc_file}" ]]; then
    files+=("${inc_file}")
    print_log -g "Found inc file" " ${inc_file}"
  fi

  files+=("${resolved_shader_path}")
  concat_shader_files "${files[@]}"

  hypr_stateful_choice_write_lua "${shaders_state_file}" \
    --config decoration.screen_shader "${compiled_shader_file}" \
    "SCREEN_SHADER=${selected_shader}" \
    "SCREEN_SHADER_PATH=${resolved_shader_path}" \
    "SCREEN_SHADER_COMPILED=${compiled_shader_file}"
}

write_shader_state() {
  parse_includes_and_update "$1"
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
  exit 1
fi

LONG_OPTS="select,set:,list,help,reload,quiet"
SHORT_OPTS="Shrq"
PARSED=$(getopt --options "${SHORT_OPTS}" --longoptions "${LONG_OPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

action=""
shader_set_name=""

while true; do
  case "$1" in
    -S | --select)
      action="select"
      ;;
    --set)
      action="set"
      shader_set_name="${2:-}"
      shift
      ;;
    --list)
      action="list"
      ;;
    -r | --reload)
      action="reload"
      ;;
    -q | --quiet)
      HYPR_STATEFUL_CHOICE_QUIET=1
      ;;
    --help | -h)
      show_help
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option: $1"
      show_help
      exit 1
      ;;
  esac
  shift
done

case "${action}" in
  select)
    select_shader
    ;;
  set)
    [[ -n "${shader_set_name}" ]] || {
      echo "Error: --set requires a shader name" >&2
      exit 1
    }
    set_shader "${shader_set_name}"
    ;;
  list)
    list_shaders
    ;;
  reload)
    reload_shader
    ;;
  *)
    echo "No action provided"
    show_help
    exit 1
    ;;
esac

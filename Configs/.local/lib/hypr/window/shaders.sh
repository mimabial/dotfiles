#!/usr/bin/env bash

# shellcheck source=/dev/null
if ! source "$(command -v hyprshell)"; then
  echo "[$0] :: Error: hyprshell not found."
  exit 1
fi
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/window/stateful-choice.common.bash"

shaders_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/shaders"
shaders_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/shaders"
shaders_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/shaders.conf"
shaders_cache_dir="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/shaders"
compiled_shader_file="${shaders_cache_dir}/compiled.cache.glsl"
quiet_notifications=0

show_help() {
  cat <<HELP
Usage: $0 [OPTIONS]

Options:
    --select | -S       Select a shader from the available options
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

apply_shader_state() {
  local state_key="$1"
  local value="$2"
  local notify_tag="$3"
  local notify_title="$4"
  local update_fn="$5"

  state_set "${state_key}" "${value}" "staterc"
  "${update_fn}" "${value}"

  if [[ "${quiet_notifications}" -ne 1 ]]; then
    send_ephemeral_notif "${notify_tag}" -t 2000 -i "preferences-desktop-display" "${notify_title}" "${value}"
  fi
}

fn_select() {
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
    "${ROFI_SHADER_SCALE}" \
    "${ROFI_SHADER_FONT:-$ROFI_FONT}" \
    "$(normalize_shader_name "${HYPR_SHADER:-neutral}")" \
    "${shader_items}" \
    selected_shader

  [[ -n "${selected_shader}" ]] || exit 0
  selected_shader="$(normalize_shader_name "${selected_shader}")"

  apply_shader_state "HYPR_SHADER" "${selected_shader}" "hypr-shader" "Shader selected" fn_update
}

fn_reload() {
  local shader_name
  shader_name="$(normalize_shader_name "${HYPR_SHADER:-neutral}")"
  apply_shader_state "HYPR_SHADER" "${shader_name}" "hypr-shader" "Shader reloaded" fn_update
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
  local resolved_shader_path shader_path_compact compiled_path_compact
  local source_var inc_file
  local files=()

  resolved_shader_path="$(resolve_shader_path "${selected_shader}")" || {
    print_log -r "Error" " Shader ${selected_shader} not found"
    return 1
  }

  source_var="$(grep -iE '^\s*//\s*!source\s*=\s*.*' "${resolved_shader_path}" 2>/dev/null | head -n1 | sed -E 's/^\s*\/\/\s*!source\s*=\s*//I' | xargs)"
  if [[ -n "${source_var}" ]]; then
    if [[ "${source_var}" == "~/"* ]]; then
      source_var="${HOME}/${source_var#~/}"
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

  mkdir -p "$(dirname "${shaders_state_file}")"
  shader_path_compact="$(hypr_compact_path "${resolved_shader_path}")"
  compiled_path_compact="$(hypr_compact_path "${compiled_shader_file}")"

  cat <<CONF >"${shaders_state_file}"
#! █▀ █░█ ▄▀█ █▀▄ █▀▀ █▀█ █▀
#! ▄█ █▀█ █▀█ █▄▀ ██▄ █▀▄ ▄█

# *┌───────────────────────────────────────────────────────────────────────────┐
# *│ System controlled content // DO NOT EDIT                                 │
# *│ User overrides live in ~/.config/hypr/shaders/                           │
# *│ Shared stock lives in ~/.local/share/hypr/shaders/                       │
# *│ Compiled cache lives in ~/.cache/hypr/shaders/                           │
# *└───────────────────────────────────────────────────────────────────────────┘

\$SCREEN_SHADER = "${selected_shader}"
\$SCREEN_SHADER_PATH = ${shader_path_compact}
\$SCREEN_SHADER_COMPILED = ${compiled_path_compact}
CONF
}

fn_update() {
  parse_includes_and_update "$1"
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
  exit 1
fi

LONG_OPTS="select,help,reload,quiet"
SHORT_OPTS="Shrq"
PARSED=$(getopt --options "${SHORT_OPTS}" --longoptions "${LONG_OPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

action=""

while true; do
  case "$1" in
    -S | --select)
      action="select"
      ;;
    -r | --reload)
      action="reload"
      ;;
    -q | --quiet)
      quiet_notifications=1
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
    fn_select
    ;;
  reload)
    fn_reload
    ;;
  *)
    echo "No action provided"
    show_help
    exit 1
    ;;
esac

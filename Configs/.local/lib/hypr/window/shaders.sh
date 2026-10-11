#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/window/lib/visual-presets.bash"

shaders_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/shaders"
shaders_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/shaders"
shaders_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/shaders.lua"
shaders_cache_dir="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/shaders"
compiled_shader_file="${shaders_cache_dir}/compiled.cache.glsl"

show_help() {
  cat <<HELP
Usage: $0 [OPTIONS]
Set or reload the active screen shader.

Options:
    --set NAME          Set a shader
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
  hypr_visual_preset_resolve_path "${name}" "frag" "${shaders_user_dir}" "${shaders_shared_dir}"
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
  hypr_visual_preset_list_names "frag" "${shaders_user_dir}" "${shaders_shared_dir}" "neutral"
}

# Keep workflow-compatible tab-separated fields, including empty metadata.
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

reload_shader() {
  local shader_name
  shader_name="$(normalize_shader_name "$(state_get "HYPR_SHADER" "neutral")")"
  hypr_visual_preset_apply "HYPR_SHADER" "${shader_name}" "hypr-shader" "Shader reloaded" compile_and_activate_shader
}

set_shader() {
  local shader_name
  shader_name="$(normalize_shader_name "${1:-}")"

  resolve_shader_path "${shader_name}" >/dev/null 2>&1 || {
    echo "Error: unknown shader '${shader_name}'" >&2
    return 1
  }

  hypr_visual_preset_apply "HYPR_SHADER" "${shader_name}" "hypr-shader" "Shader selected" compile_and_activate_shader
}

source "${HYPR_LIB_DIR}/window/lib/shader-compiler.bash"

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
  exit 1
fi

LONG_OPTS="set:,list,help,reload,quiet"
SHORT_OPTS="hrq"
PARSED=$(getopt --options "${SHORT_OPTS}" --longoptions "${LONG_OPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

action=""
shader_set_name=""

while true; do
  case "$1" in
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
      HYPR_VISUAL_PRESET_QUIET=1
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

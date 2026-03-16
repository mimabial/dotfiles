#!/usr/bin/env bash

# shellcheck source=$HOME/.local/bin/hyprshell
# shellcheck disable=SC1091
if ! source "$(command -v hyprshell)"; then
  echo "[$0] :: Error: hyprshell not found."
  exit 1
fi

shaders_user_dir="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/shaders"
shaders_shared_dir="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/shaders"
shaders_state_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/shaders.conf"
shaders_cache_dir="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/shaders"
compiled_shader_file="${shaders_cache_dir}/compiled.cache.glsl"

show_help() {
  cat <<HELP
Usage: $0 [OPTIONS]

Options:
    --select | -S       Select a shader from the available options
    --reload | -r       Reload the current shader
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

  if [[ "${name}" == */* ]] && [[ -f "${name}" ]]; then
    printf '%s\n' "${name}"
    return 0
  fi

  local candidate
  for candidate in \
    "${shaders_user_dir}/${name}.frag" \
    "${shaders_shared_dir}/${name}.frag"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
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
  local dir path name
  local -A seen=()

  for dir in "${shaders_user_dir}" "${shaders_shared_dir}"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r -d '' path; do
      name="$(basename "${path}" .frag)"
      [[ "${name}" == "neutral" ]] && continue
      [[ -n "${seen[${name}]:-}" ]] && continue
      seen["${name}"]=1
      printf '%s\n' "${name}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name '*.frag' -print0 | sort -z)
  done
}

fn_select() {
  local shader_items selected_shader
  local font_scale font_name font_override
  local hypr_border wind_border elem_border hypr_width r_override

  shader_items="$(list_shader_names)"
  if resolve_shader_path neutral >/dev/null 2>&1; then
    shader_items=$(printf 'neutral\n%s\n' "${shader_items}" | sed '/^$/d')
  fi

  [[ -n "${shader_items}" ]] || {
    send_ephemeral_notif "hypr-shader-error" -t 3000 -i "preferences-desktop-display" "Error" "No shader files found in ${shaders_user_dir} or ${shaders_shared_dir}"
    exit 1
  }

  font_scale="${ROFI_SHADER_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  font_name=${ROFI_SHADER_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}
  font_override="* {font: \"${font_name} ${font_scale}\";}"

  hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
  wind_border=$((hypr_border * 3 / 2))
  elem_border=$((hypr_border == 0 ? 5 : hypr_border))
  hypr_width=${hypr_width:-"$(hyprctl -j getoption general:border_size | jq '.int')"}
  r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;} wallbox{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"

  selected_shader=$(printf '%s\n' "${shader_items}" |
    rofi -dmenu -i -select "$(normalize_shader_name "${HYPR_SHADER:-neutral}")" \
      -p "Select shader" \
      -theme-str "entry { placeholder: \"🎨 Select shader...\"; }" \
      -theme-str "${font_override}" \
      -theme-str "${r_override}" \
      -theme-str "$(get_rofi_pos)" \
      -theme "clipboard")

  [[ -n "${selected_shader}" ]] || exit 0
  selected_shader="$(normalize_shader_name "${selected_shader}")"

  state_set "HYPR_SHADER" "${selected_shader}" "staterc"
  fn_update "${selected_shader}"
  send_ephemeral_notif "hypr-shader" -t 2000 -i "preferences-desktop-display" "Shader selected" "${selected_shader}"
}

fn_reload() {
  local shader_name
  shader_name="$(normalize_shader_name "${HYPR_SHADER:-neutral}")"
  state_set "HYPR_SHADER" "${shader_name}" "staterc"
  fn_update "${shader_name}"
  send_ephemeral_notif "hypr-shader" -t 2000 -i "preferences-desktop-display" "Shader reloaded" "${shader_name}"
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

  source_var=$(grep -iE '^\s*//\s*!source\s*=\s*.*' "${resolved_shader_path}" 2>/dev/null | head -n1 | sed -E 's/^\s*\/\/\s*!source\s*=\s*//I' | xargs)
  if [[ -n "${source_var}" ]]; then
    source_var=$(eval echo "${source_var}")
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

LONG_OPTS="select,help,reload"
SHORT_OPTS="Shr"
PARSED=$(getopt --options "${SHORT_OPTS}" --longoptions "${LONG_OPTS}" --name "$0" -- "$@") || exit 2
eval set -- "${PARSED}"

while true; do
  case "$1" in
    -S | --select)
      fn_select
      exit 0
      ;;
    -r | --reload)
      fn_reload
      exit 0
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
done

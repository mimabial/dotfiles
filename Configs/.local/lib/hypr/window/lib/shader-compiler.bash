#!/usr/bin/env bash

DEFAULT_SHADER_VERSION_DIRECTIVE="#version 300 es"

write_compiled_shader_from_files() {
  local files=("$@")
  local version_directive=""
  local main_frag_file="${files[-1]}"

  mkdir -p "${shaders_cache_dir}" || return

  if [[ -f "${main_frag_file}" ]]; then
    if ! version_directive=$(grep -m1 -E '^\s*#version\s+' "${main_frag_file}"); then
      print_log -y "Warning" " No #version directive found in ${main_frag_file}"
      version_directive="${DEFAULT_SHADER_VERSION_DIRECTIVE}"
    fi
  fi

  printf '%s\n\n' "${version_directive}" >"${compiled_shader_file}" || return

  local shader_file
  for shader_file in "${files[@]}"; do
    if [[ -f "${shader_file}" ]]; then
      print_log -g "Processing shader" " file: ${shader_file}"
      sed '/^\s*#version\s/d' "${shader_file}" >>"${compiled_shader_file}" || return
      printf '\n' >>"${compiled_shader_file}" || return
    fi
  done
}

compile_and_activate_shader() {
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
      source_var="${resolved_shader_path%/*}/${source_var}"
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
  write_compiled_shader_from_files "${files[@]}" || return

  hypr_visual_preset_write_lua "${shaders_state_file}" \
    --config decoration.screen_shader "${compiled_shader_file}" \
    "SCREEN_SHADER=${selected_shader}" \
    "SCREEN_SHADER_PATH=${resolved_shader_path}" \
    "SCREEN_SHADER_COMPILED=${compiled_shader_file}"
}

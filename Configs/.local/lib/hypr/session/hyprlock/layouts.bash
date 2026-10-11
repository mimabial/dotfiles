#!/usr/bin/env bash
HYPRLOCK_PREVIEW_PASSWORDLESS_GRACE_S=99999999

hyprlock_find_layout() {
  local -n layout_paths_ref="$1"
  local filename="${2:-default}"
  local search_name="${filename%.conf}.conf"
  local candidate extra_dir

  if [[ "${filename}" == */* ]] && [[ -f "${filename}" ]]; then
    printf '%s\n' "${filename}"
    return 0
  fi

  print_log -sec "hyprlock" -stat "Searching for layout" "${search_name}"

  for candidate in \
    "${layout_paths_ref[user_layouts]}/${search_name}" \
    "${layout_paths_ref[shared_layouts]}/${search_name}"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  extra_dir="${HYPRLOCK_CONF_DIR:-}"
  if [[ -n "${extra_dir}" ]] && [[ "${extra_dir}" != "${layout_paths_ref[user_layouts]}" ]] && [[ "${extra_dir}" != "${layout_paths_ref[shared_layouts]}" ]]; then
    candidate="${extra_dir}/${search_name}"
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  return 1
}

hyprlock_trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

hyprlock_expand_path() {
  local path="${1:-}"
  local var_name=""
  local base_path=""
  local bare_ref=""
  local braced_ref=""

  [[ -n "${path}" ]] || return 1

  # shellcheck disable=SC2088  # tilde here is a literal match prefix, not expansion
  case "${path}" in
    "~") printf '%s\n' "${HOME}" ; return 0 ;;
    "~/"*) printf '%s\n' "${HOME}/${path#"~/"}" ; return 0 ;;
  esac

  for var_name in HYPR_CONFIG_HOME HYPR_DATA_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME HOME; do
    base_path="${!var_name:-}"
    [[ -n "${base_path}" ]] || continue

    bare_ref="\$${var_name}"
    braced_ref="\${${var_name}}"

    if [[ "${path}" == "${bare_ref}" ]]; then
      printf '%s\n' "${base_path}"
      return 0
    fi
    if [[ "${path}" == "${bare_ref}/"* ]]; then
      printf '%s/%s\n' "${base_path}" "${path#"${bare_ref}/"}"
      return 0
    fi
    if [[ "${path}" == "${braced_ref}" ]]; then
      printf '%s\n' "${base_path}"
      return 0
    fi
    if [[ "${path}" == "${braced_ref}/"* ]]; then
      printf '%s/%s\n' "${base_path}" "${path#"${braced_ref}/"}"
      return 0
    fi
  done

  printf '%s\n' "${path}"
}

hyprlock_read_layout_path() {
  local -n layout_paths_ref="$1"
  local target_file="${2:-${layout_paths_ref[conf]}}"
  local line=""
  local value=""

  [[ -r "${target_file}" ]] || return 1

  while IFS= read -r line; do
    [[ "${line}" =~ ^[[:space:]]*\$LAYOUT_PATH[[:space:]]*= ]] || continue
    value="${line#*=}"
    value="${value%%#*}"
    value="$(hyprlock_trim "${value}")"
    hyprlock_expand_path "${value}"
    return 0
  done <"${target_file}"

  return 1
}

hyprlock_conf_sources_path() {
  local target_file="${1}"
  local expected_path="${2}"
  local line=""
  local value=""
  local expanded_value=""

  [[ -r "${target_file}" && -n "${expected_path}" ]] || return 1

  while IFS= read -r line; do
    value="$(hyprlock_trim "${line%%#*}")"
    [[ "${value}" =~ ^source[[:space:]]*= ]] || continue
    value="${value#*=}"
    value="$(hyprlock_trim "${value}")"
    expanded_value="$(hyprlock_expand_path "${value}")"
    [[ "${expanded_value}" == "${expected_path}" ]] && return 0
  done <"${target_file}"

  return 1
}

hyprlock_managed_conf_is_current() {
  local -n layout_paths_ref="$1"
  local target_file="${2:-${layout_paths_ref[conf]}}"
  local layout_path=""

  [[ -r "${target_file}" ]] || return 1
  hyprlock_conf_sources_path "${target_file}" "${layout_paths_ref[colors_conf]}" || return 1
  hyprlock_conf_sources_path "${target_file}" "${layout_paths_ref[shared_conf]}" || return 1

  layout_path="$(hyprlock_read_layout_path "$1" "${target_file}" 2>/dev/null || true)"
  [[ -n "${layout_path}" && -f "${layout_path}" ]] || return 1

  return 0
}

hyprlock_resolve_active_layout() {
  local -n layout_paths_ref="$1"
  local target_file="${2:-${layout_paths_ref[conf]}}"
  local layout_path=""
  local layout_name=""

  layout_path="$(hyprlock_read_layout_path "$1" "${target_file}" 2>/dev/null || true)"
  if [[ -n "${layout_path}" && -f "${layout_path}" ]]; then
    printf '%s\n' "${layout_path}"
    return 0
  fi

  if declare -F state_get >/dev/null 2>&1; then
    layout_name="$(state_get "HYPRLOCK_LAYOUT" "${HYPRLOCK_LAYOUT:-default}" 2>/dev/null || true)"
  fi
  layout_name="${layout_name:-${HYPRLOCK_LAYOUT:-default}}"

  hyprlock_find_layout "$1" "${layout_name}" || hyprlock_find_layout "$1" "default"
}

hyprlock_ensure_config() {
  local -n layout_paths_ref="$1"
  local target_file="${2:-${layout_paths_ref[conf]}}"
  local layout_path=""

  if hyprlock_managed_conf_is_current "$1" "${target_file}"; then
    return 0
  fi

  layout_path="$(hyprlock_resolve_active_layout "$1" "${target_file}")" || return 1
  hyprlock_write_config "$1" "${layout_path}" "${target_file}"
  print_log -sec "hyprlock" -stat "repaired" "$(hypr_compact_path "${target_file}")"
}

hyprlock_append_preview_marker() {
  cat <<'EOF' >>"${1}"
label {
  text = preview · any key exits
  color = $foreground_alpha
  font_size = 11
  position = 0, -12
  halign = center
  valign = top
  zindex = 10
}
EOF
}

hyprlock_managed_conf_comments() {
  cat <<'EOF'
# Managed by 'hyprshell session/hyprlock.sh'. Do not edit this file directly.
# Select a layout with 'hyprshell session/hyprlock.sh --select' or override '$LAYOUT_PATH'.
EOF
}

hyprlock_preview_layout() {
  local -n layout_paths_ref="$1"
  print_log -sec "hyprlock" -stat "Test" "Please swipe,press a key or click to exit."
  local layout_name="${2:-default}" layout_path=""
  hyprlock_stop_process
  layout_path="$(hyprlock_find_layout "$1" "${layout_name}" || true)"
  if [[ -z "${layout_path}" ]]; then
    print_log -sec "hyprlock" -stat "Error" "Layout ${layout_name} not found."
    exit 1
  fi
  local runtime_dir=""
  local temp_path=""
  runtime_dir="$(hypr_ensure_runtime_subdir hypr)" || exit 1
  temp_path="${runtime_dir}/hyprlock-test.conf"
  hyprlock_write_config "$1" "${layout_path}" "${temp_path}"
  hyprlock_append_preview_marker "${temp_path}"
  "${HYPR_LIB_DIR}/system/app2unit.sh" -S both -u "${layout_paths_ref[scope]}" -t scope -- hyprlock --no-fade-in --immediate-render --grace "${HYPRLOCK_PREVIEW_PASSWORDLESS_GRACE_S}" -c "${temp_path}"
  rm -f "${temp_path}"
}

hyprlock_write_config() {
  local -n layout_paths_ref="$1"
  local path="${2:-${layout_paths_ref[shared_layouts]}/default.conf}"
  local target_file="${3:-${layout_paths_ref[conf]}}"
  local layout_path
  local colors_path
  local source_conf

  layout_path="$(hypr_compact_path "${path}")"
  colors_path="$(hypr_compact_path "${layout_paths_ref[colors_conf]}")"
  source_conf="$(hypr_compact_path "${layout_paths_ref[shared_conf]}")"

  cat <<CONF >"${target_file}"
$(hyprlock_managed_conf_comments)

\$LAYOUT_PATH=${layout_path}
source = ${colors_path}
source = ${source_conf}
CONF
}

hyprlock_open_layout_selector() {
  quickshell ipc call lockview open >/dev/null 2>&1 && return 0
  send_ephemeral_notif "hypr-hyprlock-error" -t "${NOTIFY_MS}" -i "system-lock-screen" "Hyprlock layout" "Quickshell is not running"
  return 1
}

hyprlock_apply_layout() {
  local -n layout_paths_ref="$1"
  local layout_name="${2}"
  local layout_path
  layout_path="$(hyprlock_find_layout "$1" "${layout_name}")" || {
    print_log -sec "hyprlock" -stat "Error" "Layout ${layout_name} not found."
    return 1
  }
  state_set "HYPRLOCK_LAYOUT" "${layout_name}" "staterc"
  hyprlock_write_config "$1" "${layout_path}"
  "${HYPR_LIB_DIR}/system/font.sh" resolve "${layout_path}"
  hyprlock_render_profile "$1"
  send_ephemeral_notif "hypr-hyprlock-layout" -t "${NOTIFY_BRIEF_MS}" -i "system-lock-screen" "Hyprlock layout" "${layout_name}"
}

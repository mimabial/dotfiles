#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Shared hyprlock layout/runtime helpers.
find_filepath() {
  local filename="${1:-default}"
  local search_name="${filename%.conf}.conf"
  local candidate extra_dir

  if [[ "${filename}" == */* ]] && [[ -f "${filename}" ]]; then
    printf '%s\n' "${filename}"
    return 0
  fi

  print_log -sec "hyprlock" -stat "Searching for layout" "${search_name}"

  for candidate in \
    "${HYPRLOCK_USER_DIR}/${search_name}" \
    "${HYPRLOCK_SHARED_DIR}/${search_name}"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  extra_dir="${HYPRLOCK_CONF_DIR:-}"
  if [[ -n "${extra_dir}" ]] && [[ "${extra_dir}" != "${HYPRLOCK_USER_DIR}" ]] && [[ "${extra_dir}" != "${HYPRLOCK_SHARED_DIR}" ]]; then
    candidate="${extra_dir}/${search_name}"
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  return 1
}

check_and_sanitize_process() {
  local unit_name="${1:-${HYPRLOCK_SCOPE_NAME}}"
  if systemctl --user is-active "${unit_name}" >/dev/null 2>&1; then
    systemctl --user stop "${unit_name}" >/dev/null 2>&1
  else
    hypr_user_pkill -x hyprlock >/dev/null 2>&1 || true
  fi
}

reload_hyprlock() {
  local unit_name="${1:-${HYPRLOCK_SCOPE_NAME}}"

  if systemctl --user is-active "${unit_name}" >/dev/null 2>&1; then
    systemctl --user kill -s USR2 "${unit_name}" >/dev/null 2>&1
  else
    hypr_user_pkill -USR2 -x hyprlock >/dev/null 2>&1
  fi
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
  local target_file="${1:-${HYPR_CONFIG_HOME}/hyprlock.conf}"
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
  local target_file="${1:-${HYPR_CONFIG_HOME}/hyprlock.conf}"
  local hyprlock_conf="${HYPR_DATA_HOME:-${XDG_DATA_HOME}/hypr}/hyprlock.conf"
  local colors_conf="${HYPR_CONFIG_HOME}/hyprlock/colors.conf"
  local layout_path=""

  [[ -r "${target_file}" ]] || return 1
  hyprlock_conf_sources_path "${target_file}" "${colors_conf}" || return 1
  hyprlock_conf_sources_path "${target_file}" "${hyprlock_conf}" || return 1

  layout_path="$(hyprlock_read_layout_path "${target_file}" 2>/dev/null || true)"
  [[ -n "${layout_path}" && -f "${layout_path}" ]] || return 1

  return 0
}

hyprlock_resolve_active_layout() {
  local target_file="${1:-${HYPR_CONFIG_HOME}/hyprlock.conf}"
  local layout_path=""
  local layout_name=""

  layout_path="$(hyprlock_read_layout_path "${target_file}" 2>/dev/null || true)"
  if [[ -n "${layout_path}" && -f "${layout_path}" ]]; then
    printf '%s\n' "${layout_path}"
    return 0
  fi

  if declare -F state_get >/dev/null 2>&1; then
    layout_name="$(state_get "HYPRLOCK_LAYOUT" "${HYPRLOCK_LAYOUT:-default}" 2>/dev/null || true)"
  fi
  layout_name="${layout_name:-${HYPRLOCK_LAYOUT:-default}}"

  find_filepath "${layout_name}" || find_filepath "default"
}

ensure_hyprlock_conf() {
  local target_file="${1:-${HYPR_CONFIG_HOME}/hyprlock.conf}"
  local layout_path=""

  if hyprlock_managed_conf_is_current "${target_file}"; then
    return 0
  fi

  layout_path="$(hyprlock_resolve_active_layout "${target_file}")" || return 1
  generate_conf "${layout_path}" "${target_file}"
  print_log -sec "hyprlock" -stat "repaired" "$(hypr_compact_path "${target_file}")"
}

append_label_to_file() {
  local file="${1}"
  local valign=""

  for valign in top bottom center; do
    cat <<EOF >>"${file}"
label {
  text = PREVIEW! Press a key or swipe to exit.
  color = \$foreground
  font_size = 50
  position = 0, 0
  halign = center
  valign = ${valign}
  zindex = 6
}

EOF
  done
}

hyprlock_managed_conf_comments() {
  cat <<'EOF'
# Managed by 'hyprshell hyprlock.sh'. Do not edit this file directly.
# Layouts live in '$XDG_CONFIG_HOME/hypr/hyprlock/' and '$XDG_DATA_HOME/hypr/hyprlock/'.
# Select a layout with 'hyprshell hyprlock.sh --select' or override '$LAYOUT_PATH'.
# Shared command variables live in '$XDG_DATA_HOME/hypr/hyprlock.conf'.
# Common variables include:
#   $BACKGROUND_PATH $SPLASH_CMD $MPRIS_* $PROFILE_IMAGE
#   $GREET_* $WEATHER_CMD $WEATHER $LOCATION $BATTERY_ICON
EOF
}

layout_test() {
  print_log -sec "hyprlock" -stat "Test" "Please swipe,press a key or click to exit."
  local hyprlock_conf_name="${*:-${1}}"
  check_and_sanitize_process
  hyprlock_conf_path=$(find_filepath "${hyprlock_conf_name}")
  if [ -z "${hyprlock_conf_path}" ]; then
    print_log -sec "hyprlock" -stat "Error" "Layout ${hyprlock_conf_name} not found."
    exit 1
  fi
  local runtime_dir=""
  local temp_path=""
  runtime_dir="$(hypr_runtime_subdir hypr)" || exit 1
  temp_path="${runtime_dir}/hyprlock-test.conf"
  generate_conf "${hyprlock_conf_path}" "${temp_path}"
  append_label_to_file "${temp_path}"
  "${HYPR_LIB_DIR}/system/app2unit.sh" -S both -u "${HYPRLOCK_SCOPE_NAME}" -t scope -- hyprlock --no-fade-in --immediate-render --grace 99999999 -c "${temp_path}"
  rm -f "${temp_path}"
}

rofi_test_preview() {
  local hyprlock_conf_name="${*:-${1}}"
  local unit_name="${XDG_SESSION_DESKTOP:-unknown}-lockscreen-preview.scope"
  check_and_sanitize_process "${unit_name}"
  send_ephemeral_notif "hypr-hyprlock-preview" "Hyprlock layout: ${hyprlock_conf_name}" "Please swipe, press a key or click to exit." \
    -i "system-lock-screen" -t 3000 \
    -r 9
  "${HYPR_LIB_DIR}/system/app2unit.sh" -S both -u "${unit_name}" -t scope -- hyprlock.sh --test "${hyprlock_conf_name}"
}

generate_conf() {
  local path="${1:-${HYPRLOCK_SHARED_DIR}/default.conf}"
  local target_file="${2:-${HYPR_CONFIG_HOME}/hyprlock.conf}"
  local hyprlock_conf="${HYPR_DATA_HOME:-${XDG_DATA_HOME}/hypr}/hyprlock.conf"
  local colors_conf="${HYPR_CONFIG_HOME}/hyprlock/colors.conf"
  local layout_path
  local colors_path
  local source_conf

  layout_path="$(hypr_compact_path "${path}")"
  colors_path="$(hypr_compact_path "${colors_conf}")"
  source_conf="$(hypr_compact_path "${hyprlock_conf}")"

  cat <<CONF >"${target_file}"
#! █░█ █▄█ █▀█ █▀█ █░░ █▀█ █▀▀ █▄▀
#! █▀█ ░█░ █▀▀ █▀▄ █▄▄ █▄█ █▄▄ █░█

$(hyprlock_managed_conf_comments)

\$LAYOUT_PATH=${layout_path}
source = ${colors_path}
source = ${source_conf}
CONF
}

# hyprlock selector
fn_select() {
  # List available .conf files from user overrides first, then shared stock.
  local layout_items
  local -A seen_layouts=()
  local layout_dir layout_path layout_name
  local -a rofi_args
  for layout_dir in "${HYPRLOCK_USER_DIR}" "${HYPRLOCK_SHARED_DIR}"; do
    [[ -d "${layout_dir}" ]] || continue
    while IFS= read -r -d '' layout_path; do
      layout_name="$(basename "${layout_path}" .conf)"
      [[ "${layout_name}" == "theme" || "${layout_name}" == "colors" ]] && continue
      [[ -n "${seen_layouts[${layout_name}]:-}" ]] && continue
      seen_layouts["${layout_name}"]=1
      layout_items+="${layout_name}"$'\n'
    done < <(find -L "${layout_dir}" -maxdepth 1 -type f -name '*.conf' -print0 | sort -z)
  done

  if [ -z "$layout_items" ]; then
    send_ephemeral_notif "hypr-hyprlock-error" -t 3000 -i "preferences-desktop-display" "Error" "No .conf files found in ${HYPRLOCK_USER_DIR} or ${HYPRLOCK_SHARED_DIR}"
    exit 1
  fi

  layout_items="${layout_items}"

  rofi_build_standard_menu_args \
    rofi_args \
    "Select hyprlock layout" \
    "  Hyprlock Layout" \
    "${ROFI_HYPRLOCK_STYLE:-clipboard}" \
    "${ROFI_HYPRLOCK_SCALE:-}" \
    "${ROFI_HYPRLOCK_FONT:-${ROFI_FONT:-}}"
  rofi_args+=(
    -select "${HYPRLOCK_LAYOUT}"
    -on-selection-changed "hyprshell hyprlock.sh --test-preview  \"{entry}\""
  )

  selected_layout=$(awk -F/ '{print $NF}' <<<"$layout_items" \
    | rofi "${rofi_args[@]}")

  if [ -z "$selected_layout" ]; then
    echo "No selection made"
    exit 0
  fi

  state_set "HYPRLOCK_LAYOUT" "${selected_layout}" "staterc"
  local hyprlock_conf_path
  hyprlock_conf_path=$(find_filepath "${selected_layout}")
  generate_conf "$hyprlock_conf_path"
  "${HYPR_LIB_DIR}/font.sh" resolve "$hyprlock_conf_path"
  fn_profile

  # Notify the user
  send_ephemeral_notif "hypr-hyprlock-layout" -t 2000 -i "system-lock-screen" "Hyprlock layout" "${selected_layout}"
}

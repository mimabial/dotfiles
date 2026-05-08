#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Set to true when going directly to a submenu, so we can exit directly
BACK_TO_EXIT="${BACK_TO_EXIT:-false}"
MENU_BORDER_RADIUS="${MENU_BORDER_RADIUS:-}"
MENU_BORDER_WIDTH="${MENU_BORDER_WIDTH:-}"
MENU_ELEMENT_RADIUS="${MENU_ELEMENT_RADIUS:-}"
MENU_WINDOW_THEME_CACHE="${MENU_WINDOW_THEME_CACHE:-}"
MENU_FONT_SCALE_CACHE="${MENU_FONT_SCALE_CACHE:-}"
MENU_FONT_NAME_CACHE="${MENU_FONT_NAME_CACHE:-}"
MENU_MAX_HEIGHT="${MENU_MAX_HEIGHT:-}"
MENU_WIDTH_OVERRIDE_CACHE="${MENU_WIDTH_OVERRIDE_CACHE:-}"

declare -gA HYPR_MENU_PROMPTS=()
declare -gA HYPR_MENU_DEFAULTS=()
declare -gA HYPR_MENU_ITEMS=()
declare -gA HYPR_MENU_PARENTS=()
declare -ga HYPR_MENU_ACTION_HANDLERS=()

menu_spawn_entry() {
  setsid -f hyprshell rofi/menutree.sh "$@" >/dev/null 2>&1
}

back_to() {
  menu_exit_or_show "${1:-main}"
}

menu_exit_or_show() {
  local menu_id="${1:-main}"

  if [[ "${BACK_TO_EXIT}" == "true" ]]; then
    exit 0
  fi

  menu_show_menu "${menu_id}"
  exit 0
}

menu() {
  local prompt="$1"
  local options="$2"
  local preselect="${3:-}"
  local width_override="${4:-}"
  local options_rendered=""
  local rofi_args=()
  local rofi_stderr_file=""
  local rofi_stderr_target="/dev/stderr"
  local rofi_error=""
  local rofi_exit=0
  local selection=""
  local line=""
  local index=0
  local menu_border_metrics=""

  if [[ -z "${MENU_BORDER_RADIUS}" || -z "${MENU_BORDER_WIDTH}" ]]; then
    menu_border_metrics="$(rofi_default_border_metrics 2 2)"
    IFS=$'\t' read -r MENU_BORDER_RADIUS MENU_BORDER_WIDTH <<< "${menu_border_metrics}"
    [[ "${MENU_BORDER_RADIUS}" =~ ^[0-9]+$ ]] || MENU_BORDER_RADIUS=2
    [[ "${MENU_BORDER_WIDTH}" =~ ^[0-9]+$ ]] || MENU_BORDER_WIDTH=2
  fi
  [[ "${MENU_BORDER_RADIUS}" =~ ^[0-9]+$ ]] || MENU_BORDER_RADIUS=2
  MENU_ELEMENT_RADIUS="${MENU_BORDER_RADIUS}"

  if [[ -z "${MENU_WINDOW_THEME_CACHE}" ]]; then
    MENU_WINDOW_THEME_CACHE="$(rofi_standard_window_theme "listview" "same")"
  fi

  if [[ -z "${MENU_FONT_SCALE_CACHE}" ]]; then
    MENU_FONT_SCALE_CACHE="$(rofi_effective_font_scale "${ROFI_MENU_SCALE:-$ROFI_SCALE}")"
  fi

  if [[ -z "${MENU_FONT_NAME_CACHE}" ]]; then
    MENU_FONT_NAME_CACHE="$(rofi_effective_font_name "${ROFI_MENU_FONT:-$ROFI_FONT}")"
  fi

  if [[ -z "${MENU_MAX_HEIGHT}" ]]; then
    local screen_height=""
    screen_height="$(hyprctl -j monitors 2>/dev/null | jq -r '.[0].height // empty' 2>/dev/null || true)"
    [[ "${screen_height}" =~ ^[0-9]+$ ]] || screen_height=1080
    MENU_MAX_HEIGHT=$((screen_height * 90 / 100))
  fi

  if [[ -z "${width_override}" ]]; then
    if [[ -z "${MENU_WIDTH_OVERRIDE_CACHE}" ]]; then
      MENU_WIDTH_OVERRIDE_CACHE="$(
        rofi_theme_width_multiplier_override menutree "${ROFI_MENU_WIDTH_MULTIPLIER:-1}" 295px 2>/dev/null || true
      )"
    fi
    width_override="${MENU_WIDTH_OVERRIDE_CACHE}"
  fi

  options_rendered="$(printf '%b' "${options}")"

  rofi_args+=("-theme-str" "* {font: \"${MENU_FONT_NAME_CACHE} ${MENU_FONT_SCALE_CACHE}\";}")
  rofi_args+=("-theme-str" "${MENU_WINDOW_THEME_CACHE}")
  rofi_args+=("-theme-str" "window { max-height: ${MENU_MAX_HEIGHT}px; }")
  rofi_args+=("-theme-str" "textbox-prompt-colon {border-radius: ${MENU_ELEMENT_RADIUS}px; str: \"$prompt\";}")
  rofi_args+=("-theme-str" "entry {placeholder: \"Hello ${USER^}!\";}")
  rofi_args+=("-theme-str" "element selected.normal {border-radius: ${MENU_ELEMENT_RADIUS}px;}")
  [[ -n "${width_override}" ]] && rofi_args+=("-theme-str" "${width_override}")

  local opacity_override
  opacity_override="$(rofi_active_opacity_override)"
  [[ -n "${opacity_override}" ]] && rofi_args+=("-theme-str" "${opacity_override}")

  if [[ -n "${preselect}" ]]; then
    while IFS= read -r line; do
      ((index += 1))
      if [[ "${line}" == "${preselect}" ]]; then
        rofi_args+=("-selected-row" "$((index - 1))")
        break
      fi
    done <<<"${options_rendered}"
  fi

  rofi_stderr_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/rofi-menu.XXXXXX" 2>/dev/null || true)"
  [[ -n "${rofi_stderr_file}" ]] && rofi_stderr_target="${rofi_stderr_file}"

  selection="$(
    printf '%s' "${options_rendered}" | rofi -dmenu -i -no-show-icons -p "$prompt" -theme "$(rofi_resolve_theme menutree)" "${rofi_args[@]}" 2>"${rofi_stderr_target}"
  )"
  rofi_exit=$?

  if [[ -n "${rofi_stderr_file}" && -s "${rofi_stderr_file}" ]]; then
    rofi_error="$(<"${rofi_stderr_file}")"
  fi
  [[ -n "${rofi_stderr_file}" ]] && rm -f "${rofi_stderr_file}"

  if ((rofi_exit != 0)) && [[ -n "${rofi_error}" ]]; then
    printf 'WARN: rofi menu failed: %s\n' "${rofi_error}" >&2
  fi

  printf '%s' "${selection}"
  return "${rofi_exit}"
}

terminal() {
  present_terminal --app-id org.tui.HyprShell --title HyprShell -- "$@"
}

present_terminal() {
  local app_id=""
  local title=""
  local hypr_profile=""
  local cmd=()
  local launch_args=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --app-id)
        app_id="$2"
        shift 2
        ;;
      --title)
        title="$2"
        shift 2
        ;;
      --hypr-profile)
        hypr_profile="$2"
        shift 2
        ;;
      --)
        shift
        cmd+=("$@")
        break
        ;;
      *)
        cmd+=("$1")
        shift
        ;;
    esac
  done

  if [[ "${#cmd[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ -n "$app_id" || -n "$title" || -n "$hypr_profile" ]]; then
    [[ -n "${hypr_profile}" ]] && launch_args+=(--hypr-profile "${hypr_profile}")
    launch_args+=(--app-id "${app_id:-org.tui.Terminal}" --title "${title:-Terminal}" -- "${cmd[@]}")
    hyprshell launch/terminal-present.sh "${launch_args[@]}"
  else
    hyprshell launch/terminal-present.sh -- "${cmd[@]}"
  fi
}

open_in_editor() {
  dunstify -t 3000 -i "text-editor" "Editing config file" "$1"
  hyprshell launch/editor.sh "$1"
}

menu_define() {
  local menu_id="$1"
  local prompt="$2"
  local default="${3:-}"

  HYPR_MENU_PROMPTS["${menu_id}"]="${prompt}"
  HYPR_MENU_DEFAULTS["${menu_id}"]="${default}"
  : "${HYPR_MENU_ITEMS["${menu_id}"]:=}"
}

menu_add_item() {
  local menu_id="$1"
  local label="$2"
  local kind="$3"
  local target="$4"
  local searchable="${5:-1}"
  local record=""

  record="${label//$'\t'/ }"
  record+=$'\t'"${kind}"$'\t'"${target}"$'\t'"${searchable}"

  if [[ -n "${HYPR_MENU_ITEMS["${menu_id}"]:-}" ]]; then
    HYPR_MENU_ITEMS["${menu_id}"]+=$'\n'
  fi
  HYPR_MENU_ITEMS["${menu_id}"]+="${record}"

  if [[ "${kind}" == "submenu" && -z "${HYPR_MENU_PARENTS["${target}"]:-}" ]]; then
    HYPR_MENU_PARENTS["${target}"]="${menu_id}"
  fi
}

menu_register_action_handler() {
  HYPR_MENU_ACTION_HANDLERS+=("$1")
}

menu_render_options() {
  local menu_id="$1"
  local label=""
  local kind=""
  local target=""
  local searchable=""
  local output=""

  while IFS=$'\t' read -r label kind target searchable; do
    [[ -n "${label}" ]] || continue
    output+="${label}"$'\n'
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"

  printf '%s' "${output%$'\n'}"
}

menu_lookup_selection() {
  local menu_id="$1"
  local selection="$2"
  local out_kind_name="$3"
  local out_target_name="$4"
  local label=""
  local item_kind=""
  local item_target=""
  local _item_searchable=""

  while IFS=$'\t' read -r label item_kind item_target _item_searchable; do
    [[ "${label}" == "${selection}" ]] || continue
    printf -v "${out_kind_name}" '%s' "${item_kind}"
    printf -v "${out_target_name}" '%s' "${item_target}"
    return 0
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"

  return 1
}

menu_run_action() {
  local action_id="$1"
  local handler=""

  for handler in "${HYPR_MENU_ACTION_HANDLERS[@]}"; do
    if "${handler}" "${action_id}"; then
      return 0
    fi
  done

  return 1
}

menu_dispatch_selection() {
  local menu_id="$1"
  local selection="$2"
  local kind=""
  local target=""

  if ! menu_lookup_selection "${menu_id}" "${selection}" kind target; then
    return 1
  fi

  case "${kind}" in
    submenu)
      menu_show_menu "${target}"
      return 0
      ;;
    action)
      menu_run_action "${target}"
      ;;
    *)
      return 1
      ;;
  esac
}

menu_show_menu() {
  local menu_id="$1"
  local prompt="${HYPR_MENU_PROMPTS["${menu_id}"]:-${menu_id}}"
  local options=""
  local selection=""

  options="$(menu_render_options "${menu_id}")"
  selection="$(menu "${prompt}" "${options}" "${HYPR_MENU_DEFAULTS["${menu_id}"]:-}")"

  if [[ -z "${selection}" || "${selection}" == "CNCLD" ]]; then
    if [[ "${menu_id}" == "main" ]]; then
      exit 0
    else
      back_to "${HYPR_MENU_PARENTS["${menu_id}"]:-main}"
    fi
    return 0
  fi

  if ! menu_dispatch_selection "${menu_id}" "${selection}"; then
    menu_show_menu "${menu_id}"
  fi
}

menu_collect_search_entries() {
  local menu_id="$1"
  local out_labels_name="$2"
  local out_actions_name="$3"
  local prefix="${4:-}"
  local label=""
  local kind=""
  local target=""
  local searchable=""
  local path=""

  local -n out_labels_ref="${out_labels_name}"
  local -n out_actions_ref="${out_actions_name}"

  while IFS=$'\t' read -r label kind target searchable; do
    [[ -n "${label}" ]] || continue
    [[ "${searchable}" != "0" ]] || continue
    path="${prefix:+${prefix} › }${label}"

    case "${kind}" in
      submenu)
        menu_collect_search_entries "${target}" "${out_labels_name}" "${out_actions_name}" "${path}"
        ;;
      action)
        out_labels_ref+=("${path}")
        # shellcheck disable=SC2034 # Nameref output assigned for the caller.
        out_actions_ref["${path}"]="${target}"
        ;;
    esac
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"
}

#!/usr/bin/env bash

# Set to true when going directly to a submenu, so we can exit directly
BACK_TO_EXIT="${BACK_TO_EXIT:-false}"
MENU_BORDER_RADIUS="${MENU_BORDER_RADIUS:-}"
MENU_BORDER_WIDTH="${MENU_BORDER_WIDTH:-}"
MENU_ELEMENT_RADIUS="${MENU_ELEMENT_RADIUS:-}"
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
  setsid -f hyprshell rofi/menu.sh "$@" >/dev/null 2>&1
}

back_to() {
  local target="${1:-main}"

  if [[ "${BACK_TO_EXIT}" == "true" ]]; then
    exit 0
  fi

  menu_show_menu "${target}"
  exit 0
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
  local line=""
  local index=0

  if [[ -z "${MENU_BORDER_RADIUS}" ]]; then
    MENU_BORDER_RADIUS="$(hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r '.int // empty' 2>/dev/null || true)"
    [[ "${MENU_BORDER_RADIUS}" =~ ^[0-9]+$ ]] || MENU_BORDER_RADIUS=2
    MENU_ELEMENT_RADIUS=$((MENU_BORDER_RADIUS / 2))
  fi

  if [[ -z "${MENU_BORDER_WIDTH}" ]]; then
    MENU_BORDER_WIDTH="$(hyprctl -j getoption general:border_size 2>/dev/null | jq -r '.int // empty' 2>/dev/null || true)"
    [[ "${MENU_BORDER_WIDTH}" =~ ^[0-9]+$ ]] || MENU_BORDER_WIDTH=2
  fi

  if [[ -z "${MENU_FONT_SCALE_CACHE}" ]]; then
    MENU_FONT_SCALE_CACHE="${ROFI_MENU_SCALE:-$ROFI_SCALE}"
    [[ "${MENU_FONT_SCALE_CACHE}" =~ ^[0-9]+$ ]] || MENU_FONT_SCALE_CACHE=${ROFI_SCALE:-10}
  fi

  if [[ -z "${MENU_FONT_NAME_CACHE}" ]]; then
    MENU_FONT_NAME_CACHE="${ROFI_MENU_FONT:-$ROFI_FONT}"
    MENU_FONT_NAME_CACHE=${MENU_FONT_NAME_CACHE:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
    MENU_FONT_NAME_CACHE=${MENU_FONT_NAME_CACHE:-$(get_hypr_conf "MENU_FONT")}
    MENU_FONT_NAME_CACHE=${MENU_FONT_NAME_CACHE:-$(get_hypr_conf "FONT")}
    MENU_FONT_NAME_CACHE=${MENU_FONT_NAME_CACHE:-monospace}
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
  rofi_args+=("-theme-str" "window {border: ${MENU_BORDER_WIDTH}px solid; border-radius: ${MENU_BORDER_RADIUS}px; max-height: ${MENU_MAX_HEIGHT}px;}")
  rofi_args+=("-theme-str" "element {border-radius: ${MENU_BORDER_RADIUS}px;}")
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

  printf '%s' "${options_rendered}" | rofi -dmenu -i -no-show-icons -p "$prompt" -theme "$(rofi_resolve_theme menutree)" "${rofi_args[@]}" 2>/dev/null
}

terminal() {
  xdg-terminal-exec --app-id=org.tui.HyprShell "$@"
}

present_terminal() {
  local app_id=""
  local title=""
  local cmd=()

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

  if [[ -n "$app_id" || -n "$title" ]]; then
    hyprshell launch/terminal-present.sh --app-id "${app_id:-org.tui.Terminal}" --title "${title:-Terminal}" -- "${cmd[@]}"
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
  local item_searchable=""

  local -n out_kind_ref="${out_kind_name}"
  local -n out_target_ref="${out_target_name}"

  while IFS=$'\t' read -r label item_kind item_target item_searchable; do
    [[ "${label}" == "${selection}" ]] || continue
    out_kind_ref="${item_kind}"
    out_target_ref="${item_target}"
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
        out_actions_ref["${path}"]="${target}"
        ;;
    esac
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"
}

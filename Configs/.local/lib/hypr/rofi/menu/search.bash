#!/usr/bin/env bash

menu_collect_search_rows() {
  local menu_id="$1" path="$6" depth="${7:-0}"
  local label="" key="" kind="" target="" next_path=""
  local label_markup="" path_display="${path}" path_markup="" row=""
  local -n direct_rows_ref="$2" deeper_rows_ref="$3" direct_item_keys_ref="$4" deeper_item_keys_ref="$5"

  if ((depth > 0)); then
    path_display="${path#* › }"
    ((depth >= MENU_SEARCH_PATH_COLLAPSE_DEPTH)) && path_display="${path_display%% › *} › … › ${path_display##* › }"
  fi

  menu_escape_markup_reply "${path_display}"
  path_markup="${REPLY}"

  while IFS= read -r label; do
    [[ -n "${label}" ]] || continue
    key="${menu_id}${MENU_ITEM_KEY_SEP}${label}"
    [[ "${HYPR_MENU_SEARCHABLE["${key}"]}" != "0" ]] || continue
    kind="${HYPR_MENU_KINDS["${key}"]}"
    target="${HYPR_MENU_TARGETS["${key}"]}"

    menu_escape_markup_reply "${label}"
    label_markup="${REPLY}"

    row="${label}${MENU_ROW_OPT}display${MENU_ROW_OPT_SEP}${label_markup}"
    row+=$'\n'"<span size=\"small\" alpha=\"55%\">${path_markup}</span>"
    if ((depth > 0)); then
      deeper_rows_ref+=("${row}")
      deeper_item_keys_ref+=("${key}")
    else
      direct_rows_ref+=("${row}")
      direct_item_keys_ref+=("${key}")
    fi

    [[ "${kind}" == "submenu" ]] || continue
    next_path="${label}"
    if [[ "${label}" =~ ^[^\ -~][[:space:]]+(.+)$ ]]; then
      next_path="${BASH_REMATCH[1]}"
    fi
    menu_collect_search_rows "${target}" "$2" "$3" "$4" "$5" "${path} › ${next_path}" $((depth + 1))
  done <<<"${HYPR_MENU_LABELS["${menu_id}"]:-}"
}

menu_dispatch_search_item() {
  local item_key="$1"
  local kind="${HYPR_MENU_KINDS["${item_key}"]}"
  local target="${HYPR_MENU_TARGETS["${item_key}"]}"

  case "${kind}" in
    submenu) menu_show_menu "${target}" ;;
    action) menu_run_action "${target}" ;;
  esac
}

menu_show_search() {
  local menu_id="${1:-main}"
  local root_name="${HYPR_MENU_PROMPTS["${menu_id}"]:-${menu_id}}"
  local -a direct_rows=() deeper_rows=() direct_item_keys=() deeper_item_keys=() rows=() row_item_keys=()
  local options="" item_key="" selection=""
  local rofi_exit=0

  menu_resolve_style
  menu_collect_search_rows "${menu_id}" direct_rows deeper_rows direct_item_keys deeper_item_keys "${root_name}" 0

  if ((${#direct_rows[@]} + ${#deeper_rows[@]} == 0)); then
    menu_exit_or_show "${menu_id}"
    return 0
  fi

  rows=("${MENU_SEARCH_GUARD_ROW}" "${direct_rows[@]}" "${deeper_rows[@]}")
  row_item_keys=("" "${direct_item_keys[@]}" "${deeper_item_keys[@]}")
  options="$(IFS="${MENU_ROW_SEP}"; printf '%s' "${rows[*]}")"

  MENU_PROMPT_GLYPH="${HYPR_MENU_GLYPHS[search_all]:-}"
  selection="$(menu "Search" "${options}" --nav search --rows detail)"
  rofi_exit=$?

  if ((rofi_exit == MENU_EXIT_BACK)); then
    menu_exit_or_show "${menu_id}"
    return 0
  fi

  ((rofi_exit == 0)) || exit 0

  if [[ ! "${selection}" =~ ^[0-9]+$ ]]; then
    menu_exit_or_show "${menu_id}"
    return 0
  fi

  item_key="${row_item_keys[selection]:-}"
  if [[ -z "${item_key}" ]]; then
    menu_exit_or_show "${menu_id}"
    return 0
  fi

  menu_dispatch_search_item "${item_key}"
}

menu_search_all() {
  menu_show_search main
}

menu_run_search_action() {
  [[ "$1" == search_all ]] || return "${MENU_ACTION_UNKNOWN}"
  menu_search_all
}

menu_register_action_handler menu_run_search_action

#!/usr/bin/env bash

menu_exit_or_show() {
  [[ "${BACK_TO_EXIT}" == "true" ]] || menu_show_menu "${1:-main}"
  exit 0
}

menu_render_options() {
  local menu_id="$1" out_name="$2" preselect_name="${3:-}" label="" key="" target="" glyph="" output="" flagged="" aligned=""
  local -i row=0 active_row=-1
  local -a lines=()

  while IFS= read -r label; do
    [[ -n "${label}" ]] || continue
    key="${menu_id}${MENU_ITEM_KEY_SEP}${label}"
    target="${HYPR_MENU_TARGETS["${key}"]}"
    output+="${label}"$'\n'
    if [[ "${HYPR_MENU_KINDS["${key}"]}" == "submenu" ]]; then
      menu_descendant_depth "${target}"
      glyph="$(menu_submenu_glyph "${HYPR_MENU_DEPTHS["${target}"]}")"
      flagged+="1"$'\t'"${label}"$'\t'"${glyph}"$'\n'
    elif menu_item_active "${target}"; then
      ((active_row < 0)) && active_row=row
      flagged+="1"$'\t'"${label}"$'\t'"${MENU_CHECK_GLYPH}"$'\n'
    else
      flagged+="0"$'\t'"${label}"$'\t'$'\n'
    fi
    row+=1
  done <<<"${HYPR_MENU_LABELS["${menu_id}"]:-}"

  aligned="$(printf '%s' "${flagged}" | rofi_font_align_trailing \
    "${MENU_STYLE[font_name]}" "${MENU_STYLE[font_scale]}" "${MENU_SUBMENU_GLYPH_1}" \
    "$(menu_text_column_px)" 2>/dev/null || true)"
  if [[ -z "${aligned}" ]]; then
    aligned="${output%$'\n'}"
  fi
  printf -v "${out_name}" '%s' "${aligned}"
  if [[ -n "${preselect_name}" && -v HYPR_MENU_CHOICES["${menu_id}"] ]] && ((active_row >= 0)); then
    mapfile -t lines <<<"${aligned}"
    printf -v "${preselect_name}" '%s' "${lines[active_row]}"
  fi
}

menu_dispatch_selection() {
  local menu_id="$1"
  local selection="$2"
  local kind=""
  local target=""

  if ! menu_lookup_selection "${menu_id}" "${selection}" kind target; then
    return "${MENU_ACTION_UNKNOWN}"
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
      return "${MENU_ACTION_UNKNOWN}"
      ;;
  esac
}

menu_show_menu() {
  local menu_id="$1"
  local prompt="${HYPR_MENU_PROMPTS["${menu_id}"]:-${menu_id}}"
  local options=""
  local preselect=""
  local selection=""
  local rofi_exit=0

  menu_resolve_style
  menu_render_options "${menu_id}" options preselect
  MENU_PROMPT_GLYPH="${HYPR_MENU_GLYPHS["${menu_id}"]:-${MENU_ROOT_GLYPH}}"
  selection="$(menu "${prompt}" "${options}" --select "${preselect}" --nav tree)"
  rofi_exit=$?

  if ((rofi_exit == MENU_EXIT_SEARCH)); then
    menu_show_search "${menu_id}"
    return 0
  fi

  if ((rofi_exit == MENU_EXIT_BACK)); then
    [[ "${menu_id}" == "main" ]] && exit 0
    menu_exit_or_show "${HYPR_MENU_PARENTS["${menu_id}"]:-main}"
    return 0
  fi

  # anything else non-zero is cancel, and cancel always leaves the tree
  if ((rofi_exit != 0 && rofi_exit != MENU_EXIT_DESCEND)); then
    exit 0
  fi
  if [[ -z "${selection}" ]]; then
    exit 0
  fi

  local dispatch_status=0
  menu_dispatch_selection "${menu_id}" "${selection}" || dispatch_status=$?
  ((dispatch_status == MENU_ACTION_UNKNOWN)) || return "${dispatch_status}"
  menu_show_menu "${menu_id}"
}

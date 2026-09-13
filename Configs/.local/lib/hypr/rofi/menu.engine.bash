#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

BACK_TO_EXIT="${BACK_TO_EXIT:-false}"
MENU_BORDER_RADIUS="${MENU_BORDER_RADIUS:-}"
MENU_ELEMENT_RADIUS="${MENU_ELEMENT_RADIUS:-}"
MENU_WINDOW_THEME_CACHE="${MENU_WINDOW_THEME_CACHE:-}"
MENU_FONT_SCALE_CACHE="${MENU_FONT_SCALE_CACHE:-}"
MENU_FONT_NAME_CACHE="${MENU_FONT_NAME_CACHE:-}"
MENU_WIDTH_OVERRIDE_CACHE="${MENU_WIDTH_OVERRIDE_CACHE:-}"
MENU_SUBMENU_GLYPH_1="${MENU_SUBMENU_GLYPH_1:-󰅂}"
MENU_SUBMENU_GLYPH_2="${MENU_SUBMENU_GLYPH_2:-󰄾}"
MENU_SUBMENU_GLYPH_3="${MENU_SUBMENU_GLYPH_3:-󰶻}"
MENU_NAV_HINT="${MENU_NAV_HINT:-<span size=\"x-small\">  ← Back · → Open 
[Tab] Search · [Esc] Close</span>}"
MENU_COPY_HINT="${MENU_COPY_HINT:-<span size=\"x-small\">[Enter] Apply · [Alt+C] Copy</span>}"
MENU_MULTI_HINT="${MENU_MULTI_HINT:-<span size=\"x-small\">[Shift+Enter] Mark · [Enter] Confirm</span>}"

MENU_MULTI_BALLOT_ON="${MENU_MULTI_BALLOT_ON:-■}"
MENU_MULTI_BALLOT_OFF="${MENU_MULTI_BALLOT_OFF:-□}"

# Pixel costs from menutree.rasi.
MENU_CONTENT_CHROME_PX=73
MENU_VERTICAL_CHROME_PX=75
MENU_ROW_CHROME_PX=25
MENU_FOOTER_CHROME_PX=24

# kb-custom-N exits with 9 + N.
MENU_EXIT_BACK=10
MENU_EXIT_COPY=10
MENU_EXIT_DESCEND=11
MENU_EXIT_SEARCH=12

MENU_ROW_SEP=$'\x1e'
# Bash cannot store Rofi's NUL option marker; menu_emit_options translates this.
MENU_ROW_OPT=$'\x01'
MENU_ROW_OPT_SEP=$'\x1f'
MENU_ITEM_KEY_SEP=$'\x1d'

# Prevent require-input from accepting the hidden first result on empty Enter.
MENU_SEARCH_GUARD_ROW=$'​\n​'

declare -gA HYPR_MENU_PROMPTS=()
declare -gA HYPR_MENU_DEFAULTS=()
declare -gA HYPR_MENU_ITEMS=()
declare -gA HYPR_MENU_PARENTS=()
declare -gA HYPR_MENU_KINDS=()
declare -gA HYPR_MENU_TARGETS=()
declare -gA HYPR_MENU_SEARCHABLE=()
declare -gA HYPR_MENU_DEPTHS=()
declare -ga HYPR_MENU_ACTION_HANDLERS=()

menu_exit_or_show() {
  [[ "${BACK_TO_EXIT}" == "true" ]] || menu_show_menu "${1:-main}"
  exit 0
}

menu_metrics_cache_init() {
  [[ -n "${MENU_FONT_SCALE_CACHE}" ]] ||
    MENU_FONT_SCALE_CACHE="$(rofi_effective_font_scale "${ROFI_MENU_SCALE:-${ROFI_SCALE:-}}")"
  [[ -n "${MENU_FONT_NAME_CACHE}" ]] ||
    MENU_FONT_NAME_CACHE="$(rofi_effective_font_name "${ROFI_MENU_FONT:-${ROFI_FONT:-}}")"
  [[ -n "${MENU_WIDTH_OVERRIDE_CACHE}" ]] || MENU_WIDTH_OVERRIDE_CACHE="$(
    rofi_theme_width_multiplier_override menutree "${ROFI_MENU_WIDTH_MULTIPLIER:-1}" 295px 2>/dev/null || true
  )"
}

menu_text_column_px() {
  local floor_px=""

  [[ "${MENU_WIDTH_OVERRIDE_CACHE}" =~ ([0-9]+)(\.[0-9]+)?px ]] || { printf '0'; return; }
  floor_px="${BASH_REMATCH[1]}"
  ((floor_px > MENU_CONTENT_CHROME_PX)) || { printf '0'; return; }
  printf '%s' "$((floor_px - MENU_CONTENT_CHROME_PX))"
}

menu_emit_options() {
  local rows="$1"
  local row_mode="${2:-}"

  if [[ "${row_mode}" == "detail" ]]; then
    printf '%s' "${rows}" | tr "${MENU_ROW_OPT}" '\000'
    return 0
  fi

  printf '%s' "${rows}"
}

menu_content_theme_override() {
  local rows="$1"
  local lines_per_row="${2:-1}"
  local footer_mode="${3:-}"
  local extents="" content_px="" text_px="" cap_px="" rows_max="" footer_px=0 mon_width="" mon_height=""

  extents="$(
    printf '%s\n' "${rows}" | rofi_font_text_extents_px "${MENU_FONT_NAME_CACHE}" "${MENU_FONT_SCALE_CACHE}" 2>/dev/null || true
  )"
  read -r content_px text_px <<<"${extents}"
  [[ "${content_px}" =~ ^[0-9]+$ && "${text_px}" =~ ^[0-9]+$ ]] || return 1

  case "${footer_mode}" in
    tree) footer_px=$((text_px * 2 + MENU_FOOTER_CHROME_PX)) ;;
    copy | multi) footer_px=$((text_px + MENU_FOOTER_CHROME_PX)) ;;
  esac

  read -r mon_width mon_height < <(rofi_focused_monitor_logical_size)

  content_px=$((content_px + MENU_CONTENT_CHROME_PX))
  if [[ "${MENU_WIDTH_OVERRIDE_CACHE}" =~ ([0-9]+)(\.[0-9]+)?px ]] && ((content_px < BASH_REMATCH[1])); then
    content_px="${BASH_REMATCH[1]}"
  fi
  if [[ "${mon_width}" =~ ^[0-9]+$ ]]; then
    cap_px=$((mon_width * 60 / 100))
    ((content_px > cap_px)) && content_px="${cap_px}"
  fi
  printf 'window { width: %spx; }' "${content_px}"

  if [[ "${mon_height}" =~ ^[0-9]+$ ]]; then
    rows_max=$(((mon_height * 80 / 100 - MENU_VERTICAL_CHROME_PX - text_px - footer_px) / (text_px * lines_per_row + MENU_ROW_CHROME_PX)))
    ((rows_max < 1)) && rows_max=1
    printf ' listview { lines: %s; }' "${rows_max}"
  fi

  printf '\n'
}

menu_ensure_border_metrics() {
  [[ "${MENU_BORDER_RADIUS}" =~ ^[0-9]+$ ]] ||
    MENU_BORDER_RADIUS="$(rofi_default_border_radius 2)"
  MENU_ELEMENT_RADIUS="${MENU_BORDER_RADIUS}"

  [[ -n "${MENU_WINDOW_THEME_CACHE}" ]] ||
    MENU_WINDOW_THEME_CACHE="$(rofi_standard_window_theme "listview" "same")"
}

menu_measured_rows() {
  local out_name="$1" options_rendered="$2" nav_keys="$3" row_mode="$4"
  local ballot="" result="" rest="" row=""

  if [[ "${nav_keys}" == "multi" ]]; then
    ballot="${MENU_MULTI_BALLOT_ON} "
    printf -v "${out_name}" '%s' "${ballot}${options_rendered//$'\n'/$'\n'${ballot}}"
    return 0
  fi

  if [[ "${row_mode}" != "detail" ]]; then
    printf -v "${out_name}" '%s' "${options_rendered}"
    return 0
  fi

  rest="${options_rendered}"
  while [[ -n "${rest}" ]]; do
    row="${rest%%"${MENU_ROW_SEP}"*}"
    result+="${row%%"${MENU_ROW_OPT}"*}"$'\n'
    [[ "${rest}" == *"${MENU_ROW_SEP}"* ]] || break
    rest="${rest#*"${MENU_ROW_SEP}"}"
  done
  printf -v "${out_name}" '%s' "${result}"
}

menu_append_nav_args() {
  local -n nav_args_ref="$1"

  case "$2" in
    tree)
      nav_args_ref+=(-kb-move-char-back "" -kb-move-char-forward "" -kb-element-next ""
        -kb-custom-1 "Left" -kb-custom-2 "Right" -kb-custom-3 "Tab")
      nav_args_ref+=(-mesg "${MENU_NAV_HINT}")
      ;;
    copy)
      nav_args_ref+=(-kb-custom-1 "Alt+c")
      nav_args_ref+=(-mesg "${MENU_COPY_HINT}")
      ;;
    multi)
      nav_args_ref+=(-multi-select)
      nav_args_ref+=(-ballot-selected-str "${MENU_MULTI_BALLOT_ON} " -ballot-unselected-str "${MENU_MULTI_BALLOT_OFF} ")
      nav_args_ref+=(-mesg "${MENU_MULTI_HINT}")
      ;;
  esac
}

menu_preselect_row() {
  local out_name="$1" options_rendered="$2" preselect="$3"
  local line="" index=0

  printf -v "${out_name}" '%s' ""
  [[ -n "${preselect}" ]] || return 0
  while IFS= read -r line; do
    if [[ "${line}" == "${preselect}" ]]; then
      printf -v "${out_name}" '%s' "${index}"
      return 0
    fi
    ((index += 1))
  done <<<"${options_rendered}"
}

menu_run_rofi() {
  local prompt="$1"
  local options_rendered="$2"
  local row_mode="$3"
  shift 3
  local stderr_file="" stderr_target="/dev/stderr" error="" selection="" exit_code=0

  stderr_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/rofi-menu.XXXXXX" 2>/dev/null || true)"
  [[ -n "${stderr_file}" ]] && stderr_target="${stderr_file}"
  selection="$(menu_emit_options "${options_rendered}" "${row_mode}" |
    rofi -dmenu -i -no-show-icons -p "${prompt}" -theme "$(rofi_resolve_theme menutree)" "$@" \
      2>"${stderr_target}")"
  exit_code=$?

  if [[ -n "${stderr_file}" ]]; then
    [[ -s "${stderr_file}" ]] && error="$(<"${stderr_file}")"
    rm -f "${stderr_file}"
  fi
  ((exit_code == 0)) || [[ -z "${error}" ]] || printf 'WARN: rofi menu failed: %s\n' "${error}" >&2
  printf '%s' "${selection}"
  return "${exit_code}"
}

# menu <prompt> <options> [--select ROW] [--nav tree|copy|multi] [--rows detail]
menu() {
  local prompt="$1"
  local options="$2"
  shift 2
  local preselect="" nav_keys="" row_mode=""

  while (($#)); do
    (($# > 1)) || {
      printf 'menu: missing value for %s\n' "$1" >&2
      return 2
    }
    case "$1" in
      --select) preselect="${2:-}" ;;
      --nav) nav_keys="${2:-}" ;;
      --rows) row_mode="${2:-}" ;;
      *)
        printf 'menu: unknown option: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift 2
  done
  case "${nav_keys}" in "" | tree | copy | multi) ;; *) printf 'menu: invalid navigation mode: %s\n' "${nav_keys}" >&2; return 2 ;; esac
  case "${row_mode}" in "" | detail) ;; *) printf 'menu: invalid row mode: %s\n' "${row_mode}" >&2; return 2 ;; esac

  local options_rendered="" measured_rows="" width_override="" selected_row=""
  local opacity_override="" user_name="${USER:-user}" lines_per_row=1
  local -a rofi_args=()

  menu_ensure_border_metrics
  menu_metrics_cache_init

  printf -v options_rendered '%b' "${options}"
  menu_measured_rows measured_rows "${options_rendered}" "${nav_keys}" "${row_mode}"
  [[ "${row_mode}" == "detail" ]] && lines_per_row=2

  width_override="$(menu_content_theme_override "${measured_rows}" "${lines_per_row}" "${nav_keys}" || true)"
  [[ -n "${width_override}" ]] || width_override="${MENU_WIDTH_OVERRIDE_CACHE}"

  rofi_args+=("-theme-str" "$(rofi_font_override "${MENU_FONT_NAME_CACHE}" "${MENU_FONT_SCALE_CACHE}")")
  rofi_args+=("-theme-str" "${MENU_WINDOW_THEME_CACHE}")
  rofi_args+=("-theme-str" "textbox-prompt-colon {border-radius: ${MENU_ELEMENT_RADIUS}px; str: \"${prompt}\";}")
  rofi_args+=("-theme-str" "entry {placeholder: \"Hello ${user_name^}!\";}")
  rofi_args+=("-theme-str" "element selected.normal {border-radius: ${MENU_ELEMENT_RADIUS}px;}")
  [[ -n "${width_override}" ]] && rofi_args+=("-theme-str" "${width_override}")

  menu_append_nav_args rofi_args "${nav_keys}"

  if [[ "${row_mode}" == "detail" ]]; then
    rofi_args+=(-sep "${MENU_ROW_SEP}" -eh 2 -markup-rows -no-custom -format i)
    rofi_args+=("-theme-str" "listview {require-input: true;}")
  fi

  opacity_override="$(rofi_active_opacity_override)"
  [[ -n "${opacity_override}" ]] && rofi_args+=("-theme-str" "${opacity_override}")

  menu_preselect_row selected_row "${options_rendered}" "${preselect}"
  [[ -n "${selected_row}" ]] && rofi_args+=("-selected-row" "${selected_row}")

  menu_run_rofi "${prompt}" "${options_rendered}" "${row_mode}" "${rofi_args[@]}"
}

terminal() {
  present_terminal --app-id org.tui.HyprShell --title HyprShell -- "$@"
}

present_terminal() {
  local app_id="" title="" hypr_profile=""
  local -a hypr_cells=() hypr_size=() cmd=() launch_args=()

  while (($#)); do
    case "$1" in
      --app-id | --title | --hypr-profile)
        (($# > 1)) || return 2
        case "$1" in --app-id) app_id="$2" ;; --title) title="$2" ;; *) hypr_profile="$2" ;; esac
        shift 2 ;;
      --hypr-cells | --hypr-size)
        (($# > 2)) || return 2
        case "$1" in --hypr-cells) hypr_cells=("$2" "$3") ;; *) hypr_size=("$2" "$3") ;; esac
        shift 3 ;;
      --) shift; cmd+=("$@"); break ;;
      *) cmd+=("$1"); shift ;;
    esac
  done

  ((${#cmd[@]})) || return 0

  if [[ -n "${app_id}${title}${hypr_profile}" ]] || ((${#hypr_cells[@]} + ${#hypr_size[@]})); then
    [[ -n "${hypr_profile}" ]] && launch_args+=(--hypr-profile "${hypr_profile}")
    [[ "${#hypr_cells[@]}" -gt 0 ]] && launch_args+=(--hypr-cells "${hypr_cells[@]}")
    [[ "${#hypr_size[@]}" -gt 0 ]] && launch_args+=(--hypr-size "${hypr_size[@]}")
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

  [[ -n "${menu_id}" && "${menu_id}" != *"${MENU_ITEM_KEY_SEP}"* ]] || return 2
  HYPR_MENU_PROMPTS["${menu_id}"]="${prompt}"
  HYPR_MENU_DEFAULTS["${menu_id}"]="${default}"
  : "${HYPR_MENU_ITEMS["${menu_id}"]:=}"
}

menu_add_item() {
  local menu_id="$1" label="${2//$'\t'/ }" kind="$3" target="$4" searchable="${5:-1}"
  local key="${menu_id}${MENU_ITEM_KEY_SEP}${label}"

  [[ -n "${menu_id}" && -n "${label}" && -n "${target}" && "${menu_id}${label}" != *"${MENU_ITEM_KEY_SEP}"* &&
    "${label}" != *$'\n'* && ! -v HYPR_MENU_KINDS["${key}"] ]] || return 2
  case "${kind}:${searchable}" in action:0 | action:1 | submenu:0 | submenu:1) ;; *) return 2 ;; esac
  HYPR_MENU_ITEMS["${menu_id}"]+="${HYPR_MENU_ITEMS["${menu_id}"]:+$'\n'}${label}"
  HYPR_MENU_KINDS["${key}"]="${kind}"
  HYPR_MENU_TARGETS["${key}"]="${target}"
  HYPR_MENU_SEARCHABLE["${key}"]="${searchable}"

  if [[ "${kind}" == "submenu" && -z "${HYPR_MENU_PARENTS["${target}"]:-}" ]]; then
    HYPR_MENU_PARENTS["${target}"]="${menu_id}"
  fi
}

menu_register_action_handler() {
  HYPR_MENU_ACTION_HANDLERS+=("$1")
}

menu_descendant_depth() {
  local menu_id="$1" label="" key="" target="" item_depth=0 depth=0

  [[ -v HYPR_MENU_DEPTHS["${menu_id}"] ]] && return 0
  while IFS= read -r label; do
    [[ -n "${label}" ]] || continue
    key="${menu_id}${MENU_ITEM_KEY_SEP}${label}"
    if [[ "${HYPR_MENU_KINDS["${key}"]}" == "submenu" ]]; then
      target="${HYPR_MENU_TARGETS["${key}"]}"
      menu_descendant_depth "${target}"
      item_depth=$((HYPR_MENU_DEPTHS["${target}"] + 1))
    else
      item_depth=1
    fi
    ((item_depth > depth)) && depth="${item_depth}"
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"
  HYPR_MENU_DEPTHS["${menu_id}"]="${depth}"
}

menu_submenu_glyph() {
  case "$1" in
    1) printf '%s' "${MENU_SUBMENU_GLYPH_1}" ;;
    2) printf '%s' "${MENU_SUBMENU_GLYPH_2}" ;;
    *) printf '%s' "${MENU_SUBMENU_GLYPH_3}" ;;
  esac
}

menu_render_options() {
  local menu_id="$1" out_name="$2" label="" key="" target="" glyph="" output="" flagged="" aligned=""

  while IFS= read -r label; do
    [[ -n "${label}" ]] || continue
    key="${menu_id}${MENU_ITEM_KEY_SEP}${label}"
    output+="${label}"$'\n'
    if [[ "${HYPR_MENU_KINDS["${key}"]}" == "submenu" ]]; then
      target="${HYPR_MENU_TARGETS["${key}"]}"
      menu_descendant_depth "${target}"
      glyph="$(menu_submenu_glyph "${HYPR_MENU_DEPTHS["${target}"]}")"
      flagged+="1"$'\t'"${label}"$'\t'"${glyph}"$'\n'
    else
      flagged+="0"$'\t'"${label}"$'\t'$'\n'
    fi
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"

  aligned="$(printf '%s' "${flagged}" | rofi_font_align_trailing \
    "${MENU_FONT_NAME_CACHE}" "${MENU_FONT_SCALE_CACHE}" "${MENU_SUBMENU_GLYPH_1}" \
    "$(menu_text_column_px)" 2>/dev/null || true)"
  if [[ -z "${aligned}" ]]; then
    aligned="${output%$'\n'}"
  fi
  printf -v "${out_name}" '%s' "${aligned}"
}

menu_lookup_selection() {
  local menu_id="$1" selection="$2" out_kind_name="$3" out_target_name="$4" key="" glyph=""

  for glyph in "${MENU_SUBMENU_GLYPH_1}" "${MENU_SUBMENU_GLYPH_2}" "${MENU_SUBMENU_GLYPH_3}"; do
    [[ "${selection}" == *"${glyph}" ]] || continue
    selection="${selection%"${glyph}"}"
    selection="${selection%"${selection##*[![:space:]]}"}"
    break
  done
  key="${menu_id}${MENU_ITEM_KEY_SEP}${selection}"
  [[ -v HYPR_MENU_KINDS["${key}"] ]] || return 1
  printf -v "${out_kind_name}" '%s' "${HYPR_MENU_KINDS["${key}"]}"
  printf -v "${out_target_name}" '%s' "${HYPR_MENU_TARGETS["${key}"]}"
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
  local rofi_exit=0

  menu_metrics_cache_init
  menu_render_options "${menu_id}" options
  selection="$(menu "${prompt}" "${options}" --select "${HYPR_MENU_DEFAULTS["${menu_id}"]:-}" --nav tree)"
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
  if [[ -z "${selection}" || "${selection}" == "CNCLD" ]]; then
    exit 0
  fi

  if ! menu_dispatch_selection "${menu_id}" "${selection}"; then
    menu_show_menu "${menu_id}"
  fi
}

menu_dump_json() {
  local menu_id="" label="" key="" target="" chevron=""

  for menu_id in "${!HYPR_MENU_PROMPTS[@]}"; do
    while IFS= read -r label; do
      [[ -n "${label}" ]] || continue
      key="${menu_id}${MENU_ITEM_KEY_SEP}${label}"
      target="${HYPR_MENU_TARGETS["${key}"]}"
      chevron=""
      if [[ "${HYPR_MENU_KINDS["${key}"]}" == "submenu" ]]; then
        menu_descendant_depth "${target}"
        chevron="$(menu_submenu_glyph "${HYPR_MENU_DEPTHS["${target}"]}")"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${menu_id}" "${HYPR_MENU_PROMPTS["${menu_id}"]}" "${HYPR_MENU_PARENTS["${menu_id}"]:-}" \
        "${label}" "${HYPR_MENU_KINDS["${key}"]}" "${target}" \
        "${HYPR_MENU_SEARCHABLE["${key}"]}" "${chevron}"
    done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"
  done | jq -Rs '
    split("\n") | map(select(length > 0) | split("\t"))
    | reduce .[] as $r ({}; .[$r[0]] = ((.[$r[0]] // {prompt: $r[1], parent: $r[2], items: []})
        | .items += [{label: $r[3], kind: $r[4], target: $r[5], searchable: ($r[6] != "0"), chevron: $r[7]}]))'
}

menu_collect_subtree() {
  local menu_id="$1" path="$6" depth="${7:-0}"
  local label="" key="" kind="" target="" next_path=""
  local label_markup="" path_display="${path}" path_markup="" row=""
  local -n direct_rows_ref="$2" deeper_rows_ref="$3" direct_targets_ref="$4" deeper_targets_ref="$5"

  if ((depth > 0)); then
    path_display="${path#* › }"
    ((depth >= 4)) && path_display="${path_display%% › *} › … › ${path_display##* › }"
  fi

  path_markup="${path_display//&/\&amp;}"
  path_markup="${path_markup//</\&lt;}"
  path_markup="${path_markup//>/\&gt;}"

  while IFS= read -r label; do
    [[ -n "${label}" ]] || continue
    key="${menu_id}${MENU_ITEM_KEY_SEP}${label}"
    [[ "${HYPR_MENU_SEARCHABLE["${key}"]}" != "0" ]] || continue
    kind="${HYPR_MENU_KINDS["${key}"]}"
    target="${HYPR_MENU_TARGETS["${key}"]}"

    label_markup="${label//&/\&amp;}"
    label_markup="${label_markup//</\&lt;}"
    label_markup="${label_markup//>/\&gt;}"

    row="${label}${MENU_ROW_OPT}display${MENU_ROW_OPT_SEP}${label_markup}"
    row+=$'\n'"<span size=\"small\" alpha=\"55%\">${path_markup}</span>"
    if ((depth > 0)); then
      deeper_rows_ref+=("${row}")
      deeper_targets_ref+=("${kind}"$'\t'"${target}")
    else
      direct_rows_ref+=("${row}")
      direct_targets_ref+=("${kind}"$'\t'"${target}")
    fi

    [[ "${kind}" == "submenu" ]] || continue
    next_path="${label}"
    if [[ "${label}" =~ ^[^\ -~][[:space:]]+(.+)$ ]]; then
      next_path="${BASH_REMATCH[1]}"
    fi
    menu_collect_subtree "${target}" "$2" "$3" "$4" "$5" "${path} › ${next_path}" $((depth + 1))
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"
}

menu_show_search() {
  local menu_id="${1:-main}"
  local root_name="${HYPR_MENU_PROMPTS["${menu_id}"]:-${menu_id}}"
  local -a direct_rows=() deeper_rows=() direct_targets=() deeper_targets=() rows=() row_targets=()
  local options="" record="" selection="" kind="" target=""
  local rofi_exit=0

  menu_metrics_cache_init
  menu_collect_subtree "${menu_id}" direct_rows deeper_rows direct_targets deeper_targets "${root_name}" 0

  if ((${#direct_rows[@]} + ${#deeper_rows[@]} == 0)); then
    menu_exit_or_show "${menu_id}"
    return 0
  fi

  rows=("${MENU_SEARCH_GUARD_ROW}" "${direct_rows[@]}" "${deeper_rows[@]}")
  row_targets=("" "${direct_targets[@]}" "${deeper_targets[@]}")
  local IFS="${MENU_ROW_SEP}"
  options="${rows[*]}"

  selection="$(menu "Search" "${options}" --rows detail)"
  rofi_exit=$?

  ((rofi_exit == 0)) || exit 0

  if [[ ! "${selection}" =~ ^[0-9]+$ ]]; then
    menu_exit_or_show "${menu_id}"
    return 0
  fi

  record="${row_targets[selection]:-}"
  if [[ -z "${record}" ]]; then
    menu_exit_or_show "${menu_id}"
    return 0
  fi

  kind="${record%%$'\t'*}"
  target="${record#*$'\t'}"
  case "${kind}" in
    submenu)
      menu_show_menu "${target}"
      ;;
    action)
      menu_run_action "${target}"
      ;;
  esac
}

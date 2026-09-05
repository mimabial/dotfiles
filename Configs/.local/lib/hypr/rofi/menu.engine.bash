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
MENU_WIDTH_OVERRIDE_CACHE="${MENU_WIDTH_OVERRIDE_CACHE:-}"
MENU_SUBMENU_GLYPH="${MENU_SUBMENU_GLYPH:-›}"
MENU_NAV_HINT="${MENU_NAV_HINT:-<span size=\"x-small\">  ← Back · → Open 
[Tab] Search · [Esc] Close</span>}"
MENU_COPY_HINT="${MENU_COPY_HINT:-<span size=\"x-small\">[Enter] Apply · [Alt+C] Copy</span>}"
MENU_MULTI_HINT="${MENU_MULTI_HINT:-<span size=\"x-small\">[Shift+Enter] Mark · [Enter] Confirm</span>}"

# rofi's own ballot pair is ☑/☐, whose tick reads as a smudge at menu sizes; a
# filled square against a hollow one is the same mark at a glance
MENU_MULTI_BALLOT_ON="${MENU_MULTI_BALLOT_ON:-■}"
MENU_MULTI_BALLOT_OFF="${MENU_MULTI_BALLOT_OFF:-□}"

# menutree.rasi chrome beside the element text: mainbox 20*2, element 10*2,
# border 2*2, plus the scrollbar handle 4 and the listview spacing 5 before it
MENU_CONTENT_CHROME_PX=73

# rofi exits 10+N-1 for kb-custom-N; the tree binds Left/Right/Tab to 1, 2 and 3.
MENU_EXIT_BACK=10
MENU_EXIT_COPY=10
MENU_EXIT_DESCEND=11
MENU_EXIT_SEARCH=12

# Detail rows carry their own newline, so they need a separator that is not one.
# It cannot be NUL either -- that is the one byte a bash variable cannot hold.
MENU_ROW_SEP=$'\x1e'

# A row's options follow it after a NUL, keys and values split by \x1f. The NUL
# is the byte a bash variable cannot hold, so rows carry this stand-in and it is
# translated on the way into rofi.
MENU_ROW_OPT=$'\x01'
MENU_ROW_OPT_SEP=$'\x1f'

# require-input hides the list until something is typed, but Enter still accepts
# while it is hidden and takes row 0 with it. This sits in that slot: it maps to
# nothing, so the stray Enter is a no-op, and it holds no character anyone can
# type, so it never surfaces once a query starts filtering.
MENU_SEARCH_GUARD_ROW=$'​\n​'

declare -gA HYPR_MENU_PROMPTS=()
declare -gA HYPR_MENU_DEFAULTS=()
declare -gA HYPR_MENU_ITEMS=()
declare -gA HYPR_MENU_PARENTS=()
declare -ga HYPR_MENU_ACTION_HANDLERS=()

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

menu_metrics_cache_init() {
  if [[ -z "${MENU_FONT_SCALE_CACHE}" ]]; then
    MENU_FONT_SCALE_CACHE="$(rofi_effective_font_scale "${ROFI_MENU_SCALE:-$ROFI_SCALE}")"
  fi

  if [[ -z "${MENU_FONT_NAME_CACHE}" ]]; then
    MENU_FONT_NAME_CACHE="$(rofi_effective_font_name "${ROFI_MENU_FONT:-$ROFI_FONT}")"
  fi

  if [[ -z "${MENU_WIDTH_OVERRIDE_CACHE}" ]]; then
    MENU_WIDTH_OVERRIDE_CACHE="$(
      rofi_theme_width_multiplier_override menutree "${ROFI_MENU_WIDTH_MULTIPLIER:-1}" 295px 2>/dev/null || true
    )"
  fi
}

# Width of the text column rofi will draw rows in, or 0 when the rows themselves
# set it. The theme floor is a window width, so back the chrome out of it.
menu_text_column_px() {
  local floor_px=""

  [[ "${MENU_WIDTH_OVERRIDE_CACHE}" =~ ([0-9]+)(\.[0-9]+)?px ]] || {
    printf '0'
    return 0
  }
  floor_px="${BASH_REMATCH[1]}"
  ((floor_px > MENU_CONTENT_CHROME_PX)) || {
    printf '0'
    return 0
  }

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
  local explicit_width="${2:-}"
  local lines_per_row="${3:-1}"
  local footer_mode="${4:-}"
  local extents="" content_px="" text_px="" cap_px="" rows_max="" footer_px=0 mon_width="" mon_height=""

  extents="$(
    printf '%s\n' "${rows}" | rofi_font_text_extents_px "${MENU_FONT_NAME_CACHE}" "${MENU_FONT_SCALE_CACHE}" 2>/dev/null || true
  )"
  read -r content_px text_px <<<"${extents}"
  [[ "${content_px}" =~ ^[0-9]+$ && "${text_px}" =~ ^[0-9]+$ ]] || return 1

  case "${footer_mode}" in
    tree) footer_px=$((text_px * 2 + 24)) ;;
    copy | multi) footer_px=$((text_px + 24)) ;;
  esac

  read -r mon_width mon_height < <(rofi_focused_monitor_logical_size)

  if [[ -n "${explicit_width}" ]]; then
    printf '%s' "${explicit_width}"
  else
    content_px=$((content_px + MENU_CONTENT_CHROME_PX))
    if [[ "${MENU_WIDTH_OVERRIDE_CACHE}" =~ ([0-9]+)(\.[0-9]+)?px ]] && ((content_px < BASH_REMATCH[1])); then
      content_px="${BASH_REMATCH[1]}"
    fi
    if [[ "${mon_width}" =~ ^[0-9]+$ ]]; then
      cap_px=$((mon_width * 60 / 100))
      ((content_px > cap_px)) && content_px="${cap_px}"
    fi
    printf 'window { width: %spx; }' "${content_px}"
  fi

  # chrome above the rows: border 2*2, mainbox 20*2 padding + the listview's 20 top
  # margin, inputbar 8*2 + text.
  # each row costs element 10*2 padding + listview 5 spacing on top of its text,
  # which a detail row spends twice over. text_px stays one line either way: the
  # extents pass splits a detail row's own newline into two rows of its own.
  if [[ "${mon_height}" =~ ^[0-9]+$ ]]; then
    rows_max=$(((mon_height * 80 / 100 - 75 - text_px - footer_px) / (text_px * lines_per_row + 25)))
    ((rows_max < 1)) && rows_max=1
    printf ' listview { lines: %s; }' "${rows_max}"
  fi

  printf '\n'
}

# menu <prompt> <options> [--select ROW] [--nav tree|copy|multi] [--rows detail]
menu_ensure_border_metrics() {
  local menu_border_metrics=""

  if [[ -z "${MENU_BORDER_RADIUS}" || -z "${MENU_BORDER_WIDTH}" ]]; then
    menu_border_metrics="$(rofi_default_border_metrics 2 2)"
    IFS=$'\t' read -r MENU_BORDER_RADIUS MENU_BORDER_WIDTH <<<"${menu_border_metrics}"
    [[ "${MENU_BORDER_RADIUS}" =~ ^[0-9]+$ ]] || MENU_BORDER_RADIUS=2
    [[ "${MENU_BORDER_WIDTH}" =~ ^[0-9]+$ ]] || MENU_BORDER_WIDTH=2
  fi
  [[ "${MENU_BORDER_RADIUS}" =~ ^[0-9]+$ ]] || MENU_BORDER_RADIUS=2
  MENU_ELEMENT_RADIUS="${MENU_BORDER_RADIUS}"

  [[ -n "${MENU_WINDOW_THEME_CACHE}" ]] ||
    MENU_WINDOW_THEME_CACHE="$(rofi_standard_window_theme "listview" "same")"
}

# The text the window has to be wide enough for, which is not always the rows
# themselves.
menu_measured_rows() {
  local options_rendered="$1"
  local nav_keys="$2"
  local row_mode="$3"
  local ballot="" measured_rows="" measure_rest="" measure_chunk=""

  # the ballot rides ahead of every row, so it is measured with them or the
  # marker column pushes the text out of the window
  if [[ "${nav_keys}" == "multi" ]]; then
    ballot="${MENU_MULTI_BALLOT_ON} "
    printf '%s' "${ballot}${options_rendered//$'\n'/$'\n'${ballot}}"
    return 0
  fi

  if [[ "${row_mode}" != "detail" ]]; then
    printf '%s' "${options_rendered}"
    return 0
  fi

  # Width is fixed before the first keystroke, so it is set by the widest row
  # in the whole subtree either way. Spend it on the labels -- those are what
  # is being picked and must stay whole -- and let an over-long path ellipsize
  # rather than widen every row to fit the deepest one. The text before the
  # options is exactly the label, so it is also what there is to measure.
  measure_rest="${options_rendered}"
  while [[ -n "${measure_rest}" ]]; do
    measure_chunk="${measure_rest%%"${MENU_ROW_SEP}"*}"
    measured_rows+="${measure_chunk%%"${MENU_ROW_OPT}"*}"$'\n'
    [[ "${measure_rest}" == *"${MENU_ROW_SEP}"* ]] || break
    measure_rest="${measure_rest#*"${MENU_ROW_SEP}"}"
  done
  printf '%s' "${measured_rows}"
}

# Appends the keybindings and hint for one navigation mode.
#
# Only the tree steers with Left/Right/Tab; a dynamic caller reads the selection
# alone and would mistake a custom exit code for an accepted row unless it opts
# into "copy" and checks MENU_EXIT_COPY itself. Tab is rofi's own
# kb-element-next, so it has to be surrendered before it is taken.
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
      # Shift+Enter is rofi's kb-accept-alt, which toggles a row's ballot here;
      # Enter prints every marked row, or the highlighted one when none are marked
      nav_args_ref+=(-multi-select)
      nav_args_ref+=(-ballot-selected-str "${MENU_MULTI_BALLOT_ON} " -ballot-unselected-str "${MENU_MULTI_BALLOT_OFF} ")
      nav_args_ref+=(-mesg "${MENU_MULTI_HINT}")
      ;;
  esac
}

# The zero-based index of the row matching $2, or nothing when it is not there.
menu_preselect_row() {
  local options_rendered="$1"
  local preselect="$2"
  local line="" index=0

  [[ -n "${preselect}" ]] || return 0
  while IFS= read -r line; do
    if [[ "${line}" == "${preselect}" ]]; then
      printf '%s' "${index}"
      return 0
    fi
    ((index += 1))
  done <<<"${options_rendered}"
}

# Runs rofi, forwarding its exit code and reporting anything it wrote to stderr.
menu_run_rofi() {
  local prompt="$1"
  local options_rendered="$2"
  local row_mode="$3"
  shift 3
  local stderr_file="" stderr_target="/dev/stderr" error="" selection="" exit_code=0

  stderr_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/rofi-menu.XXXXXX" 2>/dev/null || true)"
  [[ -n "${stderr_file}" ]] && stderr_target="${stderr_file}"

  selection="$(
    menu_emit_options "${options_rendered}" "${row_mode}" |
      rofi -dmenu -i -no-show-icons -p "${prompt}" -theme "$(rofi_resolve_theme menutree)" "$@" \
        2>"${stderr_target}"
  )"
  exit_code=$?

  if [[ -n "${stderr_file}" ]]; then
    [[ -s "${stderr_file}" ]] && error="$(<"${stderr_file}")"
    rm -f "${stderr_file}"
  fi
  if ((exit_code != 0)) && [[ -n "${error}" ]]; then
    printf 'WARN: rofi menu failed: %s\n' "${error}" >&2
  fi

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

  local options_rendered="" measured_rows="" width_override="" selected_row=""
  local opacity_override="" lines_per_row=1
  local -a rofi_args=()

  menu_ensure_border_metrics
  menu_metrics_cache_init

  options_rendered="$(printf '%b' "${options}")"
  measured_rows="$(menu_measured_rows "${options_rendered}" "${nav_keys}" "${row_mode}")"
  [[ "${row_mode}" == "detail" ]] && lines_per_row=2

  width_override="$(menu_content_theme_override "${measured_rows}" "" "${lines_per_row}" "${nav_keys}" || true)"
  [[ -n "${width_override}" ]] || width_override="${MENU_WIDTH_OVERRIDE_CACHE}"

  rofi_args+=("-theme-str" "$(rofi_font_override "${MENU_FONT_NAME_CACHE}" "${MENU_FONT_SCALE_CACHE}")")
  rofi_args+=("-theme-str" "${MENU_WINDOW_THEME_CACHE}")
  rofi_args+=("-theme-str" "textbox-prompt-colon {border-radius: ${MENU_ELEMENT_RADIUS}px; str: \"${prompt}\";}")
  rofi_args+=("-theme-str" "entry {placeholder: \"Hello ${USER^}!\";}")
  rofi_args+=("-theme-str" "element selected.normal {border-radius: ${MENU_ELEMENT_RADIUS}px;}")
  [[ -n "${width_override}" ]] && rofi_args+=("-theme-str" "${width_override}")

  menu_append_nav_args rofi_args "${nav_keys}"

  # the row text is the label alone, so the answer has to be the index: labels
  # repeat across the tree and would not identify the row that was picked
  if [[ "${row_mode}" == "detail" ]]; then
    rofi_args+=(-sep "${MENU_ROW_SEP}" -eh 2 -markup-rows -no-custom -format i)
    rofi_args+=("-theme-str" "listview {require-input: true;}")
  fi

  opacity_override="$(rofi_active_opacity_override)"
  [[ -n "${opacity_override}" ]] && rofi_args+=("-theme-str" "${opacity_override}")

  selected_row="$(menu_preselect_row "${options_rendered}" "${preselect}")"
  [[ -n "${selected_row}" ]] && rofi_args+=("-selected-row" "${selected_row}")

  menu_run_rofi "${prompt}" "${options_rendered}" "${row_mode}" "${rofi_args[@]}"
}

terminal() {
  present_terminal --app-id org.tui.HyprShell --title HyprShell -- "$@"
}

present_terminal() {
  local app_id=""
  local title=""
  local hypr_profile=""
  local hypr_cells=()
  local hypr_size=()
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
      --hypr-cells)
        hypr_cells=("$2" "$3")
        shift 3
        ;;
      --hypr-size)
        hypr_size=("$2" "$3")
        shift 3
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

  if [[ -n "$app_id" || -n "$title" || -n "$hypr_profile" || "${#hypr_cells[@]}" -gt 0 || "${#hypr_size[@]}" -gt 0 ]]; then
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
  local flagged=""
  local aligned=""

  while IFS=$'\t' read -r label kind target searchable; do
    [[ -n "${label}" ]] || continue
    output+="${label}"$'\n'
    if [[ "${kind}" == "submenu" ]]; then
      flagged+="1"$'\t'"${label}"$'\n'
    else
      flagged+="0"$'\t'"${label}"$'\n'
    fi
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"

  if [[ -n "${flagged}" ]]; then
    aligned="$(
      printf '%s' "${flagged}" \
        | rofi_font_align_trailing "${MENU_FONT_NAME_CACHE}" "${MENU_FONT_SCALE_CACHE}" \
          "${MENU_SUBMENU_GLYPH}" "$(menu_text_column_px)" 2>/dev/null || true
    )"
    if [[ -n "${aligned}" ]]; then
      printf '%s' "${aligned}"
      return 0
    fi
  fi

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

  # submenu rows carry a right-aligned chevron that is not part of their label
  if [[ "${selection}" == *"${MENU_SUBMENU_GLYPH}" ]]; then
    selection="${selection%"${MENU_SUBMENU_GLYPH}"}"
    selection="${selection%"${selection##*[![:space:]]}"}"
  fi

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
  local rofi_exit=0

  menu_metrics_cache_init
  options="$(menu_render_options "${menu_id}")"
  selection="$(menu "${prompt}" "${options}" --select "${HYPR_MENU_DEFAULTS["${menu_id}"]:-}" --nav tree)"
  rofi_exit=$?

  if ((rofi_exit == MENU_EXIT_SEARCH)); then
    menu_show_search "${menu_id}"
    return 0
  fi

  if ((rofi_exit == MENU_EXIT_BACK)); then
    [[ "${menu_id}" == "main" ]] && exit 0
    back_to "${HYPR_MENU_PARENTS["${menu_id}"]:-main}"
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

# jq owns the escaping; labels pass through as raw UTF-8, which sidesteps
# jq's inability to write \uXXXX escapes above the BMP
menu_dump_json() {
  local menu_id=""
  local label=""
  local kind=""
  local target=""
  local searchable=""

  for menu_id in "${!HYPR_MENU_PROMPTS[@]}"; do
    while IFS=$'\t' read -r label kind target searchable; do
      [[ -n "${label}" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${menu_id}" "${HYPR_MENU_PROMPTS["${menu_id}"]}" "${HYPR_MENU_PARENTS["${menu_id}"]:-}" \
        "${label}" "${kind}" "${target}" "${searchable}"
    done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"
  done | jq -Rs '
    split("\n") | map(select(length > 0) | split("\t"))
    | reduce .[] as $r ({}; .[$r[0]] = ((.[$r[0]] // {prompt: $r[1], parent: $r[2], items: []})
        | .items += [{label: $r[3], kind: $r[4], target: $r[5], searchable: ($r[6] != "0")}]))'
}

# Walk a menu's subtree into two-line search rows: the label on top, the parent
# path beneath it. rofi filters every row it is handed, a divider row included,
# so the two groups cannot be separated by a header -- they are separated by
# order and by the depth of the path each one carries. Direct children come
# first, under the menu's own name; everything deeper follows, under the path
# that places it. Every row carries a path because rofi's row height is global:
# a row that left the second line empty would reserve it anyway.
#
# The path rides in rofi's per-row `display` option rather than in the row
# itself, because rofi filters on the row and displays the option: a path in the
# row would mean typing a menu's name drags its whole branch into the results.
# Emitted as "<label>\0display\x1f<label>\n<path>", each element prefixed with
# its kind and target since the row text is no longer a usable key -- labels
# repeat across the tree, so the caller keys on rofi's row index instead.
menu_collect_subtree() {
  local menu_id="$1"
  local out_direct_name="$2"
  local out_deeper_name="$3"
  local path="$4"
  local depth="${5:-0}"
  local label=""
  local kind=""
  local target=""
  local searchable=""
  local label_markup=""
  local path_display=""
  local path_markup=""
  local row=""

  local -n out_direct_ref="${out_direct_name}"
  local -n out_deeper_ref="${out_deeper_name}"

  # Every row in the view hangs off the searched menu, so naming it on the deeper
  # rows says nothing they do not already share -- they show what lies below it
  # instead. The direct children keep it, because for them it is the whole path
  # and the one place it distinguishes anything.
  path_display="${path}"
  if ((depth > 0)); then
    path_display="${path#* › }"
    # what is left carries depth segments; from four, collapse the middle, since
    # the ends are what locate a row and the rest is what overruns the window
    ((depth >= 4)) && path_display="${path_display%% › *} › … › ${path_display##* › }"
  fi

  path_markup="${path_display//&/&amp;}"
  path_markup="${path_markup//</&lt;}"
  path_markup="${path_markup//>/&gt;}"

  while IFS=$'\t' read -r label kind target searchable; do
    [[ -n "${label}" ]] || continue
    [[ "${searchable}" != "0" ]] || continue

    label_markup="${label//&/&amp;}"
    label_markup="${label_markup//</&lt;}"
    label_markup="${label_markup//>/&gt;}"

    row="${kind}"$'\t'"${target}"$'\t'"${label}"
    row+="${MENU_ROW_OPT}display${MENU_ROW_OPT_SEP}${label_markup}"
    row+=$'\n'"<span size=\"small\" alpha=\"55%\">${path_markup}</span>"
    if ((depth > 0)); then
      # shellcheck disable=SC2034 # Nameref output assigned for the caller.
      out_deeper_ref+=("${row}")
    else
      # shellcheck disable=SC2034 # Nameref output assigned for the caller.
      out_direct_ref+=("${row}")
    fi

    [[ "${kind}" == "submenu" ]] || continue

    # the path reads as menu names, so drop the leading icon from the label
    if [[ "${label}" =~ ^[^\ -~][[:space:]]+(.+)$ ]]; then
      menu_collect_subtree "${target}" "${out_direct_name}" "${out_deeper_name}" \
        "${path} › ${BASH_REMATCH[1]}" $((depth + 1))
    else
      menu_collect_subtree "${target}" "${out_direct_name}" "${out_deeper_name}" \
        "${path} › ${label}" $((depth + 1))
    fi
  done <<<"${HYPR_MENU_ITEMS["${menu_id}"]:-}"
}

menu_show_search() {
  local menu_id="${1:-main}"
  local root_name="${HYPR_MENU_PROMPTS["${menu_id}"]:-${menu_id}}"
  local -a direct_records=()
  local -a deeper_records=()
  local -a row_targets=()
  local options=""
  local record=""
  local rest=""
  local selection=""
  local kind=""
  local target=""
  local rofi_exit=0

  menu_metrics_cache_init
  menu_collect_subtree "${menu_id}" direct_records deeper_records "${root_name}" 0

  if ((${#direct_records[@]} + ${#deeper_records[@]} == 0)); then
    menu_exit_or_show "${menu_id}"
    return 0
  fi

  # index 0 is the guard row, so it holds no target and a stray Enter is a no-op
  row_targets=("")
  options="${MENU_SEARCH_GUARD_ROW}${MENU_ROW_SEP}"
  for record in "${direct_records[@]}" "${deeper_records[@]}"; do
    kind="${record%%$'\t'*}"
    rest="${record#*$'\t'}"
    target="${rest%%$'\t'*}"
    row_targets+=("${kind}"$'\t'"${target}")
    options+="${rest#*$'\t'}${MENU_ROW_SEP}"
  done
  options="${options%"${MENU_ROW_SEP}"}"

  # no explicit width: the rows are short now that the path is its own line, so
  # the measured fit beats the fixed one the inline-path list used to need
  selection="$(menu "Search" "${options}" --rows detail)"
  rofi_exit=$?

  # cancel always leaves the tree, the same as it does from a menu
  ((rofi_exit == 0)) || exit 0

  # detail mode answers with a row index, so a miss is a non-number or a gap
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

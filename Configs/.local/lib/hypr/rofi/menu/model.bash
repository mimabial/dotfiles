#!/usr/bin/env bash

BACK_TO_EXIT="${BACK_TO_EXIT:-false}"
MENU_SUBMENU_GLYPH_1="${MENU_SUBMENU_GLYPH_1:-󰅂}"
MENU_SUBMENU_GLYPH_2="${MENU_SUBMENU_GLYPH_2:-󰄾}"
MENU_SUBMENU_GLYPH_3="${MENU_SUBMENU_GLYPH_3:-󰶻}"
MENU_CHECK_GLYPH="${MENU_CHECK_GLYPH:-✓}"
MENU_NAV_HINT="${MENU_NAV_HINT:-<span size=\"x-small\">  ← Back · → Open 
[Tab] Search · [Esc] Close</span>}"
MENU_SEARCH_HINT="${MENU_SEARCH_HINT:-<span size=\"x-small\">← Back · [Enter] Open · [Esc] Close</span>}"
MENU_COPY_HINT="${MENU_COPY_HINT:-<span size=\"x-small\">[Enter] Apply · [Alt+C] Copy</span>}"
MENU_MULTI_HINT="${MENU_MULTI_HINT:-<span size=\"x-small\">[Shift+Enter] Mark · [Enter] Confirm</span>}"

MENU_MULTI_BALLOT_ON="${MENU_MULTI_BALLOT_ON:-■}"
MENU_MULTI_BALLOT_OFF="${MENU_MULTI_BALLOT_OFF:-□}"

# Pixel costs from menutree.rasi.
MENU_CONTENT_INNER_CHROME_PX=89
MENU_WINDOW_BORDER_PX=2
MENU_VERTICAL_CHROME_PX=117
MENU_ROW_CHROME_PX=25
MENU_FOOTER_CHROME_PX=24
MENU_FALLBACK_WIDTH=295px
MENU_FALLBACK_RADIUS_PX=2
MENU_MAX_WIDTH_PERCENT=60
MENU_MAX_HEIGHT_PERCENT=80
MENU_DETAIL_LINES_PER_ROW=2
MENU_SEARCH_PATH_COLLAPSE_DEPTH=4

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
declare -gA HYPR_MENU_CHOICES=()
declare -gA HYPR_MENU_LABELS=()
declare -gA HYPR_MENU_PARENTS=()
declare -gA HYPR_MENU_GLYPHS=()
declare -gA HYPR_MENU_KINDS=()
declare -gA HYPR_MENU_TARGETS=()
declare -gA HYPR_MENU_SEARCHABLE=()
declare -gA HYPR_MENU_DEPTHS=()
declare -ga HYPR_MENU_ACTION_HANDLERS=()
declare -ga HYPR_MENU_ACTIVE_CHECKS=()
declare -gA HYPR_MENU_MARKED=()
declare -gA MENU_STATE_CACHE=()
MENU_ROOT_GLYPH=""
MENU_PROMPT_GLYPH=""

declare -gA MENU_STYLE=([font_scale]="" [font_name]="" [width_theme]="" [radius_px]="" [window_theme]="")

menu_define() {
  local menu_id="$1"
  local prompt="$2"
  local kind="${3:-}"

  [[ -n "${menu_id}" && "${menu_id}" != *"${MENU_ITEM_KEY_SEP}"* ]] || return 2
  HYPR_MENU_PROMPTS["${menu_id}"]="${prompt}"
  [[ "${kind}" == choice ]] && HYPR_MENU_CHOICES["${menu_id}"]=1
  : "${HYPR_MENU_LABELS["${menu_id}"]:=}"
}

menu_add_item() {
  local menu_id="$1" label="${2//$'\t'/ }" kind="$3" target="$4" searchable="${5:-1}"
  local key="${menu_id}${MENU_ITEM_KEY_SEP}${label}"

  [[ -n "${menu_id}" && -n "${label}" && -n "${target}" && "${menu_id}${label}" != *"${MENU_ITEM_KEY_SEP}"* &&
    "${label}" != *$'\n'* && ! -v HYPR_MENU_KINDS["${key}"] ]] || return 2
  case "${kind}:${searchable}" in action:0 | action:1 | submenu:0 | submenu:1) ;; *) return 2 ;; esac
  HYPR_MENU_LABELS["${menu_id}"]+="${HYPR_MENU_LABELS["${menu_id}"]:+$'\n'}${label}"
  HYPR_MENU_KINDS["${key}"]="${kind}"
  HYPR_MENU_TARGETS["${key}"]="${target}"
  HYPR_MENU_SEARCHABLE["${key}"]="${searchable}"
  if [[ ! -v HYPR_MENU_GLYPHS["${target}"] && "${label}" =~ ^([^\ -~]+)[[:space:]] ]]; then
    HYPR_MENU_GLYPHS["${target}"]="${BASH_REMATCH[1]}"
  fi

  if [[ "${kind}" == "submenu" && -z "${HYPR_MENU_PARENTS["${target}"]:-}" ]]; then
    HYPR_MENU_PARENTS["${target}"]="${menu_id}"
  fi
}

menu_register_action_handler() {
  HYPR_MENU_ACTION_HANDLERS+=("$1")
}

menu_register_active_check() {
  HYPR_MENU_ACTIVE_CHECKS+=("$1")
}

menu_mark_active() {
  HYPR_MENU_MARKED["$1"]=1
}

menu_item_active() {
  local check=""

  [[ -v HYPR_MENU_MARKED["$1"] ]] && return 0
  for check in "${HYPR_MENU_ACTIVE_CHECKS[@]}"; do
    "${check}" "$1" && return 0
  done
  return 1
}

menu_cached_state_reply() {
  local key="$1"

  shift
  [[ -v MENU_STATE_CACHE["${key}"] ]] || MENU_STATE_CACHE["${key}"]="$("$@" 2>/dev/null)"
  REPLY="${MENU_STATE_CACHE["${key}"]}"
}

menu_choice_matches() {
  local target="$1" prefix="$2"

  shift 2
  menu_cached_state_reply "${prefix}" "$@"
  [[ "${target#"${prefix}"}" == "${REPLY}" ]]
}

menu_escape_markup_reply() {
  REPLY="${1//&/\&amp;}"
  REPLY="${REPLY//</\&lt;}"
  REPLY="${REPLY//>/\&gt;}"
}

menu_json_value_reply() {
  local pattern="\"$2\"[[:space:]]*:[[:space:]]*\"?([^\",}[:space:]]+)"

  menu_cached_state_reply "$1" cat "$1"
  [[ "${REPLY}" =~ ${pattern} ]] && REPLY="${BASH_REMATCH[1]}" || REPLY="$3"
}

menu_json_flag_is_true() {
  menu_json_value_reply "$@"
  [[ "${REPLY}" == true ]]
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
  done <<<"${HYPR_MENU_LABELS["${menu_id}"]:-}"
  HYPR_MENU_DEPTHS["${menu_id}"]="${depth}"
}

menu_submenu_glyph() {
  case "$1" in
    1) printf '%s' "${MENU_SUBMENU_GLYPH_1}" ;;
    2) printf '%s' "${MENU_SUBMENU_GLYPH_2}" ;;
    *) printf '%s' "${MENU_SUBMENU_GLYPH_3}" ;;
  esac
}

menu_lookup_selection() {
  local menu_id="$1" selection="$2" out_kind_name="$3" out_target_name="$4" key="" glyph=""

  for glyph in "${MENU_SUBMENU_GLYPH_1}" "${MENU_SUBMENU_GLYPH_2}" "${MENU_SUBMENU_GLYPH_3}" "${MENU_CHECK_GLYPH}"; do
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

MENU_ACTION_UNKNOWN=254

menu_run_action() {
  local action_id="$1"
  local handler=""
  local status=0

  MENU_PROMPT_GLYPH="${HYPR_MENU_GLYPHS["${action_id}"]:-}"
  for handler in "${HYPR_MENU_ACTION_HANDLERS[@]}"; do
    status=0
    "${handler}" "${action_id}" || status=$?
    ((status == MENU_ACTION_UNKNOWN)) || return "${status}"
  done

  return "${MENU_ACTION_UNKNOWN}"
}

menu_dump_json() {
  local menu_id="" label="" key="" target="" chevron="" checked=""

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
      checked=0
      [[ -v HYPR_MENU_MARKED["${target}"] ]] && checked=1
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${menu_id}" "${HYPR_MENU_PROMPTS["${menu_id}"]}" "${HYPR_MENU_PARENTS["${menu_id}"]:-}" \
        "${label}" "${HYPR_MENU_KINDS["${key}"]}" "${target}" \
        "${HYPR_MENU_SEARCHABLE["${key}"]}" "${chevron}" "${checked}"
    done <<<"${HYPR_MENU_LABELS["${menu_id}"]:-}"
  done | jq -Rs '
    split("\n") | map(select(length > 0) | split("\t"))
    | reduce .[] as $r ({}; .[$r[0]] = ((.[$r[0]] // {prompt: $r[1], parent: $r[2], items: []})
        | .items += [{label: $r[3], kind: $r[4], target: $r[5], searchable: ($r[6] != "0"), chevron: $r[7], checked: ($r[8] == "1")}]))'
}

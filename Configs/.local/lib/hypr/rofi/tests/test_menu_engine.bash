#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/menu.engine.bash"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "$3: expected [$1], got [$2]"; }
assert_has() { [[ "$1" == *"$2"* ]] || fail "$3: missing [$2]"; }

menu_define main Root
menu_define branch Branch
menu_define deep Deep
menu_add_item main Plain action plain
menu_add_item main Sub submenu branch
menu_add_item main Hidden action hidden 0
menu_add_item branch 'A&B <One>' action special
menu_add_item branch Deep submenu deep
menu_add_item deep Leaf action leaf

rofi_font_align_trailing() {
  local default_glyph="$3" flag="" label="" glyph=""
  while IFS=$'\t' read -r flag label glyph; do
    [[ "${flag}" == 1 ]] && printf '%s   %s\n' "${label}" "${glyph:-${default_glyph}}" || printf '%s\n' "${label}"
  done
}
options=""
menu_render_options main options
assert_eq $'Plain\nSub   󰄾\nHidden' "${options}" 'rendered menu'

kind="" target=""
menu_lookup_selection main 'Sub 󰄾' kind target
assert_eq submenu "${kind}" 'submenu kind'
assert_eq branch "${target}" 'submenu target'
[[ "${HYPR_MENU_PARENTS[branch]}" == main ]] || fail 'submenu parent'
menu_descendant_depth branch
assert_eq 2 "${HYPR_MENU_DEPTHS[branch]}" 'submenu descendant depth'
assert_eq '󰅂' "$(menu_submenu_glyph 1)" 'one-level submenu glyph'
assert_eq '󰄾' "$(menu_submenu_glyph 2)" 'two-level submenu glyph'
assert_eq '󰶻' "$(menu_submenu_glyph 3)" 'three-level submenu glyph'
menu_add_item main Plain action duplicate 2>/dev/null && fail 'duplicate label accepted'
menu_add_item main Bad invalid bad 2>/dev/null && fail 'invalid item accepted'

declare -a direct_rows=() deeper_rows=() direct_item_keys=() deeper_item_keys=()
menu_collect_search_rows main direct_rows deeper_rows direct_item_keys deeper_item_keys Root 0
assert_eq 2 "${#direct_rows[@]}" 'direct row count'
assert_eq 3 "${#deeper_rows[@]}" 'deeper row count'
assert_eq "main${MENU_ITEM_KEY_SEP}Sub" "${direct_item_keys[1]}" 'direct item key'
assert_eq "branch${MENU_ITEM_KEY_SEP}A&B <One>" "${deeper_item_keys[0]}" 'deeper item key'
assert_has "${direct_rows[0]}" $'display\x1fPlain\n<span size="small" alpha="55%">Root</span>' 'direct row'
assert_has "${deeper_rows[0]}" 'A&amp;B &lt;One&gt;' 'escaped label'
assert_has "${deeper_rows[0]}" '>Sub</span>' 'deeper path'

search_ifs="$(
  menu_metrics_cache_init() { :; }
  menu() { printf '%s' "${#IFS}" >&2; return 1; }
  menu_show_search main 2>&1
)"
assert_eq 3 "${search_ifs}" 'search preserves default field separators'

measured=""
menu_measured_rows measured "${direct_rows[0]}${MENU_ROW_SEP}${deeper_rows[0]}" '' detail
assert_eq $'Plain\nA&B <One>\n' "${measured}" 'detail measurement rows'
menu_measured_rows measured "Plain${MENU_ROW_SEP}" '' detail
assert_eq $'Plain\n' "${measured}" 'detail trailing separator'
menu_measured_rows measured '' '' detail
assert_eq '' "${measured}" 'empty detail rows'
menu_measured_rows measured $'One\nTwo' multi ''
assert_eq $'■ One\n■ Two' "${measured}" 'multi measurement rows'
selected=""
menu_preselect_row selected $'One\nTwo' Two
assert_eq 1 "${selected}" 'preselected row'

bytes="$(menu_emit_options "x${MENU_ROW_OPT}y" detail | od -An -t x1 | tr -d ' \n')"
assert_eq 780079 "${bytes}" 'Rofi NUL option marker'

json="$(menu_dump_json)"
assert_eq special "$(jq -r '.branch.items[0].target' <<<"${json}")" 'JSON target'
assert_eq false "$(jq -r '.main.items[] | select(.label == "Hidden") | .searchable' <<<"${json}")" 'JSON search flag'
assert_eq '󰄾' "$(jq -r '.main.items[] | select(.target == "branch") | .chevron' <<<"${json}")" 'JSON submenu chevron'

ACTION=""
handler_miss() { return 1; }
handler_hit() { [[ "$1" == run ]] && ACTION="$1"; }
menu_register_action_handler handler_miss
menu_register_action_handler handler_hit
menu_run_action run
assert_eq run "${ACTION}" 'action handler'
ACTION=""
menu_add_item main Run action run
menu_dispatch_search_item "main${MENU_ITEM_KEY_SEP}Run"
assert_eq run "${ACTION}" 'search action handler'
menu_run_action missing && fail 'unknown action accepted'

declare -a CAPTURED=()
hyprshell() { CAPTURED=("$@"); }
present_terminal --hypr-profile dialog --hypr-cells 80 20 --app-id app --title Title -- cmd 'two words'
assert_eq 'launch/terminal-present.sh|--hypr-profile|dialog|--hypr-cells|80|20|--app-id|app|--title|Title|--|cmd|two words' "$(IFS='|'; printf '%s' "${CAPTURED[*]}")" 'terminal arguments'
present_terminal cmd
assert_eq 'launch/terminal-present.sh|--|cmd' "$(IFS='|'; printf '%s' "${CAPTURED[*]}")" 'plain terminal arguments'
present_terminal --app-id 2>/dev/null && fail 'missing terminal option accepted'
menu Prompt Rows --nav invalid >/dev/null 2>&1 && fail 'invalid navigation accepted'
menu Prompt Rows --select >/dev/null 2>&1 && fail 'missing menu option accepted'

rofi_effective_font_scale() { printf '10'; }
rofi_effective_font_name() { printf 'Mono'; }
rofi_theme_width_multiplier_override() { printf 'window { width: 295px; }'; }
rofi_default_border_radius() { printf '2'; }
rofi_standard_window_theme() { printf 'window{border:3px;}'; }
rofi_font_text_extents_px() { cat >/dev/null; printf '425 10'; }
rofi_focused_monitor_logical_size() { printf '1920 1080'; }
rofi_font_override() { printf 'font{}'; }
rofi_resolve_theme() { printf 'menutree.rasi'; }
rofi_with_background_theme() { cat >/dev/null; printf 'Picked'; return 7; }
set +e
rofi_output="$(menu_run_rofi Prompt Rows '')"
rofi_exit=$?
set -e
assert_eq Picked "${rofi_output}" 'Rofi output'
assert_eq 7 "${rofi_exit}" 'Rofi exit code'
declare -a MENU_RUN_ARGS=()
menu_run_rofi() { MENU_RUN_ARGS=("$@"); }
MENU_FONT_SCALE_CACHE="" MENU_FONT_NAME_CACHE="" MENU_WIDTH_OVERRIDE_CACHE=""
MENU_BORDER_RADIUS="" MENU_WINDOW_THEME_CACHE=""
menu_metrics_cache_init
assert_eq 220 "$(menu_text_column_px)" 'text column excludes the applied window border'
assert_has "$(menu_content_theme_override Rows 2)" 'width: 500px;' 'search width fits the widest label'
rofi_focused_monitor_logical_size() { printf '800 600'; }
assert_has "$(menu_content_theme_override Rows 2)" 'width: 480px;' 'search monitor cap'
rofi_focused_monitor_logical_size() { printf '1920 1080'; }
menu Prompt $'One\nTwo' --select Two --nav tree >/dev/null
run_args="$(IFS='|'; printf '|%s|' "${MENU_RUN_ARGS[*]}")"
assert_has "${run_args}" '|-selected-row|1|' 'menu preselection argument'
assert_has "${run_args}" '|-kb-custom-3|Tab|' 'menu navigation argument'

printf 'PASS: menu engine\n'

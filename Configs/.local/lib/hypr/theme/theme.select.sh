#!/usr/bin/env bash


# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state system rofi wallpaper_catalog || exit 1
hypr_runtime_load_desktop_environment || exit 1
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"
source "${HYPR_LIB_DIR}/wallpaper/lib/common.bash"
source "${HYPR_LIB_DIR}/theme/pairs.sh"

theme_select_notify() {
  local icon_path="$1"
  shift

  local -a args=(-a "Theme select" -t "${NOTIFY_BRIEF_MS}" -r "${NOTIFY_ID_THEME_SELECT}")
  [[ -n "${icon_path}" ]] && args+=(-i "${icon_path}")
  notify_send_safe "${args[@]}" "$@" || true
}

theme_selector_usage() {
  cat <<HELP
Usage: hyprshell theme/theme.select [--select-menu|-s]

  (no args)         Select a theme pack
  --select-menu|-s  Select this program's menu style
HELP
  exit 0
}

source "${HYPR_LIB_DIR}/theme/lib/selector.layout.bash" || exit 1

list_style_menu_entries() {
  rofi_list_asset_files 'theme_style_*' \
    | awk -F '[_.]' '{print $((NF - 1))}' \
    | while read -r style_num; do
      printf '%s\x00icon\x1f%s\n' "${style_num}" "$(rofi_resolve_asset "theme_style_${style_num}.png")"
    done | sort -n
}

show_style_selector() {
  local font_scale=""
  local font_name=""
  local font_override=""
  local layout_override=""
  local selection=""
  local style_icon=""

  local -A selector_monitor=()
  theme_selector_monitor_metrics_into selector_monitor
  font_scale="$(rofi_effective_font_scale "${ROFI_THEME_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_THEME_MENU_FONT:-$ROFI_FONT}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  layout_override="$(theme_style_picker_layout "${font_scale}" selector_monitor)"

  selection="$(
    list_style_menu_entries | rofi_with_background_theme -dmenu -i \
      "${ROFI_MOUSE_SELECT_ARGS[@]}" \
      -theme "$(rofi_resolve_theme "${ROFI_THEME_MENU_STYLE:-theme_select}")" \
      -theme-str "${font_override}" \
      -theme-str "${layout_override}" \
      -select "${ROFI_THEME_STYLE}"
  )"

  [[ -n "${selection}" ]] || exit 0

  state_set "ROFI_THEME_STYLE" "${selection}" "staterc"
  style_icon="$(rofi_resolve_asset "theme_style_${selection}.png")"
  [[ -f "${style_icon}" ]] || style_icon="preferences-desktop-theme"
  theme_select_notify "${style_icon}" "Style ${selection} applied..."
  exit 0
}

enqueue_missing_theme_thumbnails() {
  local ext="$1"
  local -n wallpapers_ref="$2" wallpaper_hashes_ref="$3"
  local -a missing_walls=()
  local wall=""
  local hash=""
  local thumb=""
  local queue_script="${HYPR_LIB_DIR}/wallpaper/wallcache.daemon.sh"

  for wall in "${wallpapers_ref[@]}"; do
    [[ -n "${wall}" && -r "${wall}" ]] || continue
    hash="${wallpaper_hashes_ref[${wall}]:-}"
    [[ -n "${hash}" ]] || continue
    thumb="${WALLPAPER_THUMB_DIR}/${hash}.${ext}"
    [[ -e "${thumb}" ]] || missing_walls+=("${wall}")
  done

  ((${#missing_walls[@]} > 0)) || return 0

  local -a cache_args=()
  for wall in "${missing_walls[@]}"; do
    cache_args+=(-w "${wall}")
  done

  if [[ -x "${queue_script}" ]]; then
    "${queue_script}" --enqueue "${cache_args[@]}" &>/dev/null &
  else
    "${HYPR_LIB_DIR}/wallpaper/wallpaper.cache.sh" "${cache_args[@]}" &>/dev/null &
  fi
}

# One find over every theme dir; %H names the theme each match belongs to.
theme_wallpaper_counts_into() {
  local -n counts_ref="$1" names_ref="$2"
  local -a exts=() match=()
  local ext start

  ((${#names_ref[@]})) || return 0
  wallpaper_supported_extensions_into exts
  for ext in "${exts[@]}"; do
    match+=(-o -iname "*.${ext}")
  done

  while IFS= read -r start; do
    counts_ref["${start##*/}"]=$((${counts_ref["${start##*/}"]:-0} + 1))
  done < <(find -H "${names_ref[@]/#/${HYPR_CONFIG_HOME}/themes/}" -type f \( "${match[@]:1}" \) ! -path '*/logo/*' -printf '%H\n' 2>/dev/null)
}

theme_menu_entries() {
  local ext="$1"
  local -n names_ref="$2" wallpapers_ref="$3" wallpaper_hashes_ref="$4"
  local -A polarity=() wall_count=()
  local i=0 name subtitle count
  local show_count="${ROFI_THEME_WALLPAPER_COUNT:-0}"

  theme_polarities_into polarity "${names_ref[@]}"
  [[ "${show_count}" == "1" ]] && theme_wallpaper_counts_into wall_count "${!names_ref}"

  while ((i < ${#names_ref[@]})); do
    name="${names_ref[$i]}"
    subtitle="${polarity[${name}]^}"
    if [[ "${show_count}" == "1" ]]; then
      count="${wall_count[${name}]:-0}"
      subtitle+="&#10;${count} wallpaper"
      ((count == 1)) || subtitle+="s"
    fi
    printf '%s\x00display\x1f%s&#10;<span size="small" alpha="70%%">%s</span>\x1ficon\x1f%s/%s.%s\n' \
      "${name}" \
      "${name//&/\&amp;}" \
      "${subtitle}" \
      "${WALLPAPER_THUMB_DIR}" \
      "${wallpaper_hashes_ref[${wallpapers_ref[$i]}]:-}" \
      "${ext}"
    i=$((i + 1))
  done
}

show_theme_selector() {
  local font_scale=""
  local font_name=""
  local font_override=""
  local thumbnail_extension=""
  local rofi_theme_name=""
  local layout_override=""
  local selection=""
  local -a theme_names=() theme_wallpapers=()

  local -A selector_monitor=()
  theme_selector_monitor_metrics_into selector_monitor
  font_scale="$(rofi_effective_font_scale "${ROFI_THEME_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_THEME_FONT:-$ROFI_FONT}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  theme_pack_picker_layout_into thumbnail_extension rofi_theme_name layout_override "${font_scale}" selector_monitor

  theme_catalog_load_and_repair_links_into theme_names theme_wallpapers
  local -A wallpaper_hashes=()
  wallpaper_cached_file_hashes_into wallpaper_hashes "${theme_wallpapers[@]}"
  enqueue_missing_theme_thumbnails "${thumbnail_extension}" theme_wallpapers wallpaper_hashes

  selection="$(
    theme_menu_entries "${thumbnail_extension}" theme_names theme_wallpapers wallpaper_hashes | rofi_with_background_theme -dmenu -i -markup-rows \
      "${ROFI_MOUSE_SELECT_ARGS[@]}" \
      -theme "$(rofi_resolve_theme "${rofi_theme_name}")" \
      -theme-str "${font_override}" \
      -theme-str "${layout_override}" \
      -select "${HYPR_THEME}"
  )"

  [[ -n "${selection}" ]] || exit 0
  "${HYPR_LIB_DIR}/theme/theme.switch.sh" -s "${selection}"
}

case "${1:-}" in
  -m | -s | --select-menu)
    show_style_selector
    ;;
  -*)
    theme_selector_usage
    ;;
  *)
    show_theme_selector
    ;;
esac

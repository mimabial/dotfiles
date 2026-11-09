#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require rofi || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash" || exit 1

backend="all"
style="${ROFI_GAMELAUNCHER_STYLE:-steam_deck}"
font_scale_request="${ROFI_GAMELAUNCHER_SCALE:-}"
font_name_request="${ROFI_GAMELAUNCHER_FONT:-${ROFI_FONT:-}}"
emit_json=0
game_catalog_script="${HYPR_LIB_DIR}/gaming/lib/game_catalog.py"
gamepad_keys_script="${HYPR_LIB_DIR}/gaming/lib/gamepad_keys.py"
steam_deck_layout_into() {
  local -n cover_args_ref="$1" theme_ref="$2"
  local requested_font_name="$3" requested_font_scale="$4" control_padding_y="$5" control_padding_x="$6"
  local columns=6 rows=2 content_gaps=4 line_steps=4
  local font_name font_scale font_description width height radius border_width
  local font_height unit inset card_gap tabs_height hints_height chrome_height tile_width cover_width cover_height cover_radius grid_width

  font_name="$(rofi_effective_font_name "${requested_font_name}")"
  font_scale="$(rofi_effective_font_scale "${requested_font_scale}")"
  font_description="$(rofi_font_description "${font_name}" "${font_scale}")"
  read -r width height < <(rofi_focused_monitor_logical_size)
  IFS=$'\t' read -r radius border_width < <(rofi_default_border_metrics)
  radius=$((radius * ROFI_IMAGE_TILE_RADIUS_MULTIPLIER))
  font_height="$(rofi_font_text_height_px "${font_name}" "${font_scale}")" || return
  font_height=$((($(rofi_decimal_milli "${font_height}") + ROFI_MILLI - 1) / ROFI_MILLI))
  unit=$(((font_height + line_steps - 1) / line_steps))
  inset=$((2 * unit))
  card_gap=$((2 * unit))
  tabs_height=$((font_height + 2 * control_padding_y))
  hints_height=${font_height}
  chrome_height=$((tabs_height + hints_height + 2 * inset + content_gaps * unit))
  tile_width=$(((width - 2 * inset - (columns - 1) * card_gap) / columns))
  cover_width=$((tile_width - 2 * border_width))
  cover_height=$(((height - chrome_height - (rows - 1) * card_gap) / rows - 2 * border_width))
  cover_radius=$((radius > border_width ? radius - border_width : 0))
  grid_width=$((columns * tile_width + (columns - 1) * card_gap))
  cover_args_ref="--cover-size ${cover_width}x${cover_height} --cover-radius ${cover_radius} --title-font \"${font_description}\" --title-padding ${control_padding_x}x${control_padding_y} --title-margin ${inset} --title-radius ${radius}"

  printf -v theme_ref '* {font: "%s";\n element-border-radius: %spx; deck-gap: %spx; deck-card-gap: %spx; deck-inset: %spx; deck-border: %spx; deck-cover-height: %spx; deck-grid-width: %spx; deck-columns: %s; deck-rows: %s;}\n' \
    "${font_description}" "${radius}" "${unit}" "${card_gap}" "${inset}" \
    "${border_width}" "${cover_height}" "${grid_width}" "${columns}" "${rows}"
}

usage() {
  printf 'Usage: hyprshell gaming/launcher [--backend all|steam|lutris] [--style THEME] [--json]\n\nPick a game from the Steam and Lutris libraries in rofi and launch it.\n'
}

while (($# > 0)); do
  case "$1" in
    --backend | -b)
      backend="${2:-}"
      shift 2
      ;;
    --style | -s)
      style="${2:-}"
      shift 2
      ;;
    --json)
      emit_json=1
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

case "${backend}" in
  all | steam | lutris) ;;
  *)
    printf 'invalid backend: %s\n' "${backend}" >&2
    exit 2
    ;;
esac

if ((emit_json)); then
  exec python3 "${game_catalog_script}" --backend "${backend}" --json
fi

case "${style}" in
  steam_deck | gamelauncher_5 | 5)
    rofi_hypr_snapshot
    monitor_args=()
    rofi_monitor_args_into monitor_args
    popup_theme="$(rofi_popup_theme)"
    [[ "${popup_theme}" =~ control-padding:\ ([0-9]+)px\ ([0-9]+)px ]]
    steam_deck_layout_into deck_cover_args deck_theme "${font_name_request}" "${font_scale_request}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    library_modes=""
    for library_backend in all steam lutris; do
      library_modes+="${library_modes:+,}${library_backend}:python3 \"${game_catalog_script}\" --backend ${library_backend} --rofi ${deck_cover_args}"
    done
    python3 "${gamepad_keys_script}" "$$" &
    exec rofi "${monitor_args[@]}" -show "${backend}" -modes "${library_modes}" \
      -theme "$(rofi_resolve_theme steam_deck)" \
      -theme-str "${deck_theme}" \
      -theme-str "${popup_theme}"
    ;;
esac

declare -A launcher_style=()
rofi_resolve_style_into launcher_style "${font_scale_request}" "${font_name_request}" listview same

selection="$(
  python3 "${game_catalog_script}" --backend "${backend}" --rofi \
    | rofi_with_background_theme -dmenu -i -markup-rows \
      -no-custom \
      -p Games \
      -display-columns 1 \
      -display-column-separator $'\t' \
      -config "$(rofi_resolve_theme "${style}")" \
      -theme-str "${launcher_style[font_theme]}" \
      -theme-str "${launcher_style[window_theme]}" \
      -theme-str "$(rofi_window_position_theme)"
)"

[[ -n "${selection}" ]] || exit 0
selected_game_key="${selection#*$'\t'}"
[[ -n "${selected_game_key}" ]] || exit 0

exec python3 "${game_catalog_script}" --backend "${backend}" --launch "${selected_game_key}"

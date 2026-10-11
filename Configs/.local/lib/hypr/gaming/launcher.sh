#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require rofi || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash" || exit 1

backend="all"
style="${ROFI_GAMELAUNCHER_STYLE:-steam_deck}"
emit_json=0
game_catalog_script="${HYPR_LIB_DIR}/gaming/lib/game_catalog.py"
FALLBACK_MONITOR_WIDTH=1920
FALLBACK_MONITOR_HEIGHT=1080
LAUNCHER_SCREEN_PERCENT=80
STEAMDECK_SCREEN_INSET_VERTICAL_PERCENT=17
STEAMDECK_SCREEN_INSET_HORIZONTAL_PERCENT=18

steam_deck_theme_override() {
  local source_image="${HOME}/.local/share/rofi/assets/steamdeck_holographic.png"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/rofi"
  local logical_width logical_height launcher_width launcher_height cache_image
  local background_rule=""

  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"
  [[ "${logical_width}" =~ ^[1-9][0-9]*$ ]] || logical_width="${FALLBACK_MONITOR_WIDTH}"
  [[ "${logical_height}" =~ ^[1-9][0-9]*$ ]] || logical_height="${FALLBACK_MONITOR_HEIGHT}"
  launcher_width=$((logical_width * LAUNCHER_SCREEN_PERCENT / 100))
  launcher_height=$((logical_height * LAUNCHER_SCREEN_PERCENT / 100))

  if [[ -f "${source_image}" ]] && command -v magick >/dev/null 2>&1; then
    mkdir -p "${cache_dir}"
    cache_image="${cache_dir}/steamdeck_holographic_${launcher_width}x${launcher_height}.png"
    if [[ ! -f "${cache_image}" || "${source_image}" -nt "${cache_image}" ]]; then
      magick "${source_image}" \
        -resize "${launcher_width}x${launcher_height}" \
        -background none \
        -gravity center \
        -extent "${launcher_width}x${launcher_height}" \
        "${cache_image}" >/dev/null 2>&1 || cache_image=""
    fi
    [[ -f "${cache_image}" ]] && background_rule="background-image: url(\"${cache_image}\", width);"
  fi

  printf 'window {width: %spx; height: %spx; %s} mainbox {padding: %s%% %s%%;} element-icon {border-radius: 0px;}\n' \
    "${launcher_width}" "${launcher_height}" "${background_rule}" \
    "${STEAMDECK_SCREEN_INSET_VERTICAL_PERCENT}" "${STEAMDECK_SCREEN_INSET_HORIZONTAL_PERCENT}"
}

usage() {
  printf 'Usage: hyprshell gaming/launcher [--backend all|steam|lutris] [--style THEME] [--json]\n'
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

declare -A launcher_style=()
rofi_resolve_style_into launcher_style \
  "${ROFI_GAMELAUNCHER_SCALE:-}" "${ROFI_GAMELAUNCHER_FONT:-${ROFI_FONT:-}}" listview same

launcher_style_override=""
launcher_rofi_args=()
case "${style}" in
  steam_deck | gamelauncher_5 | 5)
    launcher_style_override="$(steam_deck_theme_override)"
    launcher_rofi_args=(-show-icons)
    ;;
esac

selection="$(
  python3 "${game_catalog_script}" --backend "${backend}" --rofi \
    | rofi_with_background_theme -dmenu -i -markup-rows \
      "${launcher_rofi_args[@]}" \
      -p Games \
      -display-columns 1 \
      -display-column-separator $'\t' \
      -config "$(rofi_resolve_theme "${style}")" \
      -theme-str "${launcher_style[font_theme]}" \
      -theme-str "${launcher_style[window_theme]}" \
      ${launcher_style_override:+-theme-str "${launcher_style_override}"}
)"

[[ -n "${selection}" ]] || exit 0
selected_game_key="${selection#*$'\t'}"
[[ -n "${selected_game_key}" ]] || exit 0

exec python3 "${game_catalog_script}" --backend "${backend}" --launch "${selected_game_key}"

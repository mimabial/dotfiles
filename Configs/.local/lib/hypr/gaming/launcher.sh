#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash" || exit 1

backend="all"
style="${ROFI_GAMELAUNCHER_STYLE:-steam_deck}"
json=0
catalog="${LIB_DIR}/hypr/gaming/lib/game_catalog.py"

steam_deck_theme_override() {
  local source_image="${HOME}/.local/share/rofi/assets/steamdeck_holographic.png"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/rofi"
  local logical_width logical_height launcher_width launcher_height cache_image
  local background_rule=""

  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"
  [[ "${logical_width}" =~ ^[0-9]+$ ]] || logical_width=1920
  [[ "${logical_height}" =~ ^[0-9]+$ ]] || logical_height=1080
  launcher_width=$((logical_width * 80 / 100))
  launcher_height=$((logical_height * 80 / 100))
  ((launcher_width > 0)) || launcher_width=1200
  ((launcher_height > 0)) || launcher_height=720

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

  printf 'window {width: %spx; height: %spx; %s} mainbox {padding: 17%% 18%%;} element-icon {border-radius: 0px;}\n' \
    "${launcher_width}" "${launcher_height}" "${background_rule}"
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
      json=1
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

if ((json)); then
  exec python3 "${catalog}" --backend "${backend}" --json
fi

rofi_prepare_standard_context \
  font_scale font_name launcher_font_override window_override launcher_opacity_override \
  "${ROFI_GAMELAUNCHER_SCALE:-}" "${ROFI_GAMELAUNCHER_FONT:-${ROFI_FONT:-}}" listview same

launcher_style_override=""
launcher_rofi_args=()
case "${style}" in
  steam_deck | gamelauncher_5 | 5)
    launcher_style_override="$(steam_deck_theme_override)"
    launcher_rofi_args=(-show-icons)
    launcher_opacity_override=""
    ;;
esac

selection="$(
  python3 "${catalog}" --backend "${backend}" --rofi \
    | rofi -dmenu -i -markup-rows \
      "${launcher_rofi_args[@]}" \
      -p Games \
      -display-columns 1 \
      -display-column-separator $'\t' \
      -config "$(rofi_resolve_theme "${style}")" \
      -theme-str "${launcher_font_override}" \
      -theme-str "${window_override}" \
      ${launcher_style_override:+-theme-str "${launcher_style_override}"} \
      ${launcher_opacity_override:+-theme-str "${launcher_opacity_override}"}
)"

[[ -n "${selection}" ]] || exit 0
key="${selection#*$'\t'}"
[[ -n "${key}" ]] || exit 0

exec python3 "${catalog}" --backend "${backend}" --launch "${key}"

#!/usr/bin/env bash

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

show_help() {
  cat <<HELP
Usage: $(basename "$0") [--backend steam|lutris|catalog] [--style STYLE]

Options:
  -b, --backend   Choose a game source backend
  -s, --style     Choose a gamelauncher rofi style (1-5, gamelauncher_1-5, steam_deck)
  -h, --help      Show this help
HELP
}

resolve_gamelauncher_theme() {
  local style_ref="${1:-}"
  local normalized_style=""

  normalized_style="$(rofi_normalize_gamelauncher_style "${style_ref}")"
  rofi_resolve_theme "${normalized_style}"
}

backend="catalog"
style_ref="${ROFI_GAMELAUNCHER_STYLE:-gamelauncher_5}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--backend)
      backend="$2"
      shift 2
      ;;
    -s|--style)
      style_ref="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    [0-9])
      style_ref="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

rofi_config="$(resolve_gamelauncher_theme "${style_ref}")"
font_scale="$(rofi_effective_font_scale "${ROFI_GAMELAUNCHER_SCALE:-${ROFI_LAUNCH_SCALE:-}}")"
font_name="$(rofi_effective_font_name "${ROFI_GAMELAUNCHER_FONT:-${ROFI_LAUNCH_FONT:-$ROFI_FONT}}")"
font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
i_override="$(rofi_icon_theme_override)"

hypr_border="$(rofi_default_border_radius 10)"
elem_border=$((hypr_border * 2))
icon_border=$((elem_border - 3))
[[ "${icon_border}" -lt 0 ]] && icon_border=0
r_override="element{border-radius:${elem_border}px;} element-icon{border-radius:${icon_border}px;}"

normalized_style="$(rofi_normalize_gamelauncher_style "${style_ref}")"
case "${normalized_style}" in
  gamelauncher_5)
    read -r mon_width mon_height < <(rofi_focused_monitor_logical_size)
    mon_width=${mon_width:-1920}
    mon_height=${mon_height:-1080}
    bg_asset="$(rofi_resolve_asset steamdeck_holographic.png)"
    bg_cache="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}/landing/steamdeck_holographic_${mon_width}x${mon_height}.png"
    mkdir -p "$(dirname "${bg_cache}")"
    if [[ -f "${bg_asset}" ]] && [[ ! -f "${bg_cache}" ]]; then
      magick "${bg_asset}" -resize ${mon_width}x${mon_height} -background none -gravity center -extent ${mon_width}x${mon_height} "${bg_cache}" 2>/dev/null || true
    fi
    if [[ -f "${bg_cache}" ]]; then
      r_override="window {width: ${mon_width}px; height: ${mon_height}px; background-image: url('${bg_cache}',width);} element-icon {border-radius:0px;} mainbox {padding: 17% 18%;}"
    fi
    ;;
esac

case "${backend}" in
  steam)
    backend_command=(python3 "${LIB_DIR}/hypr/gaming/gamelauncher/steam.py" --rofi-string)
    ;;
  lutris)
    backend_command=(python3 "${LIB_DIR}/hypr/gaming/gamelauncher/lutris.py" --rofi-string)
    ;;
  catalog|"" )
    backend="catalog"
    backend_command=(python3 "${LIB_DIR}/hypr/gaming/gamelauncher/catalog.py" --rofi-string)
    ;;
  *)
    echo "Unknown backend: ${backend}" >&2
    exit 1
    ;;
esac

rofi_args=(
  -dmenu -i -p Catalog
  -theme "${rofi_config}"
  -theme-str "${font_override}"
  -theme-str "${i_override}"
  -theme-str "${r_override}"
)
if [[ "${backend}" == "catalog" ]]; then
  rofi_args+=(-markup-rows)
fi

catalog_file="$(mktemp)"
trap 'rm -f "${catalog_file}"' EXIT
"${backend_command[@]}" >"${catalog_file}"

if [[ ! -s "${catalog_file}" ]]; then
  send_ephemeral_notif "hypr-gamelauncher-empty" -a "Game Launcher" -t 2500 "No games found" "Backend: ${backend}"
  exit 0
fi

selected_row="$(rofi "${rofi_args[@]}" <"${catalog_file}")"

if [[ -z "${selected_row}" ]]; then
  exit 0
fi

IFS=$'\t' read -r _ launch_command _ <<<"${selected_row}"
[[ -z "${launch_command}" ]] && exit 0
exec sh -lc "${launch_command}"

#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash" || exit 1

backend="all"
style="${ROFI_GAMELAUNCHER_STYLE:-clipboard}"
json=0
catalog="${LIB_DIR}/hypr/gaming/lib/game_catalog.py"

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
  font_scale font_name font_override window_override opacity_override \
  "${ROFI_GAMELAUNCHER_SCALE:-}" "${ROFI_GAMELAUNCHER_FONT:-${ROFI_FONT:-}}" listview same

selection="$(
  python3 "${catalog}" --backend "${backend}" --rofi \
    | rofi -dmenu -i -markup-rows \
      -p Games \
      -display-columns 1 \
      -display-column-separator $'\t' \
      -config "$(rofi_resolve_theme "${style}")" \
      -theme-str "${font_override}" \
      -theme-str "${window_override}" \
      ${opacity_override:+-theme-str "${opacity_override}"}
)"

[[ -n "${selection}" ]] || exit 0
key="${selection#*$'\t'}"
key="${key%%$'\0'*}"
[[ -n "${key}" ]] || exit 0

exec python3 "${catalog}" --backend "${backend}" --launch "${key}"

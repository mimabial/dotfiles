#!/usr/bin/env bash
# One knob for apparent text size across the desktop, modelled on
# omarchy-display-text-size. Drives three settings in lockstep, all anchored to
# a 12px base:
#   • the bar's text scale        (TEXT_SIZE in staterc; quickshell watches it)
#   • GNOME/GTK text-scaling-factor (12px -> 1.0, quantized so the interface
#     font lands on a whole point size, so 16 -> 15pt/11pt = 1.3636)
#   • terminal font point size    (12px -> 9pt, so pt = px * 9/12)
#   • Qt font DPI                 (12px -> 96, written to uwsm/env.d, which both
#     uwsm and hypr-session source; only new processes pick it up)
# rofi and dunst derive their own size from TEXT_SIZE off the same 12px anchor.
set -euo pipefail

readonly -a TEXT_SIZES=(9 10 11 12 13 14 15 16 17 18 19 20)
[[ "${1:-}" == "--list" ]] && { printf '%s\n' "${TEXT_SIZES[*]}"; exit; }

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/text-size [size|reset]
  (no args)   print the current text size, GTK factor, terminal size, and Qt DPI
  <size>      set text size in px (9-20); bar + GTK + terminals + Qt together
  --list      print available sizes
  reset       return all four to their defaults (12px / 1.0 / 9pt / 96)" "$@"

hypr_runtime_require state

readonly MIN="${TEXT_SIZES[0]}"
readonly MAX="${TEXT_SIZES[-1]}"
readonly BASE_PX=12
readonly TERM_BASE_PT=9
readonly QT_BASE_DPI=96
readonly QT_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env.d/50-text-size.sh"
readonly GKEY_SCHEMA="org.gnome.desktop.interface"
readonly GKEY_NAME="text-scaling-factor"

# Point size of the GTK interface font, used to quantize the scaling factor so
# the rendered font lands on a whole point. Falls back to the GNOME default.
gtk_font_pt() {
  local name pt
  name="$(gsettings get "${GKEY_SCHEMA}" font-name 2>/dev/null || true)"
  pt="${name%\'}"
  pt="${pt##* }"
  [[ ${pt} =~ ^[0-9]+([.][0-9]+)?$ ]] && printf '%s\n' "${pt}" || printf '11\n'
}

term_pt_for() {
  awk -v size="$1" -v pt="${TERM_BASE_PT}" -v base="${BASE_PX}" \
    'BEGIN { printf "%d", int(size * pt / base + 0.5) }'
}

factor_for() {
  awk -v size="$1" -v base="${BASE_PX}" -v font="$(gtk_font_pt)" \
    'BEGIN { printf "%.4f", int(font * size / base + 0.5) / font }'
}

# Qt apps ignore the GTK factor, and QT_FONT_DPI only reaches new sessions, so
# write the point sizes directly. Which file is read depends on the platform
# theme: qt6ct/qt5ct own the fonts when QT_QPA_PLATFORMTHEME points at them,
# kdeglobals when it does not — so keep both in step.
set_qt_fonts() {
  local size="$1" family="" mono=""
  command -v kwriteconfig6 >/dev/null 2>&1 || return 0
  family="$(hypr_config_value_from_layers FONT 2>/dev/null || true)"
  mono="$(hypr_config_value_from_layers MONOSPACE_FONT 2>/dev/null || true)"
  [[ -n "${family}" ]] || family="Cantarell"
  [[ -n "${mono}" ]] || mono="monospace"

  local ui=$((size * 10 / BASE_PX)) fixed=$((size * 9 / BASE_PX)) small=$((size * 8 / BASE_PX))
  local key=""
  for key in font menuFont toolBarFont; do
    kwriteconfig6 --file kdeglobals --group General --key "${key}" "${family},${ui},-1,5,400,0,0,0,0,0"
  done
  kwriteconfig6 --file kdeglobals --group General --key fixed "${mono},${fixed},-1,5,400,0,0,0,0,0"
  kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "${family},${small},-1,5,400,0,0,0,0,0"
  kwriteconfig6 --file kdeglobals --group WM --key activeFont "${family},${ui},-1,5,400,0,0,0,0,0"

  local tail="-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0" conf="" flavour=""
  for flavour in qt6ct qt5ct; do
    conf="${XDG_CONFIG_HOME:-$HOME/.config}/${flavour}/${flavour}.conf"
    [[ -f "${conf}" ]] || continue
    sed -i -E "s|^general=\".*\"|general=\"${family},${ui},${tail}\"|; s|^fixed=\".*\"|fixed=\"${mono},${fixed},${tail}\"|" "${conf}"
  done
}

# Family is left alone — that is fonts/font-set.sh's job.
set_terminal_size() {
  local pt="$1"

  if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf" ]]; then
    sed -i -E "s/^font_size[[:space:]]+.*/font_size ${pt}.0/" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
    pkill -USR1 -x kitty 2>/dev/null || true
  fi

  if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml" ]]; then
    sed -i -E "s/^size[[:space:]]*=.*/size = ${pt}/" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
  fi
}

current_size() {
  local size
  size="$(state_get TEXT_SIZE "" 2>/dev/null || true)"
  [[ ${size} =~ ^[0-9]+$ ]] && printf '%s\n' "${size}" || printf '%s\n' "${BASE_PX}"
}

report() {
  local size; size="$(current_size)"
  printf 'text size   %spx\n' "${size}"
  printf 'gtk factor  %s\n' "$(gsettings get "${GKEY_SCHEMA}" "${GKEY_NAME}" 2>/dev/null || echo '-')"
  printf 'terminal    %spt\n' "$(term_pt_for "${size}")"
  printf 'kde ui      %spt\n' "$((size * 10 / BASE_PX))"
  printf 'qt dpi      %s\n' "$((size * QT_BASE_DPI / BASE_PX))"
}

apply() {
  local size="$1"

  if [[ ! ${size} =~ ^[0-9]+$ ]] || ((size < MIN || size > MAX)); then
    echo "text-size: size must be an integer between ${MIN} and ${MAX}" >&2
    exit 1
  fi

  state_set TEXT_SIZE "${size}"
  gsettings set "${GKEY_SCHEMA}" "${GKEY_NAME}" "$(factor_for "${size}")" 2>/dev/null || true
  set_terminal_size "$(term_pt_for "${size}")"
  set_qt_fonts "${size}"
  mkdir -p "${QT_ENV_FILE%/*}" && printf '# generated by hyprshell system/text-size\nexport QT_FONT_DPI=%s\n' \
    "$((size * QT_BASE_DPI / BASE_PX))" >"${QT_ENV_FILE}"
  # rofi resolves its size per launch, but dunstrc is generated: re-render it
  hyprshell render/dunst.py >/dev/null 2>&1 || true
  print_log -sec "text-size" -stat "applied" "${size}px"
}

case "${1-}" in
  "") report ;;
  reset) apply "${BASE_PX}" ;;
  *) apply "$1" ;;
esac

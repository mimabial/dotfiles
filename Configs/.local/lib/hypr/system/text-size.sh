#!/usr/bin/env bash
# Keeps desktop text settings aligned to a 12px/10pt base. Terminal and Qt
# retain hundredths; Rofi and Dunst intentionally truncate in lockstep.
set -euo pipefail

readonly -a TEXT_SIZES=(9 10 11 12 13 14 15 16 17 18 19 20)
[[ "${1:-}" == "--list" ]] && { printf '%s\n' "${TEXT_SIZES[*]}"; exit; }

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/text-size [size|reset]
  (no args)   print current desktop text sizes
  <size>      set text size in px (9-20) across the desktop
  --list      print available sizes
  reset       restore 12px / 1.0 / 10pt defaults" "$@"

hypr_runtime_require state

readonly MIN="${TEXT_SIZES[0]}"
readonly MAX="${TEXT_SIZES[-1]}"
readonly BASE_PX=12
readonly BASE_PT=10
readonly ROFI_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config.rasi"
readonly GKEY_SCHEMA="org.gnome.desktop.interface"
readonly GKEY_NAME="text-scaling-factor"

gtk_font_pt() {
  local name pt
  name="$(gsettings get "${GKEY_SCHEMA}" font-name 2>/dev/null || true)"
  pt="${name%\'}"
  pt="${pt##* }"
  [[ ${pt} =~ ^[0-9]+([.][0-9]+)?$ ]] && printf '%s\n' "${pt}" || printf '11\n'
}

term_pt_for() {
  local anchor="${2:-$BASE_PT}" scaled
  scaled=$((($1 * anchor * 100 + BASE_PX / 2) / BASE_PX))
  printf '%d.%02d' "$((scaled / 100))" "$((scaled % 100))"
}

# Must match rofi_effective_font_scale's integer division.
rofi_pt_for() {
  printf '%d\n' "$(($1 * BASE_PT / BASE_PX))"
}

# Report Dunst's rendered value rather than a potentially stale calculation.
dunst_pt_now() {
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/dunst/dunstrc" pt=""
  [[ -r ${conf} ]] && pt="$(awk 'match($0, /^[[:space:]]*font[[:space:]]*=.*[^0-9]([0-9]+)[[:space:]]*$/, m) { print m[1]; exit }' "${conf}")"
  printf '%s\n' "${pt:--}"
}

# Quantize GTK scaling so the interface font lands on whole points.
factor_for() {
  awk -v size="$1" -v base="${BASE_PX}" -v font="$(gtk_font_pt)" \
    'BEGIN { printf "%.4f", int(font * size / base + 0.5) / font }'
}

# Qt ignores the GTK factor; keep KDE and qt5ct/qt6ct point sizes aligned.
set_qt_fonts() {
  local size="$1" family="" mono=""
  command -v kwriteconfig6 >/dev/null 2>&1 || return 0
  family="$(hypr_config_value_from_layers FONT 2>/dev/null || true)"
  mono="$(hypr_config_value_from_layers MONOSPACE_FONT 2>/dev/null || true)"
  [[ -n "${family}" ]] || family="Cantarell"
  [[ -n "${mono}" ]] || mono="monospace"

  local ui="" fixed="" small=""
  ui="$(term_pt_for "${size}")"
  fixed="${ui}"
  small="$(term_pt_for "${size}" 8)"
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

# Font families belong to fonts/font-sync.sh.
set_rofi_size() {
  local pt="$1"

  [[ -f "${ROFI_CONF}" ]] || return 0
  sed -i -E "s/^([[:space:]]*font:[[:space:]]*\"[^\"]*[^0-9 ])[[:space:]]+[0-9]+([.][0-9]+)?\";/\1 ${pt}\";/" \
    "${ROFI_CONF}"
}

set_terminal_size() {
  local pt="$1"

  if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf" ]]; then
    sed -i -E "s/^font_size[[:space:]]+.*/font_size ${pt}/" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
    pkill -USR1 -x kitty 2>/dev/null || true
  fi

  if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini" ]]; then
    sed -i -E "s/^(font=[^:]*:size=)[0-9.]+/\1${pt}/" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
  fi
}

current_size() {
  local size
  size="$(state_get TEXT_SIZE "" 2>/dev/null || true)"
  [[ ${size} =~ ^[0-9]+$ ]] && printf '%s\n' "${size}" || printf '%s\n' "${BASE_PX}"
}

report() {
  local size pt
  size="$(current_size)"
  pt="$(term_pt_for "${size}")"
  printf 'text size   %spx\n' "${size}"
  printf 'gtk factor  %s\n' "$(gsettings get "${GKEY_SCHEMA}" "${GKEY_NAME}" 2>/dev/null || echo '-')"
  printf 'terminal    %spt\n' "${pt}"
  printf 'rofi        %spt\n' "$(rofi_pt_for "${size}")"
  printf 'dunst       %spt\n' "$(dunst_pt_now)"
  printf 'kde ui      %spt\n' "${pt}"
}

apply() {
  local size="$1"

  if [[ ! ${size} =~ ^[0-9]+$ ]] || ((size < MIN || size > MAX)); then
    printf 'text-size: size must be an integer between %s and %s\n' "${MIN}" "${MAX}" >&2
    exit 1
  fi

  state_set TEXT_SIZE "${size}"
  gsettings set "${GKEY_SCHEMA}" "${GKEY_NAME}" "$(factor_for "${size}")" 2>/dev/null || true
  set_terminal_size "$(term_pt_for "${size}")"
  set_rofi_size "$(rofi_pt_for "${size}")"
  set_qt_fonts "${size}"
  hyprshell render/dunst.py >/dev/null 2>&1 || true
  print_log -sec "text-size" -stat "applied" "${size}px"
}

case "${1-}" in
  "") report ;;
  reset) apply "${BASE_PX}" ;;
  *) apply "$1" ;;
esac

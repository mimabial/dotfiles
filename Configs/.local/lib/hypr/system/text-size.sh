#!/usr/bin/env bash
# One knob for apparent text size across the desktop, modelled on
# omarchy-display-text-size. Drives three settings in lockstep, all anchored to
# a 12px base:
#   • the bar's text scale        (TEXT_SIZE in staterc; quickshell watches it)
#   • GNOME/GTK text-scaling-factor (12px -> 1.0, quantized so the interface
#     font lands on a whole point size, so 16 -> 15pt/11pt = 1.3636)
#   • terminal font point size    (12px -> 9pt, so pt = px * 9/12)
set -euo pipefail

readonly -a TEXT_SIZES=(9 10 11 12 13 14 15 16 17 18 19 20)
[[ "${1:-}" == "--list" ]] && { printf '%s\n' "${TEXT_SIZES[*]}"; exit; }

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/text-size [size|reset]
  (no args)   print the current text size, GTK factor, and terminal size
  <size>      set text size in px (9-20); bar + GTK + terminals together
  --list      print available sizes
  reset       return all three to their defaults (12px / 1.0 / 9pt)" "$@"

hypr_runtime_require state

readonly MIN="${TEXT_SIZES[0]}"
readonly MAX="${TEXT_SIZES[-1]}"
readonly BASE_PX=12
readonly TERM_BASE_PT=9
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
  print_log -sec "text-size" -stat "applied" "${size}px"
}

case "${1-}" in
  "") report ;;
  reset) apply "${BASE_PX}" ;;
  *) apply "$1" ;;
esac

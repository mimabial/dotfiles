#!/usr/bin/env bash
# Keeps desktop text settings aligned to a 12px/10pt base. Terminal and Qt
# retain hundredths; Rofi and Dunst intentionally truncate in lockstep.
set -euo pipefail

readonly -a TEXT_SIZES=(9 10 11 12 13 14 15 16 17 18 19 20)
[[ "${1:-}" == "--list" ]] && { printf '%s\n' "${TEXT_SIZES[*]}"; exit; }

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/text-size [size|--select|reset]
  (no args)   print current desktop text sizes
  <size>      set text size in px (9-20) across the desktop
  --select    choose a size in rofi
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
  local scaled=$((($1 * BASE_PT * 100 + BASE_PX / 2) / BASE_PX))
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

# Qt ignores the GTK factor.
set_qt_fonts() {
  local -a font_entries=()
  hypr_runtime_require system
  source "${HYPR_LIB_DIR}/theme/lib/desktop.sync.bash"
  theme_desktop_resolve_base_values
  theme_desktop_kde_font_entries font_entries
  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals" "${font_entries[@]}"
  theme_desktop_notify_kde_fonts_changed
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

resize_running_foot() {
  local delta="$1" key="KP_Add" address="" pid="" comm=""
  ((delta != 0)) || return 0
  ((delta > 0)) || { key="KP_Subtract"; delta=$((-delta)); }

  while IFS=$'\t' read -r address pid; do
    [[ ${address} =~ ^0x[0-9a-f]+$ && ${pid} =~ ^[0-9]+$ ]] || continue
    IFS= read -r comm <"/proc/${pid}/comm" || continue
    [[ ${comm} == "foot" || ${comm} == "footclient" ]] || continue
    hyprctl eval "for _=1,${delta} do hl.dispatch(hl.dsp.send_shortcut({mods=\"CTRL\", key=\"${key}\", window=\"address:${address}\"})) end; return \"ok\"" >/dev/null 2>&1 || true
  done < <(hyprctl clients -j 2>/dev/null | jq -r '.[] | [.address, .pid] | @tsv')
}

current_size() {
  local size
  size="$(state_get TEXT_SIZE "" 2>/dev/null || true)"
  [[ ${size} =~ ^[0-9]+$ ]] && printf '%s\n' "${size}" || printf '%s\n' "${BASE_PX}"
}

select_size() {
  local selected="" current="" index=$((BASE_PX - MIN)) i
  local window_width="${ROFI_TEXT_SIZE_WIDTH:-22em}" window_height="${ROFI_TEXT_SIZE_HEIGHT:-32em}"
  local -a rofi_args=()

  command -v rofi >/dev/null 2>&1 || { printf 'text-size: rofi not found\n' >&2; return 1; }
  hypr_runtime_require rofi
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"

  current="$(current_size)"
  for i in "${!TEXT_SIZES[@]}"; do
    [[ "${TEXT_SIZES[i]}" == "${current}" ]] && { index="${i}"; break; }
  done

  rofi_build_standard_menu_args \
    rofi_args \
    "Text Size" \
    "Desktop text size" \
    "${ROFI_TEXT_SIZE_STYLE:-clipboard}" \
    "${ROFI_TEXT_SIZE_SCALE:-}" \
    "${ROFI_TEXT_SIZE_FONT:-${ROFI_FONT:-}}" \
    "listview" \
    "same" "" "${window_width}" "${window_height}"
  rofi_args+=(
    -no-show-icons
    -no-custom
    -selected-row "${index}"
    -theme-str "listview { lines: ${ROFI_TEXT_SIZE_LINES:-12}; }"
  )

  selected="$(printf '%spx\n' "${TEXT_SIZES[@]}" | rofi_with_background_theme "${rofi_args[@]}")" || return 0
  [[ -n "${selected}" ]] && printf '%s\n' "${selected%px}"
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
  printf 'qt ui       %spt\n' "${pt}"
}

apply() {
  local requested="$1" previous="" size="" applied="" lock_file="" applied_file="" lock_fd=""

  if [[ ! ${requested} =~ ^[0-9]+$ ]] || ((requested < MIN || requested > MAX)); then
    printf 'text-size: size must be an integer between %s and %s\n' "${MIN}" "${MAX}" >&2
    exit 1
  fi

  previous="$(current_size)"
  # Publish before waiting so every waiter applies the newest requested value.
  state_set TEXT_SIZE "${requested}"
  lock_file="$(hypr_runtime_subdir hypr)/text-size.lock"
  applied_file="${lock_file%.lock}.foot"
  exec {lock_fd}>"${lock_file}"
  flock -w 10 "${lock_fd}" || {
    printf 'text-size: timed out waiting for another update\n' >&2
    exit 1
  }
  size="$(current_size)"
  applied="${previous}"
  [[ -r ${applied_file} ]] && IFS= read -r applied <"${applied_file}"
  [[ ${applied} =~ ^[0-9]+$ ]] || applied="${size}"

  gsettings set "${GKEY_SCHEMA}" "${GKEY_NAME}" "$(factor_for "${size}")" 2>/dev/null || true
  set_terminal_size "$(term_pt_for "${size}")"
  resize_running_foot "$((size - applied))"
  printf '%s\n' "${size}" >"${applied_file}"
  set_rofi_size "$(rofi_pt_for "${size}")"
  set_qt_fonts
  hyprshell render/dunst.py >/dev/null 2>&1 || true
  print_log -sec "text-size" -stat "applied" "${size}px"
}

case "${1-}" in
  "") report ;;
  --select)
    selected_size="$(select_size)"
    [[ -n "${selected_size}" ]] || exit 0
    apply "${selected_size}"
    ;;
  reset) apply "${BASE_PX}" ;;
  *) apply "$1" ;;
esac

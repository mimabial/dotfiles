#!/usr/bin/env bash
set -euo pipefail

mode="write-and-reload"
case "${1:-}" in
  --write-only)
    mode="write-only"
    shift
    ;;
  --reload-only)
    mode="reload-only"
    shift
    ;;
esac

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
DUNST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dunst"
DUNST_BASE_CONF="${DUNST_DIR}/dunst.conf"
DUNST_CONF="${DUNST_DIR}/dunstrc"
DUNST_THEME="${DUNST_DIR}/theme.conf"
HASH_FILE="${XDG_RUNTIME_DIR:-/tmp}/wal-dunst-hash"
THEME_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"
WAYBAR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"
LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck disable=SC1090
source "${LIB_DIR}/hypr/runtime/lock_paths.sh"

THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"
THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"

mkdir -p "${DUNST_DIR}"
touch "${DUNST_THEME}"

reload_dunst_runtime() {
  if pgrep -x dunst >/dev/null 2>&1; then
    dunstctl reload >/dev/null 2>&1 || pkill -HUP dunst 2>/dev/null || true
  fi
}

if [[ "${mode}" == "reload-only" ]]; then
  reload_dunst_runtime
  echo "[dunst] Reloaded dunstrc"
  exit 0
fi

if [[ ! -f "${WAL_CACHE}/colors-shell.sh" ]]; then
  exit 0
fi

# shellcheck disable=SC1090
source "${WAL_CACHE}/colors-shell.sh"

parse_define_color() {
  local name="$1"
  local file="$2"
  [[ -f "${file}" ]] || return 1
  awk -v key="${name}" '$1 == "@define-color" && $2 == key {gsub(/;/, "", $3); print $3; exit}' "${file}"
}

read_theme_var() {
  local key="$1"
  [[ -f "${THEME_CONF}" ]] || return 1

  awk -v key="${key}" '
    $0 ~ "^[[:space:]]*\\$" key "[[:space:]]*=" {
      line = $0
      sub("^[[:space:]]*\\$" key "[[:space:]]*=[[:space:]]*", "", line)
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^'\''|'\''$/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }
  ' "${THEME_CONF}"
}

read_hypr_var() {
  local key="$1"
  local file=""
  local value=""

  for file in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/userfonts.conf" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/hypr/variables.conf"; do
    [[ -f "${file}" ]] || continue
    value="$(awk -v key="${key}" '
      $0 ~ "^[[:space:]]*\\$" key "[[:space:]]*=" {
        line = $0
        sub("^[[:space:]]*\\$" key "[[:space:]]*=[[:space:]]*", "", line)
        sub(/[[:space:]]*#.*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        gsub(/^'\''|'\''$/, "", line)
        gsub(/^"|"$/, "", line)
        print line
        exit
      }
    ' "${file}")"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done

  return 1
}

pick_first() {
  local value
  for value in "$@"; do
    [[ -n "${value}" ]] && {
      printf '%s' "${value}"
      return 0
    }
  done
  return 1
}

with_alpha() {
  local color="$1"
  local alpha="$2"
  color="${color#\#}"
  alpha="${alpha#\#}"

  if [[ "${color}" =~ ^[0-9A-Fa-f]{8}$ ]]; then
    printf '#%s%s' "${color:0:6}" "${alpha^^}"
    return 0
  fi

  if [[ "${color}" =~ ^[0-9A-Fa-f]{6}$ ]]; then
    printf '#%s%s' "${color^^}" "${alpha^^}"
    return 0
  fi

  printf '#%s' "${color}"
}

icon_theme="${ICON_THEME:-${GTK_ICON:-$(read_theme_var ICON_THEME)}}"
icon_theme="${icon_theme:-Tela-circle-dracula}"
notification_font="$(pick_first "${NOTIFICATION_FONT:-}" "$(read_hypr_var NOTIFICATION_FONT || true)" "$(read_hypr_var FONT || true)")"
notification_font_size="$(pick_first "${FONT_SIZE:-}" "$(read_hypr_var FONT_SIZE || true)" "10")"
dunst_font_line=""
if [[ -n "${notification_font}" ]]; then
  dunst_font_line="    font = ${notification_font} ${notification_font_size}"
fi

theme_update_in_progress=0
[[ -e "${THEME_UPDATE_LOCK}" ]] && theme_update_in_progress=1

read_theme_conf_metric() {
  local key="$1"
  [[ -f "${THEME_CONF}" ]] || return 1
  grep -E "${key}[[:space:]]*=" "${THEME_CONF}" | head -1 | awk '{print $NF}'
}

read_hypr_metric() {
  local option="$1"
  command -v hyprctl >/dev/null 2>&1 || return 1
  hyprctl -j getoption "${option}" 2>/dev/null | jq -r '.int // empty'
}

resolve_hypr_metric() {
  local theme_key="$1"
  local hypr_option="$2"
  local default_value="$3"
  local value=""

  if [[ "${theme_update_in_progress}" -eq 1 ]]; then
    value="$(read_theme_conf_metric "${theme_key}" || true)"
    [[ -z "${value}" ]] && value="$(read_hypr_metric "${hypr_option}" || true)"
  else
    value="$(read_hypr_metric "${hypr_option}" || true)"
    [[ -z "${value}" ]] && value="$(read_theme_conf_metric "${theme_key}" || true)"
  fi

  printf '%s' "${value:-${default_value}}"
}

hypr_border="$(resolve_hypr_metric 'rounding' 'decoration:rounding' '5')"

gaps_in="$(resolve_hypr_metric 'gaps_in' 'general:gaps_in' '5')"
gap_size="$((gaps_in * 2))"

gaps_out="$(resolve_hypr_metric 'gaps_out' 'general:gaps_out' '6')"

border_size="$(resolve_hypr_metric 'border_size' 'general:border_size' '2')"

waybar_position="right"
if [[ -r "${WAYBAR_CONFIG}" ]]; then
  waybar_position="$(grep '"position"' "${WAYBAR_CONFIG}" | head -1 | sed 's/.*"position"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
fi
waybar_position="${waybar_position:-right}"

origin="top-right"
offset_x="$((gaps_out * 2))"
offset_y="$((gaps_out * 2))"
case "${waybar_position}" in
  left)
    origin="top-left"
    ;;
  bottom)
    origin="bottom-right"
    ;;
  top)
    origin="top-right"
    ;;
  right)
    origin="top-right"
    ;;
  *)
    origin="top-right"
    ;;
esac

bg_primary="$(pick_first "${background:-}" "${color0:-}" "#1e1e2e")"
bg_secondary="${bg_primary}"
bg_tertiary="${bg_primary}"
fg_primary="$(pick_first "${foreground:-}" "${color15:-}" "#f8f8f2")"
fg_secondary="${fg_primary}"
bg_critical="$(pick_first "${color1:-}" "${bg_primary}" "#ff5555")"
fg_critical="${fg_primary}"
border_primary="$(pick_first "${color4:-}" "${color12:-}" "#6272a4")"
border_secondary="$(pick_first "${color8:-}" "${border_primary}" "#44475a")"
accent_red="$(pick_first "${color1:-}" "${color9:-}" "#ff5555")"
accent_green="$(pick_first "${color2:-}" "${color10:-}" "${border_primary}" "#50fa7b")"
accent_yellow="$(pick_first "${color3:-}" "${color11:-}" "${border_primary}" "#f1fa8c")"
accent_blue="$(pick_first "${color4:-}" "${color12:-}" "${border_primary}" "#8be9fd")"
accent_purple="$(pick_first "${color5:-}" "${color13:-}" "${accent_blue}" "#bd93f9")"
accent_aqua="$(pick_first "${color6:-}" "${color14:-}" "${accent_blue}" "#8be9fd")"
accent_orange="$(pick_first "${color11:-}" "${color3:-}" "${accent_red}" "#ffb86c")"
gray="$(pick_first "${color8:-}" "${border_secondary}" "#6272a4")"

if [[ -s "${DUNST_THEME}" ]]; then
  theme_bg_primary="$(parse_define_color bg-primary "${DUNST_THEME}" || true)"
  theme_bg_secondary="$(parse_define_color bg-secondary "${DUNST_THEME}" || true)"
  theme_bg_tertiary="$(parse_define_color bg-tertiary "${DUNST_THEME}" || true)"
  theme_fg_primary="$(parse_define_color fg-primary "${DUNST_THEME}" || true)"
  theme_fg_secondary="$(parse_define_color fg-secondary "${DUNST_THEME}" || true)"
  theme_border_primary="$(parse_define_color border-primary "${DUNST_THEME}" || true)"
  theme_border_secondary="$(parse_define_color border-secondary "${DUNST_THEME}" || true)"
  theme_accent_blue="$(parse_define_color accent-blue "${DUNST_THEME}" || true)"
  theme_accent_red="$(parse_define_color accent-red "${DUNST_THEME}" || true)"
  theme_accent_green="$(parse_define_color accent-green "${DUNST_THEME}" || true)"
  theme_accent_yellow="$(parse_define_color accent-yellow "${DUNST_THEME}" || true)"
  theme_accent_purple="$(parse_define_color accent-purple "${DUNST_THEME}" || true)"
  theme_accent_aqua="$(parse_define_color accent-aqua "${DUNST_THEME}" || true)"
  theme_accent_orange="$(parse_define_color accent-orange "${DUNST_THEME}" || true)"
  theme_gray="$(parse_define_color gray "${DUNST_THEME}" || true)"

  [[ -n "${theme_bg_primary}" ]] && bg_primary="${theme_bg_primary}"
  [[ -n "${theme_bg_secondary}" ]] && bg_secondary="${theme_bg_secondary}"
  [[ -n "${theme_bg_tertiary}" ]] && bg_tertiary="${theme_bg_tertiary}"
  [[ -n "${theme_fg_primary}" ]] && fg_primary="${theme_fg_primary}" && fg_critical="${theme_fg_primary}"
  [[ -n "${theme_fg_secondary}" ]] && fg_secondary="${theme_fg_secondary}"
  [[ -n "${theme_border_primary}" ]] && border_primary="${theme_border_primary}"
  [[ -n "${theme_border_secondary}" ]] && border_secondary="${theme_border_secondary}"
  [[ -n "${theme_accent_blue}" ]] && accent_blue="${theme_accent_blue}"
  [[ -n "${theme_accent_red}" ]] && accent_red="${theme_accent_red}" && bg_critical="${theme_accent_red}"
  [[ -n "${theme_accent_green}" ]] && accent_green="${theme_accent_green}"
  [[ -n "${theme_accent_yellow}" ]] && accent_yellow="${theme_accent_yellow}"
  [[ -n "${theme_accent_purple}" ]] && accent_purple="${theme_accent_purple}"
  [[ -n "${theme_accent_aqua}" ]] && accent_aqua="${theme_accent_aqua}"
  [[ -n "${theme_accent_orange}" ]] && accent_orange="${theme_accent_orange}"
  [[ -n "${theme_gray}" ]] && gray="${theme_gray}"
fi

bg_low="${bg_secondary}"
fg_low="${fg_secondary}"
bg_normal="${bg_primary}"
fg_normal="${fg_primary}"
bg_category="${bg_tertiary}"
fg_category="${fg_primary}"
frame_low="${border_secondary}"
frame_normal="${border_primary}"
frame_critical="${accent_red}"
progress_fg="${accent_blue}"

bg_low_render="$(with_alpha "${bg_low}" "80")"
bg_normal_render="$(with_alpha "${bg_normal}" "80")"
bg_category_render="$(with_alpha "${bg_category}" "80")"
bg_critical_render="${bg_critical}"
fg_low_render="$(with_alpha "${fg_low}" "E6")"
fg_normal_render="$(with_alpha "${fg_normal}" "E6")"
fg_category_render="$(with_alpha "${fg_category}" "E6")"
fg_critical_render="${fg_critical}"
frame_low_render="$(with_alpha "${frame_low}" "33")"
frame_normal_render="$(with_alpha "${frame_normal}" "55")"
frame_category_email_render="$(with_alpha "${accent_blue}" "55")"
frame_category_chat_render="$(with_alpha "${accent_aqua}" "55")"
frame_category_warning_render="$(with_alpha "${accent_yellow}" "55")"
frame_category_error_render="$(with_alpha "${accent_red}" "55")"
frame_category_network_render="$(with_alpha "${accent_blue}" "55")"
frame_category_battery_render="$(with_alpha "${accent_orange}" "55")"
frame_category_update_render="$(with_alpha "${accent_green}" "55")"
frame_category_music_render="$(with_alpha "${accent_purple}" "55")"
frame_category_volume_render="$(with_alpha "${gray}" "55")"

input_hash="$({
  md5sum "${WAL_CACHE}/colors-shell.sh" 2>/dev/null || true
  [[ -f "${DUNST_BASE_CONF}" ]] && md5sum "${DUNST_BASE_CONF}" 2>/dev/null || true
  [[ -f "${DUNST_THEME}" ]] && md5sum "${DUNST_THEME}" 2>/dev/null || true
  printf '%s\n' "${icon_theme}" "${hypr_border}" "${gaps_in}" "${border_size}" "${origin}" "${offset_x}" "${offset_y}" \
    "${notification_font}" "${notification_font_size}" \
    "${gap_size}" \
    "${bg_low_render}" "${fg_low_render}" "${bg_normal_render}" "${fg_normal_render}" \
    "${bg_category_render}" "${fg_category_render}" "${bg_critical_render}" "${fg_critical_render}" \
    "${frame_low_render}" "${frame_normal_render}" "${frame_critical}" "${progress_fg}" \
    "${frame_category_email_render}" "${frame_category_chat_render}" "${frame_category_warning_render}" \
    "${frame_category_error_render}" "${frame_category_network_render}" "${frame_category_battery_render}" \
    "${frame_category_update_render}" "${frame_category_music_render}" "${frame_category_volume_render}"
} | md5sum | awk '{print $1}')"

if [[ -f "${HASH_FILE}" ]] && [[ "$(cat "${HASH_FILE}" 2>/dev/null)" == "${input_hash}" ]]; then
  exit 0
fi

if [[ ! -f "${DUNST_BASE_CONF}" ]]; then
  if [[ -f "${DUNST_CONF}" ]]; then
    cp "${DUNST_CONF}" "${DUNST_BASE_CONF}"
  elif [[ -f /etc/dunst/dunstrc ]]; then
    cp /etc/dunst/dunstrc "${DUNST_BASE_CONF}"
  else
    cat >"${DUNST_BASE_CONF}" <<'BASE'
[global]
    monitor = 0
BASE
  fi
fi

tmp_conf="$(mktemp "${DUNST_DIR}/.dunstrc.XXXXXX")"
trap 'rm -f "${tmp_conf}"' EXIT

cat >"${tmp_conf}" <<CONFIG
# WARNING: This file is auto-generated by '${0}'.
# DO NOT edit manually.
# Edit '${DUNST_BASE_CONF}' to change the base configuration.

CONFIG

cat "${DUNST_BASE_CONF}" >>"${tmp_conf}"

cat >>"${tmp_conf}" <<CONFIG

# Dynamic overrides generated from wal/theme state.
[global]
    monitor = 0
    origin = ${origin}
    offset = (${offset_x},${offset_y})
    gap_size = ${gap_size}
    frame_width = ${border_size}
    progress_bar_corner_radius = ${hypr_border}
    icon_theme = "${icon_theme}"
    corner_radius = ${hypr_border}
    icon_corner_radius = ${hypr_border}
${dunst_font_line}

[urgency_low]
    background = "${bg_low_render}"
    foreground = "${fg_low_render}"
    frame_color = "${frame_low_render}"
    highlight = "${progress_fg}"
    timeout = 2

[urgency_normal]
    background = "${bg_normal_render}"
    foreground = "${fg_normal_render}"
    frame_color = "${frame_normal_render}"
    highlight = "${progress_fg}"
    timeout = 2

[urgency_critical]
    background = "${bg_critical_render}"
    foreground = "${fg_critical_render}"
    frame_color = "${frame_critical}"
    highlight = "${frame_critical}"
    timeout = 0
CONFIG

append_category_rule() {
  local section="$1"
  local category="$2"
  local color="$3"
  local urgency

  for urgency in low normal; do
    cat >>"${tmp_conf}" <<CONFIG

[category_${section}_${urgency}]
    category = ${category}
    msg_urgency = ${urgency}
    background = "${bg_category_render}"
    foreground = "${fg_category_render}"
    frame_color = "${color}"
    highlight = "${color}"
    timeout = 2
CONFIG
  done
}

append_category_rule "email" "email" "${frame_category_email_render}"
append_category_rule "chat" "chat" "${frame_category_chat_render}"
append_category_rule "warning" "warning" "${frame_category_warning_render}"
append_category_rule "error" "error" "${frame_category_error_render}"
append_category_rule "network" "network" "${frame_category_network_render}"
append_category_rule "battery" "battery" "${frame_category_battery_render}"
append_category_rule "update" "update" "${frame_category_update_render}"
append_category_rule "music" "music" "${frame_category_music_render}"
append_category_rule "volume" "volume" "${frame_category_volume_render}"

mv "${tmp_conf}" "${DUNST_CONF}"
trap - EXIT

echo "${input_hash}" >"${HASH_FILE}"

if [[ "${mode}" == "write-only" ]] || [[ -e "${THEME_SWITCH_LOCK}" ]]; then
  echo "[dunst] Generated dunstrc"
  exit 0
fi

reload_dunst_runtime
echo "[dunst] Generated and reloaded dunstrc"

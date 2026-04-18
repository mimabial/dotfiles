#!/usr/bin/env bash
set -euo pipefail

mode="write-and-reload"
WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
DUNST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dunst"
DUNST_BASE_CONF="${DUNST_DIR}/dunst.conf"
DUNST_CONF="${DUNST_DIR}/dunstrc"
DUNST_THEME="${DUNST_DIR}/theme.generated.conf"
HASH_FILE="${XDG_RUNTIME_DIR:-/tmp}/wal-dunst-hash"
THEME_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"
WAYBAR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"
LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
WAL_DUNST_PARSE_COLOR_MISSING=1
WAL_DUNST_PARSE_COLOR_INVALID=2

# shellcheck disable=SC1090
source "${LIB_DIR}/hypr/runtime/lock_paths.sh"
# shellcheck disable=SC1090
source "${LIB_DIR}/hypr/core/common.sh"

THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"
THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"

parse_mode() {
  case "${1:-}" in
    --write-only)
      mode="write-only"
      ;;
    --reload-only)
      mode="reload-only"
      ;;
  esac
}

reload_dunst_runtime() {
  if pgrep -x dunst >/dev/null 2>&1; then
    dunstctl reload >/dev/null 2>&1 || pkill -HUP dunst 2>/dev/null || true
  fi
}

parse_define_color() {
  local name="$1"
  local file="$2"
  # Return contract:
  # 0: printed a valid color
  # 1: file/key missing, so the caller may fall back
  # 2: key found but the color value is invalid and should be surfaced
  [[ -f "${file}" ]] || return "${WAL_DUNST_PARSE_COLOR_MISSING}"
  awk \
    -v key="${name}" \
    -v exit_missing="${WAL_DUNST_PARSE_COLOR_MISSING}" \
    -v exit_invalid="${WAL_DUNST_PARSE_COLOR_INVALID}" '
    BEGIN {
      found = 0
    }
    $1 == "@define-color" && $2 == key {
      found = 1
      gsub(/;/, "", $3)
      if ($3 ~ /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/) {
        print $3
        exit 0
      }
      exit exit_invalid
    }
    END {
      if (!found) {
        exit exit_missing
      }
    }
  ' "${file}"
}

apply_theme_color_override() {
  local name="$1"
  local target="$2"
  local mirror_target="${3:-}"
  local value=""
  local rc=0

  if value="$(parse_define_color "${name}" "${DUNST_THEME}")"; then
    printf -v "${target}" '%s' "${value}"
    [[ -n "${mirror_target}" ]] && printf -v "${mirror_target}" '%s' "${value}"
    return 0
  else
    rc=$?
  fi

  case "${rc}" in
    "${WAL_DUNST_PARSE_COLOR_MISSING}")
      return "${WAL_DUNST_PARSE_COLOR_MISSING}"
      ;;
    "${WAL_DUNST_PARSE_COLOR_INVALID}")
      printf 'ERROR: invalid @define-color %s in %s\n' "${name}" "${DUNST_THEME}" >&2
      return "${WAL_DUNST_PARSE_COLOR_INVALID}"
      ;;
    *)
      return "${rc}"
      ;;
  esac
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

resolve_notification_font() {
  local layered_font_size=""
  local notification_font_size_candidate=""
  local gsettings_icon_theme=""

  icon_theme="${ICON_THEME:-${GTK_ICON:-$(read_theme_var ICON_THEME)}}"
  if [[ -z "${icon_theme}" ]] && command -v gsettings >/dev/null 2>&1; then
    gsettings_icon_theme="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" || true)"
    icon_theme="${gsettings_icon_theme}"
  fi
  icon_theme="${icon_theme:-hicolor}"
  notification_font="$(pick_first "${NOTIFICATION_FONT:-}" "$(hypr_config_value_from_layers "NOTIFICATION_FONT" || true)" "$(hypr_config_value_from_layers "FONT" || true)")"
  layered_font_size="$(hypr_config_value_from_layers "FONT_SIZE" || true)"
  if [[ -n "${FONT_SIZE:-}" ]]; then
    if [[ "${FONT_SIZE}" =~ ^[0-9]+$ ]]; then
      notification_font_size_candidate="${FONT_SIZE}"
    else
      printf 'WARN: invalid FONT_SIZE env override: %s\n' "${FONT_SIZE}" >&2
    fi
  fi
  if [[ -z "${notification_font_size_candidate}" && -n "${layered_font_size}" ]]; then
    if [[ "${layered_font_size}" =~ ^[0-9]+$ ]]; then
      notification_font_size_candidate="${layered_font_size}"
    else
      printf 'WARN: invalid FONT_SIZE layered value: %s\n' "${layered_font_size}" >&2
    fi
  fi
  notification_font_size="${notification_font_size_candidate:-10}"
  dunst_font_line=""
  if [[ -n "${notification_font}" ]]; then
    dunst_font_line="    font = ${notification_font} ${notification_font_size}"
  fi
}

resolve_layout_metrics() {
  theme_update_in_progress=0
  [[ -e "${THEME_UPDATE_LOCK}" ]] && theme_update_in_progress=1

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
  offset_x="$((gaps_out * 2 + hypr_border))"
  offset_y="$((gaps_out * 2 + hypr_border))"
  case "${waybar_position}" in
    left) origin="top-left" ;;
    bottom) origin="bottom-right" ;;
    top | right | *) origin="top-right" ;;
  esac
}

load_base_palette() {
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
}

apply_theme_palette_overrides() {
  [[ -s "${DUNST_THEME}" ]] || return 0

  local name="" target="" mirror_target="" rc=0

  while IFS=':' read -r name target mirror_target; do
    [[ -n "${name}" ]] || continue
    if apply_theme_color_override "${name}" "${target}" "${mirror_target}"; then
      continue
    else
      rc=$?
    fi
    [[ "${rc}" -eq 1 ]] && continue
    return "${rc}"
  done <<'EOF'
bg-primary:bg_primary:
bg-secondary:bg_secondary:
bg-tertiary:bg_tertiary:
fg-primary:fg_primary:fg_critical
fg-secondary:fg_secondary:
border-primary:border_primary:
border-secondary:border_secondary:
accent-blue:accent_blue:
accent-red:accent_red:bg_critical
accent-green:accent_green:
accent-yellow:accent_yellow:
accent-purple:accent_purple:
accent-aqua:accent_aqua:
accent-orange:accent_orange:
gray:gray:
EOF
}

render_palette() {
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
  bg_critical_render="$(with_alpha "${bg_critical}" "80")"
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
}

build_input_hash() {
  {
    md5sum "${WAL_CACHE}/colors-shell.sh" 2>/dev/null || true
    [[ -f "${DUNST_BASE_CONF}" ]] && md5sum "${DUNST_BASE_CONF}" 2>/dev/null || true
    [[ -f "${DUNST_THEME}" ]] && md5sum "${DUNST_THEME}" 2>/dev/null || true
    printf '%s\n' "${icon_theme}" "${hypr_border}" "${gaps_in}" "${border_size}" "${origin}" "${offset_x}" "${offset_y}" \
      "${notification_font}" "${notification_font_size}" "${gap_size}" \
      "${bg_low_render}" "${fg_low_render}" "${bg_normal_render}" "${fg_normal_render}" \
      "${bg_category_render}" "${fg_category_render}" "${bg_critical_render}" "${fg_critical_render}" \
      "${frame_low_render}" "${frame_normal_render}" "${frame_critical}" "${progress_fg}" \
      "${frame_category_email_render}" "${frame_category_chat_render}" "${frame_category_warning_render}" \
      "${frame_category_error_render}" "${frame_category_network_render}" "${frame_category_battery_render}" \
      "${frame_category_update_render}" "${frame_category_music_render}" "${frame_category_volume_render}"
  } | md5sum | awk '{print $1}'
}

hash_is_current() {
  local input_hash="$1"
  [[ -f "${HASH_FILE}" ]] && [[ "$(cat "${HASH_FILE}" 2>/dev/null)" == "${input_hash}" ]]
}

ensure_base_conf() {
  if [[ -f "${DUNST_BASE_CONF}" ]]; then
    return 0
  fi

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
}

begin_tmp_conf() {
  tmp_conf="$(mktemp "${DUNST_DIR}/.dunstrc.XXXXXX")"
  trap 'wal_dunst_cleanup_tmp_conf "$?"' EXIT
  cat >"${tmp_conf}" <<CONFIG
# WARNING: This file is auto-generated by '${0}'.
# DO NOT edit manually.
# Edit '${DUNST_BASE_CONF}' to change the base configuration.

CONFIG
  cat "${DUNST_BASE_CONF}" >>"${tmp_conf}"
}

wal_dunst_cleanup_tmp_conf() {
  local exit_code="${1:-$?}"
  rm -f "${tmp_conf}" 2>/dev/null || true
  return "${exit_code}"
}

append_dynamic_global_section() {
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
    corner_radius = $((hypr_border * 3 / 2))
    icon_corner_radius = ${hypr_border}
${dunst_font_line}
CONFIG
}

append_urgency_sections() {
  cat >>"${tmp_conf}" <<CONFIG

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
}

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

append_category_sections() {
  append_category_rule "email" "email" "${frame_category_email_render}"
  append_category_rule "chat" "chat" "${frame_category_chat_render}"
  append_category_rule "warning" "warning" "${frame_category_warning_render}"
  append_category_rule "error" "error" "${frame_category_error_render}"
  append_category_rule "network" "network" "${frame_category_network_render}"
  append_category_rule "battery" "battery" "${frame_category_battery_render}"
  append_category_rule "update" "update" "${frame_category_update_render}"
  append_category_rule "music" "music" "${frame_category_music_render}"
  append_category_rule "volume" "volume" "${frame_category_volume_render}"
}

write_dunstrc() {
  begin_tmp_conf
  append_dynamic_global_section
  append_urgency_sections
  append_category_sections
  mv "${tmp_conf}" "${DUNST_CONF}"
  trap - EXIT
}

finalize_generation() {
  local input_hash="$1"
  echo "${input_hash}" >"${HASH_FILE}"

  if [[ "${mode}" == "write-only" ]] || [[ -e "${THEME_SWITCH_LOCK}" ]]; then
    echo "[dunst] Generated dunstrc"
    return 0
  fi

  reload_dunst_runtime
  echo "[dunst] Generated and reloaded dunstrc"
}

main() {
  parse_mode "${1:-}"
  mkdir -p "${DUNST_DIR}"
  touch "${DUNST_THEME}"

  if [[ "${mode}" == "reload-only" ]]; then
    reload_dunst_runtime
    echo "[dunst] Reloaded dunstrc"
    exit 0
  fi

  [[ -f "${WAL_CACHE}/colors-shell.sh" ]] || exit 0
  # shellcheck disable=SC1090
  source "${WAL_CACHE}/colors-shell.sh"

  resolve_notification_font
  resolve_layout_metrics
  load_base_palette
  apply_theme_palette_overrides
  render_palette

  input_hash="$(build_input_hash)"
  hash_is_current "${input_hash}" && exit 0

  ensure_base_conf
  write_dunstrc
  finalize_generation "${input_hash}"
}

main "${1:-}"

#!/usr/bin/env bash
set -euo pipefail

mode="write-and-reload"
WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
DUNST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dunst"
DUNST_BASE_CONF="${DUNST_DIR}/dunst.conf"
DUNST_CONF="${DUNST_DIR}/dunstrc"
DUNST_THEME="${DUNST_DIR}/theme.generated.conf"
THEME_CONF="${HYPR_THEME_METADATA_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf}"
WAYBAR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"
LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck disable=SC1091
source "${LIB_DIR}/hypr/core/hash-cache.sh" || exit 1
# shellcheck disable=SC1091
source "${LIB_DIR}/hypr/runtime/lock_paths.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/hypr/core/common.sh"

HASH_FILE="$(hypr_hash_cache_runtime_file "wal-dunst-hash")" || exit 1
THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"

reload_dunst_runtime() {
  if hypr_user_pgrep -x dunst >/dev/null 2>&1; then
    dunstctl reload >/dev/null 2>&1 || hypr_user_pkill -HUP -x dunst 2>/dev/null || true
  fi
}

load_theme_palette_overrides() {
  local line=""
  local entry=""
  local name=""
  local value=""

  declare -gA dunst_theme_palette=()
  [[ -s "${DUNST_THEME}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ^[[:space:]]*@define-color[[:space:]]+ ]] || continue

    entry="${line#*@define-color}"
    entry="${entry#"${entry%%[![:space:]]*}"}"
    name="${entry%%[[:space:]]*}"
    value="${entry#"${name}"}"
    value="${value%%;*}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ ! "${value}" =~ ^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$ ]]; then
      printf 'ERROR: invalid @define-color %s in %s\n' "${name}" "${DUNST_THEME}" >&2
      return 1
    fi

    dunst_theme_palette["${name}"]="${value}"
  done < "${DUNST_THEME}"
}

theme_palette_value() {
  local key="$1"
  local fallback="$2"
  printf '%s' "${dunst_theme_palette[${key}]:-${fallback}}"
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
  awk -v key="${key}" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      print $NF
      exit
    }
  ' "${THEME_CONF}"
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
  local edge_padding=0

  theme_update_in_progress=0
  [[ -e "${THEME_UPDATE_LOCK}" ]] && theme_update_in_progress=1

  rounding="$(resolve_hypr_metric 'rounding' 'decoration:rounding' '5')"
  gaps_in="$(resolve_hypr_metric 'gaps_in' 'general:gaps_in' '5')"
  gap_size="$((gaps_in * 2))"
  gaps_out="$(resolve_hypr_metric 'gaps_out' 'general:gaps_out' '6')"
  border_size="$(resolve_hypr_metric 'border_size' 'general:border_size' '2')"
  edge_padding="$((gaps_out * 2 + border_size))"

  waybar_position="right"
  if [[ -r "${WAYBAR_CONFIG}" ]]; then
    waybar_position="$(grep '"position"' "${WAYBAR_CONFIG}" | head -1 | sed 's/.*"position"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  fi
  waybar_position="${waybar_position:-right}"

  origin="top-right"
  offset_x="${edge_padding}"
  offset_y="${edge_padding}"
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
    right | *)
      origin="top-right"
      ;;
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
  bg_primary="$(theme_palette_value "bg-primary" "${bg_primary}")"
  bg_secondary="$(theme_palette_value "bg-secondary" "${bg_secondary}")"
  bg_tertiary="$(theme_palette_value "bg-tertiary" "${bg_tertiary}")"
  fg_primary="$(theme_palette_value "fg-primary" "${fg_primary}")"
  fg_secondary="$(theme_palette_value "fg-secondary" "${fg_secondary}")"
  border_primary="$(theme_palette_value "border-primary" "${border_primary}")"
  border_secondary="$(theme_palette_value "border-secondary" "${border_secondary}")"
  accent_blue="$(theme_palette_value "accent-blue" "${accent_blue}")"
  accent_red="$(theme_palette_value "accent-red" "${accent_red}")"
  accent_green="$(theme_palette_value "accent-green" "${accent_green}")"
  accent_yellow="$(theme_palette_value "accent-yellow" "${accent_yellow}")"
  accent_purple="$(theme_palette_value "accent-purple" "${accent_purple}")"
  accent_aqua="$(theme_palette_value "accent-aqua" "${accent_aqua}")"
  accent_orange="$(theme_palette_value "accent-orange" "${accent_orange}")"
  gray="$(theme_palette_value "gray" "${gray}")"

  bg_critical="${accent_red}"
  fg_critical="${fg_primary}"
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
  local file=""
  local -a inputs=()

  for file in "${WAL_CACHE}/colors-shell.sh" "${DUNST_BASE_CONF}" "${DUNST_THEME}"; do
    [[ -f "${file}" ]] || continue
    inputs+=("$(hypr_hash_cache_digest_files "${file}")")
  done

  hypr_hash_cache_digest_strings \
    "${inputs[@]}" \
    "${icon_theme}" "${rounding}" "${gaps_in}" "${border_size}" "${origin}" "${offset_x}" "${offset_y}" \
    "${notification_font}" "${notification_font_size}" "${gap_size}" \
    "${bg_low_render}" "${fg_low_render}" "${bg_normal_render}" "${fg_normal_render}" \
    "${bg_category_render}" "${fg_category_render}" "${bg_critical_render}" "${fg_critical_render}" \
    "${frame_low_render}" "${frame_normal_render}" "${frame_critical}" "${progress_fg}" \
    "${frame_category_email_render}" "${frame_category_chat_render}" "${frame_category_warning_render}" \
    "${frame_category_error_render}" "${frame_category_network_render}" "${frame_category_battery_render}" \
    "${frame_category_update_render}" "${frame_category_music_render}" "${frame_category_volume_render}"
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
    progress_bar_corner_radius = ${rounding}
    icon_theme = "${icon_theme}"
    corner_radius = $((rounding * 3 / 2))
    icon_corner_radius = ${rounding}
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

main() {
  case "${1:-}" in
    --write-only) mode="write-only" ;;
    --reload-only) mode="reload-only" ;;
  esac
  mkdir -p "${DUNST_DIR}"
  touch "${DUNST_THEME}"

  if [[ "${mode}" == "reload-only" ]]; then
    reload_dunst_runtime
    echo "[dunst] Reloaded dunstrc"
    exit 0
  fi

  [[ -f "${WAL_CACHE}/colors-shell.sh" ]] || exit 0
  # shellcheck disable=SC1091
  source "${WAL_CACHE}/colors-shell.sh"

  resolve_notification_font
  resolve_layout_metrics
  load_base_palette
  load_theme_palette_overrides
  apply_theme_palette_overrides
  render_palette

  input_hash="$(build_input_hash)"
  hypr_hash_cache_is_current "${HASH_FILE}" "${input_hash}" && exit 0

  ensure_base_conf
  write_dunstrc
  hypr_hash_cache_store "${HASH_FILE}" "${input_hash}"

  if [[ "${mode}" == "write-only" ]]; then
    echo "[dunst] Generated dunstrc"
    return 0
  fi

  reload_dunst_runtime
  echo "[dunst] Generated and reloaded dunstrc"
}

main "${1:-}"

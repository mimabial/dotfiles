#!/usr/bin/env bash
# wal.qt.sh - Generate qt5ct/qt6ct palettes for the active theme mode.

source "$(command -v hyprshell)" || exit 1

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
PYWAL_KVANTUM_DIR="${HOME}/.config/Kvantum/pywal16"
QT5_CACHE_SCHEME="${WAL_CACHE}/colors-qt5ct.conf"
QT6_CACHE_SCHEME="${WAL_CACHE}/colors-qt6ct.conf"
QT5_CONFIG_SCHEME="${XDG_CONFIG_HOME:-$HOME/.config}/qt5ct/colors/pywal16.conf"
QT6_CONFIG_SCHEME="${XDG_CONFIG_HOME:-$HOME/.config}/qt6ct/colors/pywal16.conf"

declare -F export_hypr_config >/dev/null 2>&1 && export_hypr_config
selected_color_mode="${selected_color_mode:-1}"

normalize_qt_color() {
  local raw="${1%%;*}"

  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"

  if [[ "${raw}" =~ ^#?[0-9A-Fa-f]{8}$ ]]; then
    raw="${raw#\#}"
    printf '#%s\n' "${raw:0:6}"
    return 0
  fi

  if [[ "${raw}" =~ ^#?[0-9A-Fa-f]{6}$ ]]; then
    printf '#%s\n' "${raw#\#}"
    return 0
  fi

  printf '%s\n' "${raw}"
}

qt_color_with_alpha() {
  local color="$1"
  local alpha="${2:-80}"

  color="$(normalize_qt_color "${color}")"
  printf '%s%s\n' "${color#\#}" "${alpha}"
}

qt_join_palette_values() {
  local first=1
  local value=""

  for value in "$@"; do
    if [[ "${first}" -eq 1 ]]; then
      printf '%s' "${value}"
      first=0
    else
      printf ', %s' "${value}"
    fi
  done
  printf '\n'
}

qt_write_file_if_changed() {
  local target_file="$1"
  local content="$2"
  local target_dir=""
  local tmp_file=""

  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}" || return 1
  tmp_file="$(mktemp "${target_dir}/.$(basename "${target_file}").XXXXXX")" || return 1
  printf '%s' "${content}" > "${tmp_file}"

  if [[ -f "${target_file}" ]] && cmp -s "${tmp_file}" "${target_file}"; then
    rm -f "${tmp_file}"
    return 0
  fi

  mv -f "${tmp_file}" "${target_file}"
}

qt_ensure_scheme_symlink() {
  local link_path="$1"
  local target_path="$2"
  local link_dir=""

  link_dir="$(dirname "${link_path}")"
  mkdir -p "${link_dir}" || return 1
  ln -sfn "${target_path}" "${link_path}"
}

load_qt_kvconfig_colors() {
  local kvconfig_file="$1"
  local map_name="$2"
  local line=""
  local key=""
  local value=""
  local normalized=""
  local -n map_ref="${map_name}"

  map_ref=()
  [[ -f "${kvconfig_file}" ]] || return 1

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "${key}" in
      *.color)
        normalized="$(normalize_qt_color "${value}")"
        [[ "${normalized}" =~ ^#[0-9A-Fa-f]{6}$ ]] || continue
        map_ref["${key}"]="${normalized}"
        ;;
    esac
  done < "${kvconfig_file}"
}

build_theme_mode_qt_palette() {
  local kvconfig_file="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  local window=""
  local base=""
  local alternate_base=""
  local button=""
  local light=""
  local midlight=""
  local dark=""
  local mid=""
  local window_text=""
  local text=""
  local button_text=""
  local highlight=""
  local inactive_highlight=""
  local highlight_text=""
  local tooltip_text=""
  local disabled_text=""
  local link=""
  local link_visited=""
  local placeholder=""
  declare -A theme_colors

  load_qt_kvconfig_colors "${kvconfig_file}" theme_colors || return 1

  window="${theme_colors[window.color]:-${background:-#ffffff}}"
  base="${theme_colors[base.color]:-${window}}"
  alternate_base="${theme_colors[alt.base.color]:-${base}}"
  button="${theme_colors[button.color]:-${window}}"
  light="${theme_colors[light.color]:-${button}}"
  midlight="${theme_colors[mid.light.color]:-${light}}"
  dark="${theme_colors[dark.color]:-${button}}"
  mid="${theme_colors[mid.color]:-${button}}"
  window_text="${theme_colors[window.text.color]:-${theme_colors[text.color]:-${foreground:-#000000}}}"
  text="${theme_colors[text.color]:-${window_text}}"
  button_text="${theme_colors[button.text.color]:-${window_text}}"
  highlight="${theme_colors[highlight.color]:-${theme_colors[inactive.highlight.color]:-${color6:-${color4:-#888888}}}}"
  inactive_highlight="${theme_colors[inactive.highlight.color]:-${highlight}}"
  highlight_text="${theme_colors[highlight.text.color]:-${window}}"
  tooltip_text="${theme_colors[tooltip.text.color]:-${text}}"
  disabled_text="${theme_colors[disabled.text.color]:-${window_text}}"
  link="${theme_colors[link.color]:-${highlight}}"
  link_visited="${link}"
  placeholder="$(qt_color_with_alpha "${disabled_text}")"

  qt_active_colors="$(qt_join_palette_values \
    "${window_text}" "${button}" "${light}" "${midlight}" "${dark}" "${mid}" \
    "${text}" "${highlight_text}" "${button_text}" "${base}" "${window}" "${dark}" \
    "${highlight}" "${highlight_text}" "${link}" "${link_visited}" "${alternate_base}" \
    "${window}" "${window}" "${tooltip_text}" "${placeholder}")"

  qt_disabled_colors="$(qt_join_palette_values \
    "${disabled_text}" "${button}" "${light}" "${midlight}" "${dark}" "${mid}" \
    "${disabled_text}" "${highlight_text}" "${disabled_text}" "${base}" "${window}" "${dark}" \
    "${inactive_highlight}" "${highlight_text}" "${link}" "${link_visited}" "${alternate_base}" \
    "${window}" "${window}" "${tooltip_text}" "${placeholder}")"

  qt_inactive_colors="$(qt_join_palette_values \
    "${window_text}" "${button}" "${light}" "${midlight}" "${dark}" "${mid}" \
    "${text}" "${highlight_text}" "${button_text}" "${base}" "${window}" "${dark}" \
    "${inactive_highlight}" "${highlight_text}" "${link}" "${link_visited}" "${alternate_base}" \
    "${window}" "${window}" "${tooltip_text}" "${placeholder}")"
}

build_wallpaper_mode_qt_palette() {
  [[ -f "${WAL_CACHE}/colors-shell.sh" ]] || return 1
  # shellcheck source=/dev/null
  source "${WAL_CACHE}/colors-shell.sh" || return 1

  qt_active_colors="$(qt_join_palette_values \
    "${foreground}" "${color8}" "${color7}" "${color7}" "${color0}" "${color8}" \
    "${foreground}" "${foreground}" "${foreground}" "${background}" "${background}" "${color0}" \
    "${color5}" "${background}" "${color4}" "${color5}" "${color0}" "${background}" \
    "${foreground}" "${color7}" "$(qt_color_with_alpha "${foreground}")")"

  qt_disabled_colors="$(qt_join_palette_values \
    "${color8}" "${color8}" "${color7}" "${color7}" "${color0}" "${color8}" \
    "${color8}" "${color8}" "${color8}" "${background}" "${background}" "${color0}" \
    "${color8}" "${background}" "${color8}" "${color8}" "${color0}" "${background}" \
    "${color8}" "${color7}" "$(qt_color_with_alpha "${color8}")")"

  qt_inactive_colors="$(qt_join_palette_values \
    "${color7}" "${color8}" "${color7}" "${color7}" "${color0}" "${color8}" \
    "${color7}" "${color7}" "${color7}" "${background}" "${background}" "${color0}" \
    "${color4}" "${background}" "${color4}" "${color5}" "${color0}" "${background}" \
    "${color7}" "${color7}" "$(qt_color_with_alpha "${color7}")")"
}

render_qt_palette_scheme() {
  cat <<EOF
[ColorScheme]
active_colors=${qt_active_colors}
disabled_colors=${qt_disabled_colors}
inactive_colors=${qt_inactive_colors}
EOF
}

if [[ "${selected_color_mode}" -eq 0 ]] && ! build_theme_mode_qt_palette; then
  build_wallpaper_mode_qt_palette || exit 1
elif [[ "${selected_color_mode}" -ne 0 ]]; then
  build_wallpaper_mode_qt_palette || exit 1
fi

qt_scheme_content="$(render_qt_palette_scheme)"

qt_write_file_if_changed "${QT5_CACHE_SCHEME}" "${qt_scheme_content}" || exit 1
qt_write_file_if_changed "${QT6_CACHE_SCHEME}" "${qt_scheme_content}" || exit 1
qt_ensure_scheme_symlink "${QT5_CONFIG_SCHEME}" "${QT5_CACHE_SCHEME}" || exit 1
qt_ensure_scheme_symlink "${QT6_CONFIG_SCHEME}" "${QT6_CACHE_SCHEME}" || exit 1

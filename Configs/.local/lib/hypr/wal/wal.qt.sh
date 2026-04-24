#!/usr/bin/env bash
# wal.qt.sh - Generate qt5ct/qt6ct palettes for the active color mode.

# shellcheck disable=SC1090
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

  mkdir -p "$(dirname "${link_path}")" || return 1
  ln -sfn "${target_path}" "${link_path}"
}

qt_load_wal_colors() {
  [[ -f "${WAL_CACHE}/colors-shell.sh" ]] || return 1
  # shellcheck source=/dev/null
  source "${WAL_CACHE}/colors-shell.sh" || return 1
}

qt_load_theme_palette_roles() {
  local kvconfig_file="${PYWAL_KVANTUM_DIR}/pywal16.kvconfig"
  local section=""
  local line=""
  local key=""
  local value=""
  declare -A theme_colors=()

  [[ -f "${kvconfig_file}" ]] || return 1

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      \[*\])
        section=""
        [[ "${line}" == "[GeneralColors]" ]] && section="general"
        continue
        ;;
    esac

    [[ "${section}" == "general" && "${line}" == *=* ]] || continue
    key="${line%%=*}"
    value="$(normalize_qt_color "${line#*=}")"
    [[ "${value}" =~ ^#[0-9A-Fa-f]{6}$ ]] || continue
    theme_colors["${key}"]="${value}"
  done < "${kvconfig_file}"

  qt_window="${theme_colors[window.color]:-${background:-#ffffff}}"
  qt_base="${theme_colors[base.color]:-${qt_window}}"
  qt_alternate_base="${theme_colors[alt.base.color]:-${qt_base}}"
  qt_button="${theme_colors[button.color]:-${qt_window}}"
  qt_light="${theme_colors[light.color]:-${qt_button}}"
  qt_midlight="${theme_colors[mid.light.color]:-${qt_light}}"
  qt_dark="${theme_colors[dark.color]:-${qt_button}}"
  qt_mid="${theme_colors[mid.color]:-${qt_button}}"
  qt_window_text="${theme_colors[window.text.color]:-${theme_colors[text.color]:-${foreground:-#000000}}}"
  qt_text="${theme_colors[text.color]:-${qt_window_text}}"
  qt_button_text="${theme_colors[button.text.color]:-${qt_window_text}}"
  qt_highlight="${theme_colors[highlight.color]:-${theme_colors[inactive.highlight.color]:-${color6:-${color4:-#888888}}}}"
  qt_inactive_highlight="${theme_colors[inactive.highlight.color]:-${qt_highlight}}"
  qt_highlight_text="${theme_colors[highlight.text.color]:-${qt_window}}"
  qt_tooltip_text="${theme_colors[tooltip.text.color]:-${qt_text}}"
  qt_disabled_text="${theme_colors[disabled.text.color]:-${qt_window_text}}"
  qt_link="${theme_colors[link.color]:-${qt_highlight}}"
  qt_link_visited="${theme_colors[link.visited.color]:-${qt_link}}"
  qt_placeholder="$(qt_color_with_alpha "${qt_disabled_text}")"
}

build_theme_mode_qt_palette() {
  qt_load_wal_colors || true
  qt_load_theme_palette_roles || return 1

  qt_active_colors="$(qt_join_palette_values \
    "${qt_window_text}" "${qt_button}" "${qt_light}" "${qt_midlight}" "${qt_dark}" "${qt_mid}" \
    "${qt_text}" "${qt_highlight_text}" "${qt_button_text}" "${qt_base}" "${qt_window}" "${qt_dark}" \
    "${qt_highlight}" "${qt_highlight_text}" "${qt_link}" "${qt_link_visited}" "${qt_alternate_base}" \
    "${qt_window}" "${qt_window}" "${qt_tooltip_text}" "${qt_placeholder}")"

  qt_disabled_colors="$(qt_join_palette_values \
    "${qt_disabled_text}" "${qt_button}" "${qt_light}" "${qt_midlight}" "${qt_dark}" "${qt_mid}" \
    "${qt_disabled_text}" "${qt_highlight_text}" "${qt_disabled_text}" "${qt_base}" "${qt_window}" "${qt_dark}" \
    "${qt_inactive_highlight}" "${qt_highlight_text}" "${qt_link}" "${qt_link_visited}" "${qt_alternate_base}" \
    "${qt_window}" "${qt_window}" "${qt_tooltip_text}" "${qt_placeholder}")"

  qt_inactive_colors="$(qt_join_palette_values \
    "${qt_window_text}" "${qt_button}" "${qt_light}" "${qt_midlight}" "${qt_dark}" "${qt_mid}" \
    "${qt_text}" "${qt_highlight_text}" "${qt_button_text}" "${qt_base}" "${qt_window}" "${qt_dark}" \
    "${qt_inactive_highlight}" "${qt_highlight_text}" "${qt_link}" "${qt_link_visited}" "${qt_alternate_base}" \
    "${qt_window}" "${qt_window}" "${qt_tooltip_text}" "${qt_placeholder}")"
}

# shellcheck disable=SC2154
build_wallpaper_mode_qt_palette() {
  qt_load_wal_colors || return 1

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

main() {
  if [[ "${selected_color_mode}" -eq 0 ]]; then
    build_theme_mode_qt_palette || build_wallpaper_mode_qt_palette || exit 1
  else
    build_wallpaper_mode_qt_palette || exit 1
  fi

  qt_scheme_content="$(render_qt_palette_scheme)"

  qt_write_file_if_changed "${QT5_CACHE_SCHEME}" "${qt_scheme_content}" || exit 1
  qt_write_file_if_changed "${QT6_CACHE_SCHEME}" "${qt_scheme_content}" || exit 1
  qt_ensure_scheme_symlink "${QT5_CONFIG_SCHEME}" "${QT5_CACHE_SCHEME}" || exit 1
  qt_ensure_scheme_symlink "${QT6_CONFIG_SCHEME}" "${QT6_CACHE_SCHEME}" || exit 1
}

main

#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/notify.bash" || exit 1

hypr_help_guard "Usage: hyprshell rofi/color-picker [-u|-d]
Pick a screen colour with hyprpicker and save it, newest first; the bar shows the
first saved colour. -u/-d rotate the saved colours to show the previous/next one." "$@"

SAVED_COLOR_LIMIT=10
colors_file="${XDG_CACHE_HOME:-$HOME/.cache}/colorpicker/colors"

notify_color_picker() {
  if command -v dunstify >/dev/null; then
    dunstify -a "Color Picker" -t "${NOTIFY_MS}" "$@"
  else
    echo "$@"
  fi
}

replace_saved_colors() {
  local staged=""
  staged="$(mktemp "${colors_file}.XXXXXX")" || return 1
  printf '%s\n' "$@" >"${staged}" && mv -f -- "${staged}" "${colors_file}"
}

mkdir -p "${colors_file%/*}"
saved_colors=()
[[ -f "${colors_file}" ]] && mapfile -t saved_colors < <(grep -E '^#[0-9a-fA-F]{6}$' "${colors_file}")

case "${1:-}" in
  -u)
    ((${#saved_colors[@]} > 1)) && replace_saved_colors "${saved_colors[-1]}" "${saved_colors[@]:0:${#saved_colors[@]}-1}"
    exit 0
    ;;
  -d)
    ((${#saved_colors[@]} > 1)) && replace_saved_colors "${saved_colors[@]:1}" "${saved_colors[0]}"
    exit 0
    ;;
esac

command -v hyprpicker >/dev/null || {
  notify_color_picker "hyprpicker is not installed"
  exit
}

pkill -u "${UID}" -x hyprpicker >/dev/null 2>&1 || true

picker_stderr="$(mktemp "${TMPDIR:-/tmp}/hyprpicker-stderr.XXXXXX")" || exit 1
color="$(hyprpicker 2>"${picker_stderr}")"
picker_status=$?
picker_error="$(<"${picker_stderr}")"
rm -f "${picker_stderr}"

# Empty output is only silent when the picker was canceled.
if [[ -z "$color" ]]; then
  if [[ "${picker_status}" -eq 0 ]] || [[ "${picker_error}" =~ [Cc]ancel|[Ee]scape ]]; then
    exit 0
  fi
  notify_color_picker "Failed to pick color${picker_error:+: ${picker_error}}"
  exit 1
fi

if [[ ! "$color" =~ ^#[0-9a-fA-F]{6}$ ]]; then
  notify_color_picker "Failed to pick color"
  exit 1
fi

command -v wl-copy >/dev/null && printf '%s' "${color}" | wl-copy
replace_saved_colors "${color}" "${saved_colors[@]:0:SAVED_COLOR_LIMIT-1}"

#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell rofi/color-picker [-l|-j|-u|-d]
Pick a screen colour with hyprpicker; -l lists saved colours, -j emits bar JSON,
-u/-d cycle the displayed colour to the previous/next saved one." "$@"

command_exists() {
  command -v "$1" 1>/dev/null
}

notify_color_picker() {
  command_exists dunstify && {
    dunstify -a "Color Picker" -t 3000 "$@"
    return
  }
  echo "$@"
}

color_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/colorpicker"
[ -d "$color_cache_dir" ] || mkdir -p "$color_cache_dir"
[ -f "$color_cache_dir/colors" ] || touch "$color_cache_dir/colors"

color_index_file="$color_cache_dir/index"
[ -f "$color_index_file" ] || echo 0 >"$color_index_file"

saved_color_limit=10

[[ $# -eq 1 && $1 = "-l" ]] && {
  cat "$color_cache_dir/colors"
  exit
}

[[ $# -eq 1 && ($1 = "-u" || $1 = "-d") ]] && {
  saved_color_count=$(wc -l <"$color_cache_dir/colors")
  if [[ "$saved_color_count" -gt 0 ]]; then
    selected_color_index=$(<"$color_index_file")
    [[ "$selected_color_index" =~ ^[0-9]+$ ]] || selected_color_index=0
    if [[ "$1" = "-u" ]]; then
      selected_color_index=$(((selected_color_index - 1 + saved_color_count) % saved_color_count))
    else
      selected_color_index=$(((selected_color_index + 1) % saved_color_count))
    fi
    echo "$selected_color_index" >"$color_index_file"
  fi
  exit
}

[[ $# -eq 1 && $1 = "-j" ]] && {
  if [ ! -s "$color_cache_dir/colors" ]; then
    echo '{"text":"","tooltip":"Click to pick a color", "class":"empty"}'
    exit
  fi

  mapfile -t saved_colors <"$color_cache_dir/colors"
  saved_color_count=${#saved_colors[@]}

  selected_color_index=$(<"$color_index_file")
  [[ "$selected_color_index" =~ ^[0-9]+$ && "$selected_color_index" -lt "$saved_color_count" ]] || selected_color_index=0

  display_color="${saved_colors[$selected_color_index]}"
  color_tooltip="<b>   COLORS</b>\n\n"
  for color_index in "${!saved_colors[@]}"; do
    saved_color="${saved_colors[$color_index]}"
    if [[ "$color_index" -eq "$selected_color_index" ]]; then
      color_tooltip+="-> <b>$saved_color</b>  <span color='$saved_color'></span>  \n"
    else
      color_tooltip+="   <b>$saved_color</b>  <span color='$saved_color'></span>  \n"
    fi
  done

  cat <<EOF
{ "text":"<span color='$display_color'></span>", "tooltip":"$color_tooltip" ,"class":"filled"}
EOF

  exit
}

command_exists hyprpicker || {
  notify_color_picker "hyprpicker is not installed"
  exit
}

pkill -u "${UID:-$(id -u)}" -x hyprpicker >/dev/null 2>&1 || true

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

command_exists wl-copy && {
  echo "$color" | sed -z 's/\n//g' | wl-copy
}

previous_colors=$(head -n $((saved_color_limit - 1)) "$color_cache_dir/colors")
echo "$color" >"$color_cache_dir/colors"
echo "$previous_colors" >>"$color_cache_dir/colors"
sed -i '/^$/d' "$color_cache_dir/colors"
echo 0 >"$color_index_file"

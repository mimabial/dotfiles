#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell rofi/color-picker [-l|-j|-u|-d]
Pick a screen colour with hyprpicker; -l lists saved colours, -j emits waybar JSON,
-u/-d cycle the displayed colour to the previous/next saved one." "$@"

check() {
  command -v "$1" 1>/dev/null
}

notify() {
  check dunstify && {
    dunstify -a "Color Picker" -t 3000 "$@"
    return
  }
  echo "$@"
}

loc="${XDG_CACHE_HOME:-$HOME/.cache}/colorpicker"
[ -d "$loc" ] || mkdir -p "$loc"
[ -f "$loc/colors" ] || touch "$loc/colors"

idx_file="$loc/index"
[ -f "$idx_file" ] || echo 0 >"$idx_file"

limit=10

[[ $# -eq 1 && $1 = "-l" ]] && {
  cat "$loc/colors"
  exit
}

[[ $# -eq 1 && ($1 = "-u" || $1 = "-d") ]] && {
  count=$(wc -l <"$loc/colors")
  if [[ "$count" -gt 0 ]]; then
    idx=$(<"$idx_file")
    [[ "$idx" =~ ^[0-9]+$ ]] || idx=0
    if [[ "$1" = "-u" ]]; then
      idx=$(((idx - 1 + count) % count))
    else
      idx=$(((idx + 1) % count))
    fi
    echo "$idx" >"$idx_file"
  fi
  pkill -u "${UID:-$(id -u)}" -RTMIN+1 -x waybar
  exit
}

[[ $# -eq 1 && $1 = "-j" ]] && {
  if [ ! -s "$loc/colors" ]; then
    echo '{"text":"","tooltip":"Click to pick a color", "class":"empty"}'
    exit
  fi

  mapfile -t allcolors <"$loc/colors"
  count=${#allcolors[@]}

  idx=$(<"$idx_file")
  [[ "$idx" =~ ^[0-9]+$ && "$idx" -lt "$count" ]] || idx=0

  text="${allcolors[$idx]}"
  tooltip="<b>   COLORS</b>\n\n"
  for i in "${!allcolors[@]}"; do
    c="${allcolors[$i]}"
    if [[ "$i" -eq "$idx" ]]; then
      tooltip+="-> <b>$c</b>  <span color='$c'></span>  \n"
    else
      tooltip+="   <b>$c</b>  <span color='$c'></span>  \n"
    fi
  done

  cat <<EOF
{ "text":"<span color='$text'></span>", "tooltip":"$tooltip" ,"class":"filled"}
EOF

  exit
}

check hyprpicker || {
  notify "hyprpicker is not installed"
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
  notify "Failed to pick color${picker_error:+: ${picker_error}}"
  exit 1
fi

# Validate that we got an actual color (starts with #)
if [[ ! "$color" =~ ^#[0-9a-fA-F]{6}$ ]]; then
  notify "Failed to pick color"
  exit 1
fi

check wl-copy && {
  echo "$color" | sed -z 's/\n//g' | wl-copy
}

prevColors=$(head -n $((limit - 1)) "$loc/colors")
echo "$color" >"$loc/colors"
echo "$prevColors" >>"$loc/colors"
sed -i '/^$/d' "$loc/colors"
echo 0 >"$idx_file"
pkill -u "${UID:-$(id -u)}" -RTMIN+1 -x waybar

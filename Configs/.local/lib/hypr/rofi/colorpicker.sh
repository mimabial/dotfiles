#!/usr/bin/env bash

check() {
  command -v "$1" 1>/dev/null
}

notify() {
  check notify-send && {
    notify-send -a "Color Picker" "$@"
    return
  }
  echo "$@"
}

loc="$HOME/.cache/colorpicker"
[ -d "$loc" ] || mkdir -p "$loc"
[ -f "$loc/colors" ] || touch "$loc/colors"

limit=10

[[ $# -eq 1 && $1 = "-l" ]] && {
  cat "$loc/colors"
  exit
}

[[ $# -eq 1 && $1 = "-j" ]] && {
  if [ ! -s "$loc/colors" ]; then
    echo '{"text":"","tooltip":"Click to pick a color", "class":"empty"}'
    exit
  fi

  text="$(head -n 1 "$loc/colors")"

  mapfile -t allcolors < <(tail -n +2 "$loc/colors")
  # allcolors=($(tail -n +2 "$loc/colors"))
  tooltip="<b>   COLORS</b>\n\n"

  tooltip+="-> <b>$text</b>  <span color='$text'></span>  \n"
  for i in "${allcolors[@]}"; do
    tooltip+="   <b>$i</b>  <span color='$i'></span>  \n"
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

killall -q hyprpicker

# Capture only stdout, discard stderr (the error messages)
color=$(hyprpicker 2>/dev/null)

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
pkill -RTMIN+1 waybar

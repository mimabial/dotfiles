#!/usr/bin/env bash
# Terminal color preview for pywal16

# Source pywal16 colors
if ! source "${HOME}/.cache/wal/colors-shell.sh" 2>/dev/null; then
  echo "Error: pywal16 colors not found"
  exit 1
fi

# Color display function
print_color() {
  local name=$1
  local hex=$2
  # Ensure hex is at least 6 characters
  if [ ${#hex} -lt 6 ]; then
    printf "%-10s %s (invalid)\n" "$name" "#$hex"
    return
  fi
  local r=$((16#${hex:0:2}))
  local g=$((16#${hex:2:2}))
  local b=$((16#${hex:4:2}))
  printf "\e[48;2;%d;%d;%dm  \e[0m %-10s %s\n" "$r" "$g" "$b" "$name" "#$hex"
}

echo "  Pywal16 Color Palette"
echo "#-----------------------------------------------#"
echo ""

echo "Base Colors:"
for i in {0..15}; do
  var="color$i"
  hex="${!var#\#}"
  print_color "color$i" "$hex"
done

echo ""
echo "Special:"
hex="${background#\#}"
print_color "background" "$hex"
hex="${foreground#\#}"
print_color "foreground" "$hex"
hex="${cursor#\#}"
print_color "cursor" "$hex"

echo ""
echo "#-----------------------------------------------#"

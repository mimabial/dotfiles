#!/usr/bin/env bash
# Interactive Nerd Font remover

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

echo "Loading installed fonts..."

# Get installed nerd font packages
installed_fonts=$(pacman -Qq | grep -E "nerd" | sort)

if [[ -z "$installed_fonts" ]]; then
  echo "No Nerd Fonts installed."
  exit 0
fi

# Build fonts array
fonts=()
while IFS= read -r font; do
  fonts+=("$font")
done < <(echo "$installed_fonts")

echo "Found ${#fonts[@]} installed Nerd Fonts"

# Backup for filtering
all_fonts_backup=("${fonts[@]}")

# Get terminal colors once
bg_color="#1a1a1a"
fg_color="#e0e0e0"
if [[ -f ~/.cache/wal/colors.sh ]]; then
  source ~/.cache/wal/colors.sh
  bg_color="${background:-$bg_color}"
  fg_color="${foreground:-$fg_color}"
fi

# Get terminal font size once
font_size="${MONOSPACE_FONT_SIZE:-}"
if [[ -z "$font_size" && -f ~/.config/kitty/kitty.conf ]]; then
  font_size=$(grep -E "^font_size" ~/.config/kitty/kitty.conf | awk '{print $2}' | head -1)
fi
font_size=${font_size:-11}
preview_size=$(awk "BEGIN {printf \"%.0f\", $font_size * 2.5}")

echo "Scanning configs for font usage..."

# Get all fonts referenced in config to detect unused fonts
used_fonts=()
config_dir="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}"

# Search all config files for font references
if [[ -d "$config_dir" ]]; then
  # Look for font family names in all config files
  while IFS= read -r font_ref; do
    # Extract font name from various patterns
    font_name=$(echo "$font_ref" | sed -E 's/.*[fF]ont[_-]?[fF]amily[[:space:]]*[:=][[:space:]]*"?([^",;]+)"?.*/\1/; s/.*[fF]ont[[:space:]]*[:=][[:space:]]*"?([^",;]+)"?.*/\1/')
    [[ -n "$font_name" ]] && used_fonts+=("$font_name")
  done < <(grep -rh -E '([fF]ont[_-]?[fF]amily|[fF]ont)[[:space:]]*[:=]' "$config_dir" 2>/dev/null | grep -v '^[[:space:]]*#')

  # Also check variables
  while IFS= read -r var; do
    font_name=$(echo "$var" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    [[ -n "$font_name" ]] && used_fonts+=("$font_name")
  done < <(grep -rh '^\$MONOSPACE_FONT=' "$config_dir" 2>/dev/null)
fi

# Also check kitty config
if [[ -f ~/.config/kitty/kitty.conf ]]; then
  while IFS= read -r font_line; do
    # Extract everything after 'font_family' keyword
    font_name=$(echo "$font_line" | sed -E 's/^[[:space:]]*font_family[[:space:]]+//')
    [[ -n "$font_name" ]] && used_fonts+=("$font_name")
  done < <(grep -E '^[[:space:]]*font_family' ~/.config/kitty/kitty.conf)
fi

# Remove duplicates (preserve spaces in font names)
if [[ ${#used_fonts[@]} -gt 0 ]]; then
  mapfile -t used_fonts < <(printf '%s\n' "${used_fonts[@]}" | sort -u)
fi

if [[ ${#used_fonts[@]} -gt 0 ]]; then
  echo "Detected ${#used_fonts[@]} font(s) in use: ${used_fonts[*]}"
else
  echo "No fonts detected in config (all fonts will be marked unused)"
fi

# Interactive selection
current=0
selected=()
search_filter=""
show_unused_only=false
previous_pkg=""

show_preview() {
  local pkg="${fonts[$1]}"
  local force_redraw="${2:-false}"

  clear
  echo -e "\033[1;31m=== Nerd Font Remover ===\033[0m"
  [[ -n "$search_filter" ]] && echo -e "\033[1;33mSearch: $search_filter\033[0m"
  [[ "$show_unused_only" == true ]] && echo -e "\033[1;35mFilter: Unused only\033[0m"
  echo

  # Show list of fonts with current highlighted
  echo -e "\033[1mInstalled Fonts:\033[0m"
  local start=$((current - 5))
  local end=$((current + 5))
  [[ $start -lt 0 ]] && start=0
  [[ $end -ge ${#fonts[@]} ]] && end=$((${#fonts[@]} - 1))

  for i in $(seq $start $end); do
    local font_pkg="${fonts[$i]}"
    local marker=""

    # Check if selected for removal
    [[ " ${selected[*]} " =~ " ${font_pkg} " ]] && marker="✗ "

    # Highlight current
    if [[ $i -eq $current ]]; then
      echo -e "  \033[1;32m▶ $marker${fonts[$i]}\033[0m"
    else
      echo -e "    $marker${fonts[$i]}"
    fi
  done
  echo

  # Show font name and check if it's the current font
  font_family=$(echo "$pkg" | sed -E 's/^(ttf-|otf-)//; s/-nerd$//' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1' | sed 's/-/ /g')

  # Check if this font is currently in use
  local in_use_marker=""
  if [[ ${#used_fonts[@]} -gt 0 ]]; then
    # Extract package name from font files
    for font_file in $(pacman -Ql "$pkg" 2>/dev/null | grep -E '\.(ttf|otf)$' | awk '{print $2}'); do
      if [[ -f "$font_file" ]]; then
        font_name=$(fc-query "$font_file" 2>/dev/null | grep "family:" | sed 's/.*family: "\(.*\)"(s)/\1/' | head -1)
        # Check if font name matches any used font
        for used_font in "${used_fonts[@]}"; do
          if [[ "$font_name" == "$used_font" ]]; then
            in_use_marker=" \033[1;32m[IN USE]\033[0m"
            break 2
          fi
        done
      fi
    done
  fi

  echo -e "\033[1;33mPreview: $font_family$in_use_marker\033[0m"
  echo

  # Show rendered preview in Kitty (only if font changed or forced)
  if [[ "$TERM" == "xterm-kitty" ]] && command -v magick &>/dev/null; then
    if [[ "$pkg" != "$previous_pkg" || "$force_redraw" == "true" ]]; then
      echo
      font_file=$(pacman -Ql "$pkg" 2>/dev/null | grep -E '\.(ttf|otf)$' | head -1 | awk '{print $2}')

      if [[ -f "$font_file" ]]; then
        # Calculate preview dimensions
        local term_cols=$(tput cols 2>/dev/null || echo 80)
        local char_width=21
        local char_height=27
        local preview_width=$((term_cols * char_width / 3))
        local preview_height=$((char_height * 3 + 6))

        # Ensure minimum valid dimensions
        [[ $preview_width -lt 100 ]] && preview_width=500
        [[ $preview_height -lt 50 ]] && preview_height=100

        # Calculate tight vertical spacing
        local line_spacing=$((char_height + 2))

        # Generate preview
        local temp_img=$(mktemp --suffix=.png)

        if magick -size ${preview_width}x${preview_height} "xc:$bg_color" \
          -font "$font_file" -pointsize "$preview_size" -fill "$fg_color" \
          -gravity north -annotate +0+3 "abcdefghijklmnopqrstuvwxyz" \
          -font "$font_file" -pointsize "$preview_size" -fill "$fg_color" \
          -gravity north -annotate +0+$((3 + line_spacing)) "ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
          -font "$font_file" -pointsize "$preview_size" -fill "$fg_color" \
          -gravity north -annotate +0+$((3 + line_spacing * 2)) "oO08 iIlL1 g9qCGQ ~-+=>   " \
          "$temp_img" 2>/dev/null && [[ -s "$temp_img" ]]; then

          kitty +kitten icat --align center <"$temp_img" 2>/dev/null && echo
        fi
        rm -f "$temp_img"

        previous_pkg="$pkg"
      fi
    else
      echo -e "\033[2m(Preview cached - same font)\033[0m"
      echo
    fi
  fi

  # Show font variants
  font_count=$(pacman -Ql "$pkg" 2>/dev/null | grep -E '\.(ttf|otf)$' | wc -l)
  echo -e "\033[1mVariants:\033[0m ($font_count files)"

  pacman -Ql "$pkg" 2>/dev/null | grep -E '\.(ttf|otf)$' | head -5 | while read -r line; do
    font_file=$(echo "$line" | awk '{print $2}')
    if [[ -f "$font_file" ]]; then
      style=$(fc-query "$font_file" 2>/dev/null | grep "style:" | sed 's/.*style: "\(.*\)"(s)/\1/' | head -1)
      [[ -n "$style" ]] && echo "  • $style"
    fi
  done
  [[ $font_count -gt 5 ]] && echo "  ... and $((font_count - 5)) more"

  echo
  pacman -Si "$pkg" 2>/dev/null | grep -E "^(Description|Installed Size)" | sed 's/^/  /'

  echo
  echo -e "\033[2m↑/k/↓/j: Navigate  ←/h/→/l: Jump 5  Space: Select  a: Toggle all  /: Search  u: Toggle unused  Esc: Clear  Enter: Remove  q: Quit\033[0m"
  echo -e "\033[2m[${current}/${#fonts[@]}] | Selected: ${#selected[@]}\033[0m"
}

is_font_in_use() {
  local pkg="$1"
  [[ ${#used_fonts[@]} -eq 0 ]] && return 1

  for font_file in $(pacman -Ql "$pkg" 2>/dev/null | grep -E '\.(ttf|otf)$' | awk '{print $2}'); do
    if [[ -f "$font_file" ]]; then
      font_name=$(fc-query "$font_file" 2>/dev/null | grep "family:" | sed 's/.*family: "\(.*\)"(s)/\1/' | head -1)
      # Check if font name matches any used font
      for used_font in "${used_fonts[@]}"; do
        if [[ "$font_name" == "$used_font" ]]; then
          return 0
        fi
      done
    fi
  done
  return 1
}

apply_filter() {
  current=0
  filtered_fonts=()

  # Start with all fonts or search results
  local base_fonts=()
  if [[ -z "$search_filter" ]]; then
    base_fonts=("${all_fonts_backup[@]}")
  else
    for font in "${all_fonts_backup[@]}"; do
      [[ "${font,,}" =~ "${search_filter,,}" ]] && base_fonts+=("$font")
    done
  fi

  # Apply unused filter if enabled
  if [[ "$show_unused_only" == true ]]; then
    # Show loading message at bottom of screen
    echo -ne "\033[s" # Save cursor position
    tput cup $(($(tput lines) - 1)) 0
    echo -ne "\033[2KScanning fonts for usage...\033[u" # Clear line, show message, restore cursor

    # Save terminal settings and disable echo to prevent input display
    local old_tty_settings=$(stty -g)
    stty -echo 2>/dev/null

    # Flush any queued input to prevent keypresses during scan
    read -t 0.001 -n 10000 discard </dev/tty 2>/dev/null || true

    for font in "${base_fonts[@]}"; do
      if ! is_font_in_use "$font"; then
        filtered_fonts+=("$font")
      fi
    done
    fonts=("${filtered_fonts[@]}")

    # Flush input again after scan completes
    read -t 0.001 -n 10000 discard </dev/tty 2>/dev/null || true

    # Restore terminal settings
    stty "$old_tty_settings" 2>/dev/null

    # Clear the loading message
    tput cup $(($(tput lines) - 1)) 0
    echo -ne "\033[2K"
  else
    fonts=("${base_fonts[@]}")
  fi

  # Fallback to all fonts if no results
  [[ ${#fonts[@]} -eq 0 ]] && fonts=("${all_fonts_backup[@]}")
}

# Main loop
while true; do
  show_preview $current

  # Read single key from terminal directly
  IFS= read -rsn1 key </dev/tty

  case "$key" in
    $'\x1b') # ESC sequence (arrow keys or ESC to clear filter)
      read -rsn2 -t 0.1 key </dev/tty
      if [[ -z "$key" ]]; then
        # Just ESC pressed - clear all filters
        search_filter=""
        show_unused_only=false
        apply_filter
      else
        # Arrow keys
        case "$key" in
          '[A') [[ $current -gt 0 ]] && current=$((current - 1)) ;;                     # Up
          '[B') [[ $current -lt $((${#fonts[@]} - 1)) ]] && current=$((current + 1)) ;; # Down
          '[D')                                                                         # Left - jump up 5
            new_pos=$((current - 5))
            [[ $new_pos -lt 0 ]] && new_pos=0
            current=$new_pos
            ;;
          '[C') # Right - jump down 5
            new_pos=$((current + 5))
            [[ $new_pos -ge ${#fonts[@]} ]] && new_pos=$((${#fonts[@]} - 1))
            current=$new_pos
            ;;
        esac
      fi
      ;;
    $'\n' | '') # Enter - remove
      [[ ${#selected[@]} -eq 0 ]] && selected+=("${fonts[$current]}")
      selected=("${selected[@]## }")
      break
      ;;
    ' ') # Space - toggle selection
      pkg="${fonts[$current]}"
      pkg="${pkg## }"

      if [[ " ${selected[*]} " =~ " ${pkg} " ]]; then
        # Remove from array
        new_selected=()
        for item in "${selected[@]}"; do
          [[ "$item" != "$pkg" ]] && new_selected+=("$item")
        done
        selected=("${new_selected[@]}")
      else
        selected+=("$pkg")
      fi
      ;;
    'a') # Toggle all visible fonts
      # Show loading message
      tput cup $(($(tput lines) - 1)) 0
      echo -ne "\033[2KSelecting fonts..."

      if [[ ${#selected[@]} -eq ${#fonts[@]} ]]; then
        # All selected - deselect all
        selected=()
      else
        # Select all visible fonts
        selected=()
        for font in "${fonts[@]}"; do
          selected+=("$font")
        done
      fi

      # Clear loading message
      tput cup $(($(tput lines) - 1)) 0
      echo -ne "\033[2K"
      ;;
    'k') [[ $current -gt 0 ]] && current=$((current - 1)) ;;
    'j') [[ $current -lt $((${#fonts[@]} - 1)) ]] && current=$((current + 1)) ;;
    'h') # h - jump up 5
      new_pos=$((current - 5))
      [[ $new_pos -lt 0 ]] && new_pos=0
      current=$new_pos
      ;;
    'l') # l - jump down 5
      new_pos=$((current + 5))
      [[ $new_pos -ge ${#fonts[@]} ]] && new_pos=$((${#fonts[@]} - 1))
      current=$new_pos
      ;;
    '/') # Search
      echo -ne "\033[2K\rSearch: "
      read -r search_filter
      apply_filter
      ;;
    'u') # Toggle unused only filter
      if [[ "$show_unused_only" == true ]]; then
        show_unused_only=false
      else
        show_unused_only=true
      fi
      apply_filter
      ;;
    'q')
      clear
      echo "Cancelled."
      exit 0
      ;;
    *)
      continue
      ;;
  esac
done

clear

# Remove selected fonts
if [[ ${#selected[@]} -gt 0 ]]; then
  echo -e "\033[1;31mRemoving ${#selected[@]} font(s):\033[0m"
  for font in "${selected[@]}"; do
    echo "  - $font"
  done
  echo

  read -n 1 -s -r -p "Press Enter to confirm removal or Ctrl+C to cancel..."
  echo
  echo

  if sudo pacman -Rns --noconfirm "${selected[@]}"; then
    echo
    echo "Refreshing font cache..."

    # Disable echo during cache refresh to prevent escape sequences
    old_tty_settings=$(stty -g)
    stty -echo 2>/dev/null

    # Flush input before and after
    read -t 0.001 -n 10000 discard </dev/tty 2>/dev/null || true
    fc-cache -f
    read -t 0.001 -n 10000 discard </dev/tty 2>/dev/null || true

    # Restore terminal settings
    stty "$old_tty_settings" 2>/dev/null

    echo "✓ Font removal complete!"
    echo "  Removed: ${selected[*]}"
  else
    echo
    echo "✗ Font removal cancelled or failed."
    exit 1
  fi
else
  echo "No fonts selected."
fi

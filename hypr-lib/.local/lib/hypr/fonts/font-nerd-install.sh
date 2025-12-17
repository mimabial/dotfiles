#!/usr/bin/env bash
# Nerd Font installer with preview

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

# Get all nerd font packages
all_fonts=$(pacman -Sl | grep -E "nerd" | awk '{print $2}' | sort -u)
installed_fonts=$(pacman -Qq | grep -E "nerd" | sort)

# Combine into array with status
fonts=()
while IFS= read -r font; do
  if pacman -Q "$font" &>/dev/null; then
    fonts+=("$font ✓")
  else
    fonts+=("$font")
  fi
done < <(echo "$all_fonts")

# Backup for filtering
all_fonts_backup=("${fonts[@]}")

# Get terminal colors once (cached)
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

# Interactive selection with actual font preview
current=0
selected=()
search_filter=""
previous_pkg=""  # Track last rendered font to avoid redundant redraws

show_preview() {
  local pkg="${fonts[$1]%% *}" # Remove ✓ marker
  local force_redraw="${2:-false}"  # Optional parameter to force preview regeneration

  clear
  echo -e "\033[1;36m=== Nerd Font Installer ===\033[0m"
  [[ -n "$search_filter" ]] && echo -e "\033[1;33mSearch: $search_filter\033[0m"
  echo

  # Show list of fonts with current highlighted
  echo -e "\033[1mAvailable Fonts:\033[0m"
  local start=$((current - 5))
  local end=$((current + 5))
  [[ $start -lt 0 ]] && start=0
  [[ $end -ge ${#fonts[@]} ]] && end=$((${#fonts[@]} - 1))

  for i in $(seq $start $end); do
    local font_pkg="${fonts[$i]%% *}"
    local marker=""

    # Check if selected
    [[ " ${selected[*]} " =~ " ${font_pkg} " ]] && marker="▶ "

    # Highlight current
    if [[ $i -eq $current ]]; then
      echo -e "  \033[1;32m▶ $marker${fonts[$i]}\033[0m"
    else
      echo -e "    $marker${fonts[$i]}"
    fi
  done
  echo

  # Show font name
  font_family=$(echo "$pkg" | sed -E 's/^(ttf-|otf-)//; s/-nerd$//' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1' | sed 's/-/ /g')
  local is_installed=false
  pacman -Q "$pkg" &>/dev/null && is_installed=true

  if $is_installed; then
    echo -e "\033[1;33mPreview: $font_family [INSTALLED]\033[0m"
  else
    echo -e "\033[1;33mPreview: $font_family\033[0m"
  fi
  echo

  # Show font info and preview
  if $is_installed; then
    # Try to show rendered preview in Kitty (only if font changed or forced)
    if [[ "$TERM" == "xterm-kitty" ]] && command -v magick &>/dev/null; then
      if [[ "$pkg" != "$previous_pkg" || "$force_redraw" == "true" ]]; then
        echo  # Add blank line before preview
        font_file=$(pacman -Ql "$pkg" 2>/dev/null | grep -E '\.(ttf|otf)$' | head -1 | awk '{print $2}')

        if [[ -f "$font_file" ]]; then
          # Calculate preview dimensions (use cached font size)
          local term_cols=$(tput cols 2>/dev/null || echo 80)

          # Use fixed character dimensions (avoid expensive magick queries)
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

            # Use stdin to avoid file access race conditions
            kitty +kitten icat --align center <"$temp_img" 2>/dev/null && echo
          fi
          rm -f "$temp_img"

          previous_pkg="$pkg"  # Update cache
        fi
      else
        # Skip preview regeneration - font hasn't changed
        echo -e "\033[2m(Preview cached - same font)\033[0m"
        echo
      fi
    fi

    # Show installed font variants (cache this data)
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
  else
    echo -e "\033[2mNot installed\033[0m"
    echo
    pacman -Si "$pkg" 2>/dev/null | grep -E "^(Description|Download Size)" | sed 's/^/  /'
    previous_pkg="$pkg"  # Update even for uninstalled fonts
  fi

  echo
  echo -e "\033[2m↑/k/↓/j: Navigate  ←/h/→/l: Jump 5  Space: Select  /: Search  Esc: Clear  Enter: Install  q: Quit\033[0m"
  echo -e "\033[2m[${current}/${#fonts[@]}] | Selected: ${#selected[@]}\033[0m"
}

apply_filter() {
  current=0
  filtered_fonts=()

  if [[ -z "$search_filter" ]]; then
    fonts=("${all_fonts_backup[@]}")
  else
    for font in "${all_fonts_backup[@]}"; do
      [[ "${font,,}" =~ "${search_filter,,}" ]] && filtered_fonts+=("$font")
    done
    fonts=("${filtered_fonts[@]}")
    [[ ${#fonts[@]} -eq 0 ]] && fonts=("${all_fonts_backup[@]}") # No matches, show all
  fi
}

# Main loop
while true; do
  show_preview $current

  # Read single key - use 'read' from terminal directly, not from stdin which has escape codes
  IFS= read -rsn1 key </dev/tty

  case "$key" in
    $'\x1b') # ESC sequence (arrow keys or ESC to clear filter)
      read -rsn2 -t 0.1 key </dev/tty
      if [[ -z "$key" ]]; then
        # Just ESC pressed - clear filter
        search_filter=""
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
    $'\n' | '') # Enter - install
      [[ ${#selected[@]} -eq 0 ]] && selected+=("${fonts[$current]%% ✓}")
      selected=("${selected[@]## }") # Clean up
      break
      ;;
    ' ') # Space - toggle selection
      # Get the package name without ✓ marker or status
      pkg="${fonts[$current]}"
      pkg="${pkg%% ✓}" # Remove " ✓" if present
      pkg="${pkg## }"  # Remove leading spaces

      if [[ " ${selected[*]} " =~ " ${pkg} " ]]; then
        # Remove from array properly
        new_selected=()
        for item in "${selected[@]}"; do
          [[ "$item" != "$pkg" ]] && new_selected+=("$item")
        done
        selected=("${new_selected[@]}")
      else
        selected+=("$pkg")
      fi
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
    'q')
      clear
      echo "Cancelled."
      exit 0
      ;;
    *) # Ignore unknown keys
      continue
      ;;
  esac
done

clear

# Install selected fonts
if [[ ${#selected[@]} -gt 0 ]]; then
  echo "Installing ${#selected[@]} font(s): ${selected[*]}"
  echo

  if sudo pacman -S --needed --noconfirm "${selected[@]}"; then
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

    echo "✓ Font installation complete!"
    echo "  Installed: ${selected[*]}"
  else
    echo
    echo "✗ Font installation cancelled or failed."
    exit 1
  fi
else
  echo "No fonts selected."
fi

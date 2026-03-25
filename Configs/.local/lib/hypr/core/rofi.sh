#!/usr/bin/env bash
# shellcheck disable=SC1091,SC1090

rofi_user_dir() {
  printf '%s\n' "${XDG_CONFIG_HOME}/rofi"
}

rofi_shared_dir() {
  printf '%s\n' "${XDG_DATA_HOME}/rofi"
}

rofi_resolve_theme() {
  local ref="$1"
  local user_dir shared_dir
  user_dir="$(rofi_user_dir)"
  shared_dir="$(rofi_shared_dir)"

  [[ -n "${ref}" ]] || return 1

  if [[ -f "${ref}" ]]; then
    printf '%s\n' "${ref}"
    return 0
  fi

  local candidate
  for candidate in \
    "${user_dir}/themes/${ref}.rasi" \
    "${user_dir}/themes/${ref}" \
    "${user_dir}/${ref}.rasi" \
    "${user_dir}/${ref}" \
    "${shared_dir}/themes/${ref}.rasi" \
    "${shared_dir}/themes/${ref}" \
    "${shared_dir}/${ref}.rasi" \
    "${shared_dir}/${ref}"
  do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf '%s\n' "${shared_dir}/themes/${ref}.rasi"
  return 1
}

rofi_resolve_asset() {
  local ref="$1"
  local user_dir shared_dir
  user_dir="$(rofi_user_dir)"
  shared_dir="$(rofi_shared_dir)"

  [[ -n "${ref}" ]] || return 1

  if [[ -f "${ref}" ]]; then
    printf '%s\n' "${ref}"
    return 0
  fi

  local candidate
  for candidate in \
    "${user_dir}/assets/${ref}" \
    "${user_dir}/${ref}" \
    "${shared_dir}/assets/${ref}" \
    "${shared_dir}/${ref}"
  do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf '%s\n' "${shared_dir}/assets/${ref}"
  return 1
}

rofi_list_theme_files() {
  local -A seen=()
  local dir file base

  for dir in "$(rofi_user_dir)/themes" "$(rofi_shared_dir)/themes"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r file; do
      base="$(basename "${file}")"
      [[ -n "${seen[${base}]:-}" ]] && continue
      seen["${base}"]=1
      printf '%s\n' "${file}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name '*.rasi' | sort)
  done
}

rofi_list_asset_files() {
  local pattern="${1:-*}"
  local -A seen=()
  local dir file base

  for dir in "$(rofi_user_dir)/assets" "$(rofi_shared_dir)/assets"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r file; do
      base="$(basename "${file}")"
      [[ -n "${seen[${base}]:-}" ]] && continue
      seen["${base}"]=1
      printf '%s\n' "${file}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name "${pattern}" | sort)
  done
}

# launcher spawn location (wofi/rofi)
get_rofi_pos() {
  local window_width="${1:-0}"  # Window width in pixels (optional)
  local window_height="${2:-0}" # Window height in pixels (optional)

  # Auto-calculate clipboard theme dimensions if no size provided
  if [ "$window_width" -eq 0 ] && [ "$window_height" -eq 0 ]; then
    # Wofi doesn't have -dump-theme, use fallback defaults
    local font_scale="${ROFI_SCALE:-10}"
    window_width=$((23 * font_scale * 2))
    window_height=$((30 * font_scale * 2))
  fi

  readarray -t curPos < <(hyprctl cursorpos -j | jq -r '.x,.y')
  eval "$(hyprctl -j monitors | jq -r '.[] | select(.focused==true) |
        "monRes=(\(.width) \(.height) \(.scale) \(.x) \(.y)) offRes=(\(.reserved | join(" ")))"')"

  monRes[2]="${monRes[2]//./}"
  monRes[0]=$((monRes[0] * 100 / monRes[2]))
  monRes[1]=$((monRes[1] * 100 / monRes[2]))
  curPos[0]=$((curPos[0] - monRes[3]))
  curPos[1]=$((curPos[1] - monRes[4]))
  offRes=("${offRes// / }")

  # Calculate available space and determine anchor
  local edge_padding=10 # Minimum distance from screen edges
  local available_right=$((monRes[0] - curPos[0] - offRes[2]))
  local available_left=$((curPos[0] - offRes[0]))
  local available_bottom=$((monRes[1] - curPos[1] - offRes[3]))
  local available_top=$((curPos[1] - offRes[1]))
  local usable_width=$((monRes[0] - offRes[0] - offRes[2]))
  local usable_height=$((monRes[1] - offRes[1] - offRes[3]))
  [ "$usable_width" -lt $((edge_padding * 2)) ] && usable_width=$((edge_padding * 2))
  [ "$usable_height" -lt $((edge_padding * 2)) ] && usable_height=$((edge_padding * 2))

  # Calculate max safe offset to prevent window from going off screen
  local max_safe_right=$((usable_width - window_width - edge_padding))
  local max_safe_bottom=$((usable_height - window_height - edge_padding))
  [ "$max_safe_right" -lt "$edge_padding" ] && max_safe_right="$edge_padding"
  [ "$max_safe_bottom" -lt "$edge_padding" ] && max_safe_bottom="$edge_padding"

  # X positioning with overflow prevention
  if [ "$window_width" -gt 0 ]; then
    if [ "$available_right" -ge "$window_width" ]; then
      # Enough space on the right - stick to cursor
      local x_pos="west"
      local x_off="$((curPos[0] - offRes[0]))"
      [ "$x_off" -lt "$edge_padding" ] && x_off="$edge_padding"
      [ "$x_off" -gt "$max_safe_right" ] && x_off="$max_safe_right"
    elif [ "$available_left" -ge "$window_width" ]; then
      # Enough space on the left - stick to cursor
      local x_pos="east"
      local abs_x_off=$((monRes[0] - curPos[0] - offRes[2]))
      local x_off
      [ "$abs_x_off" -lt "$edge_padding" ] && abs_x_off="$edge_padding"
      if [ "$abs_x_off" -gt "$max_safe_right" ]; then
        x_off="-$max_safe_right"
      else
        x_off="-$abs_x_off"
      fi
    else
      # Not enough space either side, use the side with more space
      if [ "$available_right" -ge "$available_left" ]; then
        local x_pos="west"
        local x_off="$edge_padding" # Stick to left edge with padding
      else
        local x_pos="east"
        local x_off="-$edge_padding" # Stick to right edge with padding
      fi
    fi
  else
    # Fallback to quadrant-based positioning
    if [ "${curPos[0]}" -ge "$((monRes[0] / 2))" ]; then
      local x_pos="east"
      local x_off="-$((monRes[0] - curPos[0] - offRes[2]))"
    else
      local x_pos="west"
      local x_off="$((curPos[0] - offRes[0]))"
    fi
  fi

  # Y positioning with overflow prevention
  if [ "$window_height" -gt 0 ]; then
    if [ "$available_bottom" -ge "$window_height" ]; then
      # Enough space below - stick to cursor
      local y_pos="north"
      local y_off="$((curPos[1] - offRes[1]))"
      [ "$y_off" -lt "$edge_padding" ] && y_off="$edge_padding"
      [ "$y_off" -gt "$max_safe_bottom" ] && y_off="$max_safe_bottom"
    elif [ "$available_top" -ge "$window_height" ]; then
      # Enough space above - stick to cursor
      local y_pos="south"
      local abs_y_off=$((monRes[1] - curPos[1] - offRes[3]))
      local y_off
      [ "$abs_y_off" -lt "$edge_padding" ] && abs_y_off="$edge_padding"
      if [ "$abs_y_off" -gt "$max_safe_bottom" ]; then
        y_off="-$max_safe_bottom"
      else
        y_off="-$abs_y_off"
      fi
    else
      # Not enough space either direction, use the side with more space
      if [ "$available_bottom" -ge "$available_top" ]; then
        local y_pos="north"
        local y_off="$edge_padding" # Stick to top edge with padding
      else
        local y_pos="south"
        local y_off="-$edge_padding" # Stick to bottom edge with padding
      fi
    fi
  else
    # Fallback to quadrant-based positioning
    if [ "${curPos[1]}" -ge "$((monRes[1] / 2))" ]; then
      local y_pos="south"
      local y_off="-$((monRes[1] - curPos[1] - offRes[3]))"
    else
      local y_pos="north"
      local y_off="$((curPos[1] - offRes[1]))"
    fi
  fi

  local coordinates="window{location:${x_pos} ${y_pos};anchor:${x_pos} ${y_pos};x-offset:${x_off}px;y-offset:${y_off}px;}"
  echo "${coordinates}"
}

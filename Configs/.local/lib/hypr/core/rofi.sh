#!/usr/bin/env bash

rofi_user_dir() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/rofi"
}

rofi_shared_dir() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/rofi"
}

rofi_lookup_dirs() {
  case "${1}" in
    theme)
      printf '%s\n' \
        "$(rofi_user_dir)/themes" \
        "$(rofi_user_dir)" \
        "$(rofi_shared_dir)/themes" \
        "$(rofi_shared_dir)"
      ;;
    asset)
      printf '%s\n' \
        "$(rofi_user_dir)/assets" \
        "$(rofi_user_dir)" \
        "$(rofi_shared_dir)/assets" \
        "$(rofi_shared_dir)"
      ;;
    *)
      return 1
      ;;
  esac
}

rofi_resolve_file() {
  local kind="$1"
  local ref="$2"
  local dir=""
  local candidate=""
  local -a lookup_dirs=()

  [[ -n "${ref}" ]] || return 1
  [[ -f "${ref}" ]] && {
    printf '%s\n' "${ref}"
    return 0
  }

  mapfile -t lookup_dirs < <(rofi_lookup_dirs "${kind}")
  for dir in "${lookup_dirs[@]}"; do
    [[ -n "${dir}" ]] || continue
    case "${kind}" in
      theme)
        for candidate in "${dir}/${ref}.rasi" "${dir}/${ref}"; do
          [[ -f "${candidate}" ]] || continue
          printf '%s\n' "${candidate}"
          return 0
        done
        ;;
      asset)
        candidate="${dir}/${ref}"
        [[ -f "${candidate}" ]] || continue
        printf '%s\n' "${candidate}"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  done

  case "${kind}" in
    theme) printf '%s\n' "$(rofi_shared_dir)/themes/${ref}.rasi" ;;
    asset) printf '%s\n' "$(rofi_shared_dir)/assets/${ref}" ;;
  esac
  return 1
}

rofi_list_files() {
  local kind="$1"
  local pattern="${2:-*}"
  local dir=""
  local file=""
  local base=""
  local -A seen=()

  while IFS= read -r dir; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r file; do
      base="$(basename "${file}")"
      [[ -n "${seen[${base}]:-}" ]] && continue
      seen["${base}"]=1
      printf '%s\n' "${file}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name "${pattern}" | sort)
  done < <(
    case "${kind}" in
      theme) printf '%s\n%s\n' "$(rofi_user_dir)/themes" "$(rofi_shared_dir)/themes" ;;
      asset) printf '%s\n%s\n' "$(rofi_user_dir)/assets" "$(rofi_shared_dir)/assets" ;;
      *) return 1 ;;
    esac
  )
}

rofi_resolve_theme() {
  rofi_resolve_file theme "$1"
}

rofi_resolve_asset() {
  rofi_resolve_file asset "$1"
}

rofi_list_theme_files() {
  rofi_list_files theme '*.rasi'
}

rofi_list_asset_files() {
  rofi_list_files asset "${1:-*}"
}

rofi_focused_monitor_record() {
  hyprctl -j monitors 2>/dev/null | jq -r '
    .[] | select(.focused==true) |
    [
      (if (.transform % 2 == 0) then .width else .height end),
      (if (.transform % 2 == 0) then .height else .width end),
      (.scale // 1),
      .x,
      .y,
      .reserved[0],
      .reserved[1],
      .reserved[2],
      .reserved[3]
    ] | @tsv
  ' 2>/dev/null | head -n 1
}

rofi_default_window_size() {
  local width_name="$1"
  local height_name="$2"
  local -n width_ref="${width_name}"
  local -n height_ref="${height_name}"
  local font_scale="${ROFI_SCALE:-10}"

  if [[ "${width_ref}" -eq 0 && "${height_ref}" -eq 0 ]]; then
    width_ref=$((23 * font_scale * 2))
    height_ref=$((30 * font_scale * 2))
  fi
}

rofi_cursor_local_position() {
  local x_name="$1"
  local y_name="$2"
  local mon_x="$3"
  local mon_y="$4"
  local -n x_ref="${x_name}"
  local -n y_ref="${y_name}"
  local -a cursor_pos=(0 0)

  readarray -t cursor_pos < <(hyprctl cursorpos -j 2>/dev/null | jq -r '.x,.y' 2>/dev/null)
  [[ "${cursor_pos[0]:-}" =~ ^-?[0-9]+$ ]] || cursor_pos[0]=0
  [[ "${cursor_pos[1]:-}" =~ ^-?[0-9]+$ ]] || cursor_pos[1]=0

  x_ref=$((cursor_pos[0] - mon_x))
  y_ref=$((cursor_pos[1] - mon_y))
}

rofi_monitor_logical_geometry() {
  local width_name="$1"
  local height_name="$2"
  local x_name="$3"
  local y_name="$4"
  local reserve_name="$5"
  local monitor_line=""
  local mon_width="" mon_height="" mon_scale="" mon_x="" mon_y="" off_left="" off_top="" off_right="" off_bottom=""
  local -n width_ref="${width_name}"
  local -n height_ref="${height_name}"
  local -n x_ref="${x_name}"
  local -n y_ref="${y_name}"
  local -n reserve_ref="${reserve_name}"

  monitor_line="$(rofi_focused_monitor_record)"
  [[ -n "${monitor_line}" ]] || return 1

  IFS=$'\t' read -r mon_width mon_height mon_scale mon_x mon_y off_left off_top off_right off_bottom <<<"${monitor_line}"
  [[ "${mon_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] || mon_scale=1

  width_ref="$(awk -v w="${mon_width}" -v s="${mon_scale}" 'BEGIN { if (s <= 0) s = 1; v = int(w / s); if (v < 1) v = 1; print v }')"
  height_ref="$(awk -v h="${mon_height}" -v s="${mon_scale}" 'BEGIN { if (s <= 0) s = 1; v = int(h / s); if (v < 1) v = 1; print v }')"
  x_ref="${mon_x}"
  y_ref="${mon_y}"
  reserve_ref=("${off_left}" "${off_top}" "${off_right}" "${off_bottom}")
}

rofi_axis_position() {
  local cursor_pos="$1"
  local span="$2"
  local reserve_start="$3"
  local reserve_end="$4"
  local window_size="$5"
  local positive_dir="$6"
  local negative_dir="$7"
  local pos_name="$8"
  local off_name="$9"
  local -n pos_ref="${pos_name}"
  local -n off_ref="${off_name}"
  local edge_padding=10
  local available_positive=$((span - cursor_pos - reserve_end))
  local available_negative=$((cursor_pos - reserve_start))
  local usable_span=$((span - reserve_start - reserve_end))
  local max_safe_positive=0
  local abs_offset=0

  (( usable_span < edge_padding * 2 )) && usable_span=$((edge_padding * 2))
  max_safe_positive=$((usable_span - window_size - edge_padding))
  (( max_safe_positive < edge_padding )) && max_safe_positive="${edge_padding}"

  if (( window_size > 0 )); then
    if (( available_positive >= window_size )); then
      pos_ref="${positive_dir}"
      off_ref="$((cursor_pos - reserve_start))"
      (( off_ref < edge_padding )) && off_ref="${edge_padding}"
      (( off_ref > max_safe_positive )) && off_ref="${max_safe_positive}"
      return 0
    fi

    if (( available_negative >= window_size )); then
      pos_ref="${negative_dir}"
      abs_offset=$((span - cursor_pos - reserve_end))
      (( abs_offset < edge_padding )) && abs_offset="${edge_padding}"
      (( abs_offset > max_safe_positive )) && abs_offset="${max_safe_positive}"
      off_ref="-$abs_offset"
      return 0
    fi

    if (( available_positive >= available_negative )); then
      pos_ref="${positive_dir}"
      off_ref="${edge_padding}"
    else
      pos_ref="${negative_dir}"
      off_ref="-$edge_padding"
    fi
    return 0
  fi

  if (( cursor_pos >= span / 2 )); then
    pos_ref="${negative_dir}"
    off_ref="-$((span - cursor_pos - reserve_end))"
  else
    pos_ref="${positive_dir}"
    off_ref="$((cursor_pos - reserve_start))"
  fi
}

# launcher spawn location (wofi/rofi)
get_rofi_pos() {
  local window_width="${1:-0}"
  local window_height="${2:-0}"
  local mon_width=0 mon_height=0 mon_x=0 mon_y=0
  local cursor_x=0 cursor_y=0
  local -a mon_reserved=(0 0 0 0)
  local x_pos="" x_off="" y_pos="" y_off=""

  rofi_default_window_size window_width window_height
  rofi_monitor_logical_geometry mon_width mon_height mon_x mon_y mon_reserved || return 1
  rofi_cursor_local_position cursor_x cursor_y "${mon_x}" "${mon_y}"
  rofi_axis_position "${cursor_x}" "${mon_width}" "${mon_reserved[0]}" "${mon_reserved[2]}" "${window_width}" west east x_pos x_off
  rofi_axis_position "${cursor_y}" "${mon_height}" "${mon_reserved[1]}" "${mon_reserved[3]}" "${window_height}" north south y_pos y_off

  printf 'window{location:%s %s;anchor:%s %s;x-offset:%spx;y-offset:%spx;}\n' \
    "${x_pos}" "${y_pos}" "${x_pos}" "${y_pos}" "${x_off}" "${y_off}"
}

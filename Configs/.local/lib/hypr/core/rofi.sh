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

rofi_cursor_raw_position() {
  local x_name="$1"
  local y_name="$2"
  local -n x_ref="${x_name}"
  local -n y_ref="${y_name}"
  local -a cursor_pos=(0 0)

  readarray -t cursor_pos < <(hyprctl cursorpos -j 2>/dev/null | jq -r '.x,.y' 2>/dev/null)
  [[ "${cursor_pos[0]:-}" =~ ^-?[0-9]+$ ]] || cursor_pos[0]=0
  [[ "${cursor_pos[1]:-}" =~ ^-?[0-9]+$ ]] || cursor_pos[1]=0

  x_ref="${cursor_pos[0]}"
  y_ref="${cursor_pos[1]}"
}

rofi_monitor_record() {
  local mode="${1:-focused}"
  local monitors_json=""
  local cursor_x=0
  local cursor_y=0
  local -a jq_args=(--arg mode "${mode}" --argjson cx 0 --argjson cy 0)

  if [[ "${mode}" == "cursor" ]]; then
    rofi_cursor_raw_position cursor_x cursor_y
    jq_args=(--arg mode "${mode}" --argjson cx "${cursor_x}" --argjson cy "${cursor_y}")
  fi

  if declare -F rofi_monitors_json >/dev/null 2>&1; then
    monitors_json="$(rofi_monitors_json)"
  else
    monitors_json="$(hyprctl -j monitors 2>/dev/null || true)"
  fi

  printf '%s\n' "${monitors_json}" | jq -r "${jq_args[@]}" '
    def monitor_width: if (.transform % 2 == 0) then .width else .height end;
    def monitor_height: if (.transform % 2 == 0) then .height else .width end;
    def record: [
      monitor_width,
      monitor_height,
      (.scale // 1),
      (.x // 0),
      (.y // 0),
      (.reserved[0] // 0),
      (.reserved[1] // 0),
      (.reserved[2] // 0),
      (.reserved[3] // 0)
    ] | @tsv;

    if $mode == "cursor" then
      (
        .[] | select(
          ($cx >= .x) and
          ($cx < (.x + monitor_width)) and
          ($cy >= .y) and
          ($cy < (.y + monitor_height))
        )
      ),
      (.[] | select(.focused==true))
      | record
    else
      .[] | select(.focused==true) | record
    end
  ' 2>/dev/null | head -n 1
}

rofi_focused_monitor_record() {
  rofi_monitor_record focused
}

rofi_cursor_monitor_record() {
  rofi_monitor_record cursor
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

rofi_scale_milli() {
  local scale="${1:-1}"
  local whole="0"
  local fraction="000"

  if [[ "${scale}" =~ ^([0-9]+)([.][0-9]+)?$ ]]; then
    whole="${BASH_REMATCH[1]}"
    if [[ -n "${BASH_REMATCH[2]:-}" ]]; then
      fraction="${BASH_REMATCH[2]#.}"
      fraction="${fraction}000"
      fraction="${fraction:0:3}"
    fi
  fi

  if [[ "${whole}${fraction}" =~ ^0+$ ]]; then
    printf '1000\n'
    return 0
  fi

  printf '%s\n' "$((10#${whole} * 1000 + 10#${fraction}))"
}

rofi_scaled_divide() {
  local value="${1:-0}"
  local scale="${2:-1}"
  local min_value="${3:-}"
  local scale_milli=""
  local result=0

  [[ "${value}" =~ ^-?[0-9]+$ ]] || value=0
  scale_milli="$(rofi_scale_milli "${scale}")"
  result=$((value * 1000 / scale_milli))

  if [[ -n "${min_value}" ]] && [[ "${result}" -lt "${min_value}" ]]; then
    result="${min_value}"
  fi

  printf '%s\n' "${result}"
}

rofi_cursor_monitor_geometry() {
  local width_name="$1"
  local height_name="$2"
  local scale_name="$3"
  local x_name="$4"
  local y_name="$5"
  local reserve_name="$6"
  local monitor_line=""
  local parsed_width="" parsed_height="" parsed_scale="" parsed_x="" parsed_y="" off_left="" off_top="" off_right="" off_bottom=""
  local -n width_ref="${width_name}"
  local -n height_ref="${height_name}"
  local -n scale_ref="${scale_name}"
  local -n x_ref="${x_name}"
  local -n y_ref="${y_name}"
  local -n reserve_ref="${reserve_name}"

  monitor_line="$(rofi_cursor_monitor_record)"
  [[ -n "${monitor_line}" ]] || return 1

  IFS=$'\t' read -r parsed_width parsed_height parsed_scale parsed_x parsed_y off_left off_top off_right off_bottom <<<"${monitor_line}"
  [[ "${parsed_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] || parsed_scale=1

  width_ref="$(rofi_scaled_divide "${parsed_width}" "${parsed_scale}" 1)"
  height_ref="$(rofi_scaled_divide "${parsed_height}" "${parsed_scale}" 1)"
  scale_ref="${parsed_scale}"
  x_ref="${parsed_x}"
  y_ref="${parsed_y}"
  reserve_ref=("${off_left}" "${off_top}" "${off_right}" "${off_bottom}")
}

rofi_cursor_local_position() {
  local x_name="$1"
  local y_name="$2"
  local mon_x="$3"
  local mon_y="$4"
  local mon_scale="$5"
  local -n x_ref="${x_name}"
  local -n y_ref="${y_name}"
  local raw_cursor_x=0
  local raw_cursor_y=0

  rofi_cursor_raw_position raw_cursor_x raw_cursor_y
  x_ref="$(rofi_scaled_divide "$((raw_cursor_x - mon_x))" "${mon_scale}")"
  y_ref="$(rofi_scaled_divide "$((raw_cursor_y - mon_y))" "${mon_scale}")"
}

rofi_edge_padding_px() {
  hypr_window_edge_padding_px
}

# launcher spawn location (wofi/rofi)
get_rofi_pos() {
  local window_width="${1:-0}"
  local window_height="${2:-0}"
  local mon_width=0 mon_height=0 mon_scale=1 mon_x=0 mon_y=0
  local cursor_x=0 cursor_y=0
  local -a mon_reserved=(0 0 0 0)
  local edge_padding=0
  local cursor_padding=8
  local usable_width=0 usable_height=0
  local visible_cursor_x=0 visible_cursor_y=0
  local min_x=0 max_x=0 min_y=0 max_y=0
  local desired_x=0 desired_y=0
  local x_off=0 y_off=0

  rofi_default_window_size window_width window_height
  rofi_cursor_monitor_geometry mon_width mon_height mon_scale mon_x mon_y mon_reserved || return 1
  rofi_cursor_local_position cursor_x cursor_y "${mon_x}" "${mon_y}" "${mon_scale}"
  edge_padding="$(rofi_edge_padding_px 2>/dev/null || true)"
  [[ "${edge_padding}" =~ ^[0-9]+$ ]] || edge_padding=12

  usable_width=$((mon_width - mon_reserved[0] - mon_reserved[2]))
  usable_height=$((mon_height - mon_reserved[1] - mon_reserved[3]))
  ((usable_width < 1)) && usable_width=1
  ((usable_height < 1)) && usable_height=1

  visible_cursor_x=$((cursor_x - mon_reserved[0]))
  visible_cursor_y=$((cursor_y - mon_reserved[1]))

  min_x="${edge_padding}"
  min_y="${edge_padding}"
  max_x=$((usable_width - window_width - edge_padding))
  max_y=$((usable_height - window_height - edge_padding))

  ((max_x < min_x)) && max_x="${min_x}"
  ((max_y < min_y)) && max_y="${min_y}"

  desired_x=$((visible_cursor_x + cursor_padding))
  desired_y=$((visible_cursor_y + cursor_padding))

  x_off="${desired_x}"
  y_off="${desired_y}"
  ((x_off < min_x)) && x_off="${min_x}"
  ((x_off > max_x)) && x_off="${max_x}"
  ((y_off < min_y)) && y_off="${min_y}"
  ((y_off > max_y)) && y_off="${max_y}"

  printf 'window{location:%s %s;anchor:%s %s;x-offset:%spx;y-offset:%spx;}\n' \
    west north west north "${x_off}" "${y_off}"
}

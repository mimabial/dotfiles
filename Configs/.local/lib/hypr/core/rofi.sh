#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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
  local monitors_json=""

  if declare -F rofi_monitors_json >/dev/null 2>&1; then
    monitors_json="$(rofi_monitors_json)"
  else
    monitors_json="$(hyprctl -j monitors 2>/dev/null || true)"
  fi

  printf '%s\n' "${monitors_json}" | jq -r '
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

    .[] | select(.focused==true) | record
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

rofi_scale_milli() {
  local scale="${1:-1}"
  local whole_part=""
  local fraction_part=""

  if [[ "${scale}" =~ ^([0-9]+)([.]([0-9]+))?$ ]]; then
    whole_part="${BASH_REMATCH[1]}"
    fraction_part="${BASH_REMATCH[3]:-}"
    fraction_part="${fraction_part:0:3}"

    while ((${#fraction_part} < 3)); do
      fraction_part="${fraction_part}0"
    done

    if [[ "${whole_part}" != "0" || "${fraction_part}" != "000" ]]; then
      printf '%s\n' $((10#${whole_part} * 1000 + 10#${fraction_part:-000}))
      return 0
    fi
  fi

  printf '1000\n'
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

# launcher spawn location (wofi/rofi)
get_rofi_pos() {
  local window_width="${1:-0}"
  local window_height="${2:-0}"
  local monitors_json=""
  local monitor_line=""
  local raw_cursor_x=0 raw_cursor_y=0
  local parsed_width=0 parsed_height=0 parsed_scale=1 parsed_x=0 parsed_y=0
  local off_left=0 off_top=0 off_right=0 off_bottom=0
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
  local ignored_border_radius=""
  local border_width=0

  rofi_default_window_size window_width window_height
  hypr_border_metrics_into ignored_border_radius border_width 2>/dev/null || true
  [[ "${border_width}" =~ ^[0-9]+$ ]] || border_width=2
  # Rofi dimensions describe the content box; clamp using its outer border box.
  window_width=$((window_width + border_width * 2))
  window_height=$((window_height + border_width * 2))

  if declare -F rofi_monitors_json >/dev/null 2>&1; then
    monitors_json="$(rofi_monitors_json)"
  else
    monitors_json="$(hyprctl -j monitors 2>/dev/null || true)"
  fi
  [[ -n "${monitors_json}" ]] || return 1

  IFS=$'\t' read -r raw_cursor_x raw_cursor_y < <(
    hyprctl cursorpos -j 2>/dev/null |
      jq -r '[(.x // 0 | floor), (.y // 0 | floor)] | @tsv' 2>/dev/null
  )
  [[ "${raw_cursor_x}" =~ ^-?[0-9]+$ ]] || raw_cursor_x=0
  [[ "${raw_cursor_y}" =~ ^-?[0-9]+$ ]] || raw_cursor_y=0

  monitor_line="$(
    printf '%s\n' "${monitors_json}" | jq -r --argjson cx "${raw_cursor_x}" --argjson cy "${raw_cursor_y}" '
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

      (
        .[] | select(
          ($cx >= .x) and
          ($cx < (.x + monitor_width)) and
          ($cy >= .y) and
          ($cy < (.y + monitor_height))
        )
      ),
      (.[] | select(.focused == true))
      | record
    ' 2>/dev/null | head -n 1
  )"
  [[ -n "${monitor_line}" ]] || return 1

  IFS=$'\t' read -r parsed_width parsed_height parsed_scale parsed_x parsed_y off_left off_top off_right off_bottom <<<"${monitor_line}"
  [[ "${parsed_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] || parsed_scale=1
  mon_width="$(rofi_scaled_divide "${parsed_width}" "${parsed_scale}" 1)"
  mon_height="$(rofi_scaled_divide "${parsed_height}" "${parsed_scale}" 1)"
  mon_scale="${parsed_scale}"
  mon_x="${parsed_x}"
  mon_y="${parsed_y}"
  mon_reserved=("${off_left}" "${off_top}" "${off_right}" "${off_bottom}")
  cursor_x="$(rofi_scaled_divide "$((raw_cursor_x - mon_x))" "${mon_scale}")"
  cursor_y="$(rofi_scaled_divide "$((raw_cursor_y - mon_y))" "${mon_scale}")"
  edge_padding="$(hypr_window_edge_padding_px 2>/dev/null || true)"
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

#!/usr/bin/env bash

rofi_effective_font_scale() {
  local requested_scale="${1:-}"
  local scale="${requested_scale}"
  if [[ -n "${scale}" && ! "${scale}" =~ ^[0-9]+$ ]]; then
    printf 'WARN: invalid explicit rofi font scale: %s\n' "${scale}" >&2
    scale=""
  fi
  if [[ -z "${scale}" ]]; then
    scale="${ROFI_SCALE:-}"
    if [[ -n "${scale}" && ! "${scale}" =~ ^[0-9]+$ ]]; then
      printf 'WARN: invalid ROFI_SCALE: %s\n' "${scale}" >&2
      scale=""
    fi
  fi
  [[ -n "${scale}" ]] || scale="10"
  printf '%s\n' "${scale}"
}

rofi_effective_font_name() {
  local requested_font="${1:-}"
  local font_name="${requested_font}"
  if [[ -z "${font_name}" ]]; then
    font_name="$(hypr_config_value_from_layers "MENU_FONT" || true)"
    [[ -n "${font_name}" ]] || font_name="$(hypr_config_value_from_layers "FONT" || true)"
  fi
  font_name=${font_name:-monospace}
  printf '%s\n' "${font_name}"
}

rofi_default_border_metrics() {
  local fallback_border="${1:-0}"
  local fallback_width="${2:-0}"
  local border=""
  local width=""

  IFS=$'\t' read -r border width < <(hypr_resolved_border_metrics)
  [[ "${border}" =~ ^[0-9]+$ ]] || border="${fallback_border}"
  [[ "${width}" =~ ^[0-9]+$ ]] || width="${fallback_width}"

  printf '%s\t%s\n' "${border}" "${width}"
}

rofi_font_override() {
  local font_name="$1"
  local font_scale="$2"
  printf '* {font: "%s %s";}\n' "${font_name}" "${font_scale}"
}

rofi_picker_parse_style_args() {
  local out_style_name="$1"
  local out_rasi_name="$2"
  local fallback_style="$3"
  local usage_text="$4"
  shift 4

  # shellcheck disable=SC2178
  local -n out_style_ref="${out_style_name}"
  # shellcheck disable=SC2178
  local -n out_rasi_ref="${out_rasi_name}"

  while (($# > 0)); do
    case "$1" in
      --style|-s)
        if (($# > 1)); then
          out_style_ref="$2"
          shift 2
        else
          print_log +y "[warn] " "--style needs argument"
          out_style_ref="${fallback_style}"
          shift
        fi
        ;;
      --rasi)
        [[ -n "${2:-}" ]] || {
          print_log +r "[error] " +y "--rasi requires a file.rasi config file"
          exit 1
        }
        out_rasi_ref="$2"
        shift 2
        ;;
      -*)
        printf '%s\n' "${usage_text}"
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done
}

rofi_picker_rasi_args() {
  local out_name="$1"
  local rasi_file="$2"
  local position_override="${3:-}"

  # shellcheck disable=SC2178
  local -n out_ref="${out_name}"

  out_ref=(-config "${rasi_file}")
  [[ -n "${position_override}" ]] && out_ref+=(-theme-str "${position_override}")
}

rofi_picker_ensure_data_file() {
  local target_file="$1"
  local target_dir=""

  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}" || return 1
  [[ -f "${target_file}" ]] || : >"${target_file}"
}

rofi_picker_save_recent_entry() {
  local recent_file="$1"
  local tmp_prefix="$2"
  local recent_line="$3"
  local max_entries="${4:-50}"
  local postprocess_fn="${5:-}"
  local recent_dir=""
  local tmp_file=""

  recent_dir="$(dirname "${recent_file}")"
  mkdir -p "${recent_dir}" || return 1
  tmp_file="$(mktemp "${recent_dir}/.${tmp_prefix}.XXXXXX")" || return 1

  {
    printf '%s\n' "${recent_line}"
    cat "${recent_file}" 2>/dev/null
  } >"${tmp_file}" || {
    rm -f "${tmp_file}"
    return 1
  }

  if [[ -n "${postprocess_fn}" ]]; then
    if ! "${postprocess_fn}" "${tmp_file}"; then
      rm -f "${tmp_file}"
      return 1
    fi
  else
    local filtered_tmp=""
    filtered_tmp="$(mktemp "${recent_dir}/.${tmp_prefix}.dedup.XXXXXX")" || {
      rm -f "${tmp_file}"
      return 1
    }
    if ! awk '!seen[$0]++' "${tmp_file}" | head -n "${max_entries}" >"${filtered_tmp}"; then
      rm -f "${tmp_file}" "${filtered_tmp}"
      return 1
    fi
    if ! mv "${filtered_tmp}" "${tmp_file}"; then
      rm -f "${tmp_file}" "${filtered_tmp}"
      return 1
    fi
  fi

  if ! mv "${tmp_file}" "${recent_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi
}

rofi_picker_compute_window_geometry() {
  local out_position_name="$1"
  local out_theme_name="$2"
  local font_name="$3"
  local font_scale="$4"
  local width_em="$5"
  local height_em="$6"
  local fallback_width_px="$7"
  local fallback_height_px="$8"
  local width_px=""
  local height_px=""

  # shellcheck disable=SC2178
  local -n out_position_ref="${out_position_name}"
  # shellcheck disable=SC2178
  local -n out_theme_ref="${out_theme_name}"

  width_px="$(rofi_length_em_to_px "${width_em}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${width_px}" =~ ^[0-9]+$ ]] || width_px="${fallback_width_px}"

  height_px="$(rofi_length_em_to_px "${height_em}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${height_px}" =~ ^[0-9]+$ ]] || height_px="${fallback_height_px}"

  out_position_ref="$(get_rofi_pos "${width_px}" "${height_px}")"
  out_theme_ref="window { width: ${width_px}px; height: ${height_px}px; }"
}

rofi_length_em_to_px() {
  local em_value="$1"
  local font_name="$2"
  local font_scale="$3"
  local font_px=""

  [[ "${em_value}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  font_px="$(rofi_font_text_height_px "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${font_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1

  awk -v em="${em_value}" -v fp="${font_px}" 'BEGIN { printf "%d\n", int((em * fp) + 0.5) }'
}

rofi_font_text_height_px() {
  local font_name="$1"
  local font_scale="$2"
  local font_desc=""

  [[ -n "${font_name}" ]] || return 1
  [[ "${font_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v fs="${font_scale}" 'BEGIN { exit !(fs > 0) }' || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  font_desc="${font_name} ${font_scale}"
  FONT_DESC="${font_desc}" python3 - <<'PY'
import os
import sys

try:
    import gi
    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo
    import cairo
except Exception:
    sys.exit(1)

font_desc = os.environ.get("FONT_DESC", "").strip()
if not font_desc:
    sys.exit(1)

surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
context = cairo.Context(surface)
pango_context = PangoCairo.create_context(context)
description = Pango.FontDescription.from_string(font_desc)
pango_context.set_font_description(description)
metrics = pango_context.get_metrics(description, Pango.Language.get_default())
height = (metrics.get_ascent() + metrics.get_descent()) / Pango.SCALE
if height <= 0:
    sys.exit(1)

print(f"{height:.2f}")
PY
}

rofi_normalize_launcher_style() {
  local style_ref="${1:-style_1}"
  [[ -z "${style_ref}" ]] && style_ref="style_1"
  if [[ "${style_ref}" =~ ^[0-9]+$ ]]; then
    printf 'style_%s\n' "${style_ref}"
    return 0
  fi
  printf '%s\n' "${style_ref}"
}

rofi_theme_preview_asset() {
  local theme_ref="$1"
  local base_name="${theme_ref##*/}"
  local asset_path=""

  base_name="${base_name%.rasi}"
  for asset_path in \
    "$(rofi_resolve_asset "${base_name}.png" 2>/dev/null || true)" \
    "$(rofi_resolve_asset "theme_${base_name}.png" 2>/dev/null || true)"
  do
    [[ -f "${asset_path}" ]] || continue
    printf '%s\n' "${asset_path}"
    return 0
  done

  return 1
}

rofi_resolve_import_ref() {
  local import_ref="$1"
  local base_dir="$2"
  local resolved=""

  import_ref="${import_ref%\"}"
  import_ref="${import_ref#\"}"
  import_ref="${import_ref%\'}"
  import_ref="${import_ref#\'}"

  [[ -n "${import_ref}" ]] || return 1

  if [[ "${import_ref}" == "~/"* ]]; then
    resolved="${HOME}/${import_ref#~/}"
  elif [[ "${import_ref}" == /* ]]; then
    resolved="${import_ref}"
  elif [[ "${import_ref}" == *"/"* ]]; then
    resolved="${base_dir}/${import_ref}"
  else
    resolved="$(rofi_resolve_theme "${import_ref}" 2>/dev/null || true)"
  fi

  [[ -f "${resolved}" ]] || return 1
  printf '%s\n' "${resolved}"
}

rofi_theme_effective_files() {
  local theme_file="$1"
  local visited_name="${2:-_rofi_theme_visited}"
  local base_dir import_ref import_file

  [[ -f "${theme_file}" ]] || return 1

  # shellcheck disable=SC2178,SC2034
  declare -n _rofi_seen="${visited_name}"
  if [[ -n "${_rofi_seen["${theme_file}"]:-}" ]]; then
    return 0
  fi
  _rofi_seen["${theme_file}"]=1

  base_dir="$(dirname "${theme_file}")"
  while IFS= read -r import_ref; do
    import_file="$(rofi_resolve_import_ref "${import_ref}" "${base_dir}" 2>/dev/null || true)"
    [[ -n "${import_file}" ]] || continue
    rofi_theme_effective_files "${import_file}" "${visited_name}"
  done < <(
    sed -nE 's/^[[:space:]]*@(theme|import)[[:space:]]+"([^"]+)".*/\2/p; s/^[[:space:]]*@(theme|import)[[:space:]]+'\''([^'\'']+)'\''.*/\2/p' "${theme_file}"
  )

  printf '%s\n' "${theme_file}"
}

rofi_theme_is_fullscreen() {
  local theme_ref="$1"
  local theme_file="" file="" fullscreen_value=""
  local -A _rofi_theme_visited=()

  theme_file="$(rofi_resolve_theme "${theme_ref}" 2>/dev/null || true)"
  [[ -f "${theme_file}" ]] || return 1

  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    local file_value=""
    file_value="$(awk '
      BEGIN { IGNORECASE = 1 }
      /^[[:space:]]*fullscreen[[:space:]]*:/ {
        if (match($0, /(true|false)/)) {
          value = substr($0, RSTART, RLENGTH)
        }
      }
      END { print value }
    ' "${file}" 2>/dev/null || true)"
    [[ -n "${file_value}" ]] && fullscreen_value="${file_value}"
  done < <(rofi_theme_effective_files "${theme_file}" "_rofi_theme_visited")

  [[ "${fullscreen_value}" == "true" ]]
}

rofi_default_border_radius() {
  local fallback="${1:-0}"
  local border=""
  IFS=$'\t' read -r border _ < <(rofi_default_border_metrics "${fallback}" 0)
  [[ "${border}" =~ ^[0-9]+$ ]] || border="${fallback}"
  printf '%s\n' "${border}"
}

rofi_default_border_width() {
  local fallback="${1:-0}"
  local width=""
  IFS=$'\t' read -r _ width < <(rofi_default_border_metrics 0 "${fallback}")
  [[ "${width}" =~ ^[0-9]+$ ]] || width="${fallback}"
  printf '%s\n' "${width}"
}

rofi_standard_window_theme() {
  local container_name="${1:-listview}"
  local elem_mode="${2:-same}"
  local border_radius border_width window_radius elem_radius

  IFS=$'\t' read -r border_radius border_width < <(rofi_default_border_metrics 0 0)
  window_radius=$((border_radius * 3 / 2))

  case "${elem_mode}" in
    min5)
      elem_radius="${border_radius}"
      [[ "${elem_radius}" -eq 0 ]] && elem_radius=5
      ;;
    same)
      elem_radius="${border_radius}"
      ;;
    *)
      printf 'Unsupported rofi element border mode: %s\n' "${elem_mode}" >&2
      return 1
      ;;
  esac

  printf 'window{border:%spx;border-radius:%spx;}%s{border-radius:%spx;} element{border-radius:%spx;}\n' \
    "${border_width}" "${window_radius}" "${container_name}" "${elem_radius}" "${elem_radius}"
}

rofi_prepare_standard_context() {
  local out_scale_name="$1"
  local out_font_name="$2"
  local out_font_override_name="$3"
  local out_window_theme_name="$4"
  local out_opacity_name="$5"
  local requested_scale="${6:-}"
  local requested_font="${7:-}"
  local container_name="${8:-wallbox}"
  local elem_mode="${9:-same}"

  # shellcheck disable=SC2178
  local -n out_scale_ref="${out_scale_name}"
  # shellcheck disable=SC2178
  local -n out_font_ref="${out_font_name}"
  # shellcheck disable=SC2178
  local -n out_font_override_ref="${out_font_override_name}"
  # shellcheck disable=SC2178
  local -n out_window_theme_ref="${out_window_theme_name}"
  # shellcheck disable=SC2178
  local -n out_opacity_ref="${out_opacity_name}"

  out_scale_ref="$(rofi_effective_font_scale "${requested_scale}")"
  out_font_ref="$(rofi_effective_font_name "${requested_font}")"
  out_font_override_ref="$(rofi_font_override "${out_font_ref}" "${out_scale_ref}")"
  out_window_theme_ref="$(rofi_standard_window_theme "${container_name}" "${elem_mode}")"
  out_opacity_ref="$(rofi_active_opacity_override)"
}

rofi_build_standard_menu_args() {
  local out_name="$1"
  local prompt="$2"
  local placeholder="$3"
  local theme_ref="${4:-clipboard}"
  local requested_scale="${5:-}"
  local requested_font="${6:-}"
  local container_name="${7:-wallbox}"
  local elem_mode="${8:-same}"
  local position_override="${9:-}"
  local font_scale font_name opacity_override

  # shellcheck disable=SC2178
  local -n out_ref="${out_name}"
  out_ref=()

  font_scale="$(rofi_effective_font_scale "${requested_scale}")"
  font_name="$(rofi_effective_font_name "${requested_font}")"
  [[ -n "${position_override}" ]] || position_override="$(get_rofi_pos)"

  out_ref+=(
    -dmenu
    -i
    -p "${prompt}"
    -theme "${theme_ref}"
    -theme-str "$(rofi_font_override "${font_name}" "${font_scale}")"
    -theme-str "$(rofi_standard_window_theme "${container_name}" "${elem_mode}")"
  )

  [[ -n "${placeholder}" ]] && out_ref+=(-theme-str "entry { placeholder: \"${placeholder}\"; }")
  [[ -n "${position_override}" ]] && out_ref+=(-theme-str "${position_override}")

  opacity_override="$(rofi_active_opacity_override)"
  [[ -n "${opacity_override}" ]] && out_ref+=(-theme-str "${opacity_override}")
}

rofi_icon_theme_override() {
  local icon_theme
  icon_theme="$(get_hypr_conf "ICON_THEME")"
  printf 'configuration {icon-theme: "%s";}\n' "${icon_theme}"
}

rofi_focused_monitor_logical_size() {
  local monitor_line=""
  local mon_width mon_height mon_scale logical_width logical_height

  monitor_line="$(rofi_focused_monitor_record 2>/dev/null || true)"
  if [[ -z "${monitor_line}" ]]; then
    printf '1920 1080\n'
    return 0
  fi

  IFS=$'\t' read -r mon_width mon_height mon_scale _ <<<"${monitor_line}"
  [[ "${mon_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] || mon_scale=1
  logical_width="$(awk -v w="${mon_width}" -v s="${mon_scale}" 'BEGIN { if (s + 0 <= 0) s = 1; v = int(w / s); if (v < 1) v = 1; print v }')"
  logical_height="$(awk -v h="${mon_height}" -v s="${mon_scale}" 'BEGIN { if (s + 0 <= 0) s = 1; v = int(h / s); if (v < 1) v = 1; print v }')"
  printf '%s %s\n' "${logical_width}" "${logical_height}"
}

rofi_focused_monitor_logical_width_precise() {
  local monitor_line=""
  local mon_width mon_scale

  monitor_line="$(rofi_focused_monitor_record 2>/dev/null || true)"
  [[ -n "${monitor_line}" ]] || return 0
  IFS=$'\t' read -r mon_width _ mon_scale _ <<<"${monitor_line}"

  if [[ "${mon_width}" =~ ^[0-9]+$ ]]; then
    if [[ "${mon_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN { exit !(${mon_scale} > 0) }"; then
      awk -v w="${mon_width}" -v sc="${mon_scale}" 'BEGIN { printf "%.2f\n", (w / sc) }'
    else
      printf '%s\n' "${mon_width}"
    fi
  fi
}

rofi_theme_width_multiplier_override() {
  local theme_ref="$1"
  local factor="$2"
  local fallback_width="${3:-}"
  local theme_file=""
  local width_line=""
  local width_value=""
  local width_unit=""
  local scaled_width=""

  theme_file="$(rofi_resolve_theme "${theme_ref}" 2>/dev/null || true)"
  if [[ -f "${theme_file}" ]]; then
    width_line="$(
      awk '
        /^[[:space:]]*window[[:space:]]*\{/ {in_window=1; next}
        in_window && /^[[:space:]]*}/ {exit}
        in_window && /^[[:space:]]*width[[:space:]]*:/ {
          line=$0
          sub(/^[^:]*:[[:space:]]*/, "", line)
          sub(/[[:space:]]*;.*$/, "", line)
          gsub(/[[:space:]]*/, "", line)
          print line
          exit
        }
      ' "${theme_file}" 2>/dev/null || true
    )"
  fi

  if [[ "${width_line}" =~ ^([0-9]+([.][0-9]+)?)([a-z%]+)$ ]]; then
    width_value="${BASH_REMATCH[1]}"
    width_unit="${BASH_REMATCH[3]}"
    scaled_width="$(awk -v w="${width_value}" -v f="${factor}" 'BEGIN { printf "%.2f", (w * f) }')"
    scaled_width="${scaled_width%0}"
    scaled_width="${scaled_width%0}"
    scaled_width="${scaled_width%.}"
    printf 'window { width: %s%s; }\n' "${scaled_width}" "${width_unit}"
    return 0
  fi

  [[ -n "${fallback_width}" ]] || return 1
  printf 'window { width: %s; }\n' "${fallback_width}"
}

rofi_theme_window_height_spec() {
  awk '
    /^[[:space:]]*window[[:space:]]*\{/ { in_window = 1; next }
    in_window && /^[[:space:]]*}/ { exit }
    in_window && /^[[:space:]]*height[[:space:]]*:/ {
      if (match($0, /:[[:space:]]*([0-9]+([.][0-9]+)?)([a-z%]*)/, m)) {
        print m[1], m[3]
      }
      exit
    }
  ' "$1"
}

rofi_theme_window_height_px() {
  local theme_file="$1"
  local font_name="$2"
  local font_scale="$3"
  local theme_height=""
  local theme_height_unit=""
  local font_px=""
  local height_px=""

  read -r theme_height theme_height_unit < <(rofi_theme_window_height_spec "${theme_file}")
  case "${theme_height_unit}" in
    px)
      printf '%s\t%s\t\n' "${theme_height}" "${theme_height_unit}"
      return 0
      ;;
    em)
      font_px="$(rofi_font_text_height_px "${font_name}" "${font_scale}" 2>/dev/null || true)"
      [[ "${font_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
      height_px="$(awk -v h="${theme_height}" -v fp="${font_px}" 'BEGIN { printf "%.2f", (h * fp) }')"
      printf '%s\t%s\t%s\n' "${height_px}" "${theme_height_unit}" "${font_px}"
      return 0
      ;;
  esac

  return 1
}

rofi_wallpaper_ratio() {
  local wall_image="$1"
  local img_w=""
  local img_h=""

  command -v magick >/dev/null 2>&1 || return 1
  read -r img_w img_h < <(magick identify -format "%w %h" "${wall_image}" 2>/dev/null || true)
  [[ "${img_w}" =~ ^[0-9]+$ && "${img_h}" =~ ^[0-9]+$ && "${img_h}" -gt 0 ]] || return 1

  awk -v w="${img_w}" -v h="${img_h}" 'BEGIN { printf "%.6f", (w / h) }'
}

rofi_wallpaper_post_clamp_reduction_px() {
  local theme_name="$1"
  local monitors_json=""
  local layers_json=""
  local gaps_json=""
  local focused_monitor_name=""
  local waybar_width_px="0"
  local gaps_out_px="0"

  case "${theme_name}" in
    style_1 | pywal16) ;;
    *)
      printf '0\n'
      return 0
      ;;
  esac

  monitors_json="$(hyprctl -j monitors 2>/dev/null || true)"
  if [[ "${monitors_json}" == \[* || "${monitors_json}" == \{* ]]; then
    focused_monitor_name="$(printf '%s\n' "${monitors_json}" | jq -r '.[] | select(.focused==true) | .name' 2>/dev/null | head -n 1)"
  fi
  if [[ -n "${focused_monitor_name}" ]]; then
    layers_json="$(hyprctl -j layers 2>/dev/null || true)"
    if [[ "${layers_json}" == \{* ]]; then
      waybar_width_px="$(
        printf '%s\n' "${layers_json}" | jq -r --arg mon "${focused_monitor_name}" '
          .[$mon].levels[]?[]? | select(.namespace=="waybar") | .w
        ' 2>/dev/null | head -n 1
      )"
    fi
  fi
  [[ "${waybar_width_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || waybar_width_px=0

  gaps_json="$(hyprctl -j getoption general:gaps_out 2>/dev/null || true)"
  if [[ "${gaps_json}" == \{* ]]; then
    gaps_out_px="$(
      printf '%s\n' "${gaps_json}" | jq -r '
        if (.int? != null and (.int | tostring) != "") then
          .int
        elif (.custom? != null and .custom != "") then
          (.custom | split(" ")[0])
        else
          empty
        end
      ' 2>/dev/null | head -n 1
    )"
  fi
  [[ "${gaps_out_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || gaps_out_px=0

  awk -v wb="${waybar_width_px}" -v g="${gaps_out_px}" 'BEGIN { printf "%.2f", (wb + (g * 4)) }'
}

rofi_wallpaper_width_override() {
  local theme_file="$1"
  local font_name="$2"
  local font_scale="$3"
  local margin_px="$4"
  local wall_image="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.thmb"
  local monitor_width_logical=""
  local theme_name=""
  local did_clamp=0
  local theme_height_px=""
  local theme_height_unit=""
  local font_px=""
  local ratio=""
  local width_px=""
  local max_width_px=""
  local post_clamp_reduction_px="0"
  local width_value=""

  [[ -f "${wall_image}" ]] || return 0
  [[ -n "${theme_file}" ]] || return 0
  [[ "${margin_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || margin_px=0

  theme_name="$(basename "${theme_file}")"
  theme_name="${theme_name%.rasi}"
  monitor_width_logical="$(rofi_focused_monitor_logical_width_precise)"
  read -r theme_height_px theme_height_unit font_px < <(rofi_theme_window_height_px "${theme_file}" "${font_name}" "${font_scale}" 2>/dev/null || true)
  [[ -n "${theme_height_px}" && -n "${theme_height_unit}" ]] || return 0
  ratio="$(rofi_wallpaper_ratio "${wall_image}" 2>/dev/null || true)"
  [[ -n "${ratio}" ]] || return 0
  post_clamp_reduction_px="$(rofi_wallpaper_post_clamp_reduction_px "${theme_name}")"

  width_px="$(awk -v h="${theme_height_px}" -v r="${ratio}" 'BEGIN { printf "%.2f", (h * r) }')"

  if [[ -n "${monitor_width_logical}" ]] && awk -v w="${monitor_width_logical}" -v m="${margin_px}" 'BEGIN { exit !(w > (m * 2)) }'; then
    max_width_px="$(awk -v w="${monitor_width_logical}" -v m="${margin_px}" 'BEGIN { val = w - (m * 2); if (val < 0) val = 0; printf "%.2f", val }')"
    if awk -v w="${width_px}" -v max="${max_width_px}" 'BEGIN { exit !(w > max) }'; then
      did_clamp=1
      width_px="$(awk -v w="${width_px}" -v max="${max_width_px}" 'BEGIN { if (w > max) w = max; printf "%.2f", w }')"
    fi
  fi

  if [[ "${theme_name}" == "style_1" || "${theme_name}" == "pywal16" ]] && (( did_clamp )) && awk -v r="${post_clamp_reduction_px}" 'BEGIN { exit !(r > 0) }'; then
    width_px="$(awk -v w="${width_px}" -v r="${post_clamp_reduction_px}" 'BEGIN { v = w - r; if (v < 0) v = 0; printf "%.2f", v }')"
  fi

  if [[ "${theme_height_unit}" == "px" ]]; then
    printf 'window { width: %spx; }\n' "${width_px}"
    return 0
  fi

  width_value="$(awk -v w="${width_px}" -v fp="${font_px}" 'BEGIN { if (fp <= 0) { print 0 } else { printf "%.2f", (w / fp) } }')"
  printf 'window { width: %sem; }\n' "${width_value}"
}

rofi_active_opacity_override() {
  local opacity bg_color hex_alpha
  opacity="$(hyprctl -j getoption decoration:active_opacity 2>/dev/null | jq -r '.float // empty' 2>/dev/null || true)"
  [[ "${opacity}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 0
  hex_alpha="$(awk -v o="${opacity}" 'BEGIN { v = int((o / 2) * 255 + 0.5); if (v > 255) v = 255; if (v < 0) v = 0; printf "%02X", v }')"
  [[ "${hex_alpha}" == "FF" ]] && return 0
  bg_color="$(grep -oP 'background:\s*\K#[0-9a-fA-F]{6}' "${HOME}/.config/rofi/colors.rasi" 2>/dev/null | head -1)"
  [[ -n "${bg_color}" ]] || bg_color="#000000"
  printf 'window { transparency: "real"; background-color: %s%s; }\n' "${bg_color}" "${hex_alpha}"
}

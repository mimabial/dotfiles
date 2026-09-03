#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Font resolution, override emission, em->px and text->px conversion via Pango.
# External deps: hypr_config_value_from_layers (core/common).

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
  # follow the desktop text-size knob, anchored the same way it is: 12px = 1.0.
  # Callers that only required the rofi module still get it: pull state in here
  # rather than leaving them silently pinned to the default size.
  if [[ -z "${scale}" ]]; then
    local text_size="${TEXT_SIZE:-}"
    if [[ ! "${text_size}" =~ ^[0-9]+$ ]]; then
      declare -F state_get >/dev/null 2>&1 || hypr_runtime_require state >/dev/null 2>&1 || true
      text_size="$(state_get TEXT_SIZE 12 2>/dev/null || true)"
    fi
    [[ "${text_size}" =~ ^[0-9]+$ ]] && scale=$(( text_size * 10 / 12 ))
  fi
  [[ -n "${scale}" ]] || scale="10"
  printf '%s\n' "${scale}"
}

rofi_config_font_name() {
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config.rasi"
  local font_desc=""
  local line=""

  [[ -r "${config_file}" ]] || return 1
  while IFS= read -r line; do
    [[ "${line}" =~ ^[[:space:]]*font[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || continue
    font_desc="${BASH_REMATCH[1]}"
    if [[ "${font_desc}" =~ ^(.+)[[:space:]]+[0-9]+([.][0-9]+)?$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    else
      printf '%s\n' "${font_desc}"
    fi
    return 0
  done < "${config_file}"
  return 1
}

rofi_effective_font_name() {
  local requested_font="${1:-}"
  local font_name="${requested_font}"
  if [[ -z "${font_name}" ]]; then
    # font-apply keeps Rofi synchronized with the layered Hypr font setting.
    font_name="$(rofi_config_font_name 2>/dev/null || true)"
  fi
  if [[ -z "${font_name}" ]]; then
    font_name="$(hypr_config_value_from_layers "MENU_FONT" || true)"
    [[ -n "${font_name}" ]] || font_name="$(hypr_config_value_from_layers "FONT" || true)"
  fi
  font_name=${font_name:-monospace}
  printf '%s\n' "${font_name}"
}

rofi_font_override() {
  local font_name="$1"
  local font_scale="$2"
  printf '* {font: "%s %s";}\n' "${font_name}" "${font_scale}"
}

rofi_length_em_to_px() {
  local em_value="$1"
  local font_name="$2"
  local font_scale="$3"
  local font_px=""
  local em_milli=0
  local font_milli=0
  local px_milli=0

  [[ "${em_value}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  font_px="$(rofi_font_text_height_px "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${font_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1

  em_milli="$(rofi_decimal_milli "${em_value}")" || return 1
  font_milli="$(rofi_decimal_milli "${font_px}")" || return 1
  px_milli="$(rofi_mul_milli "${em_milli}" "${font_milli}")" || return 1
  printf '%s\n' $(((px_milli + 500) / 1000))
}

rofi_font_text_height_px() {
  local font_name="$1"
  local font_scale="$2"
  local font_desc=""
  local font_px=""

  [[ -n "${font_name}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  declare -gA ROFI_FONT_TEXT_HEIGHT_CACHE
  font_desc="${font_name} ${font_scale}"
  if [[ -v ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"] ]]; then
    printf '%s\n' "${ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"]}"
    return 0
  fi

  font_px="$(
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
# rofi's em is the line height, which includes the line gap; ascent+descent
# undercounts it (Miracode 15: 21px vs rofi's 22px) and clips the last row.
height = metrics.get_height() / Pango.SCALE
if height <= 0:
    height = (metrics.get_ascent() + metrics.get_descent()) / Pango.SCALE
if height <= 0:
    sys.exit(1)

print(f"{height:.2f}")
PY
  )" || return 1

  [[ -n "${font_px}" ]] || return 1
  ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"]="${font_px}"
  printf '%s\n' "${font_px}"
}

# "<widest row px> <line height px>" for the rows on stdin. Measured rather than
# counted so nerd-font glyphs and proportional faces are not mistaken for one
# digit advance each; both extents come from one Pango pass.
rofi_font_text_extents_px() {
  local font_name="$1"
  local font_scale="$2"
  local rows="" digest="" cache_dir="" cache_file="" extents="" width_px="" height_px=""

  [[ -n "${font_name}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  rows="$(cat)"
  [[ -n "${rows}" ]] || return 1

  # menu() always runs inside $(), so a shell-variable memo would die with the
  # subshell; key the measurement on font+rows and keep it on disk instead.
  digest="$(printf '%s\n%s' "${font_name} ${font_scale}" "${rows}" | md5sum)"
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr/rofi-text-width"
  cache_file="${cache_dir}/${digest%% *}"
  if read -r width_px height_px 2>/dev/null <"${cache_file}" &&
    [[ "${width_px}" =~ ^[0-9]+$ && "${height_px}" =~ ^[0-9]+$ ]]; then
    printf '%s %s\n' "${width_px}" "${height_px}"
    return 0
  fi

  # program on fd 3, so the rows keep stdin
  extents="$(
    printf '%s\n' "${rows}" | FONT_DESC="${font_name} ${font_scale}" python3 /dev/fd/3 3<<'PY'
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

layout = PangoCairo.create_layout(cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)))
layout.set_font_description(Pango.FontDescription.from_string(font_desc))

width = 0
height = 0
for row in sys.stdin.read().splitlines():
    layout.set_text(row, -1)
    row_width, row_height = layout.get_pixel_size()
    width = max(width, row_width)
    height = max(height, row_height)
if width <= 0 or height <= 0:
    sys.exit(1)

print(width, height)
PY
  )" || return 1

  read -r width_px height_px <<<"${extents}"
  [[ "${width_px}" =~ ^[0-9]+$ && "${height_px}" =~ ^[0-9]+$ ]] || return 1

  mkdir -p "${cache_dir}" 2>/dev/null && printf '%s %s\n' "${width_px}" "${height_px}" >"${cache_file}" 2>/dev/null
  printf '%s %s\n' "${width_px}" "${height_px}"
}

# Right-align a trailing glyph across the rows that ask for one. Reads
# "<flag>\t<label>" lines and re-emits the labels alone, padding flagged ones so
# the glyph lands in a single column. target_px is the width of the text column
# the rows will be drawn in; the glyph goes to its right edge, falling back to
# the widest label when the rows are what sets that width. The pad is whole
# spaces, so the column is exact only to one space advance -- negligible in a
# mono face, and the alternative is a per-row rofi widget, which dmenu has not.
rofi_font_align_trailing() {
  local font_name="$1"
  local font_scale="$2"
  local glyph="$3"
  local target_px="${4:-0}"
  local rows="" digest="" cache_dir="" cache_file="" aligned=""

  [[ -n "${font_name}" && -n "${glyph}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  [[ "${target_px}" =~ ^[0-9]+$ ]] || target_px=0
  command -v python3 >/dev/null 2>&1 || return 1

  rows="$(cat)"
  [[ -n "${rows}" ]] || return 1

  digest="$(printf '%s\n%s\n%s\n%s' "${font_name} ${font_scale}" "${glyph}" "${target_px}" "${rows}" | md5sum)"
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr/rofi-trailing-align"
  cache_file="${cache_dir}/${digest%% *}"
  if [[ -s "${cache_file}" ]]; then
    aligned="$(<"${cache_file}")"
    printf '%s\n' "${aligned}"
    return 0
  fi

  # program on fd 3, so the rows keep stdin
  aligned="$(
    printf '%s\n' "${rows}" |
      FONT_DESC="${font_name} ${font_scale}" GLYPH="${glyph}" TARGET_PX="${target_px}" \
        PYTHONIOENCODING=utf-8 python3 /dev/fd/3 3<<'PY'
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
glyph = os.environ.get("GLYPH", "")
if not font_desc or not glyph:
    sys.exit(1)

layout = PangoCairo.create_layout(cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)))
layout.set_font_description(Pango.FontDescription.from_string(font_desc))


def width(text):
    layout.set_text(text, -1)
    return layout.get_pixel_size()[0]


rows = []
for line in sys.stdin.read().splitlines():
    flag, _, label = line.partition("\t")
    rows.append((flag == "1", label))

space = width(" ")
if not rows or space <= 0:
    sys.exit(1)

glyph_width = width(glyph)
# two spaces of breathing room past the widest label, when the rows themselves
# are what the column is measured from
edge = max(width(label) for _, label in rows) + 2 * space + glyph_width
# Reaching a wider target costs whole spaces, and the division floors twice
# over: a target landing mid-space would round labels of differing length to
# columns one space apart, and a row as wide as the column rofi hands it is
# elided -- taking the glyph with it.
target = int(os.environ.get("TARGET_PX", "0") or 0)
edge += max(0, (target - edge) // space) * space

for flagged, label in rows:
    if not flagged:
        print(label)
        continue
    print(label + " " * max(1, round((edge - glyph_width - width(label)) / space)) + glyph)
PY
  )" || return 1
  [[ -n "${aligned}" ]] || return 1

  mkdir -p "${cache_dir}" 2>/dev/null && printf '%s\n' "${aligned}" >"${cache_file}" 2>/dev/null
  printf '%s\n' "${aligned}"
}

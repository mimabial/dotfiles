#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Font resolution, override emission, em->px conversion via Pango.
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
    local text_size=""
    declare -F state_get >/dev/null 2>&1 || hypr_runtime_require state >/dev/null 2>&1 || true
    if declare -F state_get >/dev/null 2>&1; then
      text_size="$(state_get TEXT_SIZE 12 2>/dev/null || true)"
      [[ "${text_size}" =~ ^[0-9]+$ ]] && scale=$(( text_size * 10 / 12 ))
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

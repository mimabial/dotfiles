#!/usr/bin/env bash
# Wire Firefox userChrome.css to the wal-generated Firefox chrome stylesheet.
# Firefox reads this file at startup, so theme changes apply after Firefox restarts.

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

if [[ -r "${LIB_DIR}/hypr/theme/phase-d.sh" ]]; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/hypr/theme/phase-d.sh" || exit 1
  theme_phase_d_init "${HYPR_THEME_PHASE_D_LOCK_KEY:-theme_phase_d_firefox}"
fi

WAL_CACHE="${WAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/wal}"
FIREFOX_ROOT="${FIREFOX_ROOT:-$HOME/.mozilla/firefox}"
FIREFOX_USERCHROME_SOURCE="${WAL_CACHE}/firefox-userChrome.css"
FIREFOX_USERCHROME_TEMPLATE="${FIREFOX_USERCHROME_TEMPLATE:-${XDG_CONFIG_HOME:-$HOME/.config}/wal/templates/firefox-userChrome.css}"
FIREFOX_COLORS_JSON="${WAL_CACHE}/colors.json"
FIREFOX_USERCHROME_MARKER_START="/* BEGIN HYPR WAL FIREFOX USERCHROME */"
FIREFOX_USERCHROME_MARKER_END="/* END HYPR WAL FIREFOX USERCHROME */"
FIREFOX_CUSTOM_CHROME_PREF='toolkit.legacyUserProfileCustomizations.stylesheets'

firefox_promote_file() {
  local tmp_file="$1"
  local target_file="$2"

  if declare -F theme_phase_d_promote_file >/dev/null 2>&1; then
    theme_phase_d_promote_file "${tmp_file}" "${target_file}"
    return $?
  fi

  if [[ -f "${target_file}" ]] && cmp -s "${tmp_file}" "${target_file}"; then
    rm -f -- "${tmp_file}"
  else
    mv -f -- "${tmp_file}" "${target_file}"
  fi
}

firefox_render_userchrome_source() {
  local tmp_file=""

  [[ -f "${FIREFOX_USERCHROME_TEMPLATE}" && -f "${FIREFOX_COLORS_JSON}" ]] || return 0
  mkdir -p "${WAL_CACHE}" || return 1
  tmp_file="$(mktemp "${WAL_CACHE}/.firefox-userChrome.css.XXXXXX")" || return 1

  if ! python3 - "${FIREFOX_USERCHROME_TEMPLATE}" "${tmp_file}" "${FIREFOX_COLORS_JSON}" <<'PYEOF'
import json
import re
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
colors_json = Path(sys.argv[3])
payload = json.loads(colors_json.read_text())

def parse_hex(value):
    value = str(value).strip().lstrip("#")
    if len(value) != 6:
        return None
    try:
        return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4))
    except ValueError:
        return None


def srgb_to_linear(channel):
    if channel <= 0.03928:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def luminance(value):
    rgb = parse_hex(value)
    if rgb is None:
        return 0
    red, green, blue = (srgb_to_linear(channel) for channel in rgb)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast(first, second):
    first_lum = luminance(first)
    second_lum = luminance(second)
    lighter = max(first_lum, second_lum)
    darker = min(first_lum, second_lum)
    return (lighter + 0.05) / (darker + 0.05)


def hex_from_rgb(rgb):
    return "#" + "".join(f"{max(0, min(255, round(channel * 255))):02X}" for channel in rgb)


def mix_hex(first, second, first_weight):
    first_rgb = parse_hex(first)
    second_rgb = parse_hex(second)
    if first_rgb is None:
        return second
    if second_rgb is None:
        return first

    second_weight = 1 - first_weight
    return hex_from_rgb(tuple(first_rgb[index] * first_weight + second_rgb[index] * second_weight for index in range(3)))


def choose_text(bg, foreground, background):
    if contrast(bg, foreground) >= contrast(bg, background):
        return foreground
    return background


def firefox_role_colors(background, foreground, colors):
    accent = colors.get("color4", foreground)
    bg_is_light = luminance(background) > 0.45

    if bg_is_light:
        toolbar_bg = mix_hex(background, foreground, 0.94)
        field_bg = background
        field_focus_bg = background
        field_border = mix_hex(background, foreground, 0.78)
        tab_bg = background
        tab_hover_bg = mix_hex(background, foreground, 0.86)
        panel_bg = background
        panel_border = mix_hex(background, foreground, 0.84)
        tab_outline = panel_border
        highlight_bg = mix_hex(background, accent, 0.62)
        button_hover = mix_hex(background, foreground, 0.88)
        button_active = mix_hex(background, foreground, 0.78)
    else:
        toolbar_bg = background
        field_bg = mix_hex(background, foreground, 0.86)
        field_focus_bg = mix_hex(background, foreground, 0.82)
        field_border = mix_hex(background, foreground, 0.66)
        tab_bg = mix_hex(background, foreground, 0.78)
        tab_hover_bg = mix_hex(background, foreground, 0.88)
        panel_bg = mix_hex(background, foreground, 0.80)
        panel_border = mix_hex(background, foreground, 0.66)
        tab_outline = panel_border
        highlight_bg = mix_hex(background, accent, 0.55)
        button_hover = mix_hex(background, foreground, 0.88)
        button_active = mix_hex(background, foreground, 0.76)

    roles = {
        "color_scheme": "light" if bg_is_light else "dark",
        "toolbar_bg": toolbar_bg,
        "toolbar_fg": foreground,
        "field_bg": field_bg,
        "field_fg": foreground,
        "field_border": field_border,
        "field_focus_bg": field_focus_bg,
        "tab_bg": tab_bg,
        "tab_fg": choose_text(tab_bg, foreground, background),
        "tab_hover_bg": tab_hover_bg,
        "tab_outline": tab_outline,
        "panel_bg": panel_bg,
        "panel_fg": foreground,
        "panel_border": panel_border,
        "highlight_bg": highlight_bg,
        "highlight_fg": choose_text(highlight_bg, foreground, background),
        "sidebar_bg": background,
        "sidebar_fg": foreground,
        "button_hover": button_hover,
        "button_active": button_active,
        "outline": accent,
    }
    return roles


mapping = {}
for key, value in payload.get("special", {}).items():
    mapping[key] = value
    mapping[f"{key}.strip"] = value.lstrip("#")

for key, value in payload.get("colors", {}).items():
    mapping[key] = value
    mapping[f"{key}.strip"] = value.lstrip("#")

background = payload.get("special", {}).get("background", "#1c1b22")
foreground = payload.get("special", {}).get("foreground", "#fbfbfe")
colors = payload.get("colors", {})
for role, value in firefox_role_colors(background, foreground, colors).items():
    mapping[f"firefox.{role}"] = value
    mapping[f"firefox.{role}.strip"] = value.lstrip("#")

text = template_path.read_text()
rendered = re.sub(r"\{([A-Za-z0-9_.-]+)\}", lambda match: mapping.get(match.group(1), match.group(0)), text)
rendered = rendered.replace("{{", "{").replace("}}", "}")
target_path.write_text(rendered)
PYEOF
  then
    rm -f -- "${tmp_file}"
    return 1
  fi

  firefox_promote_file "${tmp_file}" "${FIREFOX_USERCHROME_SOURCE}"
}

firefox_profile_paths() {
  local profiles_ini="${FIREFOX_ROOT}/profiles.ini"

  if [[ -f "${profiles_ini}" ]]; then
    python3 - "${profiles_ini}" "${FIREFOX_ROOT}" <<'PYEOF'
import configparser
import sys
from pathlib import Path

profiles_ini = Path(sys.argv[1])
root = Path(sys.argv[2])
config = configparser.ConfigParser()
config.read(profiles_ini)
seen = set()

for section in config.sections():
    if not section.startswith("Profile"):
        continue
    raw_path = config[section].get("Path", "").strip()
    if not raw_path:
        continue
    profile_path = Path(raw_path)
    if config[section].get("IsRelative", "1").strip() != "0":
        profile_path = root / profile_path
    profile_path = profile_path.expanduser()
    if profile_path.exists():
        resolved = str(profile_path.resolve())
        if resolved not in seen:
            seen.add(resolved)
            print(resolved)
PYEOF
    return 0
  fi

  find "${FIREFOX_ROOT}" -mindepth 1 -maxdepth 1 -type d \
    \( -name "*.default" -o -name "*.default-release" \) -print 2>/dev/null
}

firefox_write_userchrome_profile_css() {
  local profile_dir="$1"
  local chrome_dir="${profile_dir}/chrome"
  local target_file="${chrome_dir}/userChrome.css"
  local tmp_file=""

  mkdir -p "${chrome_dir}" || return 1
  tmp_file="$(mktemp "${chrome_dir}/.userChrome.css.XXXXXX")" || return 1

  {
    printf '%s\n' "${FIREFOX_USERCHROME_MARKER_START}"
    sed -n '1,$p' "${FIREFOX_USERCHROME_SOURCE}"
    printf '%s\n\n' "${FIREFOX_USERCHROME_MARKER_END}"
    if [[ -f "${target_file}" ]]; then
      awk -v start="${FIREFOX_USERCHROME_MARKER_START}" -v end="${FIREFOX_USERCHROME_MARKER_END}" '
        $0 == start { skip = 1; next }
        $0 == end { skip = 0; next }
        !skip { print }
      ' "${target_file}"
    fi
  } >"${tmp_file}"

  firefox_promote_file "${tmp_file}" "${target_file}"
}

firefox_enable_custom_chrome_pref() {
  local profile_dir="$1"
  local target_file="${profile_dir}/user.js"
  local tmp_file=""
  local pref_line="user_pref(\"${FIREFOX_CUSTOM_CHROME_PREF}\", true);"

  tmp_file="$(mktemp "${profile_dir}/.user.js.XXXXXX")" || return 1

  if [[ -f "${target_file}" ]]; then
    awk -v pref="${FIREFOX_CUSTOM_CHROME_PREF}" -v line="${pref_line}" '
      $0 ~ "^user_pref\\(\"" pref "\"," {
        if (!done) {
          print line
          done = 1
        }
        next
      }
      { print }
      END {
        if (!done) {
          print line
        }
      }
    ' "${target_file}" >"${tmp_file}"
  else
    printf '%s\n' "${pref_line}" >"${tmp_file}"
  fi

  firefox_promote_file "${tmp_file}" "${target_file}"
}

firefox_apply_profile() {
  local profile_dir="$1"

  [[ -d "${profile_dir}" ]] || return 0
  [[ -f "${FIREFOX_USERCHROME_SOURCE}" ]] || return 0
  firefox_write_userchrome_profile_css "${profile_dir}"
  firefox_enable_custom_chrome_pref "${profile_dir}"
}

firefox_render_userchrome_source

[[ -d "${FIREFOX_ROOT}" ]] || exit 0

mapfile -t firefox_profiles < <(firefox_profile_paths | LC_ALL=C sort -u)
((${#firefox_profiles[@]} > 0)) || exit 0

for firefox_profile in "${firefox_profiles[@]}"; do
  firefox_apply_profile "${firefox_profile}"
done

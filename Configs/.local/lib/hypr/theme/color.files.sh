#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# color.files.sh - Palette loading and file materialization helpers

color_replace_if_changed() {
  local target_file="$1"
  local tmp_file="$2"

  if [[ -f "${target_file}" ]] && cmp -s "${tmp_file}" "${target_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi

  mv -f "${tmp_file}" "${target_file}"
  return 0
}

load_theme_palette() {
  local theme_file="${1}"
  local bg_name="$2" fg_name="$3" cursor_name="$4" colors_name="$5"
  local -n bg_ref="$bg_name" fg_ref="$fg_name" cursor_ref="$cursor_name" colors_ref="$colors_name"
  local key="" val="" line="" i
  local -A seen=()
  [[ -r "${theme_file}" ]] || return 1

  bg_ref=""
  fg_ref=""
  cursor_ref=""
  colors_ref=()

  while IFS= read -r line || [[ -n "${line}" ]]; do
    read -r key val _ <<< "${line}"
    [[ -n "${key}" && -n "${val}" ]] || continue
    [[ -v "seen[${key}]" ]] && continue

    case "${key}" in
      background)
        bg_ref="${val}"
        seen["${key}"]=1
        ;;
      foreground)
        fg_ref="${val}"
        seen["${key}"]=1
        ;;
      cursor)
        cursor_ref="${val}"
        seen["${key}"]=1
        ;;
      color[0-9] | color1[0-5])
        [[ "${val}" =~ ^#[0-9A-Fa-f]{6}$ ]] || val=""
        colors_ref[${key#color}]="${val}"
        seen["${key}"]=1
        ;;
    esac
  done < "${theme_file}"

  for i in {0..15}; do
    [[ -n "${colors_ref[$i]}" ]] || return 1
  done

  [[ "${bg_ref}" =~ ^#[0-9A-Fa-f]{6}$ ]] || bg_ref="${colors_ref[0]}"
  [[ "${fg_ref}" =~ ^#[0-9A-Fa-f]{6}$ ]] || fg_ref="${colors_ref[15]}"
  [[ "${cursor_ref}" =~ ^#[0-9A-Fa-f]{6}$ ]] || cursor_ref="${fg_ref}"
  return 0
}

write_theme_mode_colors_json() {
  local out_file="$1"
  local theme_bg="$2"
  local theme_fg="$3"
  local theme_cursor="$4"
  local theme_colors_name="$5"
  local -n theme_colors_ref="$theme_colors_name"
  local out_dir=""
  local tmp_file=""

  out_dir="$(dirname "${out_file}")"
  mkdir -p "${out_dir}" || return 1
  tmp_file="$(mktemp "${out_dir}/.$(basename "${out_file}").XXXXXX")" || return 1

  python3 - "${tmp_file}" "${theme_bg}" "${theme_fg}" "${theme_cursor}" "${theme_colors_ref[@]}" <<'PYEOF'
import json
import sys
from pathlib import Path

target = Path(sys.argv[1])
background, foreground, cursor = sys.argv[2:5]
colors = sys.argv[5:21]

payload = {
    "checksum": "None",
    "wallpaper": "None",
    "alpha": "100",
    "special": {
        "background": background,
        "foreground": foreground,
        "cursor": cursor,
    },
    "colors": {f"color{i}": colors[i] for i in range(16)},
}

target.write_text(json.dumps(payload, indent=4) + "\n")
PYEOF

  color_replace_if_changed "${out_file}" "${tmp_file}" || return 0
}

render_theme_palette_template() {
  local template_file="$1"
  local out_file="$2"
  local colors_json="$3"
  local out_dir=""
  local tmp_file=""

  [[ -r "${template_file}" ]] || return 1
  [[ -r "${colors_json}" ]] || return 1
  out_dir="$(dirname "${out_file}")"
  mkdir -p "${out_dir}" || return 1
  tmp_file="$(mktemp "${out_dir}/.$(basename "${out_file}").XXXXXX")" || return 1

  python3 - "${template_file}" "${tmp_file}" "${colors_json}" <<'PYEOF'
import json
import re
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
colors_json = Path(sys.argv[3])
payload = json.loads(colors_json.read_text())

mapping = {}
for key, value in payload.get("special", {}).items():
    mapping[key] = value
    mapping[f"{key}.strip"] = value.lstrip("#")

for key, value in payload.get("colors", {}).items():
    mapping[key] = value
    mapping[f"{key}.strip"] = value.lstrip("#")

text = template_path.read_text()
rendered = re.sub(r"\{([A-Za-z0-9_.-]+)\}", lambda match: mapping.get(match.group(1), match.group(0)), text)
target_path.write_text(rendered)
PYEOF

  color_replace_if_changed "${out_file}" "${tmp_file}" || return 0
}

render_theme_mode_wal_templates() {
  local colors_json="$1"
  local template_dir="${XDG_CONFIG_HOME:-$HOME/.config}/wal/templates"
  local template_file=""
  local template_name=""

  [[ -d "${template_dir}" ]] || return 0

  while IFS= read -r -d '' template_file; do
    template_name="$(basename "${template_file}")"
    render_theme_palette_template \
      "${template_file}" \
      "${WAL_CACHE}/${template_name}" \
      "${colors_json}" || return 1
  done < <(find "${template_dir}" -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
}

render_theme_mode_wal_cache() {
  local theme_bg=""
  local theme_fg=""
  local theme_cursor=""
  local -a theme_colors=()

  if ! load_theme_palette "${THEME_KITTY_FILE}" theme_bg theme_fg theme_cursor theme_colors; then
    print_log -sec "theme" -warn "palette" "incomplete palette in ${THEME_KITTY_FILE}"
    return 1
  fi

  write_theme_mode_colors_json "${WAL_CACHE}/colors.json" "${theme_bg}" "${theme_fg}" "${theme_cursor}" theme_colors || return 1
  render_theme_mode_wal_templates "${WAL_CACHE}/colors.json" || return 1
  [[ -f "${WAL_CACHE}/colors-shell.sh" ]] || return 1
  [[ -f "${WAL_CACHE}/colors.json" ]] || return 1
}

resolve_wallpaper_fallback() {
  local cache_wall="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.set"
  if [[ -e "${cache_wall}" ]]; then
    readlink -f "${cache_wall}" 2>/dev/null && return 0
  fi

  local theme_wall="${HYPR_THEME_DIR}/wall.set"
  if [[ -e "${theme_wall}" ]]; then
    readlink -f "${theme_wall}" 2>/dev/null && return 0
  fi

  return 1
}

compute_template_hash() {
  local template_dir="${XDG_CONFIG_HOME:-$HOME/.config}/wal/templates"
  local hash_cmd="${HYPR_HASH_COMMAND:-sha1sum}"
  local raw_hash

  [[ -d "${template_dir}" ]] || return 0
  command -v "${hash_cmd}" &>/dev/null || hash_cmd="sha1sum"
  command -v "${hash_cmd}" &>/dev/null || return 0

  raw_hash="$({
    find "${template_dir}" -type f -print0 2>/dev/null \
      | sort -z \
      | xargs -0 "${hash_cmd}" 2>/dev/null \
      | "${hash_cmd}" 2>/dev/null \
      | awk '{print $1}'
  })"
  [[ -n "${raw_hash}" ]] && template_hash_suffix="_tpl${raw_hash:0:12}"
}

generate_hypr_colors_from_theme() {
  local kitty_theme_file="${HYPR_THEME_DIR}/kitty.theme"
  local out_file="${HOME}/.config/hypr/themes/colors.conf"
  local out_dir=""
  local tmp_file=""
  local theme_bg="" theme_fg="" theme_cursor=""
  local -a theme_colors=()

  [[ -n "${HYPR_THEME_DIR}" ]] || return 1
  [[ -r "${kitty_theme_file}" ]] || {
    print_log -sec "theme" -warn "colors" "missing kitty.theme: ${kitty_theme_file}"
    return 1
  }

  if ! load_theme_palette "${kitty_theme_file}" theme_bg theme_fg theme_cursor theme_colors; then
    print_log -sec "theme" -warn "colors" "incomplete palette in ${kitty_theme_file}"
    return 1
  fi

  out_dir="$(dirname "${out_file}")"
  mkdir -p "${out_dir}"
  tmp_file="$(mktemp "${out_dir}/.$(basename "${out_file}").XXXXXX")" || return 1
  local i
  local active_border inactive_border_bg inactive_border_fg
  local display_theme_source="${kitty_theme_file}"
  active_border="${theme_colors[4]#\#}ff"
  inactive_border_bg="${theme_colors[0]#\#}cc"
  inactive_border_fg="${theme_colors[8]#\#}cc"
  [[ -n "${HOME:-}" ]] && display_theme_source="${display_theme_source/#${HOME}/\$HOME}"

  mkdir -p "$(dirname "${out_file}")"
  [[ -L "${out_file}" ]] && rm -f "${out_file}"

  {
    echo "# Autogenerated theme colors (from kitty.theme)"
    echo "# Theme: ${HYPR_THEME}"
    echo "# Source: ${display_theme_source}"
    echo
    echo "# Standard theme colors"
    for i in {0..15}; do
      printf '\$color%s = %s\n' "${i}" "${theme_colors[$i]}"
    done
    echo
    echo "# Hyprland-friendly helpers (no leading '#')"
    for i in {0..15}; do
      local hex="${theme_colors[$i]#\#}"
      printf '\$color%see = %s\n' "${i}" "${hex}ee"
    done
    echo
    printf '\$background = %s\n' "${theme_bg}"
    printf '\$foreground = %s\n' "${theme_fg}"
    printf '\$cursor = %s\n' "${theme_fg}"
    echo
    cat <<EOF_INNER

general {
    col.active_border = rgba(${active_border}) rgba(${active_border}) 45deg
    col.inactive_border = rgba(${inactive_border_bg}) rgba(${inactive_border_fg}) 45deg
}

group {
    col.border_active = rgba(${active_border}) rgba(${active_border}) 45deg
    col.border_inactive = rgba(${inactive_border_bg}) rgba(${inactive_border_fg}) 45deg
    col.border_locked_active = rgba(${active_border}) rgba(${active_border}) 45deg
    col.border_locked_inactive = rgba(${inactive_border_bg}) rgba(${inactive_border_fg}) 45deg
}
EOF_INNER
  } >"${tmp_file}"

  mv -f "${tmp_file}" "${out_file}"
  print_log -sec "theme" -stat "colors" "wrote ${out_file}"
}

_safe_hyq_get() {
  local hyq_output="$1"
  local var_name="$2"
  local value
  value=$(echo "${hyq_output}" | grep "^__${var_name}=" | head -1 | sed 's/^__[A-Z_]*=//' | tr -d '"')
  if [[ "${value}" =~ \$\(|\`|\; ]]; then
    print_log -sec "hyq" -warn "security" "blocked unsafe value for ${var_name}"
    return 1
  fi
  echo "${value}"
}

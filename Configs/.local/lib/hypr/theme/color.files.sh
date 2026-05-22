#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# color.files.sh - Palette loading and file materialization helpers

if ! declare -F hypr_hash_cache_digest_files >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${LIB_DIR:-$HOME/.local/lib}/hypr/core/hash-cache.sh" || return 1 2>/dev/null || exit 1
fi

palette_conf_get() {
  local palette_file="$1"
  local want_section="$2"
  local want_key="$3"

  awk -F= -v want_section="${want_section}" -v want_key="${want_key}" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    /^[[:space:]]*($|[;#])/ { next }
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      section = trim($0)
      gsub(/^\[/, "", section)
      gsub(/\]$/, "", section)
      next
    }
    section == want_section {
      key = trim($1)
      if (key != want_key) {
        next
      }
      value = substr($0, index($0, "=") + 1)
      print trim(value)
      exit
    }
  ' "${palette_file}"
}

load_palette_conf() {
  local palette_file="${1}"
  local bg_name="$2" fg_name="$3" cursor_name="$4" colors_name="$5"
  local -n colors_ref="$colors_name"
  local bg="" fg="" cursor="" val="" i

  [[ -r "${palette_file}" ]] || return 1
  colors_ref=()

  bg="$(palette_conf_get "${palette_file}" "terminal" "background")"
  [[ -n "${bg}" ]] || bg="$(palette_conf_get "${palette_file}" "base" "background")"
  fg="$(palette_conf_get "${palette_file}" "terminal" "foreground")"
  [[ -n "${fg}" ]] || fg="$(palette_conf_get "${palette_file}" "base" "foreground")"
  cursor="$(palette_conf_get "${palette_file}" "terminal" "cursor")"
  [[ -n "${cursor}" ]] || cursor="${fg}"

  for i in {0..15}; do
    val="$(palette_conf_get "${palette_file}" "terminal" "color${i}")"
    [[ "${val}" =~ ^#[0-9A-Fa-f]{6}$ ]] || return 1
    colors_ref[$i]="${val}"
  done

  [[ "${bg}" =~ ^#[0-9A-Fa-f]{6}$ ]] || bg="${colors_ref[0]}"
  [[ "${fg}" =~ ^#[0-9A-Fa-f]{6}$ ]] || fg="${colors_ref[15]}"
  [[ "${cursor}" =~ ^#[0-9A-Fa-f]{6}$ ]] || cursor="${fg}"
  printf -v "${bg_name}" '%s' "${bg}"
  printf -v "${fg_name}" '%s' "${fg}"
  printf -v "${cursor_name}" '%s' "${cursor}"
}

load_theme_palette() {
  local theme_file="${1}"
  local bg_name="$2" fg_name="$3" cursor_name="$4" colors_name="$5"
  local palette_file="${theme_file%/*}/palette.conf"
  # colors is an array output, so it stays a nameref. The three scalars use
  # local working variables and write to caller via printf -v at the end.
  local -n colors_ref="$colors_name"
  local bg="" fg="" cursor=""
  local key="" val="" line="" i
  local -A seen=()

  if [[ -r "${palette_file}" ]]; then
    load_palette_conf "${palette_file}" "${bg_name}" "${fg_name}" "${cursor_name}" "${colors_name}"
    return $?
  fi

  [[ -r "${theme_file}" ]] || return 1

  colors_ref=()

  while IFS= read -r line || [[ -n "${line}" ]]; do
    read -r key val _ <<< "${line}"
    [[ -n "${key}" && -n "${val}" ]] || continue
    [[ -v "seen[${key}]" ]] && continue

    case "${key}" in
      background)
        bg="${val}"
        seen["${key}"]=1
        ;;
      foreground)
        fg="${val}"
        seen["${key}"]=1
        ;;
      cursor)
        cursor="${val}"
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

  [[ "${bg}" =~ ^#[0-9A-Fa-f]{6}$ ]] || bg="${colors_ref[0]}"
  [[ "${fg}" =~ ^#[0-9A-Fa-f]{6}$ ]] || fg="${colors_ref[15]}"
  [[ "${cursor}" =~ ^#[0-9A-Fa-f]{6}$ ]] || cursor="${fg}"
  printf -v "${bg_name}" '%s' "${bg}"
  printf -v "${fg_name}" '%s' "${fg}"
  printf -v "${cursor_name}" '%s' "${cursor}"
  return 0
}

write_theme_mode_wal_cache() {
  local out_file="$1"
  local template_dir="${XDG_CONFIG_HOME:-$HOME/.config}/wal/templates"
  local theme_bg="$2"
  local theme_fg="$3"
  local theme_cursor="$4"
  local theme_colors_name="$5"
  local -n theme_colors_ref="$theme_colors_name"
  local template_arg=""

  [[ -d "${template_dir}" ]] && template_arg="${template_dir}"
  mkdir -p "${WAL_CACHE}" || return 1

  python3 - "${out_file}" "${template_arg}" "${WAL_CACHE}" "${theme_bg}" "${theme_fg}" "${theme_cursor}" "${theme_colors_ref[@]}" <<'PYEOF'
import json
import os
import sys
import tempfile
import re
from pathlib import Path

target = Path(sys.argv[1])
template_dir = Path(sys.argv[2]) if sys.argv[2] else None
cache_dir = Path(sys.argv[3])
background, foreground, cursor = sys.argv[4:7]
colors = sys.argv[7:23]


def replace_if_changed(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == content:
        return
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as tmp:
            tmp.write(content)
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


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

replace_if_changed(target, json.dumps(payload, indent=4) + "\n")

mapping = {}
for key, value in payload.get("special", {}).items():
    mapping[key] = value
    mapping[f"{key}.strip"] = value.lstrip("#")

for key, value in payload.get("colors", {}).items():
    mapping[key] = value
    mapping[f"{key}.strip"] = value.lstrip("#")

if template_dir and template_dir.is_dir():
    for template_path in sorted(path for path in template_dir.iterdir() if path.is_file()):
        text = template_path.read_text()
        rendered = re.sub(
            r"\{([A-Za-z0-9_.-]+)\}",
            lambda match: mapping.get(match.group(1), match.group(0)),
            text,
        )
        # Match pywal16 export.template(): collapse escaped braces so CSS/JSON literal `{`/`}` survive.
        rendered = rendered.replace("{{", "{").replace("}}", "}")
        replace_if_changed(cache_dir / template_path.name, rendered)
PYEOF
}

render_theme_mode_wal_cache() {
  local theme_bg=""
  local theme_fg=""
  local theme_cursor=""
  local -a theme_colors=()
  local kitty_theme_file="${HYPR_THEME_DIR}/kitty.theme"

  if ! load_theme_palette "${kitty_theme_file}" theme_bg theme_fg theme_cursor theme_colors; then
    print_log -sec "theme" -warn "palette" "incomplete palette in ${kitty_theme_file}"
    return 1
  fi

  write_theme_mode_wal_cache "${WAL_CACHE}/colors.json" "${theme_bg}" "${theme_fg}" "${theme_cursor}" theme_colors || return 1
  [[ -f "${WAL_CACHE}/colors-shell.sh" ]] || return 1
  [[ -f "${WAL_CACHE}/colors.json" ]] || return 1
}

resolve_current_wallpaper() {
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

color_pipeline_tracked_generator_files() {
  local out_name="$1"
  local -n out_ref="${out_name}"
  local script=""
  local script_path=""
  local -a candidates=(
    "${SCRIPT_DIR}/color.lock.sh"
    "${SCRIPT_DIR}/color.state.sh"
    "${SCRIPT_DIR}/color.plan.sh"
    "${SCRIPT_DIR}/color.cache.sh"
    "${SCRIPT_DIR}/color.apply.sh"
    "${SCRIPT_DIR}/color.targets.sh"
    "${SCRIPT_DIR}/color.files.sh"
    "${SCRIPT_DIR}/color.pipeline.sh"
    "${SCRIPT_DIR}/color.finalize.sh"
    "${SCRIPT_DIR}/waybar_palette.py"
  )

  for script in "${APP_THEMING_SCRIPTS[@]:-}" "${SECONDARY_THEMING_SCRIPTS[@]:-}"; do
    script_path="${LIB_DIR}/hypr/${script}"
    candidates+=("${script_path}")
  done

  out_ref=()
  for script_path in "${candidates[@]}"; do
    [[ -f "${script_path}" ]] || continue
    case " ${out_ref[*]} " in
      *" ${script_path} "*) continue ;;
    esac
    out_ref+=("${script_path}")
  done
}

color_pipeline_wal_identity() {
  local wal_path=""
  local wal_version=""
  local wal_stat=""

  wal_path="$(command -v wal 2>/dev/null || true)"
  [[ -n "${wal_path}" ]] || {
    printf 'wal=missing\n'
    return 0
  }

  wal_version="$(wal --version 2>/dev/null | head -1 || true)"
  wal_stat="$(stat -Lc '%n:%Y:%s' "${wal_path}" 2>/dev/null || printf '%s\n' "${wal_path}")"
  printf 'wal=%s\n' "${wal_path}"
  [[ -n "${wal_version}" ]] && printf 'wal_version=%s\n' "${wal_version}"
  printf 'wal_stat=%s\n' "${wal_stat}"
}

color_pipeline_file_tuple_digest() {
  local -a files=("$@")
  local file=""
  local -a existing_files=()
  local -a tuples=()

  for file in "${files[@]}"; do
    [[ -f "${file}" ]] || continue
    existing_files+=("${file}")
  done

  if ((${#existing_files[@]} > 0)); then
    mapfile -t tuples < <(stat -Lc '%n:%Y:%s' -- "${existing_files[@]}" 2>/dev/null)
  fi
  hypr_hash_cache_digest_strings "${tuples[@]}"
}

color_pipeline_cached_generator_hash() {
  local cache_file=""
  local tuple_hash=""
  local cached_tuple_hash=""
  local cached_script_hash=""
  local files_hash=""
  local wal_identity=""
  local script_hash=""
  local -a tracked_files=()

  color_pipeline_tracked_generator_files tracked_files
  wal_identity="$(color_pipeline_wal_identity)"
  tuple_hash="$(hypr_hash_cache_digest_strings "$(color_pipeline_file_tuple_digest "${tracked_files[@]}")" "${wal_identity}")"
  cache_file="$(hypr_hash_cache_file "color-pipeline-generators.meta")" || return 1

  if [[ -f "${cache_file}" ]]; then
    cached_tuple_hash="$(hypr_hash_cache_metadata_value "${cache_file}" "tuple_hash" 2>/dev/null || true)"
    cached_script_hash="$(hypr_hash_cache_metadata_value "${cache_file}" "script_hash" 2>/dev/null || true)"
    if [[ -n "${cached_script_hash}" && "${cached_tuple_hash}" == "${tuple_hash}" ]]; then
      printf '%s\n' "${cached_script_hash}"
      return 0
    fi
  fi

  files_hash="$(hypr_hash_cache_digest_files "${tracked_files[@]}")" || return 1
  script_hash="$(hypr_hash_cache_digest_strings "${files_hash}" "${wal_identity}")" || return 1
  hypr_hash_cache_metadata_store \
    "${cache_file}" \
    "tuple_hash=${tuple_hash}" \
    "script_hash=${script_hash}" || true
  printf '%s\n' "${script_hash}"
}

compute_pipeline_input_hash() {
  local template_dir="${XDG_CONFIG_HOME:-$HOME/.config}/wal/templates"
  local generator_hash=""
  local template_hash=""
  local template_file=""
  local -a template_files=()

  generator_hash="$(color_pipeline_cached_generator_hash)" || return 1

  if [[ -d "${template_dir}" ]]; then
    while IFS= read -r -d '' template_file; do
      template_files+=("${template_file}")
    done < <(find "${template_dir}" -type f -print0 2>/dev/null | LC_ALL=C sort -z)
  fi

  if [[ ${#template_files[@]} -gt 0 ]]; then
    template_hash="$(hypr_hash_cache_digest_files "${template_files[@]}")" || return 1
  else
    template_hash="none"
  fi

  hypr_hash_cache_digest_strings \
    "generators=${generator_hash}" \
    "templates=${template_hash}"
}

color_pipeline_labeled_file_digest() {
  local label="$1"
  local file="$2"
  local file_hash=""

  if [[ -f "${file}" ]]; then
    file_hash="$(hypr_hash_cache_digest_files "${file}")" || return 1
    printf '%s=%s\n' "${label}" "${file_hash}"
  else
    printf '%s=missing\n' "${label}"
  fi
}

compute_theme_mode_input_hash() {
  local file=""
  local rel=""
  local metadata_file="${HYPR_THEME_METADATA_FILE:-${HYPR_CONFIG_HOME}/themes/theme.conf}"
  local userfonts_file="${HYPR_CONFIG_HOME}/userfonts.conf"
  local variables_file="${XDG_DATA_HOME:-$HOME/.local/share}/hypr/variables.conf"
  local cache_key=""
  local cache_file=""
  local tuple_hash=""
  local cached_tuple_hash=""
  local cached_input_hash=""
  local input_hash=""
  local label=""
  local index=0
  local -a entries=()
  local -a tracked_entries=()
  local -a tuple_entries=()
  local -a tuple_files=()
  local -a tuple_labels=()
  local -a stat_tuples=()

  if [[ -d "${HYPR_THEME_DIR}" ]]; then
    while IFS= read -r -d '' file; do
      rel="${file#"${HYPR_THEME_DIR}/"}"
      tracked_entries+=("theme:${rel}|${file}")
    done < <(
      find "${HYPR_THEME_DIR}" -type f \
        ! -path "${HYPR_THEME_DIR}/wallpapers/*" \
        -print0 2>/dev/null | LC_ALL=C sort -z
    )
  fi

  tracked_entries+=("metadata|${metadata_file}")
  tracked_entries+=("userfonts|${userfonts_file}")
  tracked_entries+=("variables|${variables_file}")

  for entry in "${tracked_entries[@]}"; do
    label="${entry%%|*}"
    file="${entry#*|}"
    if [[ -f "${file}" ]]; then
      tuple_labels+=("${label}")
      tuple_files+=("${file}")
    else
      tuple_entries+=("${label}|missing|${file}")
    fi
  done

  if ((${#tuple_files[@]} > 0)); then
    mapfile -t stat_tuples < <(stat -Lc '%n:%Y:%Z:%s' -- "${tuple_files[@]}" 2>/dev/null)
    for index in "${!tuple_files[@]}"; do
      tuple_entries+=("${tuple_labels[index]}|${stat_tuples[index]:-${tuple_files[index]}}")
    done
  fi

  cache_key="$(hypr_hash_cache_digest_strings "theme=${HYPR_THEME}" "dir=${HYPR_THEME_DIR}")"
  cache_file="$(hypr_hash_cache_file "color-theme-input-${cache_key}.meta")" || return 1
  tuple_hash="$(hypr_hash_cache_digest_strings "${tuple_entries[@]}")" || return 1

  if [[ -f "${cache_file}" ]]; then
    cached_tuple_hash="$(hypr_hash_cache_metadata_value "${cache_file}" "tuple_hash" 2>/dev/null || true)"
    cached_input_hash="$(hypr_hash_cache_metadata_value "${cache_file}" "input_hash" 2>/dev/null || true)"
    if [[ -n "${cached_input_hash}" && "${cached_tuple_hash}" == "${tuple_hash}" ]]; then
      printf '%s\n' "${cached_input_hash}"
      return 0
    fi
  fi

  entries+=("theme=${HYPR_THEME}")
  for entry in "${tracked_entries[@]}"; do
    label="${entry%%|*}"
    file="${entry#*|}"
    entries+=("$(color_pipeline_labeled_file_digest "${label}" "${file}")")
  done

  input_hash="$(hypr_hash_cache_digest_strings "${entries[@]}")" || return 1
  hypr_hash_cache_metadata_store \
    "${cache_file}" \
    "tuple_hash=${tuple_hash}" \
    "input_hash=${input_hash}" || true

  printf '%s\n' "${input_hash}"
}

compute_template_hash() {
  local pipeline_hash=""

  pipeline_hash="$(compute_pipeline_input_hash)" || return 0
  PIPELINE_INPUT_HASH="${pipeline_hash}"
  [[ -n "${pipeline_hash}" ]] && template_hash_suffix="_pipe${pipeline_hash:0:12}"
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
  value="$(
    awk -F= -v key="__${var_name}" '$1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/"/, "", value)
      print value
      exit
    }' <<<"${hyq_output}"
  )"
  if [[ "${value}" =~ \$\(|\`|\; ]]; then
    print_log -sec "hyq" -warn "security" "blocked unsafe value for ${var_name}"
    return 1
  fi
  echo "${value}"
}

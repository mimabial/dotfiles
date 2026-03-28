#!/usr/bin/env bash

# Shared config/state helpers for theme.switch.sh.

hypr_variable_cache_dir() {
  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/hypr/hyq/cache"
}

hypr_variable_cache_file() {
  local hypr_file="$1"
  local file_hash=""
  local file_mtime=""

  file_hash="$(printf '%s' "${hypr_file}" | md5sum | cut -d' ' -f1)"
  file_mtime="$(stat -c %Y "${hypr_file}" 2>/dev/null || echo "0")"
  printf '%s/%s-%s.cache\n' "$(hypr_variable_cache_dir)" "${file_hash}" "${file_mtime}"
}

hypr_variable_query() {
  local hypr_file="$1"

  hyq "${hypr_file}" \
    --export env \
    --allow-missing \
    -Q "\$GTK_THEME[string]" \
    -Q "\$ICON_THEME[string]" \
    -Q "\$CURSOR_THEME[string]" \
    -Q "\$CURSOR_SIZE" \
    -Q "\$FONT[string]" \
    -Q "\$TERMINAL_FONT[string]" \
    -Q "\$FONT_SIZE" \
    -Q "\$FONT_STYLE[string]" \
    -Q "\$DOCUMENT_FONT[string]" \
    -Q "\$DOCUMENT_FONT_SIZE" \
    -Q "\$MONOSPACE_FONT[string]" \
    -Q "\$MONOSPACE_FONT_SIZE" \
    -Q "\$BAR_FONT[string]" \
    -Q "\$MENU_FONT[string]" \
    -Q "\$NOTIFICATION_FONT[string]" \
    -Q "\$GROUPBAR_FONT[string]"
}

hypr_variable_validate() {
  local line=""
  local allowed_vars='^__(GTK_THEME|ICON_THEME|CURSOR_THEME|CURSOR_SIZE|FONT|TERMINAL_FONT|FONT_SIZE|FONT_STYLE|DOCUMENT_FONT|DOCUMENT_FONT_SIZE|MONOSPACE_FONT|MONOSPACE_FONT_SIZE|BAR_FONT|MENU_FONT|NOTIFICATION_FONT|GROUPBAR_FONT|TERMINAL)='

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    if [[ ! "${line}" =~ ${allowed_vars} ]]; then
      print_log -sec "theme" -warn "security" "blocked unexpected variable: ${line}"
      continue
    fi
    if [[ "${line}" =~ \$\(|\`|\; ]]; then
      print_log -sec "theme" -warn "security" "blocked unsafe pattern in: ${line}"
      continue
    fi
    printf '%s\n' "${line}"
  done
}

hypr_variable_unquote() {
  local value="$1"

  if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
    value="${value:1:-1}"
  elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
    value="${value:1:-1}"
  fi

  printf '%s\n' "${value}"
}

apply_hypr_variable_line() {
  local line="$1"
  local key=""
  local value=""

  [[ "${line}" =~ ^__([A-Z_]+)=(.*)$ ]] || return 0
  key="${BASH_REMATCH[1]}"
  value="$(hypr_variable_unquote "${BASH_REMATCH[2]}")"

  case "${key}" in
    GTK_THEME) GTK_THEME="${value:-$GTK_THEME}" ;;
    ICON_THEME) ICON_THEME="${value:-$ICON_THEME}" ;;
    CURSOR_THEME) CURSOR_THEME="${value:-$CURSOR_THEME}" ;;
    CURSOR_SIZE) CURSOR_SIZE="${value:-$CURSOR_SIZE}" ;;
    TERMINAL) TERMINAL="${value:-$TERMINAL}" ;;
    FONT) FONT="${value:-$FONT}" ;;
    TERMINAL_FONT) TERMINAL_FONT="${value:-$TERMINAL_FONT}" ;;
    FONT_STYLE) FONT_STYLE="${value}" ;;
    FONT_SIZE) FONT_SIZE="${value:-$FONT_SIZE}" ;;
    DOCUMENT_FONT) DOCUMENT_FONT="${value:-$DOCUMENT_FONT}" ;;
    DOCUMENT_FONT_SIZE) DOCUMENT_FONT_SIZE="${value:-$DOCUMENT_FONT_SIZE}" ;;
    MONOSPACE_FONT) MONOSPACE_FONT="${value:-$MONOSPACE_FONT}" ;;
    MONOSPACE_FONT_SIZE) MONOSPACE_FONT_SIZE="${value:-$MONOSPACE_FONT_SIZE}" ;;
    BAR_FONT) BAR_FONT="${value:-$BAR_FONT}" ;;
    MENU_FONT) MENU_FONT="${value:-$MENU_FONT}" ;;
    NOTIFICATION_FONT) NOTIFICATION_FONT="${value:-$NOTIFICATION_FONT}" ;;
    GROUPBAR_FONT) GROUPBAR_FONT="${value:-$GROUPBAR_FONT}" ;;
  esac
}

apply_hypr_variable_file() {
  local input_file="$1"
  local line=""

  while IFS= read -r line; do
    apply_hypr_variable_line "${line}"
  done <"${input_file}"
}

trim_hypr_variable_cache() {
  local cache_dir="$1"

  find "${cache_dir}" -name "*.cache" -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | tail -n +21 | cut -d' ' -f2- | xargs -r rm -f
}

load_hypr_variables() {
  local hypr_file="$1"
  local cache_dir=""
  local cache_file=""

  if ! command -v hyq &>/dev/null; then
    print_log -sec "theme" -warn "hyq not found" "theme variables won't be loaded from ${hypr_file}"
    return 1
  fi

  if [[ ! -r "${hypr_file}" ]]; then
    print_log -sec "theme" -warn "file not readable" "${hypr_file}"
    return 1
  fi

  cache_dir="$(hypr_variable_cache_dir)"
  cache_file="$(hypr_variable_cache_file "${hypr_file}")"

  if [[ ! -f "${cache_file}" ]]; then
    mkdir -p "${cache_dir}" || return 1
    if ! hypr_variable_query "${hypr_file}" | hypr_variable_validate >"${cache_file}.tmp"; then
      rm -f "${cache_file}.tmp"
      return 1
    fi
    mv "${cache_file}.tmp" "${cache_file}" || {
      rm -f "${cache_file}.tmp"
      return 1
    }
    trim_hypr_variable_cache "${cache_dir}"
  fi

  apply_hypr_variable_file "${cache_file}"
}

# Batch write INI-style config files (single sed pass per file)
# Usage: ini_write_batch "file" "group1:key1=value1" "group2:key2=value2" ...
ini_write_batch() {
  local config_file="$1"
  shift
  local sed_args=()
  declare -A group_keys

  # Ensure file exists
  [ ! -f "$config_file" ] && mkdir -p "$(dirname "$config_file")" && touch "$config_file"

  for entry in "$@"; do
    local group="${entry%%:*}"
    local rest="${entry#*:}"
    local key="${rest%%=*}"
    local value="${rest#*=}"
    local group_esc key_esc value_esc
    group_esc="$(escape_regex "$group")"
    key_esc="$(escape_regex "$key")"
    value_esc="$(printf '%s' "$value" | sed 's/[&\\/]/\\&/g')"

    # Build sed expression to update existing key or mark for addition
    sed_args+=(-e "/^\[${group_esc}\]/,/^\[/ { s/^${key_esc}=.*/${key}=${value_esc}/ }")

    # Track group/key pairs for adding missing ones
    group_keys["${group}"]+="${key}=${value}"$'\n'
  done

  # Apply existing key updates
  if [ ${#sed_args[@]} -gt 0 ]; then
    sed -i "${sed_args[@]}" "$config_file"
  fi

  # Add missing groups and keys
  for group in "${!group_keys[@]}"; do
    local group_esc
    group_esc="$(escape_regex "$group")"
    if ! grep -q "^\[${group_esc}\]" "$config_file"; then
      echo -e "\n[${group}]" >>"$config_file"
    fi
    while IFS= read -r kv; do
      [[ -z "${kv}" ]] && continue
      local key="${kv%%=*}"
      if ! ini_group_has_key "$config_file" "$group" "$key"; then
        local kv_esc
        kv_esc="$(sed_escape_append_text "${kv}")"
        sed -i "/^\[${group_esc}\]/a ${kv_esc}" "$config_file"
      fi
    done <<<"${group_keys[$group]}"
  done
}

sanitize_hypr_theme() {
  local input_file="${1}"
  local output_file="${2}"
  local buffer_file=""
  local pattern=""
  local line=""
  local line_esc=""
  local log_line=""
  local -a dirty_regex=(
    "^ *exec"
    "^ *decoration[^:]*: *drop_shadow"
    "^ *drop_shadow"
    "^ *decoration[^:]*: *shadow *="
    "^ *decoration[^:]*: *col.shadow* *="
    "^ *shadow_"
    "^ *col.shadow*"
    "^ *shadow:"
  )

  dirty_regex+=("${HYPR_CONFIG_SANITIZE[@]}")
  buffer_file="$(mktemp)" || return 1
  trap 'rm -f "${buffer_file}"' RETURN

  sed '1d' "${input_file}" >"${buffer_file}" || return 1

  for pattern in "${dirty_regex[@]}"; do
    local -a matches=()
    while IFS= read -r line; do
      matches+=("$line")
    done < <(grep -E "${pattern}" "${buffer_file}" 2>/dev/null)

    for line in "${matches[@]}"; do
      [[ -n "$line" ]] || continue
      line_esc="$(escape_regex "${line}")"
      sed -i "\|${line_esc}|d" "${buffer_file}"
      log_line="${line#"${line%%[![:space:]]*}"}"
      print_log -sec "theme" -warn "sanitize" "${log_line}"
    done
  done

  cat "${buffer_file}" >"${output_file}"
}

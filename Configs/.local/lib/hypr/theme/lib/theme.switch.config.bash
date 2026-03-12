#!/usr/bin/env bash

# Shared config/state helpers for theme.switch.sh.

load_hypr_variables() {
  local hypr_file="${1}"
  local hypr_file_normalized="${hypr_file}"
  local tmp_file=""

  # Check if hyq is available
  if ! command -v hyq &>/dev/null; then
    print_log -sec "theme" -warn "hyq not found" "theme variables won't be loaded from ${hypr_file}"
    return 1
  fi

  # Check if file exists
  if [[ ! -r "${hypr_file}" ]]; then
    print_log -sec "theme" -warn "file not readable" "${hypr_file}"
    return 1
  fi

  # Cache setup: use file path hash + mtime as cache key
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/hyq/cache"
  local file_hash file_mtime cache_key cache_file
  file_hash=$(echo -n "${hypr_file}" | md5sum | cut -d' ' -f1)
  file_mtime=$(stat -c %Y "${hypr_file}" 2>/dev/null || echo "0")
  cache_key="${file_hash}-${file_mtime}"
  cache_file="${cache_dir}/${cache_key}.cache"

  # Check cache hit - cache files are pre-validated
  if [[ -f "${cache_file}" ]]; then
    # shellcheck disable=SC1090
    source "${cache_file}"
    _apply_hypr_variables
    return 0
  fi

  # Cache miss - run hyq
  mkdir -p "${cache_dir}"

  #? Load theme specific variables and cache the result
  local hyq_output
  hyq_output="$(
    hyq "${hypr_file}" \
      --export env \
      --allow-missing \
      -Q "\$GTK_THEME[string]" \
      -Q "\$ICON_THEME[string]" \
      -Q "\$CURSOR_THEME[string]" \
      -Q "\$CURSOR_SIZE" \
      -Q "\$FONT[string]" \
      -Q "\$FONT_SIZE" \
      -Q "\$FONT_STYLE[string]" \
      -Q "\$DOCUMENT_FONT[string]" \
      -Q "\$DOCUMENT_FONT_SIZE" \
      -Q "\$MONOSPACE_FONT[string]" \
      -Q "\$MONOSPACE_FONT_SIZE"
  )"

  # SECURITY: Validate hyq output before sourcing (safe: only allow expected variable patterns)
  # Expected format: __VARIABLE_NAME="value" or __VARIABLE_NAME=number
  local validated_output=""
  local allowed_vars="^__(GTK_THEME|ICON_THEME|CURSOR_THEME|CURSOR_SIZE|FONT|FONT_SIZE|FONT_STYLE|DOCUMENT_FONT|DOCUMENT_FONT_SIZE|MONOSPACE_FONT|MONOSPACE_FONT_SIZE|BAR_FONT|MENU_FONT|NOTIFICATION_FONT|TERMINAL)="
  while IFS= read -r line; do
    # Skip empty lines
    [[ -z "${line}" ]] && continue
    # Validate line matches expected pattern: __VAR_NAME="value" or __VAR_NAME=number
    if [[ "${line}" =~ ${allowed_vars} ]]; then
      # Additional check: ensure no command substitution or dangerous characters
      if [[ ! "${line}" =~ \$\(|\`|\; ]]; then
        validated_output+="${line}"$'\n'
      else
        print_log -sec "theme" -warn "security" "blocked unsafe pattern in: ${line}"
      fi
    else
      print_log -sec "theme" -warn "security" "blocked unexpected variable: ${line}"
    fi
  done <<<"${hyq_output}"

  # Save validated output to cache (atomic write)
  echo "${validated_output}" >"${cache_file}.tmp" && mv "${cache_file}.tmp" "${cache_file}"

  # Clean old cache entries (keep last 20)
  find "${cache_dir}" -name "*.cache" -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | tail -n +21 | cut -d' ' -f2- | xargs -r rm -f

  # Source validated output (safe: contains only validated variable assignments)
  # shellcheck disable=SC1090
  source <(echo "${validated_output}")
  _apply_hypr_variables
}

# Helper to apply loaded variables (avoids duplication)
_apply_hypr_variables() {
  GTK_THEME=${__GTK_THEME:-$GTK_THEME}
  ICON_THEME=${__ICON_THEME:-$ICON_THEME}
  CURSOR_THEME=${__CURSOR_THEME:-$CURSOR_THEME}
  CURSOR_SIZE=${__CURSOR_SIZE:-$CURSOR_SIZE}
  TERMINAL=${__TERMINAL:-$TERMINAL}
  FONT=${__FONT:-$FONT}
  FONT_STYLE=${__FONT_STYLE:-''} # using hyprland this should be empty by default
  FONT_SIZE=${__FONT_SIZE:-$FONT_SIZE}
  DOCUMENT_FONT=${__DOCUMENT_FONT:-$DOCUMENT_FONT}
  DOCUMENT_FONT_SIZE=${__DOCUMENT_FONT_SIZE:-$DOCUMENT_FONT_SIZE}
  MONOSPACE_FONT=${__MONOSPACE_FONT:-$MONOSPACE_FONT}
  MONOSPACE_FONT_SIZE=${__MONOSPACE_FONT_SIZE:-$MONOSPACE_FONT_SIZE}
  BAR_FONT=${__BAR_FONT:-$BAR_FONT}
  MENU_FONT=${__MENU_FONT:-$MENU_FONT}
  NOTIFICATION_FONT=${__NOTIFICATION_FONT:-$NOTIFICATION_FONT}
}

# Escape special regex characters for sed/grep
escape_regex() {
  printf '%s' "$1" | sed 's/[][\/.^$*]/\\&/g'
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
      local key_esc
      key_esc="$(escape_regex "$key")"
      if ! grep -q "^${key_esc}=" "$config_file"; then
        sed -i "/^\[${group_esc}\]/a ${kv}" "$config_file"
      fi
    done <<<"${group_keys[$group]}"
  done
}

sanitize_hypr_theme() {
  input_file="${1}"
  output_file="${2}"
  buffer_file="$(mktemp)"

  sed '1d' "${input_file}" >"${buffer_file}"
  # Define an array of patterns to remove
  # Supports regex patterns
  dirty_regex=(
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

  # Loop through each pattern and remove matching lines
  for pattern in "${dirty_regex[@]}"; do
    # Read matching lines into array (avoids subshell)
    local -a matches=()
    while IFS= read -r line; do
      matches+=("$line")
    done < <(grep -E "${pattern}" "${buffer_file}" 2>/dev/null)

    # Remove each match with sed
    for line in "${matches[@]}"; do
      [[ -n "$line" ]] || continue
      sed -i "\|${line}|d" "${buffer_file}"
      local log_line="${line#"${line%%[![:space:]]*}"}"
      print_log -sec "theme" -warn "sanitize" "${log_line}"
    done
  done
  cat "${buffer_file}" >"${output_file}"
  rm -f "${buffer_file}"

}

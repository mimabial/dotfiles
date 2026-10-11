#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/applications/desktop-exec.bash"

DESKTOP_ENTRY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_ENTRY_ICON_DIR="${DESKTOP_ENTRY_DIR}/icons"
WEBAPP_LAUNCHER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hypr/webapps"
TUI_MARKER='X-Hypr-Tui=true'
WEBAPP_MARKER='X-Hypr-WebApp=true'
WEBAPP_ID_KEY='X-Hypr-WebApp-Id'

desktop_entry_escape_string_value() {
  local value="${1-}"

  value=${value//\\/\\\\}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}

  printf '%s\n' "$value"
}

desktop_entry_quote_exec_arg() {
  local value="${1-}"

  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\`/\\\`}
  value=${value//\$/\\\$}
  value=${value//%/%%}
  printf '"%s"\n' "$value"
}

desktop_entry_write_exec_launcher() {
  local launcher_path="$1"
  shift

  mkdir -p "$(dirname "$launcher_path")"

  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'exec'
    local arg=""
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf ' "$@"\n'
  } >"$launcher_path"

  chmod +x "$launcher_path"
}

desktop_entry_normalize_mime_types() {
  local out_name="$1" raw="${2-}"
  local entry=""
  local mime_pattern='^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*$'
  local -a normalized=()

  printf -v "${out_name}" '%s' ""
  [[ -n "$raw" ]] || return 0

  raw=${raw//$'\n'/;}
  raw=${raw//,/;}

  while IFS= read -r entry; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -n "$entry" ]] || continue

    if [[ ! "$entry" =~ $mime_pattern ]]; then
      printf 'Invalid MIME type: %s\n' "$entry" >&2
      return 1
    fi

    normalized+=("$entry")
  done < <(printf '%s\n' "$raw" | tr ';' '\n')

  if ((${#normalized[@]})); then
    printf -v "${out_name}" '%s;' "${normalized[@]}"
  fi
}

desktop_entry_safe_id() {
  local value="${1-}"

  value="${value//\//-}"
  value="${value//$'\n'/-}"
  value="${value//$'\r'/-}"
  value="${value//$'\t'/-}"
  value="${value// /-}"
  value="$(printf '%s' "$value" | tr -cd '[:alnum:]._-')"
  value="${value##[-.]}"
  value="${value%%[-.]}"

  [[ -n "$value" ]] || value="webapp"
  printf '%s\n' "$value"
}

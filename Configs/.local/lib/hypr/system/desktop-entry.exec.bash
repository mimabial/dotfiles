#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

N=$'\n'
RSEP=$(printf '%b' '\036')
USEP=$(printf '%b' '\037')

desktop_entry_exec_debug() {
  :
}

desktop_entry_exec_error() {
  printf '%s\n' "$@" >&2
}

replace() {
  local r_remainder="${1-}"
  local needle="${2-}"
  local replacement="${3-}"
  local r_left=""

  REPLACED_STR=""
  while [[ -n "$r_remainder" ]]; do
    r_left=${r_remainder%%"$needle"*}
    REPLACED_STR+="${r_left}"
    [[ "$r_left" == "$r_remainder" ]] && break
    REPLACED_STR+="${replacement}"
    r_remainder=${r_remainder#*"$needle"}
  done
}

debug() {
  desktop_entry_exec_debug "$@"
}

error() {
  desktop_entry_exec_error "$@"
}

HYPR_SYSTEM_DIR="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system"

# shellcheck source=/dev/null
source "${HYPR_SYSTEM_DIR}/app2unit.desktop.sh"

desktop_entry_exec_reset_state() {
  OIFS=$IFS
  LCODE=${LANGUAGE:-${LANG:-}}
  LCODE=${LCODE%_*}
  LCODE=${LCODE:-NOLCODE}

  ENTRY_ID=""
  ENTRY_ACTION=""
  ENTRY_PATH=""
  ENTRY_TYPE=""
  ENTRY_URL=""
  ENTRY_NAME=""
  ENTRY_ICON=""
  ENTRY_WORKDIR=""
  EXEC_NAME=""
  EXEC_PATH=""
  EXEC_USEP=""
  EXEC_RSEP_USEP=""
  EXPANDED_STR=""
  REPLACED_STR=""
}

desktop_entry_exec_split_usep() {
  local payload="${1-}"
  local token=""

  DESKTOP_ENTRY_ARGV=()

  while [[ -n "$payload" ]]; do
    if [[ "$payload" == *"$USEP"* ]]; then
      token=${payload%%"$USEP"*}
      DESKTOP_ENTRY_ARGV+=("$token")
      payload=${payload#*"$USEP"}
    else
      DESKTOP_ENTRY_ARGV+=("$payload")
      break
    fi
  done
}

desktop_entry_exec_tokenize_spec() {
  local exec_spec="${1-}"

  desktop_entry_exec_reset_state
  ENTRY_ID="inline-exec"

  [[ -n "$exec_spec" ]] || {
    error "Exec spec is empty"
    return 1
  }

  de_expand_str "$exec_spec"
  de_tokenize_exec "$EXPANDED_STR" || return 1
  desktop_entry_exec_split_usep "$EXEC_USEP"

  if [[ "${#DESKTOP_ENTRY_ARGV[@]}" -eq 0 ]]; then
    error "Resolved Exec spec is empty"
    return 1
  fi

  DESKTOP_ENTRY_EXECUTABLE="${DESKTOP_ENTRY_ARGV[0]##*/}"
}

desktop_entry_exec_resolve() {
  local entry_spec="${1-}"
  shift || true

  desktop_entry_exec_reset_state

  case "$entry_spec" in
    "")
      error "Desktop entry not specified"
      return 1
      ;;
    *.desktop:*)
      IFS=: read -r ENTRY_ID ENTRY_ACTION <<<"$entry_spec"
      ;;
    *.desktop)
      ENTRY_ID="$entry_spec"
      ;;
    *)
      error "Unsupported desktop entry spec: '$entry_spec'"
      return 1
      ;;
  esac

  make_paths
  ENTRY_PATH="$(find_entry "$ENTRY_ID")" || return 1
  read_entry_path "$ENTRY_PATH" "$ENTRY_ACTION" || return 1

  if [[ -n "$ENTRY_URL" ]]; then
    error "${ENTRY_ID}: Link desktop entries are not supported here"
    return 1
  fi

  de_inject_fields "$@" || return 1

  if [[ "$EXEC_RSEP_USEP" == *"$RSEP"* ]]; then
    error "${ENTRY_ID}: Multiple Exec iterations are not supported here"
    return 1
  fi

  desktop_entry_exec_split_usep "$EXEC_RSEP_USEP"
  if [[ "${#DESKTOP_ENTRY_ARGV[@]}" -eq 0 ]]; then
    error "${ENTRY_ID}: Resolved Exec is empty"
    return 1
  fi

  DESKTOP_ENTRY_WORKDIR="$ENTRY_WORKDIR"
  DESKTOP_ENTRY_EXECUTABLE="${DESKTOP_ENTRY_ARGV[0]##*/}"
}

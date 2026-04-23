#!/usr/bin/env bash

tmux_resurrect_dir() {
  printf '%s\n' "${TMUX_RESURRECT_DIR:-${HOME}/.local/share/tmux/resurrect}"
}

tmux_resurrect_last_file() {
  printf '%s/last\n' "$(tmux_resurrect_dir)"
}

tmux_resurrect_is_valid_snapshot() {
  local snapshot="${1:-}"

  [[ -n "${snapshot}" ]] || return 1
  [[ -f "${snapshot}" ]] || return 1
  [[ -s "${snapshot}" ]] || return 1
  grep -q $'^pane\t' "${snapshot}"
}

tmux_resurrect_current_target() {
  local last_file=""
  local target=""

  last_file="$(tmux_resurrect_last_file)"
  [[ -e "${last_file}" || -L "${last_file}" ]] || return 1

  target="$(readlink -f -- "${last_file}" 2>/dev/null || realpath -- "${last_file}" 2>/dev/null)" || return 1
  [[ -n "${target}" ]] || return 1
  printf '%s\n' "${target}"
}

tmux_resurrect_latest_valid_snapshot() {
  local resurrect_dir=""
  local candidate=""

  resurrect_dir="$(tmux_resurrect_dir)"
  [[ -d "${resurrect_dir}" ]] || return 1

  while IFS= read -r candidate; do
    tmux_resurrect_is_valid_snapshot "${candidate}" || continue
    printf '%s\n' "${candidate}"
    return 0
  done < <(find "${resurrect_dir}" -maxdepth 1 -type f -name 'tmux_resurrect_*.txt' | sort -r)

  return 1
}

tmux_resurrect_repoint_last_to_latest_valid() {
  local last_file=""
  local snapshot=""

  last_file="$(tmux_resurrect_last_file)"
  snapshot="$(tmux_resurrect_latest_valid_snapshot)" || return 1
  mkdir -p "$(dirname "${last_file}")"
  ln -fs "$(basename "${snapshot}")" "${last_file}"
  printf '%s\n' "${snapshot}"
}

tmux_server_available() {
  tmux list-sessions >/dev/null 2>&1
}

#!/usr/bin/env bash
# Sync theme changes to all running Neovim instances

theme_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"

log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
log_file="${log_dir}/nvim-theme-sync.log"
mkdir -p "${log_dir}"

log_warn() {
  printf '%s [warn] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${log_file}"
}

runtime_dir="/run/user/$(id -u)"

shopt -s nullglob
for socket in "${runtime_dir}"/nvim.*.0; do
  [ -S "${socket}" ] || continue

  base="$(basename "${socket}")"
  pid=""
  if [[ "${base}" =~ ^nvim\.([0-9]+)\..* ]]; then
    pid="${BASH_REMATCH[1]}"
  fi

  if [[ -z "${pid}" ]]; then
    log_warn "skip socket with no pid: ${socket}"
    continue
  fi

  if ! kill -0 "${pid}" 2>/dev/null; then
    log_warn "remove stale socket: ${socket} (pid ${pid} not running)"
    rm -f "${socket}"
    continue
  fi

  comm="$(ps -p "${pid}" -o comm= 2>/dev/null | tr -d ' ')"
  if [[ -z "${comm}" || "${comm}" != nvim* ]]; then
    log_warn "remove stale socket: ${socket} (pid ${pid} not nvim: ${comm:-unknown})"
    rm -f "${socket}"
    continue
  fi

  args="$(ps -p "${pid}" -o args= 2>/dev/null)"
  if [[ "${args}" =~ --headless ]] || [[ "${args}" =~ (^|[[:space:]])-es([[:space:]]|$) ]] || [[ "${args}" =~ (^|[[:space:]])-Es([[:space:]]|$) ]]; then
    log_warn "skip headless nvim: ${socket} (pid ${pid})"
    continue
  fi

  # Send command to reload theme and force UI redraw.
  # The redraw! ensures UI updates even when Neovim is unfocused.
  nvim --server "${socket}" --remote-send '<Cmd>lua require("lib.theme_manager").apply_system_theme(require("lib.theme_manager").load_themes())<CR><Cmd>redraw!<CR>' 2>/dev/null &
done

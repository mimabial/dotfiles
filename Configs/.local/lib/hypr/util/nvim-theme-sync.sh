#!/usr/bin/env bash
# Sync theme changes to all running Neovim instances

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell util/nvim-theme-sync
Reload the active theme in every running Neovim instance via its RPC socket." "$@"

theme_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.meta"

log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
log_file="${log_dir}/nvim-theme-sync.log"
mkdir -p "${log_dir}"

log_warn() {
  printf '%s [warn] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${log_file}"
}

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
remote_timeout="${NVIM_THEME_SYNC_TIMEOUT:-2s}"
remote_kill_after="${NVIM_THEME_SYNC_KILL_AFTER:-1s}"
remote_cmd='<Cmd>lua package.loaded["lib.theme_manager"]=nil; for name in pairs(package.loaded) do if name:match("^plugins%.themes%.definitions%.") then package.loaded[name]=nil end end; local manager=require("lib.theme_manager"); manager.apply_system_theme(manager.load_themes())<CR><Cmd>redraw!<CR>'

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
  if ! timeout --kill-after="${remote_kill_after}" "${remote_timeout}" \
    nvim --server "${socket}" --remote-send "${remote_cmd}" >/dev/null 2>&1; then
    log_warn "failed to sync nvim theme: ${socket} (pid ${pid})"
  fi
done

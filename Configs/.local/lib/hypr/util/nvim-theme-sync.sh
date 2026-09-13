#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell util/nvim-theme-sync
Reload the active theme in every running Neovim instance via its RPC socket." "$@"

log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
log_file="${log_dir}/nvim-theme-sync.log"
mkdir -p "${log_dir}"

log_warn() {
  printf '%s [warn] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${log_file}"
}

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
remote_timeout="${NVIM_THEME_SYNC_TIMEOUT:-2s}"
remote_kill_after="${NVIM_THEME_SYNC_KILL_AFTER:-1s}"
remote_cmd='<Cmd>lua if vim.g.neocode_theme_sync then require("lib.theme_manager").sync(true); vim.cmd("redraw!") end<CR>'

shopt -s nullglob
for socket in "${runtime_dir}"/nvim.*.0; do
  [[ -S "${socket}" ]] || continue

  base="${socket##*/}"
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

  comm=""
  [[ -r "/proc/${pid}/comm" ]] && IFS= read -r comm <"/proc/${pid}/comm" || true
  if [[ -z "${comm}" || "${comm}" != nvim* ]]; then
    log_warn "remove stale socket: ${socket} (pid ${pid} not nvim: ${comm:-unknown})"
    rm -f "${socket}"
    continue
  fi

  argv=()
  mapfile -d '' -t argv <"/proc/${pid}/cmdline" 2>/dev/null || true
  headless=0
  for arg in "${argv[@]}"; do
    [[ "${arg}" =~ ^(--headless|-[Ee]s)$ ]] && headless=1 && break
  done
  if [[ "${headless}" -eq 1 ]]; then
    log_warn "skip headless nvim: ${socket} (pid ${pid})"
    continue
  fi

  if ! timeout --kill-after="${remote_kill_after}" "${remote_timeout}" \
    nvim --server "${socket}" --remote-send "${remote_cmd}" >/dev/null 2>&1; then
    log_warn "failed to sync nvim theme: ${socket} (pid ${pid})"
  fi
done

#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_runtime_require state

usage() {
  printf 'Usage: hyprshell setup/default.sh agent|browser|terminal|editor [NAME]\n'
}

lua_default() {
  local key="$1"
  local fallback="$2"
  local vars_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/vars.lua"
  local value=""

  value="$(sed -nE 's/^[[:space:]]*'"${key}"'[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "${vars_file}" | head -n 1)"
  printf '%s\n' "${value:-${fallback}}"
}

set_lua_default() {
  local key="$1"
  local value="$2"
  local vars_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/vars.lua"
  local temp_file=""

  [[ -r "${vars_file}" ]] || { printf 'Default config not found: %s\n' "${vars_file}" >&2; return 1; }
  grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${vars_file}" || {
    printf 'Default key not found: %s\n' "${key}" >&2
    return 1
  }

  temp_file="$(mktemp "${vars_file}.tmp.XXXXXX")"
  sed -E 's/^([[:space:]]*'"${key}"'[[:space:]]*=[[:space:]]*")[^"]*(",?[[:space:]]*)$/\1'"${value}"'\2/' \
    "${vars_file}" >"${temp_file}"
  chmod --reference="${vars_file}" "${temp_file}"
  mv -f "${temp_file}" "${vars_file}"
}

notify_default() {
  local name="$1"
  local kind="$2"
  dunstify -t 3000 -i preferences-system "Default ${kind}" "${name} is now the default ${kind,,}"
}

require_command() {
  local command_name="$1"
  local display_name="$2"

  command -v "${command_name}" >/dev/null 2>&1 && return 0
  dunstify -u critical -i dialog-error "${display_name} is not installed" "Install it before making it the default"
  return 1
}

reload_desktop() {
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null
  fi
}

kind="${1:-}"
selection="${2:-}"

if [[ -z "${selection}" ]]; then
  case "${kind}" in
    agent) state_get HYPR_DEFAULT_AGENT "" ;;
    browser)
      case "$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null || true)" in
        chromium.desktop) printf 'chromium\n' ;;
        google-chrome.desktop) printf 'chrome\n' ;;
        brave-browser.desktop) printf 'brave\n' ;;
        brave-origin.desktop) printf 'brave-origin\n' ;;
        microsoft-edge.desktop) printf 'edge\n' ;;
        firefox.desktop) printf 'firefox\n' ;;
        zen.desktop) printf 'zen\n' ;;
      esac
      ;;
    terminal) state_get TERMINAL "$(lua_default TERMINAL kitty)" ;;
    editor) state_get EDITOR "$(lua_default EDITOR nvim)" ;;
    -h | --help | help) usage ;;
    *) usage >&2; exit 2 ;;
  esac
  exit 0
fi

case "${kind}:${selection}" in
  agent:agy) command_name=agy; display_name=Antigravity ;;
  agent:claude) command_name=claude; display_name=Claude ;;
  agent:codex) command_name=codex; display_name=Codex ;;
  agent:copilot) command_name=copilot; display_name=Copilot ;;
  agent:crush) command_name=crush; display_name=Crush ;;
  agent:grok) command_name=grok; display_name=Grok ;;
  agent:omp) command_name=omp; display_name='Oh My Pi' ;;
  agent:opencode) command_name=opencode; display_name=OpenCode ;;
  agent:ori) command_name=ori; display_name=Ori ;;
  agent:pi) command_name=pi; display_name=Pi ;;
  browser:chromium) command_name=chromium; desktop_id=chromium.desktop; display_name=Chromium ;;
  browser:chrome) command_name=google-chrome-stable; desktop_id=google-chrome.desktop; display_name=Chrome ;;
  browser:brave) command_name=brave; desktop_id=brave-browser.desktop; display_name=Brave ;;
  browser:brave-origin) command_name=brave-origin; desktop_id=brave-origin.desktop; display_name='Brave Origin' ;;
  browser:edge) command_name=microsoft-edge-stable; desktop_id=microsoft-edge.desktop; display_name=Edge ;;
  browser:firefox) command_name=firefox; desktop_id=firefox.desktop; display_name=Firefox ;;
  browser:zen) command_name=zen-browser; desktop_id=zen.desktop; display_name=Zen ;;
  terminal:alacritty) command_name=alacritty; desktop_id=Alacritty.desktop; display_name=Alacritty ;;
  terminal:foot) command_name=foot; desktop_id=foot.desktop; display_name=Foot ;;
  terminal:ghostty) command_name=ghostty; desktop_id=com.mitchellh.ghostty.desktop; display_name=Ghostty ;;
  terminal:kitty) command_name=kitty; desktop_id=kitty.desktop; display_name=Kitty ;;
  editor:nvim) command_name=nvim; display_name=Neovim ;;
  editor:code) command_name=code; display_name=VSCode ;;
  editor:cursor) command_name=cursor; display_name=Cursor ;;
  editor:zeditor) command_name=zeditor; display_name=Zed ;;
  editor:sublime_text) command_name=sublime_text; display_name='Sublime Text' ;;
  editor:hx) command_name=hx; display_name=Helix ;;
  editor:vim) command_name=vim; display_name=Vim ;;
  editor:emacs) command_name=emacs; display_name=Emacs ;;
  *) usage >&2; exit 2 ;;
esac

require_command "${command_name}" "${display_name}"

case "${kind}" in
  agent)
    state_set HYPR_DEFAULT_AGENT "${selection}" env-overrides
    ;;
  browser)
    env -u BROWSER xdg-settings set default-web-browser "${desktop_id}"
    set_lua_default BROWSER "${command_name}"
    state_set BROWSER "${command_name}" env-overrides
    reload_desktop
    ;;
  terminal)
    set_lua_default TERMINAL "${command_name}"
    set_lua_default TERMINAL_TUI "${command_name}"
    state_set TERMINAL "${command_name}" env-overrides
    state_set TERMINAL_TUI "${command_name}" env-overrides
    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"
    printf '# Terminal emulator preference order\n%s\n' "${desktop_id}" >"${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list"
    reload_desktop
    ;;
  editor)
    set_lua_default EDITOR "${command_name}"
    state_set EDITOR "${command_name}" env-overrides
    reload_desktop
    ;;
esac

notify_default "${display_name}" "${kind}"

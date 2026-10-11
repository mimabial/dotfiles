DEFAULT_APP_CATALOG=(
  'agent|claude|claude||Claude|󰛄'
  'agent|codex|codex||Codex|󱙺'
  'agent|opencode|opencode||OpenCode|󰚩'
  'browser|chromium|chromium|chromium.desktop|Chromium|'
  'browser|chrome|google-chrome-stable|google-chrome.desktop|Chrome|󰊯'
  'browser|brave|brave|brave-browser.desktop|Brave|󰖟'
  'browser|brave-origin|brave-origin|brave-origin.desktop|Brave Origin|󰖟'
  'browser|edge|microsoft-edge-stable|microsoft-edge.desktop|Edge|󰇩'
  'browser|firefox|firefox|firefox.desktop|Firefox|'
  'browser|zen|zen-browser|zen.desktop|Zen|󰖟'
  'terminal|alacritty|alacritty|Alacritty.desktop|Alacritty|'
  'terminal|kitty|kitty|kitty.desktop|Kitty|󰄛'
  'editor|nvim|nvim||Neovim|'
  'editor|code|code||VSCode|'
  'editor|cursor|cursor||Cursor|'
  'editor|zeditor|zeditor||Zed|󰬡'
  'editor|sublime_text|sublime_text||Sublime Text|'
  'editor|hx|hx||Helix|󰚄'
  'editor|vim|vim||Vim|'
  'editor|emacs|emacs||Emacs|'
)

default_app_lookup() {
  local -n application_ref="$1"
  local record="" role="" selection=""
  for record in "${DEFAULT_APP_CATALOG[@]}"; do
    IFS='|' read -r role selection _ <<<"${record}"
    [[ "${role}" == "$2" && "${selection}" == "$3" ]] || continue
    application_ref=([role]="$2" [selection]="$3")
    IFS='|' read -r _ _ 'application_ref[command]' 'application_ref[desktop_id]' 'application_ref[display_name]' 'application_ref[icon]' <<<"${record}"
    return 0
  done
  return 1
}

default_app_read() {
  local application_role="$1" desktop_id record role selection catalog_desktop_id state_key
  case "${application_role}" in
    agent) state_get HYPR_DEFAULT_AGENT "" ;;
    browser)
      desktop_id="$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null || true)"
      for record in "${DEFAULT_APP_CATALOG[@]}"; do
        IFS='|' read -r role selection _ catalog_desktop_id _ <<<"${record}"
        [[ "${role}" == browser && "${catalog_desktop_id}" == "${desktop_id}" ]] || continue
        printf '%s\n' "${selection}"
        return 0
      done
      ;;
    terminal | editor)
      state_key="${application_role^^}"
      state_get "${state_key}" "$(hypr_config_value_from_layers "${state_key}")"
      ;;
    *) return 2 ;;
  esac
  return 0
}

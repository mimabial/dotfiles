source "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/layouts/_dev_geometry.zsh"

_tdl_runner() {
  [[ -n ${TMUX:-} ]] || { print -u2 '[Error] Must start tmux first.'; return 1; }
  reply="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts/tmux-layout"
  [[ -x $reply ]] || { print -u2 'tmux layout runner is unavailable.'; return 1; }
}

_tdl_is_claude() {
  local word
  local -a words=("${(z)1}")
  for word in "${words[@]}"; do [[ ${word:t} == claude ]] && return 0; done
  return 1
}

_tdl_prompt_agent() {
  local first="$1" second="$2" selection choice
  if [[ -t 2 ]] && (( $+commands[fzf] )); then
    selection="$(printf 'primary\t%s\nsecondary\t%s\n' "$first" "$second" | fzf \
      --delimiter=$'\t' --with-nth=2 --prompt=' ' --marker='' --height=7 \
      --layout=reverse --border=sharp --no-multi \
      --header='Pane too narrow for two agents and an editor. Choose one.')" || return 1
    print -r -- "${selection#*$'\t'}"
    return
  fi
  while true; do
    print -u2 "Pane too narrow. Choose: 1) $first  2) $second  q) cancel"
    read -r "choice?Selection [1/2/q]: " || return 1
    case "$choice" in
      1) print -r -- "$first"; return ;;
      2) print -r -- "$second"; return ;;
      q | Q) return 1 ;;
    esac
  done
}

tdl() {
  (( $# <= 2 )) || { print -u2 'Usage: tdl [ai_command] [second_ai_command]'; return 1; }
  _tdl_runner || return
  local runner="$reply" ai="${1:-opencode}" ai2="${2:-}" focus=none width
  integer dual=$(( $# == 2 )) fallback=0

  if (( dual )); then
    width="$(tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_width}')" || return
    if ! _tmux_dev_dual_three_pane_agent_widths "$width" >/dev/null 2>&1; then
      ai="$(_tdl_prompt_agent "$ai" "$ai2")" || return
      ai2=''; dual=0; fallback=1
    fi
  fi

  if _tdl_is_claude "$ai"; then focus=primary
  elif _tdl_is_claude "$ai2"; then focus=secondary
  fi

  TMUX_LAYOUT_DUAL_MODE="$dual" \
  TMUX_LAYOUT_DUAL_FALLBACK="$fallback" \
  TMUX_LAYOUT_AGENT_CMD="clear && $ai" \
  TMUX_LAYOUT_SECOND_AGENT_CMD="${ai2:+clear && $ai2}" \
  TMUX_LAYOUT_FOCUS_AGENT_SLOT="$focus" \
  TMUX_LAYOUT_EDITOR_CMD="clear && ${EDITOR:-nvim} ." \
  "$runner" dev
}

tds() {
  (( $# <= 1 )) || { print -u2 'Usage: tds [ai_command]'; return 1; }
  _tdl_runner || return
  TMUX_LAYOUT_AGENT_CMD="clear && ${1:-opencode}" \
  TMUX_LAYOUT_EDITOR_CMD="clear && ${EDITOR:-nvim} ." \
  "$reply" square
}

tsl() {
  (( $# >= 1 && $# <= 4 )) || { print -u2 'Usage: tsl <command> [command ...]'; return 1; }
  _tdl_runner || return
  local runner="$reply" cmd
  local -a assignments
  integer index=1
  for cmd in "$@"; do
    assignments+=("TMUX_LAYOUT_SWARM_CMD_${index}=clear && $cmd")
    (( index++ ))
  done
  env TMUX_LAYOUT_SWARM_PANES="$#" "${assignments[@]}" "$runner" swarm
}

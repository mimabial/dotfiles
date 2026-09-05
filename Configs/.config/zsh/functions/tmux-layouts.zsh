source "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/layouts/_dev_geometry.zsh"

typeset -gA _TDL_AGENT_BEHAVIOR_FLAGS=(
  "claude:focus_after_layout" 1
  "codex:needs_nvm_lts"       1
)
typeset -gA _TDL_DEFAULT_BEHAVIOR_FLAGS=(
  "clear_before_run" 1
)
typeset -ga _TDL_AGENT_WRAPPER_WORDS=(builtin command exec noglob nocorrect)

_tdl_agent_command_word_from_env() {
  local word split_string
  local -a words
  integer index word_count

  index="$1"
  shift

  words=("$@")
  word_count=${#words[@]}

  while (( index <= word_count )); do
    word="${words[$index]}"

    case "$word" in
      --)
        ((index++))
        break
        ;;
      [A-Za-z_][A-Za-z0-9_]*=*)
        ((index++))
        continue
        ;;
      -u | --unset | -C | --chdir | -a | --argv0)
        (( index < word_count )) || return 1
        ((index += 2))
        continue
        ;;
      -u?* | -C?* | -a?* | --unset=* | --chdir=* | --argv0=*)
        ((index++))
        continue
        ;;
      -S | --split-string)
        (( index < word_count )) || return 1
        split_string="${words[$((index + 1))]}"
        _tdl_agent_command_word "$split_string" && return 0
        ((index += 2))
        continue
        ;;
      -S?* | --split-string=*)
        if [[ "$word" == --split-string=* ]]; then
          split_string="${word#*=}"
        else
          split_string="${word#-S}"
        fi
        _tdl_agent_command_word "$split_string" && return 0
        ((index++))
        continue
        ;;
      -*)
        ((index++))
        continue
        ;;
      *)
        break
        ;;
    esac
  done

  (( index <= word_count )) || return 1
  print -r -- "${words[$index]}"
  return 0

}

_tdl_agent_command_word() {
  local cmd="$1" word
  local -a words
  integer index=1 word_count

  words=("${(z)cmd}")
  word_count=${#words[@]}
  (( word_count > 0 )) || return 1

  while (( index <= word_count )); do
    word="${words[$index]}"

    case "$word" in
      [A-Za-z_][A-Za-z0-9_]*=*)
        ((index++))
        continue
        ;;
      env)
        ((index++))
        _tdl_agent_command_word_from_env "$index" "${words[@]}" && return 0
        return 1
        ;;
      --)
        ((index++))
        continue
        ;;
    esac

    if (( ${_TDL_AGENT_WRAPPER_WORDS[(Ie)$word]} > 0 )); then
      ((index++))
      continue
    fi

    print -r -- "$word"
    return 0
  done

  return 1
}

_tdl_agent_identity() {
  local cmd="$1" command_word

  command_word="$(_tdl_agent_command_word "$cmd" 2>/dev/null)" || return 1
  reply=("$command_word" "${command_word:t}")
}

_tdl_agent_binary_name() {
  local cmd="$1"
  local -a agent_identity

  _tdl_agent_identity "$cmd" 2>/dev/null || return 1
  agent_identity=("${reply[@]}")
  print -r -- "${agent_identity[2]}"
}

_tdl_agent_has_behavior() {
  local binary_name="$1" behavior="$2"
  local behavior_key
  [[ -n "$behavior" ]] || return 1

  (( ${+_TDL_DEFAULT_BEHAVIOR_FLAGS[$behavior]} )) && return 0
  [[ -n "$binary_name" ]] || return 1

  behavior_key="${binary_name}:${behavior}"
  (( ${+_TDL_AGENT_BEHAVIOR_FLAGS[$behavior_key]} ))
}

_tdl_load_nvm() {
  (( ${+functions[nvm]} )) && return 0
  [[ -n "${NVM_DIR:-}" && -s "${NVM_DIR}/nvm.sh" ]] || return 1
  source "${NVM_DIR}/nvm.sh" >/dev/null 2>&1
}

_tdl_agent_command_available_in_nvm_lts() {
  local binary_name="$1"
  [[ -n "$binary_name" ]] || return 1

  (
    _tdl_load_nvm || exit 1
    nvm use --delete-prefix --lts >/dev/null 2>&1 || exit 1
    command -v -- "$binary_name" >/dev/null 2>&1
  )
}

_tdl_focus_agent_slot() {
  local primary_cmd="$1" secondary_cmd="$2"
  local -a agent_identity
  local primary_binary="" secondary_binary=""

  if _tdl_agent_identity "$primary_cmd" 2>/dev/null; then
    agent_identity=("${reply[@]}")
    primary_binary="${agent_identity[2]}"
  fi

  if _tdl_agent_identity "$secondary_cmd" 2>/dev/null; then
    agent_identity=("${reply[@]}")
    secondary_binary="${agent_identity[2]}"
  fi

  if _tdl_agent_has_behavior "$primary_binary" "focus_after_layout"; then
    print -r -- "primary"
  elif _tdl_agent_has_behavior "$secondary_binary" "focus_after_layout"; then
    print -r -- "secondary"
  else
    print -r -- "none"
  fi
}

_tdl_validate_command() {
  local cmd="$1" label="$2" command_word binary_name
  local -a agent_identity
  [[ -n "$cmd" ]] || return 0

  if _tdl_agent_identity "$cmd" 2>/dev/null; then
    agent_identity=("${reply[@]}")
    command_word="${agent_identity[1]}"
    binary_name="${agent_identity[2]}"
  fi

  [[ -n "$command_word" ]] || {
    print -u2 "Invalid ${label} command."
    return 1
  }

  if _tdl_agent_has_behavior "$binary_name" "needs_nvm_lts" && [[ "$command_word" != */* ]]; then
    _tdl_agent_command_available_in_nvm_lts "$binary_name" && return 0
    print -u2 "[Error] Unknown ${label} command after nvm use --delete-prefix --lts: $command_word"
    return 1
  fi

  command -v -- "$command_word" >/dev/null 2>&1 || {
    print -u2 "[Error] Unknown ${label} command: $command_word"
    return 1
  }
}

_tdl_prepare_ai_command() {
  local cmd="$1" binary_name
  local -a agent_identity
  local -a prefix_cmds=()
  [[ -n "$cmd" ]] || return 0

  if _tdl_agent_identity "$cmd" 2>/dev/null; then
    agent_identity=("${reply[@]}")
    binary_name="${agent_identity[2]}"
  fi

  _tdl_agent_has_behavior "$binary_name" "needs_nvm_lts" && prefix_cmds+=("nvm use --delete-prefix --lts")
  _tdl_agent_has_behavior "$binary_name" "clear_before_run" && prefix_cmds+=("clear")

  if (( ${#prefix_cmds[@]} == 0 )); then
    print -r -- "$cmd"
    return 0
  fi

  print -r -- "${(j: && :)prefix_cmds} && ${cmd}"
}

_tdl_prepare_editor_command() {
  local cmd="$1"
  [[ -n "$cmd" ]] || return 0

  print -r -- "clear && ${cmd}"
}

_tdl_current_pane_width() {
  tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_width}'
}

_tdl_prompt_dual_agent_choice() {
  local primary_cmd="$1" secondary_cmd="$2" choice selection
  local -a agent_options

  if [[ -t 2 ]] && command -v fzf >/dev/null 2>&1; then
    agent_options=(
      $'primary\t'"$primary_cmd"
      $'secondary\t'"$secondary_cmd"
    )

    selection="$(
      print -l -- "${agent_options[@]}" \
        | fzf \
            --delimiter=$'\t' \
            --with-nth=2 \
            --prompt=' ' \
            --marker='' \
            --height=7 \
            --layout=reverse \
            --border=sharp \
            --no-multi \
            --header='Current pane is too narrow for two agents and an editor. Choose one agent to open.'
    )" || {
      print -u2 "Cancelled dual layout."
      return 1
    }

    print -r -- "${selection#*$'\t'}"
    return 0
  fi

  while true; do
    print -u2 "Current pane is too narrow for two agents and an editor."
    print -u2 "Choose one agent to open instead:"
    print -u2 "1) $primary_cmd"
    print -u2 "2) $secondary_cmd"
    print -u2 "q) cancel"
    read -r "choice?Selection [1/2/q]: " || return 1

    case "$choice" in
      1)
        print -r -- "$primary_cmd"
        return 0
        ;;
      2)
        print -r -- "$secondary_cmd"
        return 0
        ;;
      q | Q)
        print -u2 "Cancelled dual layout."
        return 1
        ;;
    esac
  done
}




tdl() {
  (($# > 2)) && {
    print -u2 "Usage: tdl [ai_command] [second_ai_command]"
    print -u2 "Quote commands with spaces when provided."
    return 1
  }

  [[ -z "${TMUX:-}" ]] && {
    print -u2 "[Error] Must start tmux to use tdl."
    return 1
  }

  local layout_runner ai ai2 editor_cmd focus_agent_slot current_width dual_fallback
  integer dual_mode=$(( $# == 2 ))
  ai="${1:-opencode}"
  ai2="${2:-}"
  editor_cmd="${EDITOR:-nvim} ."
  layout_runner="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts/tmux-layout"
  dual_fallback=0

  _tdl_validate_command "$ai" "primary AI" || return 1
  _tdl_validate_command "$ai2" "secondary AI" || return 1

  if (( dual_mode )); then
    current_width="$(_tdl_current_pane_width)" || return 1
    if ! _tmux_dev_dual_three_pane_agent_widths "$current_width" >/dev/null 2>&1; then
      ai="$(_tdl_prompt_dual_agent_choice "$ai" "$ai2")" || return 1
      ai2=""
      dual_mode=0
      dual_fallback=1
    fi
  fi

  focus_agent_slot="$(_tdl_focus_agent_slot "$ai" "$ai2")"
  ai="$(_tdl_prepare_ai_command "$ai")"
  ai2="$(_tdl_prepare_ai_command "$ai2")"
  editor_cmd="$(_tdl_prepare_editor_command "$editor_cmd")"

  [[ -x "$layout_runner" ]] || {
    print -u2 "tmux layout runner is not available."
    return 1
  }

  TMUX_LAYOUT_DUAL_MODE="$dual_mode" \
  TMUX_LAYOUT_DUAL_FALLBACK="$dual_fallback" \
  TMUX_LAYOUT_AGENT_CMD="$ai" \
  TMUX_LAYOUT_SECOND_AGENT_CMD="$ai2" \
  TMUX_LAYOUT_FOCUS_AGENT_SLOT="$focus_agent_slot" \
  TMUX_LAYOUT_EDITOR_CMD="$editor_cmd" \
  "$layout_runner" dev
}

tds() {
  (($# > 1)) && {
    print -u2 "Usage: tds [ai_command]"
    print -u2 "Quote commands with spaces when provided."
    return 1
  }

  [[ -z "${TMUX:-}" ]] && {
    print -u2 "[Error] Must start tmux to use tds."
    return 1
  }

  local layout_runner ai editor_cmd
  ai="${1:-opencode}"
  editor_cmd="${EDITOR:-nvim} ."
  layout_runner="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts/tmux-layout"

  _tdl_validate_command "$ai" "AI" || return 1
  ai="$(_tdl_prepare_ai_command "$ai")"
  editor_cmd="$(_tdl_prepare_editor_command "$editor_cmd")"

  [[ -x "$layout_runner" ]] || {
    print -u2 "tmux layout runner is not available."
    return 1
  }

  TMUX_LAYOUT_AGENT_CMD="$ai" \
  TMUX_LAYOUT_EDITOR_CMD="$editor_cmd" \
  "$layout_runner" square
}

tsl() {
  (( $# < 1 || $# > 4 )) && {
    print -u2 "Usage: tsl <command> [command ...]"
    print -u2 "Up to 4 commands, one per pane. Quote commands with spaces."
    return 1
  }

  [[ -z "${TMUX:-}" ]] && {
    print -u2 "[Error] Must start tmux to use tsl."
    return 1
  }

  local layout_runner
  local -a prepared env_assignments
  integer index

  for index in {1..$#}; do
    _tdl_validate_command "${@[$index]}" "swarm pane ${index}" || return 1
    prepared+=("$(_tdl_prepare_ai_command "${@[$index]}")")
  done

  layout_runner="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts/tmux-layout"
  [[ -x "$layout_runner" ]] || {
    print -u2 "tmux layout runner is not available."
    return 1
  }

  for index in {1..${#prepared[@]}}; do
    env_assignments+=("TMUX_LAYOUT_SWARM_CMD_${index}=${prepared[$index]}")
  done

  env TMUX_LAYOUT_SWARM_PANES="${#prepared[@]}" "${env_assignments[@]}" "$layout_runner" swarm
}

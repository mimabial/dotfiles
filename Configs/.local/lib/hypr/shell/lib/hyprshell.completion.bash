#!/usr/bin/env bash

# Shell completion generators for hyprshell.

declare -ga HYPR_COMPLETION_BUILTINS=()

completion_builtin_commands() {
  if declare -F hyprshell_builtin_commands >/dev/null 2>&1; then
    hyprshell_builtin_commands
    return 0
  fi

  printf '%s\n' \
    "--help" "help" "-h" \
    "-r" "reload" \
    "--version" "version" "-v" \
    "--release-notes" "release-notes" \
    "--list-script" "--list-script-path" \
    "--completions" \
    "validate" "pyinit" "init" "lock-session" "logout" "pip" "pypr" "app"
}

completion_join_space() {
  local -n values_ref="$1"
  printf '%s' "${values_ref[*]}"
}

completion_quote_zsh_array() {
  local -n values_ref="$1"
  local value=""

  for value in "${values_ref[@]}"; do
    printf '"%s" ' "${value}"
  done
}

get_completion_data() {
  mapfile -t HYPR_COMPLETION_BUILTINS < <(completion_builtin_commands)
}

gen_bash_completion() {
  local built_in_commands=""

  get_completion_data
  built_in_commands="$(completion_join_space HYPR_COMPLETION_BUILTINS)"

  cat <<EOF
# Bash completion for hyprshell
_hyprshell_completion() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        COMPREPLY=()
        cur="\${COMP_WORDS[\$COMP_CWORD]}"
        prev="\${COMP_WORDS[\$COMP_CWORD-1]}"
    }

    local built_in_commands hyprscripts
    built_in_commands="${built_in_commands}"

    if command -v hyprshell >/dev/null 2>&1; then
        hyprscripts=\$(hyprshell --list-script 2>/dev/null | sed 's/\.[^.]*$//' | tr '\n' ' ')
    fi

    if [[ \$COMP_CWORD -eq 1 ]]; then
        local all_commands="\$built_in_commands \$hyprscripts"
        COMPREPLY=(\$(compgen -W "\$all_commands" -- "\$cur"))
    elif [[ \$COMP_CWORD -eq 2 ]]; then
        case \$prev in
            --completions)
                COMPREPLY=(\$(compgen -W "bash zsh" -- "\$cur"))
                return 0
                ;;
            *)
                COMPREPLY=()
                return 0
                ;;
        esac
    else
        COMPREPLY=()
        return 0
    fi
}

complete -F _hyprshell_completion hyprshell
EOF
}

gen_zsh_completion() {
  local built_in_commands_zsh=""

  get_completion_data
  built_in_commands_zsh="$(completion_quote_zsh_array HYPR_COMPLETION_BUILTINS)"

  cat <<EOF
#compdef hyprshell

_hyprshell() {
    local cur prev words
    cur="\${words[CURRENT]}"
    prev="\${words[CURRENT-1]}"

    local built_in_commands hyprscripts
    built_in_commands=(${built_in_commands_zsh})

    if (( \$+commands[hyprshell] )); then
        local scripts_raw
        scripts_raw=(\${(f)"\$(hyprshell --list-script 2>/dev/null)"})
        hyprscripts=(\${scripts_raw[@]%.*})
    fi

    if [[ \$CURRENT -eq 2 ]]; then
        local all_commands=(\$built_in_commands \$hyprscripts)
        compadd -a all_commands
    elif [[ \$CURRENT -eq 3 ]]; then
        case \$words[2] in
            --completions)
                compadd "bash" "zsh"
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    else
        return 0
    fi
}

compdef _hyprshell hyprshell
EOF
}

generate_completions() {
  local shell_type="$1"

  case "${shell_type}" in
    bash)
      gen_bash_completion
      ;;
    zsh)
      gen_zsh_completion
      ;;
    *)
      echo "Usage: hyprshell --completions [bash|zsh]"
      echo "Generate shell completions for the specified shell"
      return 1
      ;;
  esac
}

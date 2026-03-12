#!/usr/bin/env bash

# Shell completion generators for hyprshell.

get_completion_data() {
  local built_in_commands=(
    "--help" "help" "-h"
    "-r" "reload"
    "--version" "version" "-v"
    "--release-notes" "release-notes"
    "--list-script" "--list-script-path"
    "--completions"
    "validate" "pyinit" "init" "lock-session" "logout" "pip" "pypr" "app"
  )
  local hyprscripts=()
  local script_name

  while IFS= read -r script; do
    [[ -n "${script}" ]] || continue
    script_name="${script%.*}"
    hyprscripts+=("${script_name}")
  done < <(list_script 2>/dev/null | sort -u)

  export HYPR_BUILT_IN_COMMANDS="${built_in_commands[*]}"
  export HYPR_SCRIPTS="${hyprscripts[*]}"
}

gen_bash_completion() {
  get_completion_data

  cat <<'BASH_COMPLETION'
# Bash completion for hyprshell
_hyprshell_completion() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    }

    local built_in_commands hyprscripts
    built_in_commands="--help help -h -r reload --version version -v --release-notes release-notes --list-script --list-script-path --completions validate pyinit init lock-session logout pip pypr app"

    if command -v hyprshell >/dev/null 2>&1; then
        hyprscripts=$(hyprshell --list-script 2>/dev/null | sed 's/\.[^.]*$//' | tr '\n' ' ')
    fi

    if [[ $COMP_CWORD -eq 1 ]]; then
        local all_commands="$built_in_commands $hyprscripts"
        COMPREPLY=($(compgen -W "$all_commands" -- "$cur"))
    elif [[ $COMP_CWORD -eq 2 ]]; then
        case $prev in
            --completions)
                COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
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
BASH_COMPLETION
}

gen_zsh_completion() {
  get_completion_data

  cat <<'ZSH_COMPLETION'
#compdef hyprshell

_hyprshell() {
    local cur prev words
    cur="${words[CURRENT]}"
    prev="${words[CURRENT-1]}"

    local built_in_commands hyprscripts
    built_in_commands=("--help" "help" "-h" "-r" "reload" "--version" "version" "-v" "--release-notes" "release-notes" "--list-script" "--list-script-path" "--completions" "validate" "pyinit" "init" "lock-session" "logout" "pip" "pypr" "app")

    if (( $+commands[hyprshell] )); then
        local scripts_raw
        scripts_raw=(${(f)"$(hyprshell --list-script 2>/dev/null)"})
        hyprscripts=(${scripts_raw[@]%.*})
    fi

    if [[ $CURRENT -eq 2 ]]; then
        local all_commands=($built_in_commands $hyprscripts)
        compadd -a all_commands
    elif [[ $CURRENT -eq 3 ]]; then
        case $words[2] in
            --completions)
                compadd "bash" "zsh" "fish"
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
ZSH_COMPLETION
}

gen_fish_completion() {
  get_completion_data

  cat <<'FISH_COMPLETION'
# Fish completion for hyprshell

function __hyprshell_get_commands
    echo "--help
help
-h
-r
reload
--version
version
-v
--release-notes
release-notes
--list-script
--list-script-path
--completions
validate
pyinit
init
lock-session
logout
pip
pypr
app"

    if command -v hyprshell >/dev/null 2>&1
        hyprshell --list-script 2>/dev/null | sed 's/\.[^.]*$//'
    end
end

complete -c hyprshell -f
complete -c hyprshell -n "not __fish_seen_subcommand_from (__hyprshell_get_commands)" -a "(__hyprshell_get_commands)" -d "hyprshell commands"
complete -c hyprshell -n "__fish_seen_subcommand_from --completions" -a "bash zsh fish" -d "Shell completion types"

complete -c hyprshell -s h -l help -d "Display help message"
complete -c hyprshell -s r -d "Reload config"
complete -c hyprshell -s v -l version -d "Show version information"
complete -c hyprshell -l release-notes -d "Show release notes"
complete -c hyprshell -l list-script -d "List available scripts"
complete -c hyprshell -l list-script-path -d "List scripts with full paths"
complete -c hyprshell -l completions -d "Generate shell completions"
FISH_COMPLETION
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
    fish)
      gen_fish_completion
      ;;
    *)
      echo "Usage: hyprshell --completions [bash|zsh|fish]"
      echo "Generate shell completions for the specified shell"
      return 1
      ;;
  esac
}

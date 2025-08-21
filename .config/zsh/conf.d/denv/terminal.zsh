#!/usr/bin/env zsh

#! ██████╗░░█████╗░  ███╗░░██╗░█████╗░████████╗  ███████╗██████╗░██╗████████╗
#! ██╔══██╗██╔══██╗  ████╗░██║██╔══██╗╚══██╔══╝  ██╔════╝██╔══██╗██║╚══██╔══╝
#! ██║░░██║██║░░██║  ██╔██╗██║██║░░██║░░░██║░░░  █████╗░░██║░░██║██║░░░██║░░░
#! ██║░░██║██║░░██║  ██║╚████║██║░░██║░░░██║░░░  ██╔══╝░░██║░░██║██║░░░██║░░░
#! ██████╔╝╚█████╔╝  ██║░╚███║╚█████╔╝░░░██║░░░  ███████╗██████╔╝██║░░░██║░░░
#! ╚═════╝░░╚════╝░  ╚═╝░░╚══╝░╚════╝░░░░╚═╝░░░  ╚══════╝╚═════╝░╚═╝░░░╚═╝░░░

# This file is sourced by ZSH on startup
# And ensures that we have an obstruction-free .zshrc file
# This also ensures that the proper $ENVs are loaded

function _load_functions() {
    # Load all custom function files // Directories are ignored
    for file in "${ZDOTDIR:-$HOME/.config/zsh}/functions/"*.zsh; do
        [ -r "$file" ] && source "$file"
    done
}

function _load_completions() {
    for file in "${ZDOTDIR:-$HOME/.config/zsh}/completions/"*.zsh; do
        [ -r "$file" ] && source "$file"
    done
}

function _init_zinit() {
    # Initialize zinit
    local zinit_home="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
    
    # Install zinit if not present
    if [[ ! -d "$zinit_home" ]]; then
        mkdir -p "$(dirname "$zinit_home")"
        git clone https://github.com/zdharma-continuum/zinit.git "$zinit_home"
    fi
    
    # Source zinit
    source "${zinit_home}/zinit.zsh"
    
    # Configure oh-my-zsh integration
    zinit snippet OMZL::git.zsh
    zinit snippet OMZP::git
    
    # Load essential plugins
    zinit light "chrissicool/zsh-256color"
    zinit light "zsh-users/zsh-autosuggestions"
    zinit light "zsh-users/zsh-syntax-highlighting"
    
    # Load additional user plugins if they exist
    if [[ -f "$ZDOTDIR/zinit-plugins.zsh" ]]; then
        source "$ZDOTDIR/zinit-plugins.zsh"
    fi
}

function _defer_zinit_after_prompt_before_input() {

    _init_zinit
    #! Never load time consuming functions here

    # Add your completions directory to fpath
    fpath=($ZDOTDIR/completions "${fpath[@]}")

    _load_compinit
    _load_functions
    _load_completions

    # zsh-autosuggestions won't work on first prompt when deferred
    if typeset -f _zsh_autosuggest_start >/dev/null; then
        _zsh_autosuggest_start
    fi

    chmod +r $ZDOTDIR/.zshrc # Make sure .zshrc is readable
    [[ -r $ZDOTDIR/.zshrc ]] && source $ZDOTDIR/.zshrc
}

function _load_deferred_plugin_system() {

    # Exit early if DENV_ZSH_DEFER is not set to 1
    if [[ "${DENV_ZSH_DEFER}" != "1" ]]; then
        unset -f _load_deferred_plugin_system
        return
    fi

    # Defer zinit loading until after prompt appears
    # Load zinit when line editor initializes // before user input
    if [[ -n $DEFER_ZINIT_LOAD ]]; then
        unset DEFER_ZINIT_LOAD
        [[ ${VSCODE_INJECTION} == 1 ]] || chmod -r $ZDOTDIR/.zshrc # let vscode read .zshrc
        zle -N zle-line-init _defer_zinit_after_prompt_before_input  # Loads when the line editor initializes // The best option
    fi
    #  Below this line are the commands that are executed after the prompt appears

    # TODO: add handlers in pm.sh
    # for these aliases manually add the following lines to .zshrc.(Using yay as the aur helper)
    # pc='yay -Sc' # remove all cached packages
    # po='yay -Qtdq | ${PM_COMMAND[@]} -Rns -' # remove orphaned packages

    # zsh-autosuggestions won't work on first prompt when deferred
    if typeset -f _zsh_autosuggest_start >/dev/null; then
        _zsh_autosuggest_start
    fi

    # Some binds won't work on first prompt when deferred
    bindkey '\e[H' beginning-of-line
    bindkey '\e[F' end-of-line

}

function do_render {
    # Check if the terminal supports images
    local type="${1:-image}"
    # TODO: update this list if needed
    TERMINAL_IMAGE_SUPPORT=(kitty konsole ghostty WezTerm)
    local terminal_no_art=(vscode code codium)
    TERMINAL_NO_ART="${TERMINAL_NO_ART:-${terminal_no_art[@]}}"
    CURRENT_TERMINAL="${TERM_PROGRAM:-$(ps -o comm= -p $(ps -o ppid= -p $$))}"

    case "${type}" in
    image)
        if [[ " ${TERMINAL_IMAGE_SUPPORT[@]} " =~ " ${CURRENT_TERMINAL} " ]]; then
            return 0
        else
            return 1
        fi
        ;;
    art)
        if [[ " ${TERMINAL_NO_ART[@]} " =~ " ${CURRENT_TERMINAL} " ]]; then
            return 1
        else
            return 0
        fi
        ;;
    *)
        return 1
        ;;
    esac
}

function _load_compinit() {
    # Initialize completions with optimized performance
    autoload -Uz compinit

    # Enable extended glob for the qualifier to work
    setopt EXTENDED_GLOB

    # Fastest - use glob qualifiers on directory pattern
    if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+${DENV_ZSH_COMPINIT_CHECK:-1}) ]]; then
        compinit
    else
        compinit -C
    fi

    _comp_options+=(globdots) # tab complete hidden files
}

function _load_prompt() {
    # Try to load prompts immediately
    if ! source ${ZDOTDIR}/prompt.zsh >/dev/null 2>&1; then
        [[ -f $ZDOTDIR/conf.d/denv/prompt.zsh ]] && source $ZDOTDIR/conf.d/denv/prompt.zsh
    fi
}

#? Override this environment variable in ~/.zshrc
# cleaning up home folder
# ZSH Plugin Configuration

DENV_ZSH_DEFER="1"      #Unset this variable in $ZDOTDIR/user.zsh to disable DENv's deferred Zsh loading.
DENV_ZSH_PROMPT="1"     #Unset this variable in $ZDOTDIR/user.zsh to disable DENv's prompt customization.
DENV_ZSH_NO_PLUGINS="0" #Set this variable to "1" in $ZDOTDIR/user.zsh to disable DENv's Zsh plugin loading.

ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# # History configuration
HISTFILE=${HISTFILE:-$ZDOTDIR/.zsh_history}
if [[ -f $HOME/.zsh_history ]] && [[ ! -f $HISTFILE ]]; then
    echo "Please manually move $HOME/.zsh_history to $HISTFILE"
    echo "Or move it somewhere else to avoid conflicts"
fi
HISTSIZE=10000
SAVEHIST=10000

export HISTFILE ZSH_AUTOSUGGEST_STRATEGY HISTSIZE SAVEHIST

# Package Manager
PM_COMMAND=(denv-shell pm)

# Optionally load user configuration // useful for customizing the shell without modifying the main file
if [[ -f $HOME/.user.zsh ]]; then
    source $HOME/.user.zsh # renamed to .user.zsh for intuitiveness that it is a user config
elif [[ -f $ZDOTDIR/user.zsh ]]; then
    source $ZDOTDIR/user.zsh
fi

_load_compinit

if [[ ${DENV_ZSH_NO_PLUGINS} != "1" ]]; then
    if [[ "$DENV_ZSH_DEFER" == "1" ]]; then
        # Set flag for deferred loading
        typeset -g DEFER_ZINIT_LOAD=1
        # Loads the deferred zinit plugin system by DENv
        _load_deferred_plugin_system
        _load_prompt # This disables transient prompts sadly
    else
        # Load zinit immediately if not deferring
        _init_zinit
        _load_prompt
        _load_functions
        _load_completions
    fi
fi

__package_manager () { 
    ${PM_COMMAND[@]} "$@"
}

alias c='clear' \
    in='__package_manager install' \
    un='__package_manager remove' \
    up='__package_manager upgrade' \
    ql='__package_manager search installed' \
    qa='__package_manager search all' \
    vc='code' \
    ..='cd ..' \
    ...='cd ../..' \
    .3='cd ../../..' \
    .4='cd ../../../..' \
    .5='cd ../../../../..' \
    mkdir='mkdir -p'

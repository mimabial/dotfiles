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
    ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
    [ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
    [ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
    source "${ZINIT_HOME}/zinit.zsh"
    
    # Configure oh-my-zsh integration
    zinit snippet OMZL::git.zsh
    zinit snippet OMZP::git
    
    # Load essential plugins
    zinit light "chrissicool/zsh-256color"
    zinit light "zsh-users/zsh-autosuggestions"
    zinit light "zsh-users/zsh-syntax-highlighting"
    
    # Load additional user plugins if they exist
    if [[ -f "$ZDOTDIR/plugins.zsh" ]]; then
        source "$ZDOTDIR/plugins.zsh"
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

    # Exit early if ZSH_DEFER is not set to 1
    if [[ "${ZSH_DEFER}" != "1" ]]; then
        unset -f _load_deferred_plugin_system
        return
    fi

    # Defer zinit loading until after prompt appears
    # Load zinit when line editor initializes // before user input
    if [[ -n $DEFER_ZINIT_LOAD ]]; then
        unset DEFER_ZINIT_LOAD
        [[ ${VSCODE_INJECTION} == 1 ]] || chmod +r $ZDOTDIR/.zshrc # let vscode read .zshrc
        zle -N zle-line-init _defer_zinit_after_prompt_before_input  # Loads when the line editor initializes // The best option
    fi
    #  Below this line are the commands that are executed after the prompt appears

    # autoload -Uz add-zsh-hook
    # add-zsh-hook zshaddhistory load_omz_deferred # loads after the first command is added to history
    # add-zsh-hook precmd load_omz_deferred # Loads when shell is ready to accept commands
    # add-zsh-hook preexec load_omz_deferred # Loads before the first command executes

    # TODO: add handlers in pm.sh
    # for these aliases please manually add the following lines to your .zshrc file.(Using paru as the aur helper)
    # pc='paru -Sc' # remove all cached packages
    # po='paru -Qtdq | ${PM_COMMAND[@]} -Rns -' # remove orphaned packages

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
    autoload -Uz compinit
    autoload -Uz _zinit
    (( ${+_comps} )) && _comps[zinit]=_zinit

    # Enable extended glob for the qualifier to work
    setopt EXTENDED_GLOB

    # Fastest - use glob qualifiers on directory pattern
    if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+${ZSH_COMPINIT_CHECK:-1}) ]]; then
        compinit
    else
        compinit -C
    fi

    _comp_options+=(globdots) # tab complete hidden files
}

function _load_prompt() {
    # Try to load prompts immediately
    if [ -f $ZDOTDIR/conf.d/global/prompt.zsh ]; then
        source $ZDOTDIR/conf.d/global/prompt.zsh
    fi
}

# Override this environment variable in ~/.zshrc
# cleaning up home folder
# ZSH Plugin Configuration

ZINIT_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit"

ZSH_DEFER="1"      #Unset this variable in $ZDOTDIR/startup.zsh to disable HaLL's deferred Zsh loading.
ZSH_PROMPT="1"     #Unset this variable in $ZDOTDIR/startup.zsh to disable HaLL's prompt customization.
ZSH_NO_PLUGINS="0" #Set this variable to "1" in $ZDOTDIR/startup.zsh to disable HaLL's Zsh plugin loading.

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

# HaLL Package Manager
PM_COMMAND=(hyprshell pm)

# Optionally load user configuration // useful for customizing the shell without modifying the main file
if [[ -f $HOME/.startup.zsh ]]; then
    source $HOME/.startup.zsh # renamed to .startup.zsh for intuitiveness that it is a user config
elif [[ -f $ZDOTDIR/startup.zsh ]]; then
    source $ZDOTDIR/startup.zsh
fi


if [[ ${ZSH_NO_PLUGINS} != "1" ]]; then
    if [[ "$ZSH_DEFER" == "1" ]] && [[ -d "$ZINIT_DIR" ]]; then
        # Set flag for deferred loading
        typeset -g DEFER_ZINIT_LOAD=1
        # Loads the deferred zinit plugin system
        _load_deferred_plugin_system
        _load_prompt # This disables transient prompts sadly
    elif [[ -d "$ZINIT_DIR" ]]; then
        # Load zinit immediately if not deferring
        _init_zinit
        _load_compinit
        _load_prompt
        _load_functions
        _load_completions
    else
        echo "No plugin system found. Please install a plugin system or create a $ZDOTDIR/plugins.zsh file."
    fi
fi

__package_manager () { 
    ${PM_COMMAND[@]} "$@"
}

alias cl='clear' \
    hs='hyprshell' \
    in='__package_manager install' \
    un='__package_manager remove' \
    up='__package_manager upgrade' \
    pl='__package_manager search installed' \
    pa='__package_manager search all' \
    vc='vscodium' \
    vi='nvim' \
    ..='cd ..' \
    ...='cd ../..' \
    .3='cd ../../..' \
    .4='cd ../../../..' \
    .5='cd ../../../../..' \
    mkdir='mkdir -p'


# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ~/.zshrc - Main configuration file that sources all other parts

# Define the base directory for all ZSH configurations
ZSH_CONFIG_DIR="$HOME/.zsh"

# === Load Core Settings ===
# export P10K_SCHEME_NAME=kanagawa
# Terminal capabilities
export TERM="xterm-256color"
export COLORTERM="truecolor"

# AI Environment Variables
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

HSA_OVERRIDE_GFX_VERSION=11.0.0
HIP_VISIBLE_DEVICES=0

# Force tmux to assume the terminal supports 256 colors
[[ $TMUX != "" ]] && export TERM="screen-256color"

# Set basic options
setopt autocd              # change directory just by typing its name
setopt interactivecomments # allow comments in interactive mode
setopt magicequalsubst     # enable filename expansion for arguments of the form 'anything=expression'
setopt nonomatch           # hide error message if there is no match for the pattern
setopt notify              # report the status of background jobs immediately
setopt numericglobsort     # sort filenames numerically when it makes sense
setopt promptsubst         # enable command substitution in prompt

# Don't consider certain characters part of the word
WORDCHARS=${WORDCHARS//[\/=]/}

# hide EOL sign ('%')
PROMPT_EOL_MARK=""

# Load essential functions
autoload -U promptinit && promptinit
autoload -U colors && colors

# === Load All Configuration Files ===

# Load history settings
[[ -f "$ZSH_CONFIG_DIR/config/history.zsh" ]] && source "$ZSH_CONFIG_DIR/config/history.zsh"

# Load completion system
[[ -f "$ZSH_CONFIG_DIR/config/completions.zsh" ]] && source "$ZSH_CONFIG_DIR/config/completions.zsh"

# Load key bindings
[[ -f "$ZSH_CONFIG_DIR/config/keybindings.zsh" ]] && source "$ZSH_CONFIG_DIR/config/keybindings.zsh"

# Load plugins
[[ -f "$ZSH_CONFIG_DIR/config/plugins.zsh" ]] && source "$ZSH_CONFIG_DIR/config/plugins.zsh"

# Load custom functions
[[ -f "$ZSH_CONFIG_DIR/config/functions.zsh" ]] && source "$ZSH_CONFIG_DIR/config/functions.zsh"

# Load aliases (load last so they can override anything defined earlier)
[[ -f "$ZSH_CONFIG_DIR/config/aliases.zsh" ]] && source "$ZSH_CONFIG_DIR/config/aliases.zsh"

# === Local Configuration ===

# Load machine-specific configuration if it exists
[[ -f "$ZSH_CONFIG_DIR/local.zsh" ]] && source "$ZSH_CONFIG_DIR/local.zsh"

# To customize prompt, run `p10k configure` or edit ~/.zsh/themes/p10k.zsh.
[[ ! -f ~/.zsh/themes/p10k.zsh ]] || source ~/.zsh/themes/p10k.zsh

# To customize prompt, run `p10k configure` or edit ~/dotfiles/.zsh/themes/p10k.zsh.
[[ ! -f ~/dotfiles/.zsh/themes/p10k.zsh ]] || source ~/dotfiles/.zsh/themes/p10k.zsh

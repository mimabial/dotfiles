#!/usr/bin/env zsh

#! ██████╗░░█████╗░  ███╗░░██╗░█████╗░████████╗  ███████╗██████╗░██╗████████╗
#! ██╔══██╗██╔══██╗  ████╗░██║██╔══██╗╚══██╔══╝  ██╔════╝██╔══██╗██║╚══██╔══╝
#! ██║░░██║██║░░██║  ██╔██╗██║██║░░██║░░░██║░░░  █████╗░░██║░░██║██║░░░██║░░░
#! ██║░░██║██║░░██║  ██║╚████║██║░░██║░░░██║░░░  ██╔══╝░░██║░░██║██║░░░██║░░░
#! ██████╔╝╚█████╔╝  ██║░╚███║╚█████╔╝░░░██║░░░  ███████╗██████╔╝██║░░░██║░░░
#! ╚═════╝░░╚════╝░  ╚═╝░░╚══╝░╚════╝░░░░╚═╝░░░  ╚══════╝╚═════╝░╚═╝░░░╚═╝░░░

# Load prompt immediately

# Exit early if DENV_ZSH_PROMPT is not set to 1
if [[ "${DENV_ZSH_PROMPT}" != "1" ]]; then
    return
fi

if [ -r $HOME/.p10k.zsh ] || [ -r $ZDOTDIR/.p10k.zsh ]; then
    # ===== START Initialize Powerlevel10k theme =====
    # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.config/zsh/.zshrc.
    # Initialization code that may require console input (password prompts, [y/n]
    # confirmations, etc.) must go above this block; everything else may go below.
    POWERLEVEL10K_INSTANT_PROMPT=${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh
    [[ -r $POWERLEVEL10K_INSTANT_PROMPT ]] && source $POWERLEVEL10K_INSTANT_PROMPT
    POWERLEVEL10K_TRANSIENT_PROMPT=same-dir
    P10k_THEME=${P10k_THEME:-/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme}
    [[ -r $P10k_THEME ]] && source $P10k_THEME
    # To customize prompt, run `p10k configure` or edit $HOME/.p10k.zsh
    if [[ -f $HOME/.p10k.zsh ]]; then
        source $HOME/.p10k.zsh
    elif [[ -f $ZDOTDIR/.p10k.zsh ]]; then
        source $ZDOTDIR/.p10k.zsh
    fi
    # ===== END Initialize Powerlevel10k theme =====
fi

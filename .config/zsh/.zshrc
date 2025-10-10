# Add user configurations here
# Edit $ZDOTDIR/startup.zsh to customize behavior before loading zshrc
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Ignore commands that start with spaces and duplicates.
export HISTCONTROL=ignoreboth
# Don't add certain commands to the history file.
export HISTIGNORE="&:[bf]g:c:clear:history:exit:q:pwd:* --help"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  Plugins 
# zinit plugins are loaded in $ZDOTDIR/startup.zsh file, see the file for more information
#  Aliases 
# Override aliases here in '$ZDOTDIR/.zshrc' (already set in .zshenv)
# export EDITOR=code
# unset -f command_not_found_handler # Uncomment to prevent searching for commands not found in package manager
export NEWT_COLORS='window=black,gray;button=black,white;actbutton=white,blue'

#  Startup 
# Commands to execute on startup (before the prompt is shown)
# Check if the interactive shell option is set
# if [[ $- == *i* ]]; then
# This is a good place to load graphic/ascii art, display system information, etc.
#   if command -v fastfetch >/dev/null; then
#     fastfetch
#   fi
# fi

#   Overrides 
# ZSH_NO_PLUGINS=1 # Set to 1 to disable loading of oh-my-zsh plugins, useful if you want to use your zsh plugins system
# unset ZSH_PROMPT # Uncomment to unset/disable loading of prompts and let you load your own prompts
# ZSH_COMPINIT_CHECK=1 # Set 24 (hours) per compinit security check // lessens startup time
# ZSH_DEFER=1 # Set to 1 to defer loading of zinit plugins ONLY if prompt is already loaded

#  Startup 
# Commands to execute on startup (before the prompt is shown)
# Check if the interactive shell option is set
if [[ $- == *i* ]]; then
    # This is a good place to load graphic/ascii art, display system information, etc.
fi

#   Overrides 
# DENV_ZSH_NO_PLUGINS=1 # Set to 1 to disable loading of zinit plugins, useful if you want to use your own zsh plugin system 
# unset DENV_ZSH_PROMPT # Uncomment to unset/disable loading of prompts from DENv and let you load your own prompts
# DENV_ZSH_COMPINIT_CHECK=1 # Set 24 (hours) per compinit security check // lessens startup time

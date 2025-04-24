set -g fish_greeting

source ~/.config/fish/hydra_config.fish

if status is-interactive
    # Basic settings
    set -g fish_greeting "" # Disable greeting
    set -gx EDITOR nvim # Set editor (change to your preference)

    # Custom aliases
    alias ll "ls -la"
    alias la "ls -a"
    alias c clear
    alias g git

    # Path additions (customize as needed)
    fish_add_path ~/.local/bin

    abbr rmf rm -rf
    abbr vi nvim
    abbr v nvim
    abbr yz yazi
    abbr dc docker-compose
    abbr ns kubens
    abbr ctx kubectx
    abbr gs gst
    abbr lg lazygit
    abbr gci git commit
    abbr k kubectl
    abbr d kitten diff
    abbr gd git difftool --no-symlinks --dir-diff
    abbr gds git difftool --no-symlinks --dir-diff --staged
    abbr gsh git difftool --no-symlinks --dir-diff HEAD~1 HEAD
    abbr gr8 git rev-parse --short=8 HEAD
    abbr gcm git checkout main
    abbr gcim git commit -m
    abbr glola git log --oneline --decorate --color --graph --all
    abbr - cd -
    abbr dcps docker-compose ps
    abbr dcupd docker-compose up -d
    abbr dcup docker-compose up
    abbr dcdn docker-compose down
    abbr ly lazygit -ucd ~/.local/share/yadm/lazygit -w ~ -g ~/.local/share/yadm/repo.git

    starship init fish | source
    zoxide init fish | source
    fzf --fish | source

    # Handy change dir shortcuts
    abbr .. 'cd ..'
    abbr ... 'cd ../..'
    abbr .3 'cd ../../..'
    abbr .4 'cd ../../../..'
    abbr .5 'cd ../../../../..'

    # Always mkdir a path (this doesn't inhibit functionality to make a single dir)
    abbr mkdir 'mkdir -p'

    # FZF configuration
    set -gx FZF_DEFAULT_OPTS "--height 99% --preview-window 'right:99%' --style minimal --border"
    set -gx FZF_DEFAULT_COMMAND "fd --type f --hidden --follow --exclude .git"

    # Set different preview commands based on the context
    ## Enhanced preview for files
    set -gx FZF_CTRL_F_OPTS "--preview 'bat --style=numbers --color=always --line-range :500 {}'"
    ## Preview directories with tree or ls
    set -gx FZF_CTRL_O_OPTS "--preview 'ls -la {} | head -50'"

    # Key bindings for our custom functions
    bind \cf __fzf_find_file
    bind \cr __fzf_history
    bind \co __fzf_cd

    # Kitty integration (if needed)
    if set -q KITTY_INSTALLATION_DIR
        set --global KITTY_SHELL_INTEGRATION enabled
        source "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_conf.d/kitty-shell-integration.fish"
    end

end

set -g fish_greeting

source ~/.config/fish/hydra_config.fish

if status is-interactive
    starship init fish | source
end

abbr vi nvim
abbr v nvim
abbr dc docker-compose
abbr ns kubens
abbr ctx kubectx
abbr gs gst
abbr lg lazygit
abbr l lf
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
abbr ll ls -lhtr
abbr ly lazygit -ucd ~/.local/share/yadm/lazygit -w ~ -g ~/.local/share/yadm/repo.git

starship init fish | source
zoxide init fish | source

bind \cx\ce edit_command_buffer # ctrl+x ctrl+e to edit command buffer
bind \cH backward-kill-path-component # ctrl+backspace to delete path component
bind \cw backward-kill-bigword # ctrl+w to delete big word
bind \e\[3\;5~ kill-word # ctrl+delete to delete forward word

fish_add_path ~/.fzf/bin
set -Ux FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'
set -Ux FZF_DEFAULT_OPTS "--history=$HOME/.fzf_history --bind='ctrl-e:preview-down,ctrl-y:preview-up,ctrl-o:toggle-preview'"

# brew install coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent gnu-getopt grep
set -l OS (uname -s)
if [ "$OS" = Darwin ]
    # alias ls "ls -G"
    alias sed gsed
    alias df gdf
    alias cp gcp
end

function mkcd
    mkdir -pv $argv
    cd $argv
end

abbr lv "NVIM_APPNAME=lazyvim nvim"
abbr nvim_old "NVIM_APPNAME=nvim_old nvim"

if [ -n "$KITTY_PID" ]
    abbr ks "kitten ssh"
end

# Handy change dir shortcuts
abbr .. 'cd ..'
abbr ... 'cd ../..'
abbr .3 'cd ../../..'
abbr .4 'cd ../../../..'
abbr .5 'cd ../../../../..'

# Always mkdir a path (this doesn't inhibit functionality to make a single dir)
abbr mkdir 'mkdir -p'

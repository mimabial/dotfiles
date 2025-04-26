# ~/.zsh/config/functions.zsh - Custom functions

# Check if ripgrep is installed before defining ripgrep-dependent functions
if command -v rg &> /dev/null; then
    # Alias for ripgrep with common exclusions
    alias torg="rg --hidden --glob='!Trash/' --glob='!Code\ -\ OSS/' --glob='!.cache/' --glob='!.rustup/' --glob='!.cargo/'"
    
    # Search file contents
    fif() {
      if [ ! "$#" -gt 0 ]; then echo "Need a search term"; return 1; fi
      torg --files-with-matches --no-messages "$1" |
        fzf --exact --preview "highlight -O ansi -l {} 2> /dev/null || rg --pretty --context 10 '$1' {}"
    }

    # Content search with preview
    search_content() {
      local match=$(
        torg --color=always --line-number --no-heading --smart-case "${*:-}" |
          fzf --exact --ansi \
              --color "hl:-1:underline,hl+:-1:underline:reverse" \
              --delimiter : \
              --preview 'bat --color=always {1} --highlight-line {2}' \
              --preview-window 'up,60%,border-bottom,+{2}+3/3,~3'
      )
      local file=$(echo "$match" | cut -d':' -f1)
      if [[ -n $file ]]; then
        ${EDITOR:-vim} "$file" +$(echo "$match" | cut -d':' -f2)
      fi
    }

    alias tofzf="fzf --exact"
    alias sc=search_content
fi

# Extract function - handle various archive formats
extract() {
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xjf $1     ;;
      *.tar.gz)    tar xzf $1     ;;
      *.bz2)       bunzip2 $1     ;;
      *.rar)       unrar e $1     ;;
      *.gz)        gunzip $1      ;;
      *.tar)       tar xf $1      ;;
      *.tbz2)      tar xjf $1     ;;
      *.tgz)       tar xzf $1     ;;
      *.zip)       unzip $1       ;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1        ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Make directory and change into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Find files modified in the last n days
findm() {
  local days=${1:-1}
  find . -type f -mtime -$days | sort
}

# Git commit all with message
gcom() {
  git add -A && git commit -m "$1"
}

# Create a new git branch and switch to it
gcb() {
  git checkout -b "$1"
}

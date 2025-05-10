# ~/.zsh/config/functions.zsh - Custom functions

# Check if ripgrep is installed before defining ripgrep-dependent functions
if command -v rg &>/dev/null; then
  # Alias for ripgrep with common exclusions
  alias torg="rg --hidden --glob='!Trash/' --glob='!Code\ -\ OSS/' --glob='!.cache/' --glob='!.rustup/' --glob='!.cargo/'"

  # Search file contents
  fif() {
    if [ ! "$#" -gt 0 ]; then
      echo "Need a search term"
      return 1
    fi
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
  if [ -f $1 ]; then
    case $1 in
      *.tar.bz2) tar xjf $1 ;;
      *.tar.gz) tar xzf $1 ;;
      *.bz2) bunzip2 $1 ;;
      *.rar) unrar e $1 ;;
      *.gz) gunzip $1 ;;
      *.tar) tar xf $1 ;;
      *.tbz2) tar xjf $1 ;;
      *.tgz) tar xzf $1 ;;
      *.zip) unzip $1 ;;
      *.Z) uncompress $1 ;;
      *.7z) 7z x $1 ;;
      *) echo "'$1' cannot be extracted via extract()" ;;
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

function ai() {
  ~/llama.cpp/build/bin/main -m ~/models/deepseek/deepseek-coder-6.7b-instruct.Q5_K_M.gguf -ngl 99
}

pacsize() {
  pacman -Qi |
    awk '
      /^Name/{ pkg=$3 }
      /^Installed Size/{ printf "%8s %s\n", $4 $5, pkg }
    ' |
    sort -h
}

empty_trash() {
  local action=$1
  local trash_base="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
  local trash_files="$trash_base/files"
  local trash_info="$trash_base/info"

  # Usage/help
  if [[ "$action" == "-h" || "$action" == "--help" || -z "$action" ]]; then
    cat <<EOF
    Usage: empty_trash all | <name>
      all       Empty entire trash (prompt before deleting)
      <name>    Remove only that file/folder from Trash/files
      -h|--help Show this help message
EOF
    return
  fi

  # Ensure trash dirs exist
  if [[ ! -d $trash_files || ! -d $trash_info ]]; then
    echo "⚠️  No trash directory found at '$trash_base'." >&2
    return 1
  fi

  # "all" case: prompt & remove everything
  if [[ $action == "all" ]]; then
    # check if already empty
    if [[ -z "$(ls -A $trash_files)" ]]; then
      echo "🗑️  Trash is already empty."
      return
    fi

    read -q "?Are you sure you want to completely empty the trash? [y/N] "
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      command rm -rf -- "$trash_files/"* "$trash_info/"*
      echo "✅  Trash emptied."
    else
      echo "❎  Aborted."
    fi

    return
  fi

  # Single-name case
  local target_file="$trash_files/$action"
  local target_info="$trash_info/$action.trashinfo"

  if [[ -e $target_file ]]; then
    # prompt once
    read -q "?Remove '$action' from trash? [y/N] "
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm -rf -- "$target_file"
      [[ -e $target_info ]] && rm -f -- "$target_info"
      echo "✅  Removed '$action' from trash."
    else
      echo "❎  Aborted."
    fi
  else
    echo "⚠️  No such file or folder in trash: '$action'." >&2
    return 1
  fi
}

# list the N largest files under a directory (default: . and 10 files)
heavy() {
  local dir="${1:-.}"
  local n="${2:-10}"

  # du: list all files & dirs under $dir, human-readable, same-fs only
  # grep -v '/$': drop directories
  # sort -rh: largest first
  # head -n $n: show top N
  du -ahx -- "$dir" 2>/dev/null |
    grep -v '/$' |
    sort -rh |
    head -n "$n"
}

pristine() {
  # path to your llama.cpp build
  local LCPP="$HOME/llama.cpp/build/bin/llama-cli"
  # path to your converted GGUF model
  local MODEL="$HOME/models/deepseek/deepseek-coder-6.7b-instruct.Q5_K_M.gguf"

  if [[ ! -x "$LCPP" ]]; then
    echo "❌ ERROR: llama.cpp binary not found at $LCPP"
    return 1
  fi
  if [[ ! -f "$MODEL" ]]; then
    echo "❌ ERROR: model file not found at $MODEL"
    return 1
  fi

  "$LCPP" \
    -m "$MODEL" \
    --interactive-first \
    --conversation \
    --system-prompt "You are a helpful assistant. Always respond in English. Wait for user input before responding." \
    --prompt "Hello" \
    --color
}

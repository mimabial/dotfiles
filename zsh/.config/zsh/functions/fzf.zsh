# FZF wrapper functions for enhanced file/directory navigation
# Dependencies: fzf (required), ripgrep/bat (optional for enhanced features)
# NOTE: _fuzzy_search_cmd_history requires fzf shell integration
#       Source fzf's shell setup: source /usr/share/fzf/key-bindings.zsh (or similar)

# Track if we've already warned about missing dependencies
typeset -g _FZF_WARNED_RG=0
typeset -g _FZF_WARNED_BAT=0

# Shared exclusion patterns for all search functions
typeset -ga _FZF_EXCLUDE_DIRS=(
    'History'
    'Trash'
    'build'
    'backup'
    'BraveSoftware'
    'cfg_backups'
    'chromium'
    'code_tracker'
    'dist'
    'dotfiles'
    'flatpak'
    'libreoffice'
    'logs'
    'node_modules'
    'obs-studio'
    'resurrect'
    'sessions'
    'target'
    '.cache'
    '.claude'
    '.git'
    '.npm'
    '.var'
    '.venv'
    '*-debug'
)

typeset -ga _FZF_EXCLUDE_FILES=(
    '%usr%local%share.vim'
    '*.log'
    'history'
    '.bash_history'
    '.DS_Store'
    '.netrwhist'
    '.viminfo'
    '.zcompdump*'
    '.zsh_history'
)

# Generate find exclusion arguments: returns "-name .git -prune -o -name node_modules -prune -o ..."
_get_find_excludes() {
    local result=""
    for dir in "${_FZF_EXCLUDE_DIRS[@]}"; do
        result+=" -name $dir -prune -o"
    done
    for file in "${_FZF_EXCLUDE_FILES[@]}"; do
        result+=" ! -name '$file'"
    done
    echo "$result"
}

# Generate ripgrep glob patterns: returns "--glob='!.git/' --glob='!node_modules/' ..."
_get_rg_globs() {
    local result=""
    for dir in "${_FZF_EXCLUDE_DIRS[@]}"; do
        result+=" --glob='!$dir/'"
    done
    for file in "${_FZF_EXCLUDE_FILES[@]}"; do
        result+=" --glob='!$file'"
    done
    echo "$result"
}

# Generate grep path exclusions: returns "-not -path '*/.git/*' -not -path '*/node_modules/*' ..."
_get_grep_excludes() {
    local result=""
    for dir in "${_FZF_EXCLUDE_DIRS[@]}"; do
        result+=" -not -path '*/$dir/*'"
    done
    for file in "${_FZF_EXCLUDE_FILES[@]}"; do
        result+=" -not -path '*/$file'"
    done
    echo "$result"
}

_check_dependencies() {
    local missing=()
    
    if ! command -v "fzf" &>/dev/null; then
        echo "ERROR: fzf is required but not installed"
        echo "Install: brew install fzf  OR  apt install fzf"
        return 1
    fi
    
    if ! command -v "rg" &>/dev/null && [[ $_FZF_WARNED_RG -eq 0 ]]; then
        missing+=("ripgrep (rg)")
        _FZF_WARNED_RG=1
    fi
    
    if ! command -v "bat" &>/dev/null && [[ $_FZF_WARNED_BAT -eq 0 ]]; then
        missing+=("bat")
        _FZF_WARNED_BAT=1
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "⚠  Optional dependencies missing: ${(j:, :)missing}"
        echo "   Install for better experience:"
        [[ " ${missing[@]} " =~ " ripgrep (rg) " ]] && echo "   • ripgrep: brew install ripgrep  OR  apt install ripgrep"
        [[ " ${missing[@]} " =~ " bat " ]] && echo "   • bat: brew install bat  OR  apt install bat"
        echo ""
    fi
}

_fuzzy_edit_search_file_content_dynamic() {
    _check_dependencies || return 1
    
    local initial_query="$1"
    local selected_result
    local rg_globs="$(_get_rg_globs)"
    local grep_excludes="$(_get_grep_excludes)"
    local preview_cmd='f=$(echo {} | cut -d: -f1); line=$(echo {} | cut -d: -f2); if command -v "bat" &>/dev/null; then bat --color=always --style=numbers --highlight-line=$line --line-range=$((line > 5 ? line - 5 : 1)): "$f"; else cat -n "$f" | awk -v line=$line "NR>=line-5 && NR<=line+20 {if(NR==line) print \" -> \" \$0; else print \$0}"; fi'
    
    if command -v "rg" &>/dev/null; then
        # Dynamic ripgrep search - re-runs on every keystroke
        selected_result=$(fzf \
            --disabled \
            --ansi \
            --delimiter=: \
            --height "95%" \
            --layout=reverse \
            --preview-window "right,60%,border-sharp,<60(down,50%,border-top)" \
            --cycle \
            --preview "$preview_cmd" \
            --query "$initial_query" \
            --prompt "Search: " \
            --bind "start:reload(rg --hidden --line-number --column --color=always --smart-case --max-count=30 $rg_globs '.' 2>/dev/null || true)" \
            --bind "change:reload(sleep 0.1; if [[ -n {q} ]]; then rg --hidden --line-number --column --color=always --smart-case --max-count=30 $rg_globs {q} 2>/dev/null || true; fi)" \
            --bind "enter:execute(
                if [[ -n {} ]]; then
                    f=\$(echo {} | cut -d: -f1)
                    line=\$(echo {} | cut -d: -f2)
                    if command -v \"\$EDITOR\" &>/dev/null; then
                        \$EDITOR +\$line \"\$f\"
                    else
                        nvim +\$line \"\$f\"
                    fi
                fi
            )" \
            --bind "ctrl-o:execute(
                if [[ -n {} ]]; then
                    f=\$(echo {} | cut -d: -f1)
                    if command -v \"bat\" &>/dev/null; then
                        bat --paging=always \"\$f\"
                    else
                        less \"\$f\"
                    fi
                fi
            )" \
            --header "Dynamic Search | Enter: Edit | Ctrl-O: View"
        )
    else
        # Dynamic grep fallback
        selected_result=$(fzf \
            --disabled \
            --ansi \
            --delimiter=: \
            --height "90%" \
            --layout=reverse \
            --preview-window "right,60%,border-sharp,<60(down,50%,border-top)" \
            --cycle \
            --preview "$preview_cmd" \
            --query "$initial_query" \
            --prompt "Search: " \
            --bind "start:reload(find . -type f $grep_excludes -exec grep -Hn --color=always '.' {} + 2>/dev/null | head -500 || true)" \
            --bind "change:reload(sleep 0.1; if [[ -n {q} ]]; then find . -type f $grep_excludes -exec grep -Hn --color=always {q} {} + 2>/dev/null | head -1000 || true; fi)" \
            --bind "enter:execute(
                if [[ -n {} ]]; then
                    f=\$(echo {} | cut -d: -f1)
                    line=\$(echo {} | cut -d: -f2)
                    if command -v \"\$EDITOR\" &>/dev/null; then
                        \$EDITOR +\$line \"\$f\"
                    else
                        nvim +\$line \"\$f\"
                    fi
                fi
            )" \
            --bind "ctrl-o:execute(
                if [[ -n {} ]]; then
                    f=\$(echo {} | cut -d: -f1)
                    if command -v \"bat\" &>/dev/null; then
                        bat --paging=always \"\$f\"
                    else
                        less \"\$f\"
                    fi
                fi
            )" \
            --header "Dynamic Search | Enter: Edit | Ctrl-O: View"
        )
    fi
}

_fuzzy_change_directory() {
    _check_dependencies || return 1

    local initial_query="$1"
    local selected_dir
    local fzf_options=('--preview=ls -Ap {}' '--preview-window=right,60%,<100(down,40%,border-top)')
    fzf_options+=(--height "80%" --layout=reverse --cycle -i)
    local max_depth=7

    # Build exclusion pattern for directories only (just the name tests, no -prune yet)
    local exclude_pattern=""
    for dir in "${_FZF_EXCLUDE_DIRS[@]}"; do
        exclude_pattern+=" -o -name '$dir'"
    done
    # Remove leading " -o"
    exclude_pattern="${exclude_pattern# -o }"

    if [[ -n "$initial_query" ]]; then
        fzf_options+=("--query=$initial_query")
    fi

    # Use find with explicit hidden directory support
    # \( -name X -o -name Y ... \) groups all dir names to exclude
    # -prune skips them, -o means "otherwise", -type d -print shows all other directories (including hidden)
    selected_dir=$(eval "find . -maxdepth $max_depth \\( $exclude_pattern \\) -prune -o -type d -print 2>/dev/null" | fzf "${fzf_options[@]}")

    if [[ -n "$selected_dir" && -d "$selected_dir" ]]; then
        cd "$selected_dir" || return 1
    else
        return 1
    fi
}

_fuzzy_edit_search_file_content() {
    # [f]uzzy [e]dit  [s]earch [f]ile [c]ontent
    _check_dependencies || return 1
    
    local search_term="$1"
    local selected_result
    local fzf_options=()
    local search_cmd
    local preview_cmd
    local rg_globs="$(_get_rg_globs)"
    local grep_excludes="$(_get_grep_excludes)"
    
    # Check if ripgrep is available (faster and better than grep)
    if command -v "rg" &>/dev/null; then
        if [[ -n "$search_term" ]]; then
            search_cmd="rg --line-number --column --color=always --smart-case --hidden --max-count=50 $rg_globs '$search_term' 2>/dev/null"
        else
            # Show all files with line numbers
            search_cmd="find . -type f $grep_excludes 2>/dev/null | head -1000 | xargs -I {} echo '{}:1:'"
            fzf_options+=("--query=" "--print-query")
        fi
        
        # Preview command for ripgrep results
        preview_cmd='f=$(echo {} | cut -d: -f1); line=$(echo {} | cut -d: -f2); if command -v "bat" &>/dev/null; then bat --color=always --style=numbers --highlight-line=$line --line-range=$((line > 5 ? line - 5 : 1)): "$f"; else cat -n "$f" | awk -v line=$line "NR>=line-5 && NR<=line+20 {if(NR==line) print \" -> \" \$0; else print \$0}"; fi'
    else
        # Fallback to grep with consistent exclusion patterns
        if [[ -n "$search_term" ]]; then
            search_cmd="find . -type f $grep_excludes -exec grep -Hn --color=always '$search_term' {} + 2>/dev/null | head -2500"
        else
            # Show files instead of grepping all content
            search_cmd="find . -type f $grep_excludes 2>/dev/null | head -1000 | xargs -I {} echo '{}:1:'"
            fzf_options+=("--query=" "--print-query")
        fi
        
        # Preview command for grep results  
        preview_cmd='f=$(echo {} | cut -d: -f1); line=$(echo {} | cut -d: -f2); if command -v "bat" &>/dev/null; then bat --color=always --style=numbers --highlight-line=$line --line-range=$((line > 5 ? line - 5 : 1)): "$f"; else cat -n "$f" | awk -v line=$line "NR>=line-5 && NR<=line+20 {if(NR==line) print \" -> \" \$0; else print \$0}"; fi'
    fi
    
    fzf_options+=(
        --height "90%" 
        --layout=reverse 
        --preview-window "right,60%,border-sharp,<60(down,50%,border-top)"
        --cycle
        --ansi
        --delimiter=:
        --preview "$preview_cmd"
        --bind "enter:execute(
            f=\$(echo {} | cut -d: -f1)
            line=\$(echo {} | cut -d: -f2)
            if command -v \"\$EDITOR\" &>/dev/null; then
                \$EDITOR +\$line \"\$f\"
            else
                nvim +\$line \"\$f\"
            fi
        )"
        --bind "ctrl-o:execute(
            f=\$(echo {} | cut -d: -f1)
            if command -v \"bat\" &>/dev/null; then
                bat --paging=always \"\$f\"
            else
                less \"\$f\"
            fi
        )"
        --header "Enter: Edit file at line | Ctrl-O: View file"
    )
    eval "$search_cmd" | fzf "${fzf_options[@]}"
}

_fuzzy_edit_search_file() {
    _check_dependencies || return 1
    
    local initial_query="$1"
    local selected_file
    local fzf_options=()
    local preview_cmd='if command -v "bat" &>/dev/null; then bat --color=always --style=numbers {}; else cat {}; fi'
    
    fzf_options+=(
        --height "80%" 
        --layout=reverse 
        --preview "$preview_cmd"
        --preview-window "right,60%,<100(down,40%,border-top)"
        --cycle
    )
    local max_depth=5

    if [[ -n "$initial_query" ]]; then
        fzf_options+=("--query=$initial_query")
    fi

    selected_file=$(find . -maxdepth $max_depth -type f 2>/dev/null | fzf "${fzf_options[@]}")

    if [[ -n "$selected_file" && -f "$selected_file" ]]; then
        if command -v "$EDITOR" &>/dev/null; then
            "$EDITOR" "$selected_file"
        else
            echo "EDITOR is not specified. using vim.  (you can export EDITOR in ~/.zshrc)"
            nvim "$selected_file"
        fi
    else
        return 1
    fi
}

_fuzzy_search_cmd_history() {
  _check_dependencies || return 1
  
  local selected
  setopt localoptions noglobsubst noposixbuiltins pipefail no_aliases noglob nobash_rematch 2> /dev/null

  local fzf_query=""
  if [[ -n "$1" ]]; then
    fzf_query="--query=${(qqq)1}"
  else
    fzf_query="--query=${(qqq)LBUFFER}"
  fi

  if zmodload -F zsh/parameter p:{commands,history} 2>/dev/null && (( ${+commands[perl]} )); then
    selected="$(printf '%s\t%s\000' "${(kv)history[@]}" |
      perl -0 -ne 'if (!$seen{(/^\s*[0-9]+\**\t(.*)/s, $1)}++) { s/\n/\n\t/g; print; }' |
      FZF_DEFAULT_OPTS=$(__fzf_defaults "" "-n2..,.. --scheme=history --bind=ctrl-r:toggle-sort --wrap-sign '\t↳ ' --highlight-line ${FZF_CTRL_R_OPTS-} $fzf_query +m --read0") \
      FZF_DEFAULT_OPTS_FILE='' $(__fzfcmd))"
  else
    selected="$(fc -rl 1 | __fzf_exec_awk '{ cmd=$0; sub(/^[ \t]*[0-9]+\**[ \t]+/, "", cmd); if (!seen[cmd]++) print $0 }' |
      FZF_DEFAULT_OPTS=$(__fzf_defaults "" "-n2..,.. --scheme=history --bind=ctrl-r:toggle-sort --wrap-sign '\t↳ ' --highlight-line ${FZF_CTRL_R_OPTS-} $fzf_query +m") \
      FZF_DEFAULT_OPTS_FILE='' $(__fzfcmd))"
  fi
  local ret=$?
  if [ -n "$selected" ]; then
    if [[ -n "$WIDGET" ]]; then
      # Called as ZLE widget - update current buffer
      if [[ $(__fzf_exec_awk '{print $1; exit}' <<< "$selected") =~ ^[1-9][0-9]* ]]; then
        zle vi-fetch-history -n $MATCH
      else
        LBUFFER="$selected"
      fi
    else
      # Called as regular command - push to next prompt using print -z
      local cmd=$(echo "$selected" | sed -E 's/^[[:space:]]*[0-9]+\*?[[:space:]]+//')
      print -z "$cmd"
    fi
  fi
  return $ret
}

# Register as ZLE widget so it can modify the command line
zle -N _fuzzy_search_cmd_history
# Bind to Ctrl+X R for fuzzy command history
bindkey '^Xr' _fuzzy_search_cmd_history

alias fec='_fuzzy_edit_search_file_content' \
    fecd='_fuzzy_edit_search_file_content_dynamic' \
    fcd='_fuzzy_change_directory' \
    fe='_fuzzy_edit_search_file' \
    fch='_fuzzy_search_cmd_history'

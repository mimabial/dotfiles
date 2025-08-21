_fuzzy_edit_find_by_content() {
    local search_term="$1"
    local selected_file
    
    if [[ -z "$search_term" ]]; then
        echo "Please provide a search term: ffbc <search_term>"
        return 1
    fi

    if command -v "rg" &>/dev/null; then
        search_results=$(rg -l --smart-case "$search_term")
    else
        search_results=$(grep -irl "$search_term" .)
    fi
    
    if [[ -z "$search_results" ]]; then
        echo "No files found containing: '$search_term'"
        return 1
    fi
    
    selected_file=$(echo "$search_results" | fzf \
        --height "80%" \
        --layout=reverse \
        --preview-window right:60%:border-sharp \
        --cycle \
        --preview "if command -v 'bat' &>/dev/null; then bat --color=always --style=plain {}; else cat {}; fi | grep --color=always -C 3 '$search_term'")
        
    if [[ -n "$selected_file" && -f "$selected_file" ]]; then
        echo "Selected file: $selected_file"
        if command -v "$EDITOR" &>/dev/null; then
            "$EDITOR" "$selected_file"
        else
            echo "EDITOR is not specified. using vim. (you can export EDITOR in ~/.zshrc)"
            vim "$selected_file"
        fi
    else
        return 1
    fi
}

_fuzzy_change_directory() {
    local initial_query="$1"
    local selected_dir
    local fzf_options=('--preview=ls -p {}' '--preview-window=right:50%:border-sharp')
    fzf_options+=(--height "80%" --layout=reverse --preview-window right:50% --cycle)
    local max_depth=7

    if [[ -n "$initial_query" ]]; then
        fzf_options+=("--query=$initial_query")
    fi

    #type -d
    selected_dir=$(find . -maxdepth $max_depth \( -name .git -o -name node_modules -o -name .venv -o -name target -o -name .cache \) -prune -o -type d -print 2>/dev/null | fzf "${fzf_options[@]}")

    if [[ -n "$selected_dir" && -d "$selected_dir" ]]; then
        cd "$selected_dir" || return 1
    else
        return 1
    fi
}

_fuzzy_edit_search_file_content() {
    # [f]uzzy [e]dit  [s]earch [f]ile [c]ontent
    local search_term="$1"
    local selected_result
    local fzf_options=()
    local search_cmd
    local preview_cmd
    
    # Check if ripgrep is available (faster and better than grep)
    if command -v "rg" &>/dev/null; then
        if [[ -n "$search_term" ]]; then
            search_cmd="rg --line-number --column --color=always --smart-case '$search_term'"
        else
            # If no search term, search for any non-empty line
            search_cmd="rg --line-number --column --color=always --smart-case '.'"
            fzf_options+=("--query=" "--print-query")
        fi
        
        # Preview command for ripgrep results
        preview_cmd='f=$(echo {} | cut -d: -f1); line=$(echo {} | cut -d: -f2); if command -v "bat" &>/dev/null; then bat --color=always --style=numbers --highlight-line=$line "$f"; else cat -n "$f" | sed "${line}s/.*/ -> &/"; fi'
    else
        # Fallback to grep
        if [[ -n "$search_term" ]]; then
            search_cmd="grep -rn --color=always '$search_term' ."
        else
            # If no search term, find all files with content
            search_cmd="grep -rn --color=always '.' ."
            fzf_options+=("--query=" "--print-query")
        fi
        
        # Preview command for grep results  
        preview_cmd='f=$(echo {} | cut -d: -f1); line=$(echo {} | cut -d: -f2); if command -v "bat" &>/dev/null; then bat --color=always --style=numbers --highlight-line=$line "$f"; else cat -n "$f" | sed "${line}s/.*/ -> &/"; fi'
    fi
    
    fzf_options+=(
        --height "90%" 
        --layout=reverse 
        --preview-window right:60%:border-sharp 
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
                vim +\$line \"\$f\"
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
    local show_preview=false
    local initial_query=""
    
    # Check if first argument is a preview flag
    if [[ "$1" == "--preview" || "$1" == "-p" ]]; then
        show_preview=true
        shift  # Remove the preview flag from arguments
    fi
    
    # Remaining arguments form the query
    initial_query="$*"
    
    local selected_file
    local fzf_options=()
    local preview_cmd
    
    # Set up basic fzf options
    fzf_options+=(--height "80%" --layout=reverse --cycle)
    
    # Add preview options only if first arg was a preview flag
    if [[ "$show_preview" == true ]]; then
        if command -v "bat" &>/dev/null; then
            preview_cmd=('bat --color always --style=plain --paging=never {}')
        else
            preview_cmd=('cat {}')
        fi
        fzf_options+=(--preview-window right:60%:border-sharp --preview "${preview_cmd[@]}")
    fi
    
    local max_depth=5

    if [[ -n "$initial_query" ]]; then
        fzf_options+=("--query=$initial_query")
    fi

    # -type f: only find files
    selected_file=$(find . -maxdepth $max_depth -type f 2>/dev/null | fzf "${fzf_options[@]}")

    if [[ -n "$selected_file" && -f "$selected_file" ]]; then
        if command -v "$EDITOR" &>/dev/null; then
            "$EDITOR" "$selected_file"
        else
            echo "EDITOR is not specified. using vim.  (you can export EDITOR in ~/.zshrc)"
            vim "$selected_file"
        fi
    else
        return 1
    fi
}

_fuzzy_search_cmd_history() {
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
    if [[ $(__fzf_exec_awk '{print $1; exit}' <<< "$selected") =~ ^[1-9][0-9]* ]]; then
      zle vi-fetch-history -n $MATCH
    else
      LBUFFER="$selected"
    fi
  fi
  return $ret
}

alias ffec='_fuzzy_edit_search_file_content' \
    ffcd='_fuzzy_change_directory' \
    ffe='_fuzzy_edit_search_file' \
    ffch='_fuzzy_search_cmd_history' \
    ffbc='_fuzzy_edit_find_by_content'

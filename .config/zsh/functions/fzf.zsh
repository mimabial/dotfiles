_fuzzy_edit_search_file_content_dynamic() {
    local initial_query="$1"
    local selected_result
    local preview_cmd='f=$(echo {} | cut -d: -f1); line=$(echo {} | cut -d: -f2); if command -v "bat" &>/dev/null; then bat --color=always --style=numbers --highlight-line=$line "$f"; else cat -n "$f" | sed "${line}s/.*/ -> &/"; fi'
    
    if command -v "rg" &>/dev/null; then
        # Dynamic ripgrep search - re-runs on every keystroke
        selected_result=$(fzf \
            --disabled \
            --ansi \
            --delimiter=: \
            --height "90%" \
            --layout=reverse \
            --preview-window right:60%:border-sharp \
            --cycle \
            --preview "$preview_cmd" \
            --query "$initial_query" \
            --bind "start:reload(rg --hidden --line-number --column --color=always --smart-case --max-count=30 --glob='!.git' --glob='!node_modules' --glob='!.venv' --glob='!target' --glob='!build' --glob='!dist' '.' || echo 'No results')" \
            --bind "change:reload(sleep 0.1; if [[ {q} == '' ]]; then echo 'Type to search...'; else rg --hidden --line-number --column --color=always --smart-case --max-count=30 --glob='!.git' --glob='!node_modules' --glob='!.venv' --glob='!target' --glob='!build' --glob='!dist' {q} || echo 'No results for: {q}'; fi)" \
            --bind "enter:execute(
                if [[ {} != 'Type to search...' ]] && [[ {} != 'No results'* ]]; then
                    f=\$(echo {} | cut -d: -f1)
                    line=\$(echo {} | cut -d: -f2)
                    if command -v \"\$EDITOR\" &>/dev/null; then
                        \$EDITOR +\$line \"\$f\"
                    else
                        vim +\$line \"\$f\"
                    fi
                fi
            )" \
            --bind "ctrl-o:execute(
                if [[ {} != 'Type to search...' ]] && [[ {} != 'No results'* ]]; then
                    f=\$(echo {} | cut -d: -f1)
                    if command -v \"bat\" &>/dev/null; then
                        bat --paging=always \"\$f\"
                    else
                        less \"\$f\"
                    fi
                fi
            )" \
            --header "Dynamic Search | Enter: Edit | Ctrl-O: View | Type to search..."
        )
    else
        # Dynamic grep fallback
        selected_result=$(fzf \
            --disabled \
            --ansi \
            --delimiter=: \
            --height "90%" \
            --layout=reverse \
            --preview-window right:60%:border-sharp \
            --cycle \
            --preview "$preview_cmd" \
            --query "$initial_query" \
            --bind "start:reload(find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/target/*' -exec grep -Hn --color=always '.' {} \; 2>/dev/null | head -500 || echo 'No results')" \
            --bind "change:reload(sleep 0.1; if [[ {q} == '' ]]; then echo 'Type to search...'; else find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/target/*' -exec grep -Hn --color=always {q} {} \; 2>/dev/null | head -1000 || echo 'No results for: {q}'; fi)" \
            --bind "enter:execute(
                if [[ {} != 'Type to search...' ]] && [[ {} != 'No results'* ]]; then
                    f=\$(echo {} | cut -d: -f1)
                    line=\$(echo {} | cut -d: -f2)
                    if command -v \"\$EDITOR\" &>/dev/null; then
                        \$EDITOR +\$line \"\$f\"
                    else
                        vim +\$line \"\$f\"
                    fi
                fi
            )" \
            --bind "ctrl-o:execute(
                if [[ {} != 'Type to search...' ]] && [[ {} != 'No results'* ]]; then
                    f=\$(echo {} | cut -d: -f1)
                    if command -v \"bat\" &>/dev/null; then
                        bat --paging=always \"\$f\"
                    else
                        less \"\$f\"
                    fi
                fi
            )" \
            --header "Dynamic Search | Enter: Edit | Ctrl-O: View | Type to search..."
        )
    fi
}

_fuzzy_change_directory() {
    local initial_query="$1"
    local selected_dir
    local fzf_options=('--preview=ls -p {}' '--preview-window=right:60%')
    fzf_options+=(--height "80%" --layout=reverse --preview-window right:60% --cycle)
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
            # More comprehensive ripgrep search with result limit
            search_cmd="rg --line-number --column --color=always --smart-case --hidden --max-count=50 '$search_term'"
        else
            # If no search term, search for any non-empty line (limited results)
            search_cmd="rg --line-number --column --color=always --smart-case --hidden --max-count=20 '.'"
            fzf_options+=("--query=" "--print-query")
        fi
        
        # Preview command for ripgrep results
        preview_cmd='f=$(echo {} | cut -d: -f1); line=$(echo {} | cut -d: -f2); if command -v "bat" &>/dev/null; then bat --color=always --style=numbers --highlight-line=$line "$f"; else cat -n "$f" | sed "${line}s/.*/ -> &/"; fi'
    else
        # Fallback to grep with more comprehensive options and limits
        if [[ -n "$search_term" ]]; then
            # More thorough grep search with result limit
            search_cmd="find . -type f -not -path '*/\.*' -exec grep -Hn --color=always '$search_term' {} \; 2>/dev/null | head -2500"
        else
            # If no search term, find all files with content (limited)
            search_cmd="find . -type f -not -path '*/\.*' -exec grep -Hn --color=always '.' {} \; 2>/dev/null | head -1000"
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
    local initial_query="$1"
    local selected_file
    local fzf_options=()
    fzf_options+=(--height "80%" --layout=reverse --preview-window right:60% --cycle)
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

alias zec='_fuzzy_edit_search_file_content' \
    zecd='_fuzzy_edit_search_file_content_dynamic' \
    zcd='_fuzzy_change_directory' \
    ze='_fuzzy_edit_search_file' \
    zch='_fuzzy_search_cmd_history'

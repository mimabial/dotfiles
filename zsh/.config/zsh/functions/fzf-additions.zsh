# Additional fzf workflows to complement existing fzf.zsh
# These add git, process, and preview-only functionality

if ! command -v "fzf" &>/dev/null; then
    return 0
fi

# Fuzzy git branch switcher
fzgb() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Not a git repository"
        return 1
    fi

    local branch
    branch=$(git branch --all --color=always | \
        grep -v '/HEAD\s' | \
        fzf --ansi --height 50% --reverse \
            --preview 'git log --oneline --graph --date=short --pretty="format:%C(auto)%cd %h%d %s" $(echo {} | sed "s/.* //" | sed "s#remotes/origin/##") | head -50' \
            --bind 'ctrl-/:toggle-preview' \
            --header 'Switch branch | Ctrl-/: Toggle preview' | \
        sed 's/.* //' | \
        sed 's#remotes/origin/##')

    if [[ -n "$branch" ]]; then
        git checkout "$branch"
    fi
}

# Fuzzy git add (stage files)
fzga() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Not a git repository"
        return 1
    fi

    local files
    files=$(git status --short | \
        fzf --multi --ansi --height 60% --reverse \
            --preview 'git diff --color=always {2} | head -100' \
            --bind 'ctrl-/:toggle-preview' \
            --header 'Select files to stage (Tab: multi-select) | Ctrl-/: Toggle diff' | \
        awk '{print $2}')

    if [[ -n "$files" ]]; then
        echo "$files" | xargs git add
        echo "Staged: $(echo "$files" | wc -l) file(s)"
    fi
}

# Fuzzy git log browser
fzgl() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Not a git repository"
        return 1
    fi

    git log --graph --color=always \
        --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" | \
    fzf --ansi --no-sort --reverse --height 90% \
        --preview 'echo {} | grep -o "[a-f0-9]\{7\}" | head -1 | xargs git show --color=always' \
        --bind 'ctrl-/:toggle-preview' \
        --bind 'enter:execute(echo {} | grep -o "[a-f0-9]\{7\}" | head -1 | xargs git show | less -R)' \
        --header 'Browse commits | Enter: View full commit | Ctrl-/: Toggle preview'
}

# Fuzzy process killer
fzkill() {
    local pid
    pid=$(ps -ef | sed 1d | fzf --multi --height 60% --reverse \
        --preview 'echo {}' \
        --preview-window down:3:wrap \
        --header 'Select process to kill (Tab: multi-select)' | \
        awk '{print $2}')

    if [[ -n "$pid" ]]; then
        echo "$pid" | xargs kill -9
        echo "Killed process(es): $pid"
    fi
}

# Fuzzy view (preview-only, no editing)
fzv() {
    local file
    if command -v "fd" &>/dev/null; then
        file=$(fd --type f --hidden --exclude .git --max-depth 5 | \
            fzf --height 80% --reverse \
                --preview 'bat --color=always --style=numbers {}' \
                --preview-window 'right,70%' \
                --bind 'ctrl-/:toggle-preview' \
                --header 'View file | Enter: Open with bat')
    else
        file=$(find . -type f -not -path '*/\.git/*' -not -path '*/node_modules/*' | \
            fzf --height 80% --reverse \
                --preview 'bat --color=always --style=numbers {} 2>/dev/null || cat {}' \
                --preview-window 'right,70%' \
                --bind 'ctrl-/:toggle-preview' \
                --header 'View file | Enter: Open with bat')
    fi

    if [[ -n "$file" ]]; then
        if command -v "bat" &>/dev/null; then
            bat --paging=always "$file"
        else
            less "$file"
        fi
    fi
}

# Fuzzy directory jump with zoxide integration
if command -v "zoxide" &>/dev/null; then
    fzj() {
        local dir
        dir=$(zoxide query -l | \
            fzf --height 60% --reverse \
                --preview 'eza --tree --level=2 --icons {} 2>/dev/null || ls -la {}' \
                --preview-window 'right,50%' \
                --bind 'ctrl-/:toggle-preview' \
                --header 'Jump to directory (sorted by frecency)')

        if [[ -n "$dir" ]]; then
            cd "$dir" || return 1
        fi
    }
fi

# Fuzzy environment variable viewer
fzenv() {
    env | sort | \
    fzf --height 60% --reverse \
        --preview 'echo {}' \
        --preview-window down:3:wrap \
        --bind 'ctrl-y:execute-silent(echo {} | cut -d= -f2 | xargs echo -n | pbcopy || xclip -selection clipboard)' \
        --header 'Environment variables | Ctrl-Y: Copy value'
}

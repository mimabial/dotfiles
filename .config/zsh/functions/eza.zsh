if command -v "eza" &>/dev/null; then
    alias l='eza -lh --icons=never' \
        ll='eza -lha --icons=never --sort=name --group-directories-first' \
        ld='eza -lhD --icons=never' \
        lt='eza --icons=never --tree'
fi

#!/usr/bin/env bash
# wal.tmux.sh - Apply pywal16 colors to tmux with theme override support

hashFile="${XDG_RUNTIME_DIR:-/tmp}/wal-tmux-hash"
WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
TMUX_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"

# Source pywal16 colors
if [ ! -f "${WAL_CACHE}/colors.sh" ]; then
  exit 0
fi

# Change detection: skip if colors unchanged
input_hash=$(md5sum "${WAL_CACHE}/colors.sh" 2>/dev/null | cut -d' ' -f1)
if [[ -f "$hashFile" && "$(cat "$hashFile" 2>/dev/null)" == "$input_hash" ]]; then
  exit 0
fi

source "${WAL_CACHE}/colors.sh"

# Map pywal colors to tmux theme variables
# Note: Theme-specific tmux colors are handled by color.set.sh processing tmux.theme files
tmux_bg="${background:-$color0}"
tmux_fg="${foreground:-$color15}"
tmux_accent="$color4"
tmux_gray="$color8"
tmux_highlight="$color4"
tmux_red="$color1"
tmux_brightred="$color9"
tmux_green="$color2"
tmux_yellow="$color3"
tmux_blue="$color4"
tmux_magenta="$color5"
tmux_cyan="$color6"

# Generate colors-tmux.conf
cat > "${WAL_CACHE}/colors-tmux.conf" << EOF
# ============================================================================
# Standard 16 color palette (from pywal16)
# ============================================================================
set -g @color0 "$color0"     # black
set -g @color1 "$color1"     # red
set -g @color2 "$color2"     # green
set -g @color3 "$color3"     # yellow
set -g @color4 "$color4"     # blue
set -g @color5 "$color5"     # magenta
set -g @color6 "$color6"     # cyan
set -g @color7 "$color7"     # white
set -g @color8 "$color8"     # bright black (gray)
set -g @color9 "$color9"     # bright red
set -g @color10 "$color10"   # bright green
set -g @color11 "$color11"   # bright yellow
set -g @color12 "$color12"   # bright blue
set -g @color13 "$color13"   # bright magenta
set -g @color14 "$color14"   # bright cyan
set -g @color15 "$color15"   # bright white

# ============================================================================
# Semantic color aliases
# ============================================================================
set -g @theme_bg "${tmux_bg:-$color0}"
set -g @theme_fg "${tmux_fg:-$color15}"
set -g @theme_accent "${tmux_accent:-$color4}"
set -g @theme_gray "${tmux_gray:-$color8}"
set -g @theme_highlight "${tmux_highlight:-$color4}"
set -g @theme_red "${tmux_red:-$color1}"
set -g @theme_brightred "${tmux_brightred:-$color9}"
set -g @theme_green "${tmux_green:-$color2}"
set -g @theme_yellow "${tmux_yellow:-$color3}"
set -g @theme_blue "${tmux_blue:-$color4}"
set -g @theme_magenta "${tmux_magenta:-$color5}"
set -g @theme_cyan "${tmux_cyan:-$color6}"

# ============================================================================
# Tmux color settings
# ============================================================================
set -g status-style "bg=${tmux_bg:-$color0},fg=${tmux_fg:-$color15}"
set -g message-style "bg=${tmux_bg:-$color0},fg=${tmux_accent:-$color4}"
set -g message-command-style "bg=${tmux_bg:-$color0},fg=${tmux_accent:-$color4}"
set -g pane-border-style "fg=${tmux_gray:-$color8}"
set -g pane-active-border-style "fg=${tmux_accent:-$color4}"
set -g mode-style "bg=${tmux_accent:-$color4},fg=${tmux_bg:-$color0}"
set -g window-status-style "fg=${tmux_gray:-$color8}"
set -g window-status-current-style "fg=${tmux_accent:-$color4},bold"
set -g clock-mode-colour "${tmux_accent:-$color4}"
EOF

# Generate status.tmux.conf
cat > "${WAL_CACHE}/status.tmux.conf" << 'EOF'
# --- pane-border configuration ------------------------------------------------
setw -g pane-border-status top
setw -g pane-border-format "#(sleep 0.5; tmux-icons $(ps -t #{pane_tty} -o args= | head -n 2))"

set -g pane-border-indicators colour
setw -g pane-border-lines single

setw -g window-status-activity-style none
setw -g window-status-separator ""

# -- popup style ---------------------------------------------------------------
set -g popup-style "bg=default"
set -g popup-border-style "fg=default,bg=default"
set -g popup-border-lines "padded"

# -- status layout -------------------------------------------------------------
set -g status-left "#[bold]#[fg=default,bg=#{@theme_gray}]#{tmux_mode_indicator}#[default]"
set -g status-left-length 500

setw -g window-status-current-format "#[italics,bold]#[fg=#{@theme_accent},bg=terminal]  #I:#W#(echo #{window_panes} | sed 's/0/⁰/g;s/1/¹/g;s/2/²/g;s/3/³/g;s/4/⁴/g;s/5/⁵/g;s/6/⁶/g;s/7/⁷/g;s/8/⁸/g;s/9/⁹/g')#[default]#{?window_bell_flag,#[fg=#{@theme_red}] 󰂞#[default],}#{?window_zoomed_flag,#[fg=#{@theme_red}]#($HOME/.local/bin/tmux-fancy-numbers\ #P)#[default],}"
setw -g window-status-format "  #I:#W#(echo #{window_panes} | sed 's/0/⁰/g;s/1/¹/g;s/2/²/g;s/3/³/g;s/4/⁴/g;s/5/⁵/g;s/6/⁶/g;s/7/⁷/g;s/8/⁸/g;s/9/⁹/g')#{?window_bell_flag,#[fg=#{@theme_red}] 󰂞#[default],}#{?window_zoomed_flag,#[fg=#{@theme_red}]#($HOME/.local/bin/tmux-fancy-numbers\ #P)#[default],}"

set -g status-right "#{?#{!=:#{battery_percentage},0},#[nobold,fg=#{battery_color_fg}]#{battery_icon} #{battery_percentage}#[default],} #[fg=#{@theme_gray}]#($XDG_CONFIG_HOME/tmux/scripts/tmux-player)#[default] #[bold]#{pomodoro_status}#[default] #[fg=#{@theme_accent}]⋮#[default] #[bold]#{cpu_fg_color}#{cpu_percentage}#[default] #[bold]#{ram_fg_color}#{ram_icon}#[default] "
set -g status-right-length 200
EOF

# Save hash for next run
echo "$input_hash" > "$hashFile"

echo "[tmux] Generated tmux color configs"

# Reload tmux if running
if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null; then
  tmux source-file "${TMUX_CONFIG}" 2>/dev/null && echo "[tmux] Reloaded tmux config"
fi

#!/bin/bash

MODE_INDICATOR=$(tmux display-message -p "#[fg=$thm_fg,bg=$thm_bg_alt]#{tmux_mode_indicator} ")
POMODORO_STATUS=$(tmux display-message -p "#[bold]#{pomodoro_status}")
STATUS_SEP=$(tmux display-message -p "#[fg=$thm_bg_green,bg=terminal] ⋮#[fg=default,bg=default]")
TIME=$(tmux display-message -p "#[fg=$thm_inactive_fg]%H:%M#[default]")

echo "$MODE_INDICATOR $TIME $STATUS_SEP $POMODORO_STATUS"

typeset -gr _TMUX_DEV_DUAL_TARGET_EDITOR_WIDTH_PCT_DEFAULT=33
typeset -gr _TMUX_DEV_DUAL_MIN_EDITOR_WIDTH_DEFAULT=40
typeset -gr _TMUX_DEV_DUAL_MIN_AGENT_WIDTH_DEFAULT=47
typeset -gr _TMUX_DEV_DUAL_SEPARATOR_COUNT_DEFAULT=2
typeset -gr _TMUX_DEV_TWO_AGENT_SEPARATOR_COUNT_DEFAULT=1
typeset -gr _TMUX_DEV_SINGLE_AGENT_RIGHT_WIDTH_PCT_DEFAULT=40
typeset -gr _TMUX_DEV_SINGLE_AGENT_MIN_SIDE_AGENT_WIDTH_DEFAULT=47
typeset -gr _TMUX_DEV_SINGLE_AGENT_SEPARATOR_COUNT_DEFAULT=1

_tmux_dev_dual_three_pane_agent_widths() {
  local total_width="$1"
  integer target_editor_width_pct min_editor_width min_agent_width separator_count
  integer usable_width target_editor_width remaining_width left_width right_width

  target_editor_width_pct="${TMUX_DEV_DUAL_TARGET_EDITOR_WIDTH_PCT:-$_TMUX_DEV_DUAL_TARGET_EDITOR_WIDTH_PCT_DEFAULT}"
  min_editor_width="${TMUX_DEV_DUAL_MIN_EDITOR_WIDTH:-$_TMUX_DEV_DUAL_MIN_EDITOR_WIDTH_DEFAULT}"
  min_agent_width="${TMUX_DEV_DUAL_MIN_AGENT_WIDTH:-$_TMUX_DEV_DUAL_MIN_AGENT_WIDTH_DEFAULT}"
  separator_count="${TMUX_DEV_DUAL_SEPARATOR_COUNT:-$_TMUX_DEV_DUAL_SEPARATOR_COUNT_DEFAULT}"

  ((usable_width = total_width - separator_count))
  ((usable_width < 1)) && return 1

  ((target_editor_width = (usable_width * target_editor_width_pct + 50) / 100))
  ((target_editor_width < min_editor_width)) && return 1
  ((remaining_width = usable_width - target_editor_width))
  ((remaining_width < (min_agent_width * 2))) && return 1

  ((left_width = remaining_width / 2))
  ((right_width = remaining_width - left_width))
  ((left_width < min_agent_width)) && return 1
  ((right_width < min_agent_width)) && return 1

  print -r -- "$left_width $right_width"
}

_tmux_dev_dual_supports_two_agents() {
  local total_width="$1"
  integer min_agent_width separator_count usable_width

  min_agent_width="${TMUX_DEV_DUAL_MIN_AGENT_WIDTH:-$_TMUX_DEV_DUAL_MIN_AGENT_WIDTH_DEFAULT}"
  separator_count="${TMUX_DEV_TWO_AGENT_SEPARATOR_COUNT:-$_TMUX_DEV_TWO_AGENT_SEPARATOR_COUNT_DEFAULT}"

  ((usable_width = total_width - separator_count))
  ((usable_width >= (min_agent_width * 2)))
}

_tmux_dev_single_agent_side_width() {
  local total_width="$1"
  integer right_width_pct min_agent_width separator_count usable_width side_width

  right_width_pct="${TMUX_DEV_SINGLE_AGENT_RIGHT_WIDTH_PCT:-$_TMUX_DEV_SINGLE_AGENT_RIGHT_WIDTH_PCT_DEFAULT}"
  min_agent_width="${TMUX_DEV_SINGLE_AGENT_MIN_SIDE_AGENT_WIDTH:-$_TMUX_DEV_SINGLE_AGENT_MIN_SIDE_AGENT_WIDTH_DEFAULT}"
  separator_count="${TMUX_DEV_SINGLE_AGENT_SEPARATOR_COUNT:-$_TMUX_DEV_SINGLE_AGENT_SEPARATOR_COUNT_DEFAULT}"

  ((usable_width = total_width - separator_count))
  ((usable_width < 1)) && return 1

  ((side_width = (usable_width * right_width_pct + 50) / 100))
  ((side_width < min_agent_width)) && return 1

  print -r -- "$side_width"
}

IDLE_WINDOW_COVER_TOLERANCE_PX=2

idle_window_activity() {
  command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 1
  hyprctl --batch -j 'clients;monitors' 2>/dev/null | jq -rse --argjson tolerance "${IDLE_WINDOW_COVER_TOLERANCE_PX}" '
    (.[0] // []) as $clients | (.[1] // []) as $monitors |
    def visible($c): any($monitors[]?;
      .activeWorkspace.id == $c.workspace.id
      or ((.specialWorkspace.id // 0) != 0 and .specialWorkspace.id == $c.workspace.id));
    def covers($c): any($monitors[]?;
      .id == $c.monitor
      and (($c.at[0] - .x) | fabs) <= $tolerance and (($c.at[1] - .y) | fabs) <= $tolerance
      and $c.size[0] >= ((if ((.transform // 0) % 2) == 1 then .height else .width end) / (.scale // 1)) - $tolerance
      and $c.size[1] >= ((if ((.transform // 0) % 2) == 1 then .width else .height end) / (.scale // 1)) - $tolerance);
    [any($monitors[]?; .fullscreenClient != null),
     any($clients[]?; . as $c | $c.mapped == true and ($c.hidden | not)
       and (($c.fullscreen // 0) == 0) and visible($c)
       and ((($c.class // "") | test("^steam_app_[0-9]+$")) or covers($c)))]
    | map(if . then 1 else 0 end) | @tsv'
}

idle_audio_is_playing() {
  command -v playerctl >/dev/null 2>&1 || return 1
  local statuses
  statuses=$'\n'"$(playerctl -a status 2>/dev/null)"$'\n'
  [[ "${statuses}" == *$'\nPlaying\n'* ]]
}

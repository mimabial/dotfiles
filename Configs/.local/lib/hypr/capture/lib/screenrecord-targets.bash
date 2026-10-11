screenrecord_monitors_json() {
  hyprctl monitors -j 2>/dev/null || printf '[]\n'
}

screenrecord_focused_monitor_value() {
  local jq_filter="$1"

  screenrecord_monitors_json \
    | jq -r "first(.[] | select(.focused == true) | ${jq_filter}) // empty"
}

screenrecord_default_resolution() {
  local width height
  read -r width height < <(screenrecord_focused_monitor_value '"\(.width) \(.height)"')
  width="${width:-0}"
  height="${height:-0}"
  if ((width > RECORD_MAX_WIDTH || height > RECORD_MAX_HEIGHT)); then
    echo "${RECORD_MAX_WIDTH}x${RECORD_MAX_HEIGHT}"
  else
    echo "0x0"
  fi
}

active_workspace_window_rectangles() {
  hyprctl --batch -j "activeworkspace;clients" \
    | jq -sr '
        .[0].id as $ws
        | (.[1] // [])[]
        | select(.workspace.id == $ws and .mapped and (.hidden | not))
        | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"
      '
}

select_window_rectangle() {
  local result_file
  result_file=$(mktemp)
  trap 'rm -f "$result_file"' RETURN

  while true; do
    active_workspace_window_rectangles | slurp 2>/dev/null >"$result_file" &
    local slurp_pid=$!

    nc -U "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" 2>/dev/null |
      while IFS= read -r event; do
        [[ "$event" == workspace\>\>* ]] && kill "$slurp_pid" 2>/dev/null && break
      done &
    local watch_pid=$!

    wait "$slurp_pid" 2>/dev/null
    local exit_code=$?
    kill "$watch_pid" 2>/dev/null
    wait "$watch_pid" 2>/dev/null

    local geom
    geom=$(<"$result_file")

    if [[ -n "$geom" ]]; then
      echo "$geom"
      return 0
    fi

    [[ $exit_code -eq $SLURP_EXIT_CANCELLED ]] && return 1
  done
}

screenrecord_audio_args() {
  local -n audio_args_ref="$1"
  local audio_devices=""

  audio_args_ref=()
  [[ "$DESKTOP_AUDIO" == true ]] && audio_devices+="default_output"
  if [[ "$MICROPHONE_AUDIO" == true ]]; then
    [[ -n "$audio_devices" ]] && audio_devices+="|"
    audio_devices+="default_input"
  fi
  # shellcheck disable=SC2034 # nameref output assigned for caller.
  [[ -n "$audio_devices" ]] && audio_args_ref=(-a "$audio_devices" -ac aac)
}

screenrecord_target_args() {
  local out_args_name="$1"
  local target="$2"
  local resolution="$3"
  shift 3
  local -n out_args_ref="${out_args_name}"

  # shellcheck disable=SC2034 # nameref output assigned for caller.
  out_args_ref=(-w "$target" "$@" -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)
}

screenrecord_formatted_region() {
  awk '{split($1,pos,","); print $2"+"pos[1]"+"pos[2]}'
}

screenrecord_bypasses_portal() {
  [[ "$USE_REGION" == true || "$USE_SMART" == true || "$USE_OUTPUT" == true || "$USE_WINDOW" == true ]]
}

screenrecord_maybe_force_display_gpu() {
  screenrecord_bypasses_portal || return 0
  [[ -z "$(gpu-screen-recorder --list-monitors 2>/dev/null)" ]] || return 0

  local output_name card mesa_vendor
  output_name="$(screenrecord_focused_monitor_value '.name')"
  for card in /dev/dri/card*; do
    [[ -e "$card" ]] || continue
    if gpu-screen-recorder --list-capture-options "$card" 2>/dev/null | grep -q "$output_name"; then
      mesa_vendor="$(find /usr/share/glvnd/egl_vendor.d/ -name '*mesa*' 2>/dev/null | head -1)"
      [[ -f "$mesa_vendor" ]] && export __EGL_VENDOR_LIBRARY_FILENAMES="$mesa_vendor"
      return 0
    fi
  done
}

screenrecord_window_args() {
  local out_args_name="$1"
  local resolution="$2"
  local win_geom=""
  local win_formatted=""

  win_geom=$(select_window_rectangle) || {
    screenrecord_notify "Window selection cancelled"
    return 1
  }
  win_formatted=$(screenrecord_formatted_region <<<"$win_geom")
  screenrecord_target_args "${out_args_name}" "region" "$resolution" -region "$win_formatted"
}

screenrecord_region_args() {
  local out_args_name="$1"
  local resolution="$2"
  local region=""
  local region_formatted=""

  region=$(slurp 2>/dev/null) || {
    screenrecord_notify "Region selection cancelled"
    return 1
  }
  region_formatted=$(screenrecord_formatted_region <<<"$region")
  screenrecord_target_args "${out_args_name}" "region" "$resolution" -region "$region_formatted"
}

screenrecord_smart_args() {
  local out_args_name="$1"
  local resolution="$2"
  local region=""
  local region_formatted=""

  region="$(capture_smart_select)" || {
    screenrecord_notify "Region selection cancelled"
    return 1
  }
  region_formatted=$(screenrecord_formatted_region <<<"$region")
  screenrecord_target_args "${out_args_name}" "region" "$resolution" -region "$region_formatted"
}

screenrecord_output_args() {
  local out_args_name="$1"
  local resolution="$2"
  local output=""

  output="$(screenrecord_focused_monitor_value '.name')"
  [[ -n "$output" ]] || return 0
  screenrecord_target_args "${out_args_name}" "$output" "$resolution"
}

screenrecord_capture_args() {
  local out_args_name="$1"
  local resolution="$2"

  screenrecord_target_args "${out_args_name}" "portal" "$resolution"
  if [[ "$USE_WINDOW" == true ]]; then
    screenrecord_window_args "${out_args_name}" "$resolution"
  elif [[ "$USE_SMART" == true ]]; then
    screenrecord_smart_args "${out_args_name}" "$resolution"
  elif [[ "$USE_REGION" == true ]]; then
    screenrecord_region_args "${out_args_name}" "$resolution"
  elif [[ "$USE_OUTPUT" == true ]]; then
    screenrecord_output_args "${out_args_name}" "$resolution"
  fi
}

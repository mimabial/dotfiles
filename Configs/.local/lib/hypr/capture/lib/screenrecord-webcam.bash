screenrecord_webcam_device() {
  local device="${WEBCAM_DEVICE}"
  if [[ -n "$device" ]]; then
    printf '%s\n' "$device"
    return 0
  fi

  device=$(v4l2-ctl --list-devices 2>/dev/null | grep -m1 "^[[:space:]]*/dev/video" | tr -d '\t')
  if [[ -z "$device" ]]; then
    screenrecord_notify "No webcam devices found" "" "camera-web" "critical"
    return 1
  fi

  printf '%s\n' "$device"
}

screenrecord_webcam_target_width() {
  local scale
  scale="$(screenrecord_focused_monitor_value '.scale')"
  [[ "${scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] || scale=1
  awk "BEGIN {printf \"%.0f\", ${WEBCAM_OVERLAY_WIDTH} * $scale}"
}

screenrecord_webcam_video_size_arg() {
  local device="$1"
  local preferred_resolutions=("640x360" "1280x720" "1920x1080")
  local video_size_arg=""
  local available_formats
  available_formats=$(v4l2-ctl --list-formats-ext -d "$device" 2>/dev/null)

  for resolution in "${preferred_resolutions[@]}"; do
    if grep -q "$resolution" <<<"$available_formats"; then
      video_size_arg="-video_size $resolution"
      break
    fi
  done

  printf '%s\n' "${video_size_arg}"
}

start_webcam_overlay() {
  cleanup_webcam

  local device=""
  local target_width=""
  local video_size_arg=""
  device="$(screenrecord_webcam_device)" || return 1
  target_width="$(screenrecord_webcam_target_width)"
  video_size_arg="$(screenrecord_webcam_video_size_arg "$device")"

  # shellcheck disable=SC2086
  ffplay -f v4l2 $video_size_arg -framerate 30 "$device" \
    -vf "crop=iw/2:ih,scale=${target_width}:-1" \
    -window_title "WebcamOverlay" \
    -noborder \
    -fflags nobuffer -flags low_delay \
    -probesize 32 -analyzeduration 0 \
    -loglevel quiet &
}

cleanup_webcam() {
  screenrecord_signal_matching TERM -f "WebcamOverlay"
}

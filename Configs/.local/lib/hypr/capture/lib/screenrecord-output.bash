screenrecord_notify() {
  local summary="$1"
  local body="${2:-}"
  local icon="${3:-media-record}"
  local urgency="${4:-normal}"
  local timeout="${5:-${NOTIFY_MS}}"
  local stack_tag="${6:-}"
  local args=(-a "Screen Recorder" -i "$icon" -u "$urgency" -t "$timeout")

  [[ -n "$stack_tag" ]] && args+=(-h "string:x-dunst-stack-tag:${stack_tag}")

  if [[ -n "$body" ]]; then
    dunstify "${args[@]}" "$summary" "$body"
  else
    dunstify "${args[@]}" "$summary"
  fi
}

screenrecord_action_notify() {
  local summary="$1"
  local body="$2"
  local icon="$3"

  dunstify -a "Screen Recorder" -i "$icon" -t "${RECORDING_SAVED_NOTIFY_MS}" "$summary" "$body" -A "default,open"
}

trim_recording_start() {
  local latest="$1"
  local trimmed="${latest%.mp4}-trimmed.mp4"

  if ffmpeg -y -ss "${RECORDING_START_TRIM_SECONDS}" -i "$latest" -c copy "$trimmed" -loglevel quiet 2>/dev/null; then
    mv "$trimmed" "$latest"
  else
    rm -f "$trimmed"
  fi
}

notify_recording_saved() {
  local filename="$1"
  local preview="${filename%.mp4}-preview.png"
  local action=""

  ffmpeg -y -i "$filename" -ss "${RECORDING_PREVIEW_FRAME_SECONDS}" -vframes 1 -q:v 2 "$preview" -loglevel quiet 2>/dev/null

  action=$(screenrecord_action_notify "Recording saved" "Click to open" "${preview:-$filename}")
  [[ "$action" == "default" ]] && mpv "$filename"
  rm -f "$preview"
}

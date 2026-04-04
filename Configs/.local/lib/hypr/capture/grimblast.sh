#!/usr/bin/env bash
## Grimblast: a helper for screenshots within hyprland
## Requirements:
##  - `grim`: screenshot utility for wayland
##  - `slurp`: to select an area
##  - `hyprctl`: to read properties of current window (provided by Hyprland)
##  - `hyprpicker`: to freeze the screen when selecting area
##  - `wl-copy`: clipboard utility (provided by wl-clipboard)
##  - `jq`: json utility to parse hyprctl output
##  - `dunstify`: to show notifications (provided by dunst)
## Those are needed to be installed, if unsure, run `grimblast check`
##
## See `man 1 grimblast` or `grimblast usage` for further details.

## Author: Misterio (https://github.com/misterio77)

## This tool is based on grimshot, with swaymsg commands replaced by their
## hyprctl equivalents.
## https://github.com/swaywm/sway/blob/master/contrib/grimshot

# Check whether another instance is running
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
runtime_dir="${XDG_RUNTIME_DIR:-$cache_home}"
mkdir -p "${runtime_dir}"
grimblast_lock_dir="${runtime_dir}/grimblast.lock"
if ! mkdir "${grimblast_lock_dir}" 2>/dev/null; then
  exit 2
fi
grimblast_release_lockfile() {
  local exit_code="${1:-$?}"
  rmdir "${grimblast_lock_dir}" 2>/dev/null || true
  return "${exit_code}"
}
trap 'grimblast_release_lockfile "$?"' EXIT

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/capture/capture.select.bash"

get_target_directory() {
  [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]] &&
    . "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"

  echo "${XDG_SCREENSHOTS_DIR:-${XDG_PICTURES_DIR:-$HOME}}"
}

tmp_editor_directory() {
  printf '%s\n' "${TMPDIR:-/tmp}"
}

ensure_editor() {
  : "${GRIMBLAST_EDITOR:=gimp}"
}

NOTIFY=no
OPENFILE_NOTIFICATION=no
CURSOR=
FREEZE=
WAIT=no
SCALE=
CUSTOM_GEOM=

# Store positional arguments
pos=()

while [[ $# -gt 0 ]]; do
  case $1 in
  -n | --notify)
    NOTIFY=yes
    shift
    ;;
  -o | --openfile)
    OPENFILE_NOTIFICATION=yes
    shift
    ;;
  -c | --cursor)
    CURSOR=yes
    shift
    ;;
  -f | --freeze)
    FREEZE=yes
    shift
    ;;
  -w | --wait)
    if [[ -n "${2-}" && "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      WAIT=$2
      shift 2
    else
      echo "Invalid or missing value for --wait" >&2
      exit 3
    fi
    ;;
  -s | --scale)
    if [[ -n "${2-}" && "$2" =~ ^[1-9][0-9]*(\.[0-9]+)?$ ]]; then
      SCALE=$2 # assign the next argument to SCALE
      shift 2
    else
      echo "Invalid or missing argument for --scale" >&2
      exit 1
    fi
    ;;
  -g | --geometry)
    if [[ -n "${2-}" ]]; then
      CUSTOM_GEOM="$2"
      shift 2
    else
      echo "Invalid or missing argument for --geometry" >&2
      exit 1
    fi
    ;;
  --)
    shift
    pos+=("$@")
    break
    ;;
  -)
    pos+=("$1")
    shift
    break
    ;;
  -*)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
  *)
    pos+=("$1")
    shift
    ;;
  esac
done

set -- "${pos[@]:-}"

ACTION=${1:-usage}
SUBJECT=${2:-screen}
FILE=${3:-$(get_target_directory)/$(date -Ins).png}
FILE_EDITOR=${3:-$(tmp_editor_directory)/$(date -Ins).png}

grimblast_usage() {
  cat <<'EOF'
Usage:
  grimblast [--notify] [--openfile] [--cursor] [--freeze] [--wait N] [--scale <scale>] [--geometry "X,Y WxH"] (copy|save|copysave|edit) [active|screen|output|area] [FILE|-]
  grimblast check
  grimblast usage

Commands:
  copy: Copy the screenshot data into the clipboard.
  save: Save the screenshot to a regular file or '-' to pipe to STDOUT.
  copysave: Combine the previous 2 options.
  edit: Open screenshot in the image editor of your choice (default is gimp). See man page for info.
  check: Verify if required tools are installed and exit.
  usage: Show this message and exit.

Targets:
  active: Currently active window.
  screen: All visible outputs.
  output: Currently active output.
  area: Manually select a region or window.
EOF
}

case "${ACTION}" in
  save | copy | edit | copysave | check | usage) ;;
  *)
    grimblast_usage
    exit 0
    ;;
esac

if [[ "${ACTION}" == "usage" ]]; then
  grimblast_usage
  exit 0
fi

notify() {
  dunstify -t 3000 -a grimblast "$@"
}

notify_ok() {
  [[ "$NOTIFY" == "no" ]] && return

  notify "$@"
}

notify_open() {
  local action=""

  if [[ "$OPENFILE_NOTIFICATION" == "no" ]]; then
    notify_ok "$@"
  else
    action=$(notify_ok -A "default=open_folder" "$@")
    if [[ "$action" == "default" ]]; then
      # this does not work for filenames with commas in them
      if dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:"file://$4" string:""; then
        :
      else
        dunstify -t 3000 -a grimblast -i "dialog-error" "Error displaying folder with dbus-send"
        echo "Displayed: Error displaying folder with dbus-send"
      fi
    fi
  fi
}

notify_error() {
  local message="${1:-Error taking screenshot with grim}"
  local title="${2:-Screenshot}"

  if [[ $NOTIFY == "yes" ]]; then
    notify -u critical "${title}" "${message}"
  else
    printf '%s\n' "${message}"
  fi
}

kill_hyprpicker() {
  if pidof hyprpicker >/dev/null; then
    pkill hyprpicker
  fi
}

die() {
  local message="${1:-Bye}"

  kill_hyprpicker
  notify_error "Error: ${message}"
  exit 2
}

check_required_command() {
  local command_name="$1"
  local result="NOT FOUND"

  if command -v "${command_name}" >/dev/null 2>&1; then
    result="OK"
  fi
  printf '   %s: %s\n' "${command_name}" "${result}"
}

take_screenshot() {
  local target_file="$1"
  local geometry="$2"
  local output_name="$3"

  if [[ -n "${output_name}" ]]; then
    grim ${CURSOR:+-c} ${SCALE:+-s "$SCALE"} -o "${output_name}" "${target_file}" || die "Unable to invoke grim"
  elif [[ -z "${geometry}" ]]; then
    grim ${CURSOR:+-c} ${SCALE:+-s "$SCALE"} "${target_file}" || die "Unable to invoke grim"
  else
    if ! grim ${CURSOR:+-c} ${SCALE:+-s "$SCALE"} -g "${geometry}" "${target_file}"; then
      die "Unable to invoke grim"
    fi
  fi
}

wait_delay() {
  if [[ "$WAIT" != "no" ]]; then
    sleep "$WAIT"
  fi
}

if [[ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
  echo "Error: HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)"
  exit 1
fi

if [[ "$ACTION" == "check" ]]; then
  echo "Checking if required tools are installed. If something is missing, install it to your system and make it available in PATH..."
  check_required_command grim
  check_required_command slurp
  check_required_command hyprctl
  check_required_command hyprpicker
  check_required_command wl-copy
  check_required_command jq
  check_required_command dunstify
  exit
elif [[ "$SUBJECT" == "active" ]]; then
  wait_delay
  FOCUSED=$(hyprctl activewindow -j)
  GEOM=$(echo "$FOCUSED" | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
  APP_ID=$(echo "$FOCUSED" | jq -r '.class')
  WHAT="$APP_ID window"
elif [[ "$SUBJECT" == "screen" ]]; then
  wait_delay
  GEOM=""
  WHAT="Screen"
elif [[ "$SUBJECT" == "output" ]]; then
  wait_delay
  GEOM=""
  OUTPUT=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')
  WHAT="$OUTPUT"
elif [[ "$SUBJECT" == "area" ]]; then
  if [[ "$CURSOR" == "yes" ]]; then
    die "Error: '--cursor' cannot be used with subject 'area'"
  fi

  if [[ -n "$CUSTOM_GEOM" ]]; then
    GEOM="$CUSTOM_GEOM"
  else
    if [[ "$FREEZE" == "yes" ]] && command -v "hyprpicker" >/dev/null 2>&1; then
      FREEZE_PID="$(capture_start_freeze 0.2)"
    fi

    # disable animation for layer namespace "selection" (slurp)
    # this removes the black border seen around screenshots
    hyprctl keyword layerrule "noanim,selection" >/dev/null

    # convert SLURP_ARGS to a bash array
    IFS=' ' read -r -a _slurp_args <<<"$SLURP_ARGS"
    # shellcheck disable=2086 # if we don't split, spaces mess up slurp
    GEOM=$(capture_visible_workspace_rectangles | slurp "${_slurp_args[@]}")
    capture_stop_freeze "${FREEZE_PID:-}"

    # Check if user exited slurp without selecting the area
    if [[ -z "$GEOM" ]]; then
      kill_hyprpicker
      exit 1
    fi
  fi
  WHAT="Area"
  wait_delay
elif [[ "$SUBJECT" == "window" ]]; then
  die "Subject 'window' is now included in 'area'"
else
  die "Unknown subject to take a screen shot from" "$SUBJECT"
fi

if [[ "$ACTION" == "copy" ]]; then
  take_screenshot - "$GEOM" "$OUTPUT" | wl-copy --type image/png || die "Clipboard error"
  notify_ok "$WHAT copied to buffer"
elif [[ "$ACTION" == "save" ]]; then
  if take_screenshot "$FILE" "$GEOM" "$OUTPUT"; then
    TITLE="Screenshot of $SUBJECT"
    MESSAGE=$(basename "$FILE")
    kill_hyprpicker
    notify_open "$TITLE" "$MESSAGE" -i "$FILE"
    echo "$FILE"
  else
    notify_error "Error taking screenshot with grim"
  fi
elif [[ "$ACTION" == "edit" ]]; then
  ensure_editor
  if take_screenshot "$FILE_EDITOR" "$GEOM" "$OUTPUT"; then
    TITLE="Screenshot of $SUBJECT"
    MESSAGE="Open screenshot in image editor"
    notify_ok "$TITLE" "$MESSAGE" -i "$FILE_EDITOR"
    $GRIMBLAST_EDITOR "$FILE_EDITOR"
    echo "$FILE_EDITOR"
  else
    notify_error "Error taking screenshot"
  fi
else
  if [[ "$ACTION" == "copysave" ]]; then
    take_screenshot - "$GEOM" "$OUTPUT" | tee "$FILE" | wl-copy --type image/png || die "Clipboard error"
    notify_ok "$WHAT copied to buffer and saved to $FILE" -i "$FILE"
    echo "$FILE"
  else
    notify_error "Error taking screenshot with grim"
  fi
fi

kill_hyprpicker

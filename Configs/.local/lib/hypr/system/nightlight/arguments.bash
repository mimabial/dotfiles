nightlight_show_help() {
  cat <<EOF
Usage: hyprshell system/hyprsunset [OPTIONS]

Options:
    --cm MODE                   Color mode: 'temp' for temperature, 'gamma' for gamma
    -i, --increase[=STEP]       Increase the selected color mode value (-i500 or --increase=500)
    -d, --decrease[=STEP]       Decrease the selected color mode value (-d500 or --decrease=500)
    -s, --set VALUE             Set specific value for the selected color mode
    -r, --read                  Read current screen temperature and gamma
    -t, --toggle                Toggle hyprsunset (on/off)
    -q, --quiet                 Disable notifications
    -P, --sigproc PROC,SIGNAL   Send signal to a process (for example: process,10)
    -h, --help                  Show this help message

Examples:
    hyprshell system/hyprsunset -r                     # Read current values
    hyprshell system/hyprsunset --cm temp -i           # Increase temperature by 500K
    hyprshell system/hyprsunset --cm temp --decrease=1000  # Decrease temperature by 1000K
    hyprshell system/hyprsunset --cm temp -s 4000      # Set temperature to 4000K
    hyprshell system/hyprsunset --cm gamma -i          # Increase gamma by 5
    hyprshell system/hyprsunset --cm gamma -d10        # Decrease gamma by 10
    hyprshell system/hyprsunset --cm gamma -s 80       # Set gamma to 80
    hyprshell system/hyprsunset -t --quiet             # Toggle mode quietly
    hyprshell system/hyprsunset --sigproc process,10   # Send RTMIN+10 to a process
EOF
}

nightlight_parse_args() {
  local -n options_ref="$1"
  shift
  local longopts="cm:,increase::,decrease::,set:,read,toggle,quiet,sigproc:,help"
  local shortopts="i::d::s:rtqP:h"
  local parsed=""

  parsed=$(getopt --options "${shortopts}" --longoptions "${longopts}" --name "$0" -- "$@") || return 2
  eval set -- "${parsed}"

  while true; do
    case "$1" in
      --cm) options_ref[color_mode]="$2"; shift 2 ;;
      -i|--increase) options_ref[action]="increase"; options_ref[custom_step]="$2"; shift 2 ;;
      -d|--decrease) options_ref[action]="decrease"; options_ref[custom_step]="$2"; shift 2 ;;
      -s|--set) options_ref[action]="set"; options_ref[custom_step]="$2"; shift 2 ;;
      -r|--read) options_ref[action]="read"; shift ;;
      -t|--toggle) options_ref[action]="toggle"; shift ;;
      -q|--quiet) options_ref[notify]=false; shift ;;
      -P|--sigproc) options_ref[signal_proc]="$2"; shift 2 ;;
      -h|--help) options_ref[help]=true; shift ;;
      --)
        shift
        (($# == 0)) || { echo "Unexpected argument: $1 (attach a step: -d1000 or --decrease=1000)" >&2; return 2; }
        return 0
        ;;
      *) echo "Invalid option: $1" >&2; return 1 ;;
    esac
  done
}

nightlight_validate_color_mode() {
  case "$1" in
    temp|gamma) return 0 ;;
    *)
      echo "Error: Color mode must be 'temp' or 'gamma'"
      return 1
      ;;
  esac
}

nightlight_parse_signal_target() {
  local raw="$1"
  local -n process_ref="$2"
  local -n signal_ref="$3"

  case "${raw}" in
    *,*) IFS=',' read -r process_ref signal_ref <<<"${raw}" ;;
    *:*) IFS=':' read -r process_ref signal_ref <<<"${raw}" ;;
    *)
      echo "Error: Invalid sigproc format. Use PROCESS,SIGNAL or PROCESS:SIGNAL"
      return 1
      ;;
  esac

  if ! [[ "${signal_ref}" =~ ^[0-9]+$ ]]; then
    echo "Error: Signal must be a number"
    return 1
  fi
}

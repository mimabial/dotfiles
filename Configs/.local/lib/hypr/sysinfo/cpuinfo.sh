#!/bin/bash

#  Benchmark 1: cpuinfo.sh
#   Time (mean ± σ):     159.4 ms ±  26.1 ms    [User: 38.6 ms, System: 62.2 ms]
#   Range (min … max):    99.8 ms … 182.7 ms    17 runs

# Parse arguments
OUTPUT_MODE="all"
while [[ $# -gt 0 ]]; do
  case $1 in
    -i | --icon)
      OUTPUT_MODE="icon"
      shift
      ;;
    -u | --util)
      OUTPUT_MODE="util"
      shift
      ;;
    -t | --temp)
      OUTPUT_MODE="temp"
      shift
      ;;
    -a | --all)
      OUTPUT_MODE="all"
      shift
      ;;
    *) shift ;;
  esac
done

cpuinfo_file="/tmp/${UID}-processors"
cache_file="/tmp/cpuinfo-cache-${UID}.json"

# -i and -u read from cache if it exists
if [[ "$OUTPUT_MODE" != "all" && -f "$cache_file" ]]; then
  case $OUTPUT_MODE in
    "icon")
      jq -c '{text: .icon, tooltip: .tooltip}' "$cache_file"
      exit 0
      ;;
    "util")
      jq -c '{text: .util, tooltip: .tooltip}' "$cache_file"
      exit 0
      ;;
    "temp")
      jq -c '{text: .temp, tooltip: .tooltip}' "$cache_file"
      exit 0
      ;;
  esac
fi

map_floor() {
  IFS=', ' read -r -a pairs <<<"$1"
  if [[ ${pairs[-1]} != *":"* ]]; then
    def_val="${pairs[-1]}"
    unset 'pairs[${#pairs[@]}-1]'
  fi
  for pair in "${pairs[@]}"; do
    IFS=':' read -r key value <<<"$pair"
    num="${2%%.*}"
    if [[ "$num" =~ ^-?[0-9]+$ && "$key" =~ ^-?[0-9]+$ ]]; then
      if ((num > key)); then
        echo "$value"
        return
      fi
    elif [[ -n "$num" && -n "$key" && "$num" > "$key" ]]; then
      echo "$value"
      return
    fi
  done
  [ -n "$def_val" ] && echo $def_val || echo " "
}

init_query() {
  cpu_info_file="/tmp/${UID}-processors"
  [[ -f "${cpu_info_file}" ]] && source "${cpu_info_file}"

  if [[ -z "$CPUINFO_MODEL" ]]; then
    CPUINFO_MODEL=$(lscpu | awk -F': ' '/Model name/ {gsub(/^ *| *$| CPU.*/,"",$2); print $2}')
    echo "CPUINFO_MODEL=\"$CPUINFO_MODEL\"" >>"${cpu_info_file}"
  fi
  if [[ -z "$CPUINFO_MAX_FREQ" ]]; then
    CPUINFO_MAX_FREQ=$(lscpu | awk '/CPU max MHz/ { sub(/\..*/,"",$4); print $4}')
    echo "CPUINFO_MAX_FREQ=\"$CPUINFO_MAX_FREQ\"" >>"${cpu_info_file}"
  fi

  statFile=$(head -1 /proc/stat)
  if [[ -z "$CPUINFO_PREV_STAT" ]]; then
    CPUINFO_PREV_STAT=$(awk '{print $2+$3+$4+$6+$7+$8 }' <<<"$statFile")
    echo "CPUINFO_PREV_STAT=\"$CPUINFO_PREV_STAT\"" >>"${cpu_info_file}"
  fi
  if [[ -z "$CPUINFO_PREV_IDLE" ]]; then
    CPUINFO_PREV_IDLE=$(awk '{print $5 }' <<<"$statFile")
    echo "CPUINFO_PREV_IDLE=\"$CPUINFO_PREV_IDLE\"" >>"${cpu_info_file}"
  fi
}

get_temp_color() {
  local temp=$1
  declare -A temp_colors=(
    [90]="#8b0000" [85]="#ad1f2f" [80]="#d22f2f" [75]="#ff471a"
    [70]="#ff6347" [65]="#ff8c00" [60]="#ffa500" [45]=""
    [40]="#add8e6" [35]="#87ceeb" [30]="#4682b4" [25]="#4169e1"
    [20]="#0000ff" [0]="#00008b"
  )
  for threshold in $(echo "${!temp_colors[@]}" | tr ' ' '\n' | sort -nr); do
    if ((temp >= threshold)); then
      echo "${temp_colors[$threshold]}"
      return
    fi
  done
}

get_utilization() {
  local statFile currStat currIdle diffStat diffIdle
  statFile=$(head -1 /proc/stat)
  currStat=$(awk '{print $2+$3+$4+$6+$7+$8 }' <<<"$statFile")
  currIdle=$(awk '{print $5 }' <<<"$statFile")
  diffStat=$((currStat - CPUINFO_PREV_STAT))
  diffIdle=$((currIdle - CPUINFO_PREV_IDLE))

  CPUINFO_PREV_STAT=$currStat
  CPUINFO_PREV_IDLE=$currIdle

  sed -i -e "/^CPUINFO_PREV_STAT=/c\CPUINFO_PREV_STAT=\"$currStat\"" -e "/^CPUINFO_PREV_IDLE=/c\CPUINFO_PREV_IDLE=\"$currIdle\"" "$cpuinfo_file" || {
    echo "CPUINFO_PREV_STAT=\"$currStat\"" >>"$cpuinfo_file"
    echo "CPUINFO_PREV_IDLE=\"$currIdle\"" >>"$cpuinfo_file"
  }

  awk -v stat="$diffStat" -v idle="$diffIdle" 'BEGIN {printf "%.0f", (stat/(stat+idle))*100}'
}

# shellcheck disable=SC1090
source "${cpuinfo_file}"
init_query

if [[ $CPUINFO_EMOJI -ne 1 ]]; then
  temp_lv="85:, 65:,, 45:, "
else
  temp_lv="85:🌋, 65:🔥, 45:☁️, ❄️"
fi
util_lv="90:, 60:󰓅, 30:󰾅, 󰾆"

sensors_json=$(sensors -j 2>/dev/null)

cpu_temps="$(jq -r '[.["coretemp-isa-0000"], .["k10temp-pci-00c3"]] | map(select(. != null)) | map(to_entries) | add | map(select(.value | objects) | "\(.key): \((.value | to_entries[] | select(.key | test("temp[0-9]+_input")) | .value | floor))°C") | join(", ")' <<<"$sensors_json")"

if [ -n "${CPUINFO_TEMPERATURE_ID}" ]; then
  temperature=$(grep -oP "(?<=${CPUINFO_TEMPERATURE_ID}: )\d+" <<<"${cpu_temps}")
fi

if [[ -z "$temperature" ]]; then
  cpu_temp_line="${cpu_temps%%$'°C'*}"
  temperature="${cpu_temp_line#*: }"
fi

utilization=$(get_utilization)
frequency=$(perl -ne 'BEGIN { $sum = 0; $count = 0 } if (/cpu MHz\s+:\s+([\d.]+)/) { $sum += $1; $count++ } END { if ($count > 0) { printf "%.2f\n", $sum / $count } else { print "NaN\n" } }' /proc/cpuinfo)

icons="$(map_floor "$util_lv" "$utilization")$(map_floor "$temp_lv" "$temperature")"
speedo="${icons:0:1}"
thermo="${icons:1:1}"
thermo_alt=󰻠 # better looking icon
emoji="${icons:2}"

# Build tooltip with newlines
tooltip="$emoji $CPUINFO_MODEL
$thermo Temperature: $cpu_temps
$speedo Utilization: $utilization%
  Clock Speed: $frequency/$CPUINFO_MAX_FREQ MHz"

color=$(get_temp_color "${temperature}")
if [[ -n "$color" ]]; then
  icon_text="<span size='14pt' color='$color'>$thermo_alt</span>"
else
  icon_text="<span size='14pt'>$thermo_alt</span>"
fi

# Write cache

# Format utilization with two digits for text display only
formatted_util=$(printf "%02d" "$utilization")

jq -n -c \
  --arg temp "${temperature}°C" \
  --arg icon "$icon_text" \
  --arg util "${formatted_util}󱉸" \
  --arg tooltip "$tooltip" \
  '{temp: $temp, icon: $icon, util: $util, tooltip: $tooltip}' >"$cache_file"

# Output
case $OUTPUT_MODE in
  "icon") jq -c '{text: .icon, tooltip: .tooltip}' "$cache_file" ;;
  "util") jq -c '{text: .util, tooltip: .tooltip}' "$cache_file" ;;
  "temp") jq -c '{text: .temp, tooltip: .tooltip}' "$cache_file" ;;
  *) jq -c --arg r $'\r' '{text: (.icon + $r + .util), tooltip: .tooltip}' "$cache_file" ;;
esac

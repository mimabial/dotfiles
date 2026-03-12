#!/bin/bash

#  Benchmark 1: cpuinfo.sh
#   Time (mean ± σ):     159.4 ms ±  26.1 ms    [User: 38.6 ms, System: 62.2 ms]
#   Range (min … max):    99.8 ms … 182.7 ms    17 runs

cpuinfo_file="${XDG_RUNTIME_DIR:-/tmp}/hypr-$UID-processors"

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

temp_lv="85:, 65:,, 45:, "
util_lv="90:, 60:󰓅, 30:󰾅, 󰾆"

sensors_json=$(sensors -j 2>/dev/null)
cpu_temps="$(perl -e '
use strict;
use warnings;
my $parser;
BEGIN {
    eval { require Cpanel::JSON::XS; $parser = Cpanel::JSON::XS->new->utf8; 1 }
      or eval { require JSON::XS; $parser = JSON::XS->new->utf8; 1 }
      or do { require JSON::PP; $parser = JSON::PP->new->utf8; };
}
my $json = do { local $/; <> };
my $data = eval { $parser->decode($json) } || {};
my @chips = ("coretemp-isa-0000","k10temp-pci-00c3","zenpower-pci-00c3");
my @lines;
for my $chip (@chips) {
    next unless exists $data->{$chip} && ref $data->{$chip} eq "HASH";
    my $entries = $data->{$chip};
    my @labels = keys %$entries;
    my (@packages, @others);
    for my $label (@labels) {
        if ($label =~ /^Package id\s+(\d+)/i) {
            push @packages, [$1, $label];
        } else {
            push @others, $label;
        }
    }
    @packages = map { $_->[1] } sort { $a->[0] <=> $b->[0] } @packages;
    @others = sort @others;
    for my $label (@packages, @others) {
        my $obj = $entries->{$label};
        next unless ref $obj eq "HASH";
        my $temp;
        for my $k (keys %$obj) {
            next unless $k =~ /^temp\d+_input$/;
            $temp = int($obj->{$k});
            last;
        }
        push @lines, "$label: ${temp}°C" if defined $temp;
    }
}
print join("\n", @lines);
' <<<"$sensors_json")"

if [ -n "${CPUINFO_TEMPERATURE_ID}" ]; then
  temperature=$(perl -ne 'BEGIN{$id=shift} if (/^\Q$id\E:\s*([0-9]+)/){print $1; exit}' "$CPUINFO_TEMPERATURE_ID" <<<"$cpu_temps")
fi

if [[ -z "$temperature" ]]; then
  cpu_temp_line="${cpu_temps%%$'°C'*}"
  temperature="${cpu_temp_line#*: }"
fi

if [[ -n "$cpu_temps" ]]; then
  cpu_temps_indented=$'\t'"${cpu_temps//$'\n'/$'\n\t'}"
elif [[ -n "$temperature" ]]; then
  cpu_temps_indented=$'\t'"${temperature}°C"
else
  cpu_temps_indented=$'\t'"N/A"
fi

utilization=$(get_utilization)
frequency=$(perl -ne 'BEGIN { $sum = 0; $count = 0 } if (/cpu MHz\s+:\s+([\d.]+)/) { $sum += $1; $count++ } END { if ($count > 0) { printf "%.0f\n", $sum / $count } else { print "NaN\n" } }' /proc/cpuinfo)

icons="$(map_floor "$util_lv" "$utilization")$(map_floor "$temp_lv" "$temperature")"
speed="${icons:0:1}"
thermo="${icons:1:1}"
thermo_alt=󰻠 # better looking icon
# Build tooltip with newlines
tooltip="$CPUINFO_MODEL"$'\n'"$thermo Temperature:"$'\n'"$cpu_temps_indented"
tooltip+=$'\n'"$speed Utilization: $utilization%"
tooltip+=$'\n'" Clock Speed: $frequency/$CPUINFO_MAX_FREQ MHz"

color=$(get_temp_color "${temperature}")
if [[ -n "$color" ]]; then
  icon_text="<span size='14pt' color='$color'>$thermo_alt</span>"
else
  icon_text="<span size='14pt'>$thermo_alt</span>"
fi

# Format utilization with two digits for text display only
formatted_util=$(printf "%02d" "$utilization")

jq -n -c \
  --arg icon "$icon_text" \
  --arg util "${formatted_util}󱉸" \
  --arg tooltip "$tooltip" \
  '{text: ($icon + "\r" + $util), tooltip: $tooltip}'

#!/usr/bin/env bash

set -euo pipefail

cpuinfo_file="${XDG_RUNTIME_DIR:-/tmp}/hypr-$UID-processors"

map_floor() {
  local mapping="$1"
  local input="$2"
  local def_val=""
  local pair=""
  local key=""
  local value=""
  local num="${input%%.*}"

  IFS=', ' read -r -a pairs <<<"${mapping}"
  if [[ ${pairs[-1]} != *":"* ]]; then
    def_val="${pairs[-1]}"
    unset 'pairs[${#pairs[@]}-1]'
  fi

  for pair in "${pairs[@]}"; do
    IFS=':' read -r key value <<<"${pair}"
    if [[ "$num" =~ ^-?[0-9]+$ && "$key" =~ ^-?[0-9]+$ ]]; then
      (( num > key )) && printf '%s\n' "${value}" && return
    elif [[ -n "$num" && -n "$key" && "$num" > "$key" ]]; then
      printf '%s\n' "${value}" && return
    fi
  done

  [[ -n "${def_val}" ]] && printf '%s\n' "${def_val}" || printf ' \n'
}

load_cpu_cache() {
  # Same file path declared at the top of the script — read AND write must
  # agree, otherwise cached values never survive a poll.
  [[ -f "${cpuinfo_file}" ]] && source "${cpuinfo_file}"
  return 0
}

cache_cpu_value() {
  local key="$1"
  local value="$2"
  echo "${key}=\"${value}\"" >>"${cpuinfo_file}"
}

# ${VAR:-} fallbacks below: on first run nothing has populated the cache, so
# the bare ${VAR} would crash under set -u. The `-n` test then sees empty and
# falls through to compute + cache.
initialize_cpu_metadata() {
  [[ -n "${CPUINFO_MODEL:-}" ]] || {
    CPUINFO_MODEL=$(lscpu | awk -F': ' '/Model name/ {gsub(/^ *| *$| CPU.*/,"",$2); print $2}')
    cache_cpu_value "CPUINFO_MODEL" "${CPUINFO_MODEL}"
  }

  [[ -n "${CPUINFO_MAX_FREQ:-}" ]] || {
    CPUINFO_MAX_FREQ=$(lscpu | awk '/CPU max MHz/ { sub(/\..*/,"",$4); print $4}')
    cache_cpu_value "CPUINFO_MAX_FREQ" "${CPUINFO_MAX_FREQ}"
  }
}

initialize_cpu_stats() {
  local stat_file
  stat_file=$(head -1 /proc/stat)

  [[ -n "${CPUINFO_PREV_STAT:-}" ]] || {
    CPUINFO_PREV_STAT=$(awk '{print $2+$3+$4+$6+$7+$8 }' <<<"${stat_file}")
    cache_cpu_value "CPUINFO_PREV_STAT" "${CPUINFO_PREV_STAT}"
  }

  [[ -n "${CPUINFO_PREV_IDLE:-}" ]] || {
    CPUINFO_PREV_IDLE=$(awk '{print $5 }' <<<"${stat_file}")
    cache_cpu_value "CPUINFO_PREV_IDLE" "${CPUINFO_PREV_IDLE}"
  }
}

init_query() {
  load_cpu_cache
  initialize_cpu_metadata
  initialize_cpu_stats
}

get_temp_color() {
  local temp=$1
  declare -A temp_colors=(
    [90]="#8b0000" [85]="#ad1f2f" [80]="#d22f2f" [75]="#ff471a"
    [70]="#ff6347" [65]="#ff8c00" [60]="#ffa500" [45]=""
    [40]="#add8e6" [35]="#87ceeb" [30]="#4682b4" [25]="#4169e1"
    [20]="#0000ff" [0]="#00008b"
  )
  local threshold=""

  for threshold in $(printf '%s\n' "${!temp_colors[@]}" | sort -nr); do
    if ((temp >= threshold)); then
      echo "${temp_colors[$threshold]}"
      return
    fi
  done
}

update_cpu_stats_cache() {
  local curr_stat="$1"
  local curr_idle="$2"

  CPUINFO_PREV_STAT=$curr_stat
  CPUINFO_PREV_IDLE=$curr_idle

  sed -i \
    -e "/^CPUINFO_PREV_STAT=/c\CPUINFO_PREV_STAT=\"$curr_stat\"" \
    -e "/^CPUINFO_PREV_IDLE=/c\CPUINFO_PREV_IDLE=\"$curr_idle\"" \
    "$cpuinfo_file" || {
      echo "CPUINFO_PREV_STAT=\"$curr_stat\"" >>"$cpuinfo_file"
      echo "CPUINFO_PREV_IDLE=\"$curr_idle\"" >>"$cpuinfo_file"
    }
}

get_utilization() {
  local stat_file=""
  local curr_stat=0
  local curr_idle=0
  local diff_stat=0
  local diff_idle=0

  stat_file=$(head -1 /proc/stat)
  curr_stat=$(awk '{print $2+$3+$4+$6+$7+$8 }' <<<"${stat_file}")
  curr_idle=$(awk '{print $5 }' <<<"${stat_file}")
  diff_stat=$((curr_stat - CPUINFO_PREV_STAT))
  diff_idle=$((curr_idle - CPUINFO_PREV_IDLE))

  update_cpu_stats_cache "${curr_stat}" "${curr_idle}"
  awk -v stat="${diff_stat}" -v idle="${diff_idle}" 'BEGIN {printf "%.0f", (stat/(stat+idle))*100}'
}

read_cpu_temperatures() {
  local sensors_json=""

  sensors_json=$(sensors -j 2>/dev/null)
  perl -e '
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
my @cpu_prefixes = qw(coretemp- k10temp- zenpower- cpu_thermal-);
my $cpu_label_re = qr/^(?:Package\s+id|Tctl|Tdie|Tccd\d|CPU|Core\s+\d)/i;
my @lines;
for my $chip (sort keys %$data) {
    next unless ref $data->{$chip} eq "HASH";
    my $is_cpu_chip = grep { index($chip, $_) == 0 } @cpu_prefixes;
    my $entries = $data->{$chip};
    my (@packages, @others);
    for my $label (keys %$entries) {
        next unless ref $entries->{$label} eq "HASH";
        next if !$is_cpu_chip && $label !~ $cpu_label_re;
        if ($label =~ /^Package\s+id\s+(\d+)/i) {
            push @packages, [$1, $label, $entries->{$label}];
        } else {
            push @others, [$label, $entries->{$label}];
        }
    }
    @packages = sort { $a->[0] <=> $b->[0] } @packages;
    @others = sort { $a->[0] cmp $b->[0] } @others;
    for my $entry (@packages, @others) {
        my ($label, $obj) = ref $entry->[2] ? ($entry->[1], $entry->[2]) : @$entry;
        next unless ref $obj eq "HASH";
        for my $k (keys %$obj) {
            next unless $k =~ /^temp\d+_input$/;
            my $temp = int($obj->{$k});
            push @lines, "$label: ${temp}°C";
            last;
        }
    }
}
print join("\n", @lines);
' <<<"${sensors_json}"
}

resolve_temperature_value() {
  local cpu_temps="$1"
  # ${temperature:-} — a caller may set this from elsewhere, but on the
  # standard polling path it isn't pre-populated.
  if [[ -n "${temperature:-}" ]]; then
    printf '%s\n' "${temperature}"
    return
  fi

  local cpu_temp_line="${cpu_temps%%$'°C'*}"
  printf '%s\n' "${cpu_temp_line#*: }"
}

format_cpu_temperatures() {
  local cpu_temps="$1"
  local temperature="$2"

  if [[ -n "${cpu_temps}" ]]; then
    printf '\t%s\n' "${cpu_temps//$'\n'/$'\n\t'}"
  elif [[ -n "${temperature}" ]]; then
    printf '\t%s°C\n' "${temperature}"
  else
    printf '\tN/A\n'
  fi
}

read_cpu_frequency() {
  perl -ne 'BEGIN { $sum = 0; $count = 0 } if (/cpu MHz\s+:\s+([\d.]+)/) { $sum += $1; $count++ } END { if ($count > 0) { printf "%.0f\n", $sum / $count } else { print "NaN\n" } }' /proc/cpuinfo
}

build_cpu_tooltip() {
  local model="$1"
  local thermo="$2"
  local temps="$3"
  local utilization="$4"
  local frequency="$5"

  local tooltip="${model}"$'\n'"${thermo} Temperature:"$'\n'"${temps}"
  tooltip+=$'\n'"${speed} Utilization: ${utilization}%"
  tooltip+=$'\n'" Clock Speed: ${frequency}/${CPUINFO_MAX_FREQ} MHz"
  printf '%s\n' "${tooltip}"
}

build_cpu_icon() {
  local temperature="$1"
  local color=""

  color=$(get_temp_color "${temperature}")
  if [[ -n "${color}" ]]; then
    printf "<span size='14pt' color='%s'>󰻠</span>\n" "${color}"
  else
    printf "<span size='14pt'>󰻠</span>\n"
  fi
}

emit_cpu_json() {
  local icon="$1"
  local utilization="$2"
  local tooltip="$3"
  local formatted_util=""

  # Cap module text at 99 so a 3-digit reading doesn't break the bar's
  # fixed-width slot. The tooltip is built upstream with the raw value, so
  # 100% is visible there.
  local util_int="${utilization%%.*}"
  [[ "${util_int}" =~ ^[0-9]+$ ]] && (( util_int > 99 )) && util_int=99
  formatted_util=$(printf "%02d" "${util_int}")
  jq -n -c \
    --arg icon "${icon}" \
    --arg util "${formatted_util}󱉸" \
    --arg tooltip "${tooltip}" \
    '{text: ($icon + "\r" + $util), tooltip: $tooltip}'
}

init_query

temp_lv="85:, 65:,, 45:, "
util_lv="90:, 60:󰓅, 30:󰾅, 󰾆"
cpu_temps="$(read_cpu_temperatures)"
temperature="$(resolve_temperature_value "${cpu_temps}")"
cpu_temps_indented="$(format_cpu_temperatures "${cpu_temps}" "${temperature}")"
utilization="$(get_utilization)"
frequency="$(read_cpu_frequency)"
icons="$(map_floor "$util_lv" "$utilization")$(map_floor "$temp_lv" "$temperature")"
speed="${icons:0:1}"
thermo="${icons:1:1}"
tooltip="$(build_cpu_tooltip "${CPUINFO_MODEL}" "${thermo}" "${cpu_temps_indented}" "${utilization}" "${frequency}")"
icon_text="$(build_cpu_icon "${temperature}")"

emit_cpu_json "${icon_text}" "${utilization}" "${tooltip}"

#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell sysinfo/network-speed [-d|-u]
Emit network speed as bar JSON: -d download, -u upload, default both." "$@"

ALT_MODE=false
args=()
for arg in "$@"; do
  case "${arg}" in
    --alt | -A) ALT_MODE=true ;;
    *) args+=("${arg}") ;;
  esac
done

MODE="both"
case "${args[0]:-}" in
  -u | --upload) MODE="upload" ;;
  -d | --download) MODE="download" ;;
  "") MODE="both" ;;
  *)
    echo '{"text":"ERR","tooltip":"Invalid option. Use -d, -u, or none"}'
    exit 1
    ;;
esac

network_speed_state_dir() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  local fallback_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/runtime"

  if mkdir -p "${runtime_dir}/hypr" 2>/dev/null; then
    printf '%s\n' "${runtime_dir}/hypr"
    return 0
  fi

  mkdir -p "${fallback_dir}" || return 1
  printf '%s\n' "${fallback_dir}"
}

STATE_DIR="$(network_speed_state_dir)" || exit 1
STATE_FILE="${STATE_DIR}/bar-netspeed-${UID:-$(id -u)}"
route=$(ip -o route show default 2>/dev/null || true)
INTERFACE=""
[[ $route =~ [[:space:]]dev[[:space:]]([^[:space:]]+) ]] && INTERFACE=${BASH_REMATCH[1]}

if [ -z "$INTERFACE" ]; then
  if "${ALT_MODE}"; then
    printf '%s\n' '{"text":"0.00 KB/s","tooltip":"Not Connected"}'
  else
    printf '%s\n' '{"text":"00\n00\nKB\n/s","tooltip":"Not Connected"}'
  fi
  exit 0
fi

RX_NOW=$(<"/sys/class/net/$INTERFACE/statistics/rx_bytes")
TX_NOW=$(<"/sys/class/net/$INTERFACE/statistics/tx_bytes")
TIME_NOW=${EPOCHREALTIME}

RX_BYTES_PER_SEC=0
TX_BYTES_PER_SEC=0

if [ -f "$STATE_FILE" ]; then
  read -r PREV_INTERFACE RX_PREV TX_PREV TIME_PREV <"$STATE_FILE"
  if [[ $PREV_INTERFACE == "$INTERFACE" && $RX_PREV =~ ^[0-9]+$ && $TX_PREV =~ ^[0-9]+$ ]]; then
    read -r RX_BYTES_PER_SEC TX_BYTES_PER_SEC < <(
      awk -v now="$TIME_NOW" -v prev="$TIME_PREV" -v rx="$RX_NOW" -v old_rx="$RX_PREV" \
        -v tx="$TX_NOW" -v old_tx="$TX_PREV" 'BEGIN {
          dt = now - prev
          down = dt > 0 ? (rx - old_rx) / dt : 0
          up = dt > 0 ? (tx - old_tx) / dt : 0
          printf "%.0f %.0f\n", (down > 0 ? down : 0), (up > 0 ? up : 0)
        }'
    )
  fi
fi

printf '%s %s %s %s\n' "$INTERFACE" "$RX_NOW" "$TX_NOW" "$TIME_NOW" >"$STATE_FILE"

awk -v down="$RX_BYTES_PER_SEC" -v up="$TX_BYTES_PER_SEC" -v mode="$MODE" -v alt="$ALT_MODE" '
  function scale(b, compact, value, unit) {
    unit = "KB"; value = b / 1024
    if (b >= 1073741824) { unit = "GB"; value = b / 1073741824 }
    else if (b >= 1048576) { unit = "MB"; value = b / 1048576 }
    return sprintf(compact ? "%.2f%s/s" : "%.2f %s/s", value, unit)
  }
  function split_value(b, vertical, value, unit, whole, decimal) {
    unit = "K"; value = b / 1024
    if (b >= 1073741824) { unit = "G"; value = b / 1073741824 }
    else if (b >= 1048576) { unit = "M"; value = b / 1048576 }
    if (value > 99.99) value = 99.99
    whole = int(value); decimal = int((value - whole) * 100)
    return vertical ? sprintf("%02d\\n%02d\\n%sB\\n/s", whole, decimal, unit) \
                    : sprintf("%02d%s\\n%02dB", whole, unit, decimal)
  }
  BEGIN {
    down_label = scale(down, alt == "true")
    up_label = scale(up, alt == "true")
    if (alt == "true") {
      if (mode == "both") text = "󰮏:" down_label " 󰸇:" up_label
      else if (mode == "download") text = "󰮏:" down_label
      else text = "󰸇:" up_label
    } else if (mode == "both") {
      text = "󰇚:\\n" split_value(down, 0) "\\n󰕒:\\n" split_value(up, 0)
    } else {
      text = split_value(mode == "download" ? down : up, 1)
    }
    printf "{\"text\":\"%s\",\"tooltip\":\"Down: %s\\nUp: %s\"}\n", \
      text, scale(down, 0), scale(up, 0)
  }'

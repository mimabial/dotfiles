#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

scales=(1 1.25 1.5 1.67 2 3 4)
reverse=0
[[ "${1:-}" == "--reverse" || "${1:-}" == "reverse" ]] && reverse=1

monitor_info="$(hyprctl monitors -j | jq -r '([.[] | select(.focused == true)][0] // .[0])')"
active_monitor="$(jq -r '.name // empty' <<<"${monitor_info}")"
current_scale="$(jq -r '.scale // 1' <<<"${monitor_info}")"
width="$(jq -r '.width // empty' <<<"${monitor_info}")"
height="$(jq -r '.height // empty' <<<"${monitor_info}")"
refresh_rate="$(jq -r '.refreshRate // empty' <<<"${monitor_info}")"
pos_x="$(jq -r '.x // 0' <<<"${monitor_info}")"
pos_y="$(jq -r '.y // 0' <<<"${monitor_info}")"
transform="$(jq -r '.transform // 0' <<<"${monitor_info}")"

if [[ -z "${active_monitor}" || -z "${width}" || -z "${height}" || -z "${refresh_rate}" ]]; then
  monitor_notify "Monitor scaling failed" "No focused monitor found"
  exit 1
fi

current_idx="$(
  awk -v s="${current_scale}" -v list="${scales[*]}" 'BEGIN {
    n = split(list, arr, " ")
    best = 0
    best_diff = 1000000
    for (i = 1; i <= n; i++) {
      d = s - arr[i]
      if (d < 0) d = -d
      if (d < best_diff) {
        best_diff = d
        best = i - 1
      }
    }
    print best
  }'
)"

if [[ "${reverse}" -eq 1 ]]; then
  next_idx=$(((current_idx - 1 + ${#scales[@]}) % ${#scales[@]}))
else
  next_idx=$(((current_idx + 1) % ${#scales[@]}))
fi

new_scale="${scales[$next_idx]}"
new_gdk_scale="$(monitor_gdk_scale_for "${new_scale}")"
mode="${width}x${height}@${refresh_rate}"
position="${pos_x}x${pos_y}"
rule="monitor=${active_monitor},${mode},${position},${new_scale}"
if [[ "${transform}" != "0" ]]; then
  rule+=",transform,${transform}"
fi

fragment_name="20-scale-$(monitor_sanitize_name "${active_monitor}")"
monitor_set_fragment "${fragment_name}" "$(printf 'env = GDK_SCALE,%s\n%s' "${new_gdk_scale}" "${rule}")"
monitor_reload
monitor_notify "Display scaling set to ${new_scale}x" "${active_monitor} (GDK ${new_gdk_scale})"

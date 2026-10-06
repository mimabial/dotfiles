#!/usr/bin/env bash
set -euo pipefail

scales=(1 1.25 1.5 1.67 2 3 4)
[[ "${1:-}" == "--list" ]] && { printf '%s\n' "${scales[*]}"; exit; }

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

hypr_help_guard "Usage: hyprshell system/monitor-scale [-m NAME] [--reverse|SCALE]
Set or cycle a monitor's scale.
  --list               print available scales
  -m, --monitor NAME   target this monitor instead of the focused one" "$@"

target_monitor="" target_scale="" step=1
if [[ "${1:-}" == "-m" || "${1:-}" == "--monitor" ]]; then
  [[ -n "${2:-}" ]] || { printf 'Missing monitor name after %s\n' "${1}" >&2; exit 2; }
  target_monitor="$2"
  shift 2
fi

case "${1:-}" in
  "") ;;
  --reverse | reverse) step=-1 ;;
  *)
    target_scale="${1%x}"
    [[ " ${scales[*]} " == *" ${target_scale} "* ]] || { printf 'Unsupported monitor scale: %s\n' "${1}" >&2; exit 2; }
    ;;
esac

IFS=$'\t' read -r active_monitor width height refresh_rate pos_x pos_y transform nearest_index < <(
  hypr_monitors_json | jq -r --arg name "${target_monitor}" --arg presets "${scales[*]}" '
    (if $name == "" then map(select(.focused))[0] // .[0] else map(select(.name == $name))[0] end) // empty
    | [.name, .width, .height, .refreshRate, .x, .y, .transform,
      (.scale as $scale | $presets | split(" ") | map(tonumber) | to_entries | min_by((.value - $scale) | fabs) | .key)]
    | @tsv'
) || true
[[ -n "${active_monitor:-}" ]] || {
  monitor_notify "Monitor scaling failed" "${target_monitor:-No focused monitor} not found"
  exit 1
}
[[ -n "${target_scale}" ]] || target_scale="${scales[$(((nearest_index + step + ${#scales[@]}) % ${#scales[@]}))]}"

gdk_scale="$(monitor_gdk_scale_for "${target_scale}")"
# GDK_SCALE is session-global, so it lives in its own fragment: kept per monitor,
# a disconnected output's fragment would still win over the connected one.
monitor_set_fragment "10-gdk-scale" "hl.env(\"GDK_SCALE\", $(monitor_lua_quote "${gdk_scale}"))"
monitor_set_fragment "20-scale-$(monitor_sanitize_name "${active_monitor}")" "$(printf 'hl.monitor({output = %s, mode = %s, position = %s, scale = %s, transform = %s})' \
  "$(monitor_lua_quote "${active_monitor}")" \
  "$(monitor_lua_quote "${width}x${height}@${refresh_rate}")" \
  "$(monitor_lua_quote "${pos_x}x${pos_y}")" \
  "${target_scale}" \
  "${transform}")"
monitor_reload
monitor_notify "Display scaling set to ${target_scale}x" "${active_monitor} (GDK ${gdk_scale})"

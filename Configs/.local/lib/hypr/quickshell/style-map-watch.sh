#!/usr/bin/env bash
source "${HOME}/.local/lib/hypr/runtime/init.bash"
hypr_help_guard "Usage: style-map-watch.sh [--once] [--interval SECONDS]

Watches the quickshell config and regenerates ~/.cache/hypr/quickshell/style-map/.
Uses inotifywait when installed, otherwise polls modification times.

  --once              regenerate and exit
  --interval SECONDS  poll interval for the fallback (default 2)" "$@"

CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}/quickshell"
GENERATOR="${HOME}/.local/lib/hypr/quickshell/style-map.py"
interval=2

while (($#)); do
    case "$1" in
    --once) once=1 ;;
    --interval)
        interval="$2"
        shift
        ;;
    *)
        printf 'style-map-watch: unknown option %s\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
done

generate() { python3 "${GENERATOR}"; }

watched() {
    find "${CONFIG}/layouts" "${CONFIG}/styles" -type f -name '*.json' 2>/dev/null
    find "${CONFIG}" -maxdepth 2 -type f -name '*.qml' 2>/dev/null
}

fingerprint() { watched | xargs -r stat -c '%n %Y' 2>/dev/null | sort; }

generate
[[ -n ${once:-} ]] && exit 0

if command -v inotifywait >/dev/null 2>&1; then
    while inotifywait -q -e close_write,move,create,delete \
        "${CONFIG}/layouts" "${CONFIG}/styles" "${CONFIG}" "${CONFIG}/modules" >/dev/null; do
        # a save often lands as several events; let them settle before rebuilding
        sleep 0.3
        generate
    done
else
    previous=$(fingerprint)
    while sleep "${interval}"; do
        current=$(fingerprint)
        [[ ${current} == "${previous}" ]] && continue
        previous=${current}
        generate
    done
fi

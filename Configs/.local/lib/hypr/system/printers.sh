#!/usr/bin/env bash
#
# printers.sh — CUPS queue state and actions for the bar.
#
# Usage: printers.sh [--report|--waybar|--enable P|--disable P|--default P|--cancel ID|--cancel-all|--web]
# Depends on: lpstat, jq; cupsenable/cupsdisable/cancel/lpoptions for the actions
#
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell system/printers [option]

  --report        JSON: {"printers":[{name,state,enabled,reason,default}],
                         "jobs":[{id,printer,user,size}],"pending":n,"stopped":n}
  --waybar        Bar JSON: text, class, tooltip
  --enable NAME   Resume a stopped queue
  --disable NAME  Stop a queue, leaving its jobs held
  --default NAME  Make it the default destination
  --cancel ID     Cancel one job
  --cancel-all    Cancel every queued job
  --web           Open the CUPS interface

Reads lpstat, so it sees whatever queues CUPS has, local or network.
USAGE
}

printers_json() {
  lpstat -p -d 2>/dev/null | jq -R -s '
    split("\n") | map(select(length > 0)) as $lines
    | ($lines | map(select(startswith("system default destination:"))
        | sub("^system default destination: "; "")) | first // "") as $default
    | [ $lines[] | select(startswith("printer ")) ]
    | map(
        (sub("^printer "; "") | split(" ")[0]) as $name
        | {
            name: $name,
            enabled: (test("is idle|now printing|is printing")),
            state: (if test("now printing|is printing") then "printing"
                    elif test("is idle") then "idle"
                    else "stopped" end),
            default: ($name == $default)
          }
      )'
}

jobs_json() {
  lpstat -o 2>/dev/null | jq -R -s '
    split("\n") | map(select(length > 0))
    | map(
        (split(" ") | map(select(length > 0))) as $f
        | {
            id: $f[0],
            printer: ($f[0] | sub("-[0-9]+$"; "")),
            user: ($f[1] // ""),
            size: (($f[2] // "0") | tonumber? // 0)
          }
      )'
}

report_json() {
  jq -n \
    --argjson printers "$(printers_json)" \
    --argjson jobs "$(jobs_json)" '{
      printers: $printers,
      jobs: $jobs,
      pending: ($jobs | length),
      stopped: ($printers | map(select(.state == "stopped")) | length)
    }'
}

case "${1:---report}" in
  -h | --help)
    usage
    exit 0
    ;;
  --report)
    report_json
    ;;
  --waybar)
    # a stopped queue is the case worth surfacing: jobs pile up silently
    report_json | jq -r '
      {
        text: (if (.printers | length) == 0 then ""
               elif .stopped > 0 then "󰐬"
               elif .pending > 0 then "󱊖"
               else "󰐪" end),
        class: (if (.printers | length) == 0 then "empty"
                elif .stopped > 0 then "stopped"
                elif .pending > 0 then "printing"
                else "idle" end),
        tooltip: (if (.printers | length) == 0 then "No printers"
                  else ((.printers | map("\(.name) — \(.state)")) + (if .pending > 0 then ["\(.pending) job(s) queued"] else [] end) | join("\n"))
                  end)
      } | @json'
    ;;
  --enable)
    [[ -n "${2:-}" ]] || { usage >&2; exit 1; }
    cupsenable "$2"
    ;;
  --disable)
    [[ -n "${2:-}" ]] || { usage >&2; exit 1; }
    cupsdisable "$2"
    ;;
  --default)
    [[ -n "${2:-}" ]] || { usage >&2; exit 1; }
    lpoptions -d "$2" >/dev/null
    ;;
  --cancel)
    [[ -n "${2:-}" ]] || { usage >&2; exit 1; }
    cancel "$2"
    ;;
  --cancel-all)
    cancel -a
    ;;
  --web)
    xdg-open "http://localhost:631/" >/dev/null 2>&1 &
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

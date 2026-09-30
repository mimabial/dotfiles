#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell system/printers [option]

  --report        JSON: {"printers":[{name,state,reason,default,transport}],
                         "jobs":[{id,printer,user,size}],"pending":n,"stopped":n}
  --bar           Bar JSON: text, class, tooltip
  --enable NAME   Resume a stopped queue
  --disable NAME  Stop a queue, leaving its jobs held
  --default NAME  Make it the default destination
  --switch NAME   Toggle the queue between USB and network
  --cancel ID     Cancel one job
  --cancel-all    Cancel every queued job

Reads lpstat, so it sees whatever queues CUPS has, local or network, except fax.
USAGE
}

# Listing every destination makes lpstat browse DNS-SD for a second per flag;
# naming the queues cupsd reports keeps it to the local answer.
queue_names() {
  ipptool -c ipp://localhost/ /dev/stdin 2>/dev/null <<'IPP' | tail -n +2
{
  OPERATION CUPS-Get-Printers
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR keyword requested-attributes printer-name
  DISPLAY printer-name
}
IPP
}

printers_json() {
  local names
  mapfile -t names < <(queue_names)
  {
    lpstat -d
    if ((${#names[@]})); then lpstat -p "${names[@]}" -v "${names[@]}"; fi
  } 2>/dev/null | jq -R -s '
    (capture("system default destination: (?<name>\\S+)").name // "") as $default
    | ([scan("device for ([^:]+): (\\S+)") | {key: .[0], value: .[1]}] | from_entries) as $devices
    | [ scan("(?m)^printer (\\S+) (.*)\\n(?:\\t(.*))?") as [$name, $status, $reason]
        | ($devices[$name] // "") as $device
        | select($device | startswith("hpfax:") | not)
        | {
            name: $name,
            state: (if $status | test("now printing|is printing") then "printing"
                    elif $status | test("is idle") then "idle"
                    else "stopped" end),
            reason: ($reason // ""),
            default: ($name == $default),
            transport: ($device | if test("^(usb://|hp:/usb/)") then "usb"
                        elif test("^(hp:/net/|ipps?://|socket://|lpd://)|ip=") then "network"
                        else "" end)
          }
      ]'
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
  --bar)
    # a stopped queue is the case worth surfacing: jobs pile up silently
    report_json | jq -r '
      {
        text: (if (.printers | length) == 0 then ""
               elif .stopped > 0 then "󰐬"
               elif .pending > 0 then "󱊖"
               else "󱞆" end),
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
    cupsaccept "$2"
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
  --switch)
    [[ -n "${2:-}" ]] || { usage >&2; exit 1; }
    exec bash "${BASH_SOURCE[0]%/*}/printer.connection.switch.sh" -p "$2"
    ;;
  --cancel)
    [[ -n "${2:-}" ]] || { usage >&2; exit 1; }
    cancel "$2"
    ;;
  --cancel-all)
    cancel -a
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: hyprshell system/printers [option]

  --report        JSON: {"printers":[{name,state,reason,default,transport}],
                         "jobs":[{id,printer,user,size}],"pending":n,"stopped":n}
  --bar           Bar JSON: text, class, tooltip
  --watch         Print one line per CUPS printer or job event, until the parent exits
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
  ipptool -c ipp://localhost/ /dev/stdin 2>/dev/null <<'IPP'
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

subscribe_dbus_events() {
  local recipients=""
  recipients="$(ipptool -c ipp://localhost/ /dev/stdin 2>/dev/null <<'IPP'
{
  OPERATION Get-Subscriptions
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri ipp://localhost/
  ATTR name requesting-user-name $user
  ATTR keyword requested-attributes notify-recipient-uri
  STATUS successful-ok
  STATUS client-error-not-found
  DISPLAY notify-recipient-uri
}
IPP
)" || return 1
  [[ $'\n'"${recipients}"$'\n' == *$'\n'dbus://$'\n'* ]] && return 0
  ipptool -q ipp://localhost/ /dev/stdin <<'IPP'
{
  OPERATION Create-Printer-Subscriptions
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri ipp://localhost/
  ATTR name requesting-user-name $user
  GROUP subscription-attributes-tag
  ATTR uri notify-recipient-uri dbus://
  ATTR keyword notify-events printer-added,printer-deleted,printer-modified,printer-state-changed,job-created,job-completed,job-state-changed
  ATTR integer notify-lease-duration 0
  STATUS successful-ok
}
IPP
}

report_json() {
  local view="$1" names csv_rows
  mapfile -t csv_rows < <(queue_names)
  names=("${csv_rows[@]:1}")
  jq -n -r --arg view "${view}" \
    --rawfile printers_text <({ lpstat -d; if ((${#names[@]})); then lpstat -p "${names[@]}" -v "${names[@]}"; fi; } 2>/dev/null) \
    --rawfile jobs_text <(lpstat -o 2>/dev/null) '
    def printers:
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
        ];
    def jobs:
      split("\n") | map(select(length > 0))
      | map(
          (split(" ") | map(select(length > 0))) as $f
          | {
              id: $f[0],
              printer: ($f[0] | sub("-[0-9]+$"; "")),
              user: ($f[1] // ""),
              size: (($f[2] // "0") | tonumber? // 0)
            }
        );
    ($printers_text | printers) as $printers
    | ($jobs_text | jobs) as $jobs
    | {
        printers: $printers,
        jobs: $jobs,
        pending: ($jobs | length),
        stopped: ($printers | map(select(.state == "stopped")) | length)
      }
    | if $view == "bar" then
        # a stopped queue is the case worth surfacing: jobs pile up silently
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
        } | @json
      end'
}

case "${1:---report}" in
  -h | --help)
    usage
    exit 0
    ;;
  --report)
    report_json report
    ;;
  --bar)
    report_json bar
    ;;
  --watch)
    subscribe_dbus_events
    exec setpriv --pdeathsig TERM dbus-monitor --system --profile "type='signal',interface='org.cups.cupsd.Notifier'" 2>/dev/null
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

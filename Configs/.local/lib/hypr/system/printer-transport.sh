#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/printers/queues.bash"

printer_usage() {
  cat <<'EOF'
Usage: printer-transport.sh [toggle|usb|network|status] [options]
       printer-transport.sh [printer-name] [options]

Switch a CUPS printer queue between USB and network device URIs.

Actions:
  toggle              Toggle transport (default action)
  usb                 Force USB transport
  network             Force network transport
  status              Show detected/current URIs without changing anything

Options:
  -p, --printer <name>       Printer queue name (defaults to CUPS default)
      --usb-uri <uri>        Explicit USB URI (seed/override auto-detection)
      --network-uri <uri>    Explicit network URI (seed/override auto-detection)
  -h, --help                 Show this help

Examples:
  printer-transport.sh
  printer-transport.sh usb
  printer-transport.sh network -p OfficeJet_3830
  printer-transport.sh --network-uri 'hp:/net/OfficeJet_3830_series?ip=192.168.1.33'
EOF
}

printer_parse_args_into() {
  local -n options_ref=$1
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      toggle|usb|network|status)
        options_ref[action]="$1"
        shift
        ;;
      -p|--printer)
        [[ $# -lt 2 ]] && { echo "Error: --printer requires a value." >&2; exit 1; }
        options_ref[requested_printer]="$2"
        shift 2
        ;;
      --usb-uri)
        [[ $# -lt 2 ]] && { echo "Error: --usb-uri requires a value." >&2; exit 1; }
        options_ref[usb_uri]="$2"
        shift 2
        ;;
      --network-uri)
        [[ $# -lt 2 ]] && { echo "Error: --network-uri requires a value." >&2; exit 1; }
        options_ref[network_uri]="$2"
        shift 2
        ;;
      -h|--help)
        printer_usage
        exit 0
        ;;
      *)
        if [[ -z "${options_ref[requested_printer]}" ]]; then
          options_ref[requested_printer]="$1"
          shift
        else
          echo "Error: unexpected argument '$1'." >&2
          printer_usage >&2
          exit 1
        fi
        ;;
    esac
  done
}

main() {
  local -A printer_context=(
    [action]=toggle [requested_printer]="" [usb_uri]="" [network_uri]="" [printer]=""
    [current_uri]="" [current_transport]="" [uri_hint]="" [state_dir]="" [state_file]=""
    [stored_usb_uri]="" [stored_network_uri]="" [target_transport]="" [target_uri]=""
  )
  printer_parse_args_into printer_context "$@"
  printer_require_transport_tools
  printer_load_printer_context printer_context
  printer_run_with_state_lock printer_context
}

source "${BASH_SOURCE[0]%/*}/printers/transport-uris.bash"
source "${BASH_SOURCE[0]%/*}/printers/transport-state.bash"
source "${BASH_SOURCE[0]%/*}/printers/transport-actions.bash"

main "$@"

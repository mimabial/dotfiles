#!/usr/bin/env bash

set -euo pipefail

validate_dns_entry() {
  local entry="$1"
  local address="$entry"
  local server_name=""

  if [[ "${entry}" == *"#"* ]]; then
    address="${entry%%#*}"
    server_name="${entry#*#}"
    [[ -n "${server_name}" ]] || return 1
    [[ "${server_name}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  fi

  python3 - "${address}" <<'PY' >/dev/null 2>&1
import ipaddress
import sys

try:
    ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
PY
}

normalize_dns_servers() {
  local raw_servers="$1"
  local entry
  local -a entries=() normalized=()

  [[ "${raw_servers}" != *$'\n'* ]] || return 1
  [[ "${raw_servers}" != *$'\r'* ]] || return 1

  read -r -a entries <<<"${raw_servers}"
  [[ ${#entries[@]} -gt 0 ]] || return 1

  for entry in "${entries[@]}"; do
    validate_dns_entry "${entry}" || return 1
    normalized+=("${entry}")
  done

  printf '%s' "${normalized[*]}"
}

write_resolved_config() {
  sudo tee /etc/systemd/resolved.conf >/dev/null
}

disable_network_dns_override_file() {
  local file="$1"

  grep -q "^\[DHCPv4\]" "${file}" || return 0

  if ! sed -n '/^\[DHCPv4\]/,/^\[/p' "${file}" | grep -q "^UseDNS="; then
    sudo sed -i '/^\[DHCPv4\]/a UseDNS=no' "${file}"
  fi

  if grep -q "^\[IPv6AcceptRA\]" "${file}" &&
    ! sed -n '/^\[IPv6AcceptRA\]/,/^\[/p' "${file}" | grep -q "^UseDNS="; then
    sudo sed -i '/^\[IPv6AcceptRA\]/a UseDNS=no' "${file}"
  fi
}

enable_network_dns_override_file() {
  local file="$1"

  sudo sed -i '/^UseDNS=no/d' "${file}"
}

for_each_network_file() {
  local callback="$1"
  local file

  for file in /etc/systemd/network/*.network; do
    [[ -f "${file}" ]] || continue
    "${callback}" "${file}"
  done
}

restart_dns_services() {
  sudo systemctl restart systemd-networkd systemd-resolved
}

apply_dns_override_mode() {
  case "$1" in
    static) for_each_network_file disable_network_dns_override_file ;;
    dhcp) for_each_network_file enable_network_dns_override_file ;;
    *)
      echo "Error: Invalid DNS override mode: $1" >&2
      return 1
      ;;
  esac
}

prompt_dns_provider() {
  printf '%s\n' "Cloudflare" "DHCP" "Custom" |
    fzf --prompt="Select DNS provider > " --height=5 --reverse
}

prompt_custom_dns_servers() {
  local dns_servers=""

  echo "Enter your DNS servers (space-separated, e.g. '192.168.1.1 1.1.1.1'):" >&2
  read -r dns_servers
  [[ -n "${dns_servers}" ]] || {
    echo "Error: No DNS servers provided." >&2
    return 1
  }

  normalize_dns_servers "${dns_servers}" || {
    echo "Error: Invalid DNS server list." >&2
    echo "Only IP literals are accepted, optionally with #server-name." >&2
    return 1
  }
}

apply_cloudflare_dns() {
  write_resolved_config <<'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=9.9.9.9 149.112.112.112
DNSOverTLS=opportunistic
EOF

  apply_dns_override_mode static
  restart_dns_services
}

apply_dhcp_dns() {
  write_resolved_config <<'EOF'
[Resolve]
DNSOverTLS=no
EOF

  apply_dns_override_mode dhcp
  restart_dns_services
}

apply_custom_dns() {
  local dns_servers="$1"

  printf '[Resolve]\nDNS=%s\nFallbackDNS=9.9.9.9 149.112.112.112\n' "${dns_servers}" |
    write_resolved_config

  apply_dns_override_mode static
  restart_dns_services
}

main() {
  local dns_provider="${1:-}"
  local dns_servers=""

  if [[ -z "${dns_provider}" ]]; then
    dns_provider="$(prompt_dns_provider)" || return 1
    [[ -n "${dns_provider}" ]] || return 0
  fi

  case "${dns_provider}" in
    Cloudflare) apply_cloudflare_dns ;;
    DHCP) apply_dhcp_dns ;;
    Custom)
      dns_servers="$(prompt_custom_dns_servers)" || return 1
      apply_custom_dns "${dns_servers}"
      ;;
    *)
      echo "Error: Unknown DNS provider: ${dns_provider}" >&2
      return 1
      ;;
  esac
}

main "$@"

#!/usr/bin/env bash

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
  local -a normalized=()

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

if [[ -z $1 ]]; then
  dns=$(echo -e "Cloudflare\nDHCP\nCustom" | fzf --prompt="Select DNS provider > " --height=5 --reverse)
  [[ -z "$dns" ]] && exit 0
else
  dns=$1
fi

case "$dns" in
Cloudflare)
  sudo tee /etc/systemd/resolved.conf >/dev/null <<'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=9.9.9.9 149.112.112.112
DNSOverTLS=opportunistic
EOF
  
  # Ensure network interfaces don't override our DNS settings
  for file in /etc/systemd/network/*.network; do
    [[ -f "$file" ]] || continue
    if ! grep -q "^\[DHCPv4\]" "$file"; then continue; fi
    
    # Add UseDNS=no to DHCPv4 section if not present
    if ! sed -n '/^\[DHCPv4\]/,/^\[/p' "$file" | grep -q "^UseDNS="; then
      sudo sed -i '/^\[DHCPv4\]/a UseDNS=no' "$file"
    fi
    
    # Add UseDNS=no to IPv6AcceptRA section if present
    if grep -q "^\[IPv6AcceptRA\]" "$file" && ! sed -n '/^\[IPv6AcceptRA\]/,/^\[/p' "$file" | grep -q "^UseDNS="; then
      sudo sed -i '/^\[IPv6AcceptRA\]/a UseDNS=no' "$file"
    fi
  done
  
  sudo systemctl restart systemd-networkd systemd-resolved
  ;;

DHCP)
  sudo tee /etc/systemd/resolved.conf >/dev/null <<'EOF'
[Resolve]
DNSOverTLS=no
EOF
  
  # Allow network interfaces to use DHCP DNS
  for file in /etc/systemd/network/*.network; do
    [[ -f "$file" ]] || continue
    sudo sed -i '/^UseDNS=no/d' "$file"
  done
  
  sudo systemctl restart systemd-networkd systemd-resolved
  ;;

Custom)
  echo "Enter your DNS servers (space-separated, e.g. '192.168.1.1 1.1.1.1'):"
  read -r dns_servers

  if [[ -z "$dns_servers" ]]; then
    echo "Error: No DNS servers provided."
    exit 1
  fi

  dns_servers="$(normalize_dns_servers "${dns_servers}")" || {
    echo "Error: Invalid DNS server list."
    echo "Only IP literals are accepted, optionally with #server-name."
    exit 1
  }

  printf '[Resolve]\nDNS=%s\nFallbackDNS=9.9.9.9 149.112.112.112\n' "${dns_servers}" |
    sudo tee /etc/systemd/resolved.conf >/dev/null
  
  # Ensure network interfaces don't override our DNS settings
  for file in /etc/systemd/network/*.network; do
    [[ -f "$file" ]] || continue
    if ! grep -q "^\[DHCPv4\]" "$file"; then continue; fi
    
    # Add UseDNS=no to DHCPv4 section if not present
    if ! sed -n '/^\[DHCPv4\]/,/^\[/p' "$file" | grep -q "^UseDNS="; then
      sudo sed -i '/^\[DHCPv4\]/a UseDNS=no' "$file"
    fi
    
    # Add UseDNS=no to IPv6AcceptRA section if present
    if grep -q "^\[IPv6AcceptRA\]" "$file" && ! sed -n '/^\[IPv6AcceptRA\]/,/^\[/p' "$file" | grep -q "^UseDNS="; then
      sudo sed -i '/^\[IPv6AcceptRA\]/a UseDNS=no' "$file"
    fi
  done
  
  sudo systemctl restart systemd-networkd systemd-resolved

  ;;
esac

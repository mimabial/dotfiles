#!/usr/bin/env bash
# Wire the fftab-bridge native-messaging host into Firefox for this machine.
set -euo pipefail

bridge_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
host_path="${bridge_dir}/host/fftab_host.py"
manifest_dir="${HOME}/.mozilla/native-messaging-hosts"

[[ -x "${host_path}" ]] || chmod +x "${host_path}"
mkdir -p "${manifest_dir}"
cat >"${manifest_dir}/fftab_bridge.json" <<EOF
{
  "name": "fftab_bridge",
  "description": "MPRIS bridge: one player per Firefox media tab",
  "path": "${host_path}",
  "type": "stdio",
  "allowed_extensions": ["fftab-bridge@hypr.local"]
}
EOF

echo "native-messaging manifest written: ${manifest_dir}/fftab_bridge.json"
echo "remaining manual steps in Firefox:"
echo "  1. install the signed extension: ${bridge_dir}/extension/web-ext-artifacts/<version>.xpi"
echo "  2. about:config -> media.hardwaremediakeys.enabled = false (disables Firefox's own MPRIS)"

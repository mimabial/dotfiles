#!/usr/bin/env bash
set -euo pipefail

bridge_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
host_path="${bridge_dir}/host/fftab_host.py"
manifest_dir="${HOME}/.mozilla/native-messaging-hosts"

[[ -x "${host_path}" ]] || chmod +x "${host_path}"
# shellcheck source=/dev/null
. "$(dirname "$0")/manifest.bash"
fftab_write_manifest "${manifest_dir}/fftab_bridge.json" "${host_path}" "fftab-bridge@hypr.local"

echo "native-messaging manifest written: ${manifest_dir}/fftab_bridge.json"
echo "remaining manual steps in Firefox:"
echo "  1. install the signed extension: ${bridge_dir}/extension/web-ext-artifacts/<version>.xpi"
echo "  2. about:config -> media.hardwaremediakeys.enabled = false (disables Firefox's own MPRIS)"

#!/usr/bin/env bash
set -euo pipefail

bridge_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
host_path="${bridge_dir}/host/fftab_host.py"

[[ -x "${host_path}" ]] || chmod +x "${host_path}"
# shellcheck source=/dev/null
. "$(dirname "$0")/manifest.bash"
fftab_write_manifest "${FFTAB_MANIFEST}" "${host_path}" "${FFTAB_EXTENSION_ID}"

echo "native-messaging manifest written: ${FFTAB_MANIFEST}"
echo "remaining manual steps in Firefox:"
echo "  1. install the signed extension: ${bridge_dir}/extension/web-ext-artifacts/<version>.xpi"
echo "  2. about:config -> media.hardwaremediakeys.enabled = false (disables Firefox's own MPRIS)"

#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/manifest.bash"
set -euo pipefail

bridge_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--help" ]]; then
  printf 'Usage: %s [--help]\n\nSign an extension update:\n  cd %s/extension\n  web-ext sign --channel unlisted --api-key <issuer> --api-secret <secret>\n\nGet credentials from addons.mozilla.org/developers → Tools → Manage API Keys,\nthen install the new XPI from web-ext-artifacts/.\n' "$0" "${bridge_dir}"
  exit 0
fi

# Per-host opt-out: export FFTAB_ENSURE_DISABLE=1 in env-overrides.
env_overrides="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/env-overrides"
if [[ -n "${FFTAB_ENSURE_DISABLE:-}" ]] ||
  grep -qsE '^\s*export\s+FFTAB_ENSURE_DISABLE=' "${env_overrides}"; then
  exit 0
fi

host_path="${bridge_dir}/host/fftab_host.py"
manifest="${HOME}/.mozilla/native-messaging-hosts/fftab_bridge.json"
extension_id="fftab-bridge@hypr.local"
issues=()

for command_name in playerctl jq yt-dlp unzip; do
  command -v "${command_name}" >/dev/null 2>&1 || issues+=("missing binary: ${command_name} (in pkg_core.lst)")
done
python3 - <<'EOF' >/dev/null 2>&1 || issues+=("missing GI bindings: python-gobject + playerctl (in pkg_core.lst)")
import gi
gi.require_version("Playerctl", "2.0")
from gi.repository import Playerctl
EOF

[[ -x "${host_path}" ]] || chmod +x "${host_path}" 2>/dev/null || issues+=("host not executable: ${host_path}")
if ! grep -qsF "\"path\": \"${host_path}\"" "${manifest}"; then
  fftab_write_manifest "${manifest}" "${host_path}" "${extension_id}"
fi

profiles_ini="${HOME}/.mozilla/firefox/profiles.ini"
profile_name=""
if [[ -r "${profiles_ini}" ]]; then
  profile_name="$(awk -F= '/^\[Install/{f=1} f && /^Default=/{print $2; exit}' "${profiles_ini}")"
fi
if [[ -n "${profile_name}" && -d "${HOME}/.mozilla/firefox/${profile_name}" ]]; then
  profile_dir="${HOME}/.mozilla/firefox/${profile_name}"
  user_js_file="${profile_dir}/user.js"
  if ! grep -qsF 'media.hardwaremediakeys.enabled' "${user_js_file}"; then
    printf 'user_pref("media.hardwaremediakeys.enabled", false);\n' >>"${user_js_file}"
    grep -qsF '"media.hardwaremediakeys.enabled", false' "${profile_dir}/prefs.js" ||
      issues+=("Firefox pref set via user.js — restart Firefox to apply")
  fi
  extension_manifest="${bridge_dir}/extension/manifest.json"
  source_version="$(jq -r '.version // empty' "${extension_manifest}" 2>/dev/null || true)"
  installed_version="$(
    jq -r --arg id "${extension_id}" \
      '.addons[] | select(.id == $id) | .version' \
      "${profile_dir}/extensions.json" 2>/dev/null | head -1
  )"
  signed_xpi=""
  if [[ -n "${source_version}" ]]; then
    for candidate in "${bridge_dir}"/extension/web-ext-artifacts/*.xpi; do
      [[ -f "${candidate}" ]] || continue
      candidate_version="$(unzip -p "${candidate}" manifest.json 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
      if [[ "${candidate_version}" == "${source_version}" ]]; then
        signed_xpi="${candidate}"
        break
      fi
    done
  fi
  if [[ -z "${installed_version}" ]]; then
    issues+=("extension not installed — open in Firefox: ${signed_xpi:-<no signed XPI; run ${bridge_dir}/ensure.sh --help>}")
  elif [[ -n "${source_version}" && "${installed_version}" != "${source_version}" ]]; then
    if [[ -n "${signed_xpi}" ]]; then
      issues+=("extension ${installed_version} is outdated — install ${source_version}: ${signed_xpi}")
    else
      issues+=("extension ${installed_version} is outdated — source ${source_version} needs signing; run ${bridge_dir}/ensure.sh --help")
    fi
  fi
else
  issues+=("no default Firefox profile yet — run Firefox once, then re-login")
fi

((${#issues[@]})) || exit 0
notify-send -a "fftab-bridge" "Media bridge setup needed" "$(printf '%s\n' "${issues[@]}")" 2>/dev/null ||
  printf 'fftab-bridge: %s\n' "${issues[@]}" >&2

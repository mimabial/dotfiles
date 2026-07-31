#!/usr/bin/env bash
# Self-check for the fftab-bridge media stack. Auto-fixes what needs no user
# (native-messaging manifest, Firefox pref via user.js) and notifies whatever
# remains. Silent no-op when everything is healthy. Hooked at session start.
set -euo pipefail

# Per-host opt-out: export FFTAB_ENSURE_DISABLE=1 in env-overrides.
env_overrides="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/env-overrides"
if [[ -n "${FFTAB_ENSURE_DISABLE:-}" ]] ||
  grep -qsE '^\s*export\s+FFTAB_ENSURE_DISABLE=' "${env_overrides}"; then
  exit 0
fi

bridge_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
host_path="${bridge_dir}/host/fftab_host.py"
manifest="${HOME}/.mozilla/native-messaging-hosts/fftab_bridge.json"
ext_id="fftab-bridge@hypr.local"
issues=()

for bin in playerctl jq yt-dlp unzip; do
  command -v "${bin}" >/dev/null 2>&1 || issues+=("missing binary: ${bin} (in pkg_core.lst)")
done
python3 - <<'EOF' >/dev/null 2>&1 || issues+=("missing GI bindings: python-gobject + playerctl (in pkg_core.lst)")
import gi
gi.require_version("Playerctl", "2.0")
from gi.repository import Playerctl
EOF

[[ -x "${host_path}" ]] || chmod +x "${host_path}" 2>/dev/null || issues+=("host not executable: ${host_path}")
if ! grep -qsF "\"path\": \"${host_path}\"" "${manifest}"; then
  mkdir -p "$(dirname "${manifest}")"
  cat >"${manifest}" <<EOF2
{
  "name": "fftab_bridge",
  "description": "MPRIS bridge: one player per Firefox media tab",
  "path": "${host_path}",
  "type": "stdio",
  "allowed_extensions": ["${ext_id}"]
}
EOF2
fi

profiles_ini="${HOME}/.mozilla/firefox/profiles.ini"
profile=""
if [[ -r "${profiles_ini}" ]]; then
  profile="$(awk -F= '/^\[Install/{f=1} f && /^Default=/{print $2; exit}' "${profiles_ini}")"
fi
if [[ -n "${profile}" && -d "${HOME}/.mozilla/firefox/${profile}" ]]; then
  profile_dir="${HOME}/.mozilla/firefox/${profile}"
  userjs="${profile_dir}/user.js"
  if ! grep -qsF 'media.hardwaremediakeys.enabled' "${userjs}"; then
    printf 'user_pref("media.hardwaremediakeys.enabled", false);\n' >>"${userjs}"
    grep -qsF '"media.hardwaremediakeys.enabled", false' "${profile_dir}/prefs.js" ||
      issues+=("Firefox pref set via user.js — restart Firefox to apply")
  fi
  extension_manifest="${bridge_dir}/extension/manifest.json"
  source_version="$(jq -r '.version // empty' "${extension_manifest}" 2>/dev/null || true)"
  installed_version="$(
    jq -r --arg id "${ext_id}" \
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
    issues+=("extension not installed — open in Firefox: ${signed_xpi:-<no current signed xpi found; see README>}")
  elif [[ -n "${source_version}" && "${installed_version}" != "${source_version}" ]]; then
    if [[ -n "${signed_xpi}" ]]; then
      issues+=("extension ${installed_version} is outdated — install ${source_version}: ${signed_xpi}")
    else
      issues+=("extension ${installed_version} is outdated — source ${source_version} needs AMO signing; see README")
    fi
  fi
else
  issues+=("no default Firefox profile yet — run Firefox once, then re-login")
fi

((${#issues[@]})) || exit 0
notify-send -a "fftab-bridge" "Media bridge setup needed" "$(printf '%s\n' "${issues[@]}")" 2>/dev/null ||
  printf 'fftab-bridge: %s\n' "${issues[@]}" >&2

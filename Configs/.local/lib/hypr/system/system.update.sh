#!/usr/bin/env bash

set -euo pipefail

[[ -f /etc/arch-release ]] || exit 0

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash"
hypr_runtime_require system || exit 1

# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/pm.updates.lib.sh"

# long by default: the bar panel offers an explicit re-check for when it matters
cache_ttl="${HYPR_UPDATE_CACHE_TTL:-21600}"

hypr_help_guard "Usage: hyprshell system/system.update [up|--run-upgrade|--refresh]
Report pending updates as waybar JSON; 'up' opens an upgrade terminal.
Repeat calls inside ${cache_ttl:-900}s reuse the cached report; --refresh forces a re-check." "$@"

if aur_helper="$(get_aur_helper)"; then
  :
else
  aur_helper=""
fi
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
temp_file="${runtime_dir}/update_info"
cache_file="${runtime_dir}/update_status.json"
temp_db=""
declare -a system_update_errors=()

system_update_cleanup_temp_db() {
  local exit_code="${1:-$?}"
  if [[ -n "${temp_db}" ]]; then
    rm -rf "${temp_db}" 2>/dev/null || true
    temp_db=""
  fi
  return "${exit_code}"
}

system_update_handle_signal() {
  local signal_exit_code="$1"
  system_update_cleanup_temp_db "${signal_exit_code}"
  exit "${signal_exit_code}"
}

normalize_count() {
  [[ "${1:-0}" =~ ^[0-9]+$ ]] && printf '%s\n' "${1:-0}" || printf '0\n'
}

# Epoch of the last full -Syu, or 0 when the log says nothing.
last_full_upgrade_ts() {
  local line=""

  line="$(tac /var/log/pacman.log 2>/dev/null | grep -m1 'starting full system upgrade' || true)"
  [[ "${line}" =~ ^\[([^]]+)\] ]] && date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || printf '0\n'
}

capture_update_list() {
  local out_var="$1"
  local label="$2"
  shift 2

  local output=""
  local stderr_file=""
  local stderr_output=""
  local rc=0

  stderr_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/system-update-${label}.XXXXXX")" || return 1
  set +e
  output="$("$@" 2>"${stderr_file}")"
  rc=$?
  set -e
  stderr_output="$(<"${stderr_file}")"
  rm -f "${stderr_file}"

  printf -v "${out_var}" '%s' "${output}"

  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi

  if [[ -n "${output}" && -z "${stderr_output}" ]]; then
    return 0
  fi

  case "${rc}" in
    1 | 2)
      [[ -z "${stderr_output}" ]] && return 0
      ;;
  esac

  system_update_errors+=("${label}: ${stderr_output:-exit ${rc}}")
  [[ -n "${output}" ]] && return 0
  return 0
}

read_update_info() {
  official=0
  aur=0
  flatpak=0

  [[ -f "$temp_file" ]] || return 1

  while IFS="=" read -r key value; do
    case "$key" in
      OFFICIAL_UPDATES) official="$value" ;;
      AUR_UPDATES) aur="$value" ;;
      FLATPAK_UPDATES) flatpak="$value" ;;
    esac
  done <"$temp_file"

  official="$(normalize_count "$official")"
  aur="$(normalize_count "$aur")"
  flatpak="$(normalize_count "$flatpak")"
}

write_update_info() {
  mkdir -p "$runtime_dir"
  cat >"$temp_file" <<EOF
OFFICIAL_UPDATES=$1
AUR_UPDATES=$2
FLATPAK_UPDATES=$3
EOF
}

require_update_info() {
  [[ -f "$temp_file" ]] && return 0
  echo "No upgrade info found. Please run the script without parameters first."
  return 1
}

keep_awake_owned=0
report_refreshed=0
upgrade_lock_fd=""

# Pacman's own db.lck only catches the second transaction, and never the flatpak
# leg, so the whole upgrade runs under one lock.
acquire_upgrade_lock() {
  local lock_file=""

  lock_file="$(hypr_lock_path system_update)" || return 0
  exec {upgrade_lock_fd}>"${lock_file}" || return 0
  flock -n "${upgrade_lock_fd}" && return 0

  echo "An upgrade is already running." >&2
  return 1
}

require_free_space() {
  local required="${HYPR_UPDATE_MIN_FREE_BYTES:-$((2 * 1024 * 1024 * 1024))}"
  local available=""

  available="$(df --output=avail --block-size=1 /var/cache/pacman/pkg 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
  [[ "${available}" =~ ^[0-9]+$ ]] || return 0
  ((available >= required)) && return 0

  printf 'Only %s free where packages are cached; an upgrade needs at least %s.\n' \
    "$(numfmt --to=iec "${available}")" "$(numfmt --to=iec "${required}")" >&2
  return 1
}

prune_package_cache() {
  command -v paccache >/dev/null 2>&1 || return 0

  # The cache is the only offline downgrade path, so keep two. Pruning before the
  # upgrade is what leaves the running version with a spare.
  echo "Pruning package cache"
  sudo paccache -rk2 || echo "Could not prune the package cache." >&2
}

# Keys on disk can predate the signatures of packages pulled after a long gap.
refresh_keyring() {
  local max_age=$((30 * 86400))
  local last_upgrade=0

  last_upgrade="$(last_full_upgrade_ts)"
  if ((last_upgrade > 0)) && (($(date +%s) - last_upgrade < max_age)); then
    return 0
  fi

  # -Sy alone is a partial upgrade; the full -Syu below is what settles it.
  echo "Refreshing Arch signing keys"
  sudo pacman -Sy --noconfirm archlinux-keyring
}

# Hypridle would otherwise lock or suspend mid-transaction. A keep-awake the user
# set is theirs; only what this run turned on gets restored.
inhibit_idle() {
  idle_manual_enabled && return 0
  idle_set_manual 1 || return 0
  idle_notify_manager
  keep_awake_owned=1
}

release_idle() {
  ((keep_awake_owned)) || return 0
  keep_awake_owned=0
  idle_set_manual 0
  idle_notify_manager
}

review_orphans() {
  local -a orphans=()
  local reply=""

  mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
  ((${#orphans[@]})) || return 0

  printf '\nOrphaned packages (%s):\n' "${#orphans[@]}"
  printf '  %s\n' "${orphans[@]}"
  [[ -t 0 ]] || return 0

  read -r -p "Remove them? [y/N] " reply || reply=""
  [[ "${reply}" =~ ^[Yy] ]] || return 0
  hyprshell pm remove-orphans
}

kernel_replaced() {
  local kernel="" found=0

  for kernel in /usr/lib/modules/*/vmlinuz; do
    [[ -f "${kernel}" ]] || continue
    pacman -Qo "${kernel}" >/dev/null 2>&1 || continue
    found=1
    kernel="${kernel%/vmlinuz}"
    [[ "${kernel##*/}" == "$(uname -r)" ]] && return 1
  done

  ((found))
}

compositor_replaced() {
  local pid=""

  pid="$(pgrep -x Hyprland 2>/dev/null | head -n 1)"
  [[ -n "${pid}" ]] || return 1
  [[ "$(readlink "/proc/${pid}/exe" 2>/dev/null || true)" == *"(deleted)"* ]]
}

prompt_restart() {
  local reason="" reply=""

  if kernel_replaced; then
    reason="The kernel was replaced"
  elif compositor_replaced; then
    reason="Hyprland was replaced"
  else
    return 0
  fi

  hyprshell util/state.sh set reboot-required
  printf '\n%s; a reboot is required.\n' "${reason}"
  [[ -t 0 ]] || return 0

  read -r -p "Reboot now? [y/N] " reply || reply=""
  [[ "${reply}" =~ ^[Yy] ]] || return 0

  # A confirmed reboot never returns to the EXIT trap.
  release_idle
  exec hyprshell system/powerctl.sh reboot
}

# Re-check in place rather than dropping the cache: the bar watches this file, so
# one authoritative check here beats every bar instance racing to run its own.
refresh_report() {
  echo
  echo "Re-checking updates"
  if "${BASH_SOURCE[0]}" --refresh >/dev/null; then
    report_refreshed=1
  fi
}

upgrade_finish() {
  local exit_code=$?

  release_idle || true
  ((report_refreshed)) || rm -f "${cache_file}" 2>/dev/null || true
  return "${exit_code}"
}

run_updates() {
  trap 'upgrade_finish' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  require_update_info || return 1
  read_update_info || return 1
  require_free_space || return 1

  command -v fastfetch >/dev/null 2>&1 && fastfetch
  printf '[Official] %-10s\n[AUR]      %-10s\n[Flatpak]  %-10s\n' "$official" "$aur" "$flatpak"

  prune_package_cache
  inhibit_idle
  refresh_keyring

  if [[ -n "${aur_helper}" ]]; then
    "$aur_helper" -Syu
  else
    sudo pacman -Syu
  fi
  if pkg_installed flatpak; then
    flatpak update
  fi

  review_orphans
  refresh_report
  prompt_restart
}

if [[ "${1:-}" == "up" ]]; then
  require_update_info || exit 1
  exec hyprshell launch/terminal-present.sh --hypr-profile dialog --app-id "org.tui.SystemUpdate" --title "System Update" -- hyprshell system/system.update.sh --run-upgrade
fi

if [[ "${1:-}" == "--run-upgrade" ]]; then
  hypr_runtime_require state || exit 1
  # shellcheck source=/dev/null
  source "${BASH_SOURCE[0]%/*}/../session/idle.state.sh"
  acquire_upgrade_lock || exit 1
  run_updates
  exit $?
fi

if [[ "${1:-}" != "--refresh" ]] && [[ -s "${cache_file}" ]] \
  && (($(date +%s) - $(stat -c %Y "${cache_file}" 2>/dev/null || echo 0) < cache_ttl)) \
  && jq -e . >/dev/null 2>&1 <"${cache_file}"; then
  cat "${cache_file}"
  exit 0
fi

# Quickshell SIGKILLs this provider on reload, so the traps below never run and
# each death leaks an 8.7M pacman db copy until $XDG_RUNTIME_DIR is full.
find "${XDG_RUNTIME_DIR:-/tmp}" -maxdepth 1 -type d -name 'checkupdates_db_*' -mmin +10 \
  -exec rm -rf {} + 2>/dev/null || true
temp_db=$(mktemp -d "${XDG_RUNTIME_DIR:-"/tmp"}/checkupdates_db_XXXXXX")
trap 'system_update_cleanup_temp_db "$?"' EXIT
trap 'system_update_handle_signal 130' INT
trap 'system_update_handle_signal 143' TERM

capture_update_list ofc_list pacman pm_updates_repo_cmd "$temp_db"
ofc=$(pm_updates_count <<<"$ofc_list")

if [[ -n "${aur_helper}" ]]; then
  capture_update_list aur_list aur pm_updates_aur_cmd "${aur_helper}"
  aur=$(pm_updates_count <<<"$aur_list")
else
  aur_list=""
  aur=0
fi

if pkg_installed flatpak; then
  capture_update_list fpk_list flatpak pm_updates_flatpak_cmd
  fpk=$(pm_updates_count <<<"$fpk_list")
else
  fpk=0
  fpk_list=""
fi

upd=$((ofc + aur + fpk))

format_package_updates() {
  local update_list="${1-}"
  local line=""
  local pkg=""
  local old_ver=""
  local new_ver=""
  local body=""

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    read -r pkg old_ver _arrow new_ver <<<"$line"
    body+="  ${pkg}  ${old_ver} → ${new_ver}"$'\n'
  done <<<"$update_list"
  printf '%s' "$body"
}

format_flatpak_updates() {
  local line=""
  local app=""
  local new_ver=""
  local branch=""
  local old_ver=""
  local pkg_name=""
  local body=""

  while IFS=$'\t' read -r app new_ver branch; do
    [[ -n "$app" ]] || continue
    old_ver=$(flatpak info "$app" 2>/dev/null | awk '/Version:/ {print $2; exit}')
    old_ver="${old_ver:-installed}"
    pkg_name="${app##*.}"
    body+="  ${pkg_name}  ${old_ver} → ${new_ver}"$'\n'
  done <<<"$fpk_list"
  printf '%s' "$body"
}

format_check_errors() {
  [[ "${#system_update_errors[@]}" -gt 0 ]] || return 0
  printf '  %s\n' "${system_update_errors[@]}"
}

pango_escape() { sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g'; }

append_tooltip_section() {
  local header="$1"
  local body
  body="$(pango_escape <<<"$2")"
  [[ -n "$body" ]] || return 0
  [[ -n "$content" ]] && content+=$'\n'
  content+="<b>${header}:</b>"$'\n'"${body}"
}

build_tooltip() {
  local aur_label="${aur_helper^^}"
  local title=""
  content=""
  aur_label="${aur_label:-NONE}"
  title="<b>${upd} Updates</b>"$'\n'"  ${ofc} Official (Pacman)"$'\n'"  ${aur} AUR (${aur_label})"$'\n'"  ${fpk} Universal (Flatpak)"

  append_tooltip_section "PACMAN" "$(format_package_updates "$ofc_list")"
  append_tooltip_section "AUR" "$(format_package_updates "$aur_list")"
  append_tooltip_section "FLATPAK" "$(format_flatpak_updates)"
  append_tooltip_section "CHECK ERRORS" "$(format_check_errors)"

  printf '%s' "${title}"
  [[ -n "$content" ]] && printf '\n\n%s' "$content"
}

packages_json() {
  # "pkg old -> new [age]" lines (pacman/aur) into objects the popup can render
  jq -R -s -c 'split("\n")
    | map(select(length > 0)
      | (split(" ") | map(select(length > 0)))
      | select(length > 0)
      | (index("->") // index("\u2192")) as $arrow
      | {name: .[0],
         from: (.[1] // ""),
         to: (if $arrow then (.[$arrow + 1] // "") else (.[-1] // "") end)})' <<<"${1-}"
}

flatpak_json() {
  local body
  body="$(format_flatpak_updates)"
  jq -R -s -c 'split("\n")
    | map(select(length > 0)
      | sub("^ +"; "")
      | (split("  ") | map(select(length > 0)))
      | select(length > 0)
      | {name: .[0], from: ((.[1] // "") | split(" \u2192 ") | .[0] // ""),
         to: ((.[1] // "") | split(" \u2192 ") | .[1] // "")})' <<<"${body}"
}

errors_json() {
  local list=""
  ((${#system_update_errors[@]})) && printf -v list '%s\n' "${system_update_errors[@]}"
  jq -R -s -c 'split("\n") | map(select(length > 0))' <<<"${list}"
}

# Facts for the panel's idle state, gathered only on a real check: the payload
# they ride in is what gets cached.
system_facts_json() {
  local line upgraded=0
  line="$(tac /var/log/pacman.log 2>/dev/null | grep -m1 'starting full system upgrade' || true)"
  [[ "${line}" =~ ^\[([^]]+)\] ]] && upgraded="$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo 0)"
  jq -cn --argjson checked "$(date +%s)" \
    --argjson installed "$(pacman -Qq 2>/dev/null | wc -l)" \
    --argjson upgraded "${upgraded}" \
    '{checked: $checked, installed: $installed, upgraded: $upgraded}'
}

print_waybar_json() {
  local text="$1"
  local tooltip="$2"
  local class="${3:-}"
  local payload
  payload="$(jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    --argjson pacman "$(packages_json "${ofc_list-}")" \
    --argjson aur "$(packages_json "${aur_list-}")" \
    --argjson flatpak "$(flatpak_json)" \
    --argjson errors "$(errors_json)" \
    --argjson system "$(system_facts_json)" \
    '{text:$text, tooltip:$tooltip, class:$class,
      packages: {pacman: $pacman, aur: $aur, flatpak: $flatpak}, errors: $errors, system: $system}')"
  mkdir -p "${runtime_dir}"
  local tmp
  tmp="$(mktemp "${cache_file}.XXXXXX")"
  printf '%s\n' "${payload}" >"${tmp}" && mv -f "${tmp}" "${cache_file}" || rm -f "${tmp}"
  printf '%s\n' "${payload}"
}

write_update_info "$ofc" "$aur" "$fpk"
if [[ "${#system_update_errors[@]}" -gt 0 && "$upd" -eq 0 ]]; then
  print_waybar_json "" "$(build_tooltip)" "error"
elif [[ "${#system_update_errors[@]}" -gt 0 ]]; then
  print_waybar_json "" "$(build_tooltip)" "warning"
elif [ "$upd" -eq 0 ]; then
  print_waybar_json "" " Packages are up to date" "up-to-date"
else
  print_waybar_json "" "$(build_tooltip)" "updates"
fi

upgrade_owns_idle_inhibition=0
upgrade_report_refreshed=0
upgrade_reboot_reason=""
upgrade_lock_fd=""

# Cover the entire upgrade, not only pacman's transaction.
upgrade_acquire_lock() {
  local lock_file=""

  hypr_lock_path_into lock_file system_update || return 1
  exec {upgrade_lock_fd}>"${lock_file}" || return 1
  flock -n "${upgrade_lock_fd}" && return 0

  echo "An upgrade is already running." >&2
  return 1
}

upgrade_require_free_space() {
  local required_bytes="${HYPR_UPDATE_MIN_FREE_BYTES:-$((2 * 1024 * 1024 * 1024))}"
  local available_bytes=""

  available_bytes="$(df --output=avail --block-size=1 /var/cache/pacman/pkg 2>/dev/null | tail -n 1)"
  available_bytes="${available_bytes//[[:space:]]/}"
  [[ "${available_bytes}" =~ ^[0-9]+$ ]] || return 0
  ((available_bytes >= required_bytes)) && return 0

  printf 'Only %s free where packages are cached; an upgrade needs at least %s.\n' \
    "$(numfmt --to=iec "${available_bytes}")" "$(numfmt --to=iec "${required_bytes}")" >&2
  return 1
}

PACKAGE_CACHE_KEPT_VERSIONS=2

upgrade_prune_package_cache() {
  command -v paccache >/dev/null 2>&1 || return 0

  # Keep the running package and one fallback for offline downgrades.
  echo "Pruning package cache"
  sudo paccache -r -k "${PACKAGE_CACHE_KEPT_VERSIONS}" || echo "Could not prune the package cache." >&2
}

# Keys on disk can predate the signatures of packages pulled after a long gap.
upgrade_refresh_keyring() {
  local max_age_seconds=$((30 * 86400))
  local last_upgrade=0

  last_upgrade="$(updates_last_upgrade_epoch)"
  if ((last_upgrade > 0)) && ((EPOCHSECONDS - last_upgrade < max_age_seconds)); then
    return 0
  fi

  # Safe only because the full -Syu immediately follows.
  echo "Refreshing Arch signing keys"
  sudo pacman -Sy --noconfirm archlinux-keyring
}

# Restore keep-awake only when this run enabled it.
upgrade_inhibit_idle() {
  idle_manual_enabled && return 0
  idle_set_manual 1 || return 0
  idle_notify_manager || true
  upgrade_owns_idle_inhibition=1
}

upgrade_release_idle() {
  ((upgrade_owns_idle_inhibition)) || return 0
  upgrade_owns_idle_inhibition=0
  idle_set_manual 0
  idle_notify_manager || true
}

upgrade_review_news() {
  local news="" reply=""

  [[ -n "${update_aur_helper}" ]] || return 0
  news="$("${update_aur_helper}" -Pw 2>/dev/null)" || return 0
  [[ -n "${news}" ]] || return 0

  printf '\nArch Linux news since your last upgrade:\n%s\n' "${news}"
  [[ -t 0 ]] || return 0

  read -r -p "Continue with the upgrade? [Y/n] " reply || reply=""
  [[ ! "${reply}" =~ ^[Nn] ]]
}

upgrade_kernel_replaced() {
  local kernel="" current="" found=0
  current="$(uname -r)"

  for kernel in /usr/lib/modules/*/vmlinuz; do
    [[ -f "${kernel}" ]] || continue
    pacman -Qo "${kernel}" >/dev/null 2>&1 || continue
    found=1
    kernel="${kernel%/vmlinuz}"
    [[ "${kernel##*/}" == "${current}" ]] && return 1
  done

  ((found))
}

upgrade_compositor_replaced() {
  local pid=""

  pid="$(pgrep -xo Hyprland 2>/dev/null || true)"
  [[ -n "${pid}" ]] || return 1
  [[ "$(readlink "/proc/${pid}/exe" 2>/dev/null || true)" == *"(deleted)"* ]]
}

upgrade_flag_required_reboot() {
  if upgrade_kernel_replaced; then
    upgrade_reboot_reason="The kernel was replaced"
  elif upgrade_compositor_replaced; then
    upgrade_reboot_reason="Hyprland was replaced"
  else
    return 0
  fi

  hyprshell util/state-flags.sh set reboot-required
}

upgrade_await_close() {
  local reply=""

  [[ -t 0 ]] || return 0
  if [[ -z "${upgrade_reboot_reason}" ]]; then
    read -r -n 1 -p $'\nDone. Press any key to close.' _ || true
    return 0
  fi

  printf '\n%s; a reboot is required.\n' "${upgrade_reboot_reason}"
  IFS= read -r -p "Update complete. Type 'reboot' to restart now, or press Enter to close: " reply || reply=""
  [[ "${reply}" != reboot ]] || exec hyprshell system/powerctl.sh reboot
}

upgrade_refresh_report() {
  echo
  echo "Re-checking updates"
  if "${HYPR_LIB_DIR}/system/package-updates.sh" --refresh >/dev/null; then
    upgrade_report_refreshed=1
  fi
}

upgrade_finish() {
  local exit_code=$?

  upgrade_release_idle || true
  ((upgrade_report_refreshed)) || rm -f "${update_cache_path}" 2>/dev/null || true
  quickshell ipc call indicators refresh updates >/dev/null 2>&1 || true
  upgrade_await_close
  return "${exit_code}"
}

upgrade_run() {
  local update_source="${1:-all}"
  trap 'upgrade_finish' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  updates_require_cached_report || return 1
  local repo_update_count="" aur_update_count="" flatpak_update_count=""
  updates_read_cached_counts_into repo_update_count aur_update_count flatpak_update_count || return 1
  if [[ "${update_source}" != flatpak ]]; then
    upgrade_require_free_space || return 1
  fi

  command -v fastfetch >/dev/null 2>&1 && fastfetch
  printf '[Official] %-10s\n[AUR]      %-10s\n[Flatpak]  %-10s\n' "$repo_update_count" "$aur_update_count" "$flatpak_update_count"
  [[ "${update_source}" == flatpak ]] || upgrade_review_news || return 0

  upgrade_inhibit_idle
  case "${update_source}" in
    all | pacman)
      upgrade_prune_package_cache
      upgrade_refresh_keyring
      ;;
  esac

  "${HYPR_LIB_DIR}/system/package-manager.sh" --pm "${update_aur_helper:-pacman}" upgrade "${update_source}" || return
  upgrade_refresh_report
  [[ "${update_source}" == flatpak ]] || upgrade_flag_required_reboot
}


#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C

# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/pm.updates.lib.sh"

NO_CONFIRM=0
FORCE_PM=""

usage() {
  cat <<'HELP'
Usage: hyprshell pm [--pm yay|paru|pacman] [--noconfirm] <command> [args...]

Commands:
  add <pkg...>             Install repo packages with pacman, --needed --noconfirm
  aur-add <pkg...>         Install AUR packages with yay/paru, --needed --noconfirm
  install, i [pkg...]      Install repo packages; fzf selector when empty
  install-repo [pkg...]    Alias for install
  install-aur [pkg...]     Install AUR packages; fzf selector when empty
  remove, r [pkg...]       Remove packages; fzf selector when empty
  upgrade, u               Upgrade repo/AUR packages and Flatpaks when available
  fetch, f                 Refresh package metadata
  info, n <pkg>            Show package information
  list, l all|installed    List repo or installed packages
  la, li                   Shortcuts for list all / installed
  query, pq <pkg>          Check whether a package is installed
  file-query, fq <file>    Query the package owning a file
  count-updates, cu        Count pending repo/AUR/Flatpak updates
  list-updates, lu         List pending repo/AUR/Flatpak updates
  clean-cache              Clean package caches
  remove-orphans           Remove orphaned packages
  which                    Print selected package manager
  which-aur                Print preferred AUR helper
HELP
}

die() {
  printf '%s: %s\n' "${0##*/}" "$1" >&2
  exit 1
}

need_args() {
  (($# > 0)) || die "missing argument"
}

has() {
  command -v "$1" >/dev/null 2>&1
}

parse_flags() {
  while (($# > 0)); do
    case "$1" in
      --pm)
        (($# >= 2)) || die "missing value for --pm"
        FORCE_PM="$2"
        shift 2
        ;;
      --noconfirm | --no-confirm)
        NO_CONFIRM=1
        shift
        ;;
      -h | --help | help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown flag: $1"
        ;;
      *)
        break
        ;;
    esac
  done

  (($# > 0)) || {
    usage
    exit 0
  }
  CMD="$1"
  shift
  ARGS=("$@")
}

aur_helper() {
  [[ "${FORCE_PM}" == pacman ]] && return 1

  if [[ -n "${FORCE_PM}" && "${FORCE_PM}" != pacman ]]; then
    has "${FORCE_PM}" || die "package manager not found: ${FORCE_PM}"
    printf '%s\n' "${FORCE_PM}"
    return 0
  fi
  if has yay; then
    printf 'yay\n'
  elif has paru; then
    printf 'paru\n'
  else
    return 1
  fi
}

selected_pm() {
  if [[ -n "${FORCE_PM}" ]]; then
    has "${FORCE_PM}" || die "package manager not found: ${FORCE_PM}"
    printf '%s\n' "${FORCE_PM}"
  elif aur_helper >/dev/null; then
    aur_helper
  else
    printf 'pacman\n'
  fi
}

confirm_flags() {
  local out_name="$1"
  local -n out_ref="${out_name}"
  out_ref=()
  ((NO_CONFIRM == 1)) && out_ref+=(--noconfirm)
}

pacman_privileged() {
  if [[ -t 0 && -t 1 ]] && has sudo; then
    sudo pacman "$@"
  elif has pkexec; then
    pkexec pacman "$@"
  elif has sudo; then
    sudo pacman "$@"
  else
    die "neither sudo nor pkexec is available"
  fi
}

repo_install() {
  need_args "$@"
  local -a flags=(--needed)
  ((NO_CONFIRM == 1)) && flags+=(--noconfirm)
  pacman_privileged -S "${flags[@]}" -- "$@"
}

aur_install() {
  need_args "$@"
  local helper=""
  local -a flags=(--aur --needed)
  helper="$(aur_helper)" || die "no AUR helper found; install yay or paru"
  ((NO_CONFIRM == 1)) && flags+=(--noconfirm)
  "${helper}" -S "${flags[@]}" -- "$@"
}

remove_packages() {
  need_args "$@"
  local -a flags=()
  confirm_flags flags
  pacman_privileged -Rns "${flags[@]}" -- "$@"
}

fzf_pick() {
  local preview="$1"
  local color="$2"
  shift 2
  has fzf || die "fzf is not installed"
  fzf \
    --multi \
    --preview="${preview}" \
    --preview-window=down:65%:wrap \
    --bind=alt-p:toggle-preview \
    --bind=alt-j:preview-down,alt-k:preview-up \
    --bind=alt-d:preview-half-page-down,alt-u:preview-half-page-up \
    --color="pointer:${color},marker:${color}" \
    "$@"
}

aur_names() {
  local helper=""
  helper="$(aur_helper)" || die "no AUR helper found; install yay or paru"
  case "${helper}" in
    yay) yay -Pc | awk '{ print $1 }' ;;
    paru) paru -Slq aur ;;
  esac
}

install_repo_interactive() {
  local -a selected=()
  mapfile -t selected < <(pacman -Slq | fzf_pick 'pacman -Sii -- {1}' green)
  ((${#selected[@]} == 0)) && return 0
  NO_CONFIRM=1
  repo_install "${selected[@]}"
}

install_aur_interactive() {
  local helper=""
  local -a selected=()
  helper="$(aur_helper)" || die "no AUR helper found; install yay or paru"
  mapfile -t selected < <(
    aur_names |
      fzf_pick \
        "${helper} -Sii --aur -- {1}" \
        green \
        --bind="alt-b:change-preview:${helper} -Gp -- {1} | tail -n +5" \
        --bind="alt-B:change-preview:${helper} -Sii --aur -- {1}"
  )
  ((${#selected[@]} == 0)) && return 0
  NO_CONFIRM=1
  aur_install "${selected[@]}"
}

remove_interactive() {
  local -a selected=()
  mapfile -t selected < <(pacman -Qqe | fzf_pick 'pacman -Qi -- {1}' red)
  ((${#selected[@]} == 0)) && return 0
  remove_packages "${selected[@]}"
}

upgrade_all() {
  local helper=""
  local -a flags=()
  confirm_flags flags

  if helper="$(aur_helper)"; then
    "${helper}" -Syu "${flags[@]}"
  else
    pacman_privileged -Syu "${flags[@]}"
  fi
  has flatpak && flatpak update -y
}

fetch_metadata() {
  local helper=""
  if helper="$(aur_helper)"; then
    "${helper}" -Sy
  else
    pacman_privileged -Sy
  fi
  has flatpak && flatpak update --appstream
}

show_info() {
  need_args "$@"
  local helper=""
  if helper="$(aur_helper)"; then
    "${helper}" -Si --color=auto "$1"
  else
    pacman -Si --color=auto "$1"
  fi
}

list_packages() {
  case "${1:-}" in
    all) pacman -Sl --color=never ;;
    installed) pacman -Q --color=never ;;
    *) die "expected list scope: all or installed" ;;
  esac
}

query_package() {
  need_args "$@"
  if pacman -Q "$1" >/dev/null 2>&1; then
    printf 'Installed\n'
    return 0
  fi
  printf 'Not installed\n'
  return 1
}

file_query() {
  need_args "$@"
  pacman -F -- "$1"
}

capture_updates() {
  set +e
  "$@"
  local rc=$?
  set -e
  case "${rc}" in
    0 | 1 | 2) return 0 ;;
    *) return "${rc}" ;;
  esac
}

list_updates() {
  local helper=""
  local temp_db=""

  if has checkupdates; then
    temp_db="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pm-checkupdates.XXXXXX")"
    capture_updates pm_updates_repo_cmd "${temp_db}" |
      awk 'NF { print "pacman\t" $0 }'
    rm -rf -- "${temp_db}" >/dev/null 2>&1 || true
  fi

  if helper="$(aur_helper)"; then
    capture_updates pm_updates_aur_cmd "${helper}" | awk 'NF { print "aur\t" $0 }'
  fi

  if has flatpak; then
    capture_updates pm_updates_flatpak_cmd |
      awk 'NF { print "flatpak\t" $0 }'
  fi
}

count_updates() {
  list_updates | pm_updates_count
}

clean_cache() {
  local helper=""
  if helper="$(aur_helper)"; then
    "${helper}" -Sc
  else
    pacman_privileged -Sc
  fi
}

remove_orphans() {
  local -a orphans=()
  local -a flags=()
  mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
  ((${#orphans[@]} == 0)) && {
    printf 'No orphaned packages.\n'
    return 0
  }
  confirm_flags flags
  pacman_privileged -Rns "${flags[@]}" -- "${orphans[@]}"
}

run() {
  case "${CMD}" in
    add)
      NO_CONFIRM=1
      repo_install "${ARGS[@]}"
      ;;
    aur-add)
      NO_CONFIRM=1
      aur_install "${ARGS[@]}"
      ;;
    install | install-repo | i)
      if ((${#ARGS[@]} == 0)); then install_repo_interactive; else repo_install "${ARGS[@]}"; fi
      ;;
    install-aur)
      if ((${#ARGS[@]} == 0)); then install_aur_interactive; else aur_install "${ARGS[@]}"; fi
      ;;
    remove | r)
      if ((${#ARGS[@]} == 0)); then remove_interactive; else remove_packages "${ARGS[@]}"; fi
      ;;
    upgrade | u) upgrade_all ;;
    fetch | f) fetch_metadata ;;
    info | n) show_info "${ARGS[@]}" ;;
    list | l) list_packages "${ARGS[@]}" ;;
    la) list_packages all ;;
    li) list_packages installed ;;
    query | pq) query_package "${ARGS[@]}" ;;
    file-query | fq) file_query "${ARGS[@]}" ;;
    count-updates | cu) count_updates ;;
    list-updates | lu) list_updates ;;
    clean-cache) clean_cache ;;
    remove-orphans) remove_orphans ;;
    which) selected_pm ;;
    which-aur) aur_helper || die "no AUR helper found; install yay or paru" ;;
    help | h | -h | --help) usage ;;
    *) die "unknown command: ${CMD}" ;;
  esac
}

CMD=""
ARGS=()
parse_flags "$@"
run

#!/usr/bin/env bash
# shellcheck disable=SC2154
#|---/ /+--------------------------+---/ /|#
#|--/ /-| Main installation script |--/ /-|#
#|/ /---+--------------------------+/ /---|#

scrDir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck disable=SC1091
if ! source "${scrDir}/global_fn.sh"; then
  echo "Error: unable to source global_fn.sh..."
  exit 1
fi

flg_Install=0
flg_Restore=0
flg_Service=0
flg_DryRun=0
flg_Shell=0
flg_Nvidia=1
flg_ThemeInstall=1
flg_Lint=0

usage() {
  cat <<EOF
Usage: $0 [options] [custom-package-list]
            i : [i]nstall hyprland without configs
            d : install hyprland [d]efaults without configs --noconfirm
            r : [r]estore config files
            s : enable system [s]ervices
            n : ignore/[n]o [n]vidia actions (-irsn to ignore nvidia)
            h : re-evaluate S[h]ell
            m : no the[m]e reinstallations
            t : [t]est run without executing (-irst to dry run all)
            l : [l]int package manifests and exit

NOTE:
        running without args is equivalent to -irs
        to ignore nvidia, run -irsn

WRONG:
        install.sh -n # This will not run install/restore/service phases

EOF
}

has_action() {
  [ "${flg_Install}" -eq 1 ] || [ "${flg_Restore}" -eq 1 ] || [ "${flg_Service}" -eq 1 ]
}

run_package_lint() {
  local -a lint_args=(--availability "${scrDir}/pkg_core.lst")
  [ -n "${custom_pkg}" ] && lint_args+=("${custom_pkg}")
  run_step "lint package manifests" "${scrDir}/packaging/lint.sh" "${lint_args[@]}"
}

while getopts idrstmnhl RunStep; do
  case "${RunStep}" in
  i) flg_Install=1 ;;
  d)
    flg_Install=1
    export use_default="--noconfirm"
    ;;
  r) flg_Restore=1 ;;
  s) flg_Service=1 ;;
  n)
    export flg_Nvidia=0
    print_log -r "[nvidia] " -b "Ignored :: " "skipping Nvidia actions"
    ;;
  h)
    export flg_Shell=1
    print_log -r "[shell] " -b "Reevaluate :: " "shell options"
    ;;
  t) flg_DryRun=1 ;;
  m) flg_ThemeInstall=0 ;;
  l) flg_Lint=1 ;;
  *)
    usage
    exit 1
    ;;
  esac
done

shift $((OPTIND - 1))
custom_pkg="${1:-}"

HYDE_LOG="$(date +'%y%m%d_%Hh%Mm%Ss')"
export flg_DryRun flg_Nvidia flg_Shell flg_Install flg_Restore flg_Service flg_ThemeInstall HYDE_LOG custom_pkg

if [ "${flg_DryRun}" -eq 1 ]; then
  print_log -n "[test-run] " -b "enabled :: " "Testing without executing"
elif [ "${flg_Lint}" -ne 1 ] && [ "${OPTIND}" -eq 1 ]; then
  flg_Install=1
  flg_Restore=1
  flg_Service=1
  export flg_Install flg_Restore flg_Service
fi

if [ "${flg_Lint}" -eq 1 ]; then
  run_package_lint
  exit $?
fi

if has_action; then
  run_step "preflight checks" "${scrDir}/preflight/all.sh"
fi

if [ "${flg_Install}" -eq 1 ]; then
  run_step "hardware detection" "${scrDir}/hardware/all.sh"
fi

if [ "${flg_Install}" -eq 1 ] && [ "${flg_Restore}" -eq 1 ]; then
  run_step "pre-install config" "${scrDir}/install_pre.sh"
fi

if [ "${flg_Install}" -eq 1 ]; then
  run_step "packaging phase" "${scrDir}/packaging/all.sh" "${custom_pkg}"
fi

if [ "${flg_Restore}" -eq 1 ]; then
  run_step "restore phase" "${scrDir}/restore/all.sh"
fi

if [ "${flg_Install}" -eq 1 ] && [ "${flg_Restore}" -eq 1 ]; then
  run_step "post-install phase" "${scrDir}/post-install/all.sh"
fi

if [ "${flg_Service}" -eq 1 ]; then
  run_step "service phase" "${scrDir}/services/all.sh"
fi

if [ "${flg_Install}" -eq 1 ]; then
  echo ""
  print_log -g "Installation" " :: " "COMPLETED!"
fi

print_log -b "Log" " :: " -y "View logs at ${cacheDir}/logs/${HYDE_LOG}"

if has_action && [ "${flg_DryRun}" -ne 1 ]; then
  if [[ -z "${HYPRLAND_CONFIG:-}" || ! -f "${HYPRLAND_CONFIG}" ]]; then
    print_log -warn "Hyprland config not found! Might be a new install or upgrade."
    print_log -warn "Please reboot the system to apply new changes."
  fi

  print_log -stat "HyDE" "It is not recommended to use newly installed or upgraded HyDE without rebooting the system. Do you want to reboot the system? (y/N)"
  read -r answer

  if [[ "${answer}" == [Yy] ]]; then
    echo "Rebooting system"
    systemctl reboot
  else
    echo "The system will not reboot"
  fi
fi

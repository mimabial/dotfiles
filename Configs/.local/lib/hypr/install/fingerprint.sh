#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/install/lib/pam-authentication.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell install/fingerprint [--remove]
Set up (or remove) fingerprint authentication for PAM." "$@"

check_fingerprint_hardware() {
  if ! lsusb | grep -Eiq 'fingerprint|synaptics|goodix|elan|validity|FPC'; then
    print_auth_error "\nNo fingerprint sensor detected."
    return 1
  fi
  return 0
}

if [[ "--remove" == "${1:-}" ]]; then
  print_auth_success "Removing fingerprint scanner from authentication.\n"

  remove_pam_authentication "fingerprint" "pam_fprintd.so"

  print_auth_info "Removing fingerprint packages..."
  hyprshell pm --noconfirm remove fprintd

  print_auth_success "Fingerprint authentication has been completely removed."
else
  print_auth_success "Setting up fingerprint scanner for authentication.\n"

  print_auth_info "Installing required packages..."
  hyprshell pm add fprintd usbutils

  if ! check_fingerprint_hardware; then
    exit 1
  fi

  configure_pam_authentication "fingerprint" "pam_fprintd.so"

  print_auth_success "\nLet's setup your right index finger as the first fingerprint."
  print_auth_info "Keep moving the finger around on sensor until the process completes.\n"

  if sudo fprintd-enroll "$USER"; then
    print_auth_success "\nFingerprint enrolled successfully!"

    print_auth_info "\nNow let's verify that it's working correctly.\n"
    if fprintd-verify; then
      print_auth_success "\nPerfect! Fingerprint authentication is now configured."
      print_auth_info "You can use your fingerprint for sudo, polkit, and lock screen (Super + U, then L)."
    else
      print_auth_error "\nVerification failed. You may want to try enrolling again."
    fi
  else
    print_auth_error "\nEnrollment failed. Please try again."
    exit 1
  fi
fi

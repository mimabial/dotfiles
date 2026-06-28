#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/install/auth.common.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell install/fingerprint [--remove]
Set up (or remove) fingerprint authentication for PAM." "$@"

check_fingerprint_hardware() {
  if ! lsusb | grep -Eiq 'fingerprint|synaptics|goodix|elan|validity|FPC'; then
    print_error "\nNo fingerprint sensor detected."
    return 1
  fi
  return 0
}

setup_pam_config() {
  setup_pam_module \
    "fingerprint" \
    "pam_fprintd.so" \
    "auth    sufficient pam_fprintd.so" \
    "auth      sufficient pam_fprintd.so"
}

remove_pam_config() {
  remove_pam_module "fingerprint" "pam_fprintd.so" 'pam_fprintd\.so'
}

if [[ "--remove" == "${1:-}" ]]; then
  print_success "Removing fingerprint scanner from authentication.\n"

  # Remove PAM configuration
  remove_pam_config

  # Uninstall packages
  print_info "Removing fingerprint packages..."
  hyprshell pm --noconfirm remove fprintd

  print_success "Fingerprint authentication has been completely removed."
else
  print_success "Setting up fingerprint scanner for authentication.\n"

  # Install required packages
  print_info "Installing required packages..."
  hyprshell pm add fprintd usbutils

  if ! check_fingerprint_hardware; then
    exit 1
  fi

  # Configure PAM
  setup_pam_config

  # Enroll first fingerprint
  print_success "\nLet's setup your right index finger as the first fingerprint."
  print_info "Keep moving the finger around on sensor until the process completes.\n"

  if sudo fprintd-enroll "$USER"; then
    print_success "\nFingerprint enrolled successfully!"

    # Verify
    print_info "\nNow let's verify that it's working correctly.\n"
    if fprintd-verify; then
      print_success "\nPerfect! Fingerprint authentication is now configured."
      print_info "You can use your fingerprint for sudo, polkit, and lock screen (Super + Escape)."
    else
      print_error "\nVerification failed. You may want to try enrolling again."
    fi
  else
    print_error "\nEnrollment failed. Please try again."
    exit 1
  fi
fi

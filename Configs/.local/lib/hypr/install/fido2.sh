#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/install/auth.common.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell install/fido2 [--remove]
Set up (or remove) FIDO2 hardware-key authentication for PAM." "$@"

check_fido2_hardware() {
  tokens=$(fido2-token -L 2>/dev/null)
  if [ -z "$tokens" ]; then
    print_error "\nNo FIDO2 device detected. Please plug it in (you may need to unlock it as well)."
    return 1
  fi
  return 0
}

setup_pam_config() {
  setup_pam_module \
    "FIDO2" \
    "pam_u2f.so" \
    "auth    sufficient pam_u2f.so cue authfile=/etc/fido2/fido2" \
    "auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2"
}

remove_pam_config() {
  remove_pam_module "FIDO2" "pam_u2f.so" 'pam_u2f\.so'
}

if [[ "--remove" == "${1:-}" ]]; then
  print_success "Removing FIDO2 device from authentication.\n"

  # Remove PAM configuration
  remove_pam_config

  # Remove FIDO2 configuration
  if [ -d /etc/fido2 ]; then
    print_info "Removing FIDO2 configuration..."
    sudo rm -rf /etc/fido2
  fi

  # Uninstall packages
  print_info "Removing FIDO2 packages..."
  hyprshell pm --noconfirm remove libfido2 pam-u2f

  print_success "FIDO2 authentication has been completely removed."
else
  print_success "Setting up FIDO2 device for authentication.\n"

  # Install required packages
  print_info "Installing required packages..."
  hyprshell pm add libfido2 pam-u2f

  if ! check_fido2_hardware; then
    exit 1
  fi

  # Create the pamu2fcfg file
  if [ ! -f /etc/fido2/fido2 ]; then
    sudo mkdir -p /etc/fido2
    print_success "\nLet's setup your device by confirming on the device now."
    print_info "Touch your FIDO2 key when it lights up...\n"

    if pamu2fcfg >"${TMPDIR:-/tmp}/fido2"; then
      sudo mv "${TMPDIR:-/tmp}/fido2" /etc/fido2/fido2
      print_success "FIDO2 device registered successfully!"
    else
      print_error "\nFIDO2 registration failed. Please try again."
      exit 1
    fi
  else
    print_info "FIDO2 device already registered."
  fi

  # Configure PAM
  setup_pam_config

  # Test with sudo
  print_info "\nTesting FIDO2 authentication with sudo..."
  print_info "Touch your FIDO2 key when prompted.\n"

  if sudo echo "FIDO2 authentication test successful"; then
    print_success "\nPerfect! FIDO2 authentication is now configured."
    print_info "You can use your FIDO2 key for sudo and polkit authentication."
  else
    print_error "\nVerification failed. You may want to check your configuration."
  fi
fi

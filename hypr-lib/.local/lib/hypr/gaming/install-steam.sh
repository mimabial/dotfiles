#!/bin/bash

# Install Steam with proper multilib support
echo "Installing Steam..."

# Enable multilib if not already enabled
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling multilib repository..."
    sudo sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
    sudo pacman -Sy
fi

# Install steam and common dependencies
sudo pacman -S --needed --noconfirm steam ttf-liberation lib32-fontconfig

echo ""
echo "Steam installation complete!"
echo "Launch Steam from your application menu."

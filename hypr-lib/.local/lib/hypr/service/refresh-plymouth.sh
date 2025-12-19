#!/bin/bash

sudo cp ~/.local/share/hypr/default/plymouth/* /usr/share/plymouth/themes/hypr/
sudo plymouth-set-default-theme hypr

if command -v limine-mkinitcpio &>/dev/null; then
  sudo limine-mkinitcpio
else
  sudo mkinitcpio -P
fi

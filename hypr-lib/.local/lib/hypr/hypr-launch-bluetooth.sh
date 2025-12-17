#!/bin/bash

rfkill unblock bluetooth
exec hyprshell hypr-launch-or-focus-tui.sh bluetui

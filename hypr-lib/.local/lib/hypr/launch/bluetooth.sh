#!/bin/bash

rfkill unblock bluetooth
exec hyprshell launch/focus-tui.sh bluetui

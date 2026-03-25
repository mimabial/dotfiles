#!/bin/bash

browser=$(xdg-settings get default-web-browser)

case $browser in
google-chrome* | brave-browser* | microsoft-edge* | opera* | vivaldi* | helium-browser*) ;;
*) browser="chromium.desktop" ;;
esac

browser_exec="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' {~/.local,~/.nix-profile,/usr}/share/applications/"$browser" 2>/dev/null | head -1)"
[[ -z "${browser_exec}" ]] && browser_exec="chromium"
exec setsid uwsm-app -- "${browser_exec}" --app="$1" "${@:2}"

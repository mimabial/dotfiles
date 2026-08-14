#!/bin/bash
#
# removes a symbolic svg icon, then links the original ICON.png to ICON-symbolic.png
# nothing is checked, so it may fail on errors
echo Executa això:
echo rm "$1-symbolic.svg"
echo ln -s "$1.png" "$1-symbolic.png"

rm "$1-symbolic.svg"
ln -s "$1.png" "$1-symbolic.png"
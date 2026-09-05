#!/usr/bin/env bash
# dunst's [notification_archive] rule target.
#
# A file of its own because dunst takes the whole `script` value as the program
# path — it is expanded with wordexp(3) but never split into arguments — so
# `archive.sh add` cannot be named directly from the rule.
exec "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/notify/archive.sh" add

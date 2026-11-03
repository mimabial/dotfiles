#!/usr/bin/env bash
set -euo pipefail

rule=/etc/udev/rules.d/42-logitech-hidraw-uaccess.rules
udev_settle_timeout_seconds=5

cat >"${rule}.tmp" <<'RULES'
ACTION == "remove", GOTO="logitech_hidraw_end"
SUBSYSTEM != "hidraw", GOTO="logitech_hidraw_end"
ATTRS{idVendor}=="046d", GOTO="logitech_hidraw_uaccess"
KERNELS == "0005:046D:*", GOTO="logitech_hidraw_uaccess"
GOTO="logitech_hidraw_end"
LABEL="logitech_hidraw_uaccess"
TAG+="uaccess"
LABEL="logitech_hidraw_end"
RULES
chmod 0644 "${rule}.tmp"
mv -f "${rule}.tmp" "${rule}"
udevadm control --reload-rules
udevadm trigger --subsystem-match=hidraw --action=add
udevadm settle --timeout="${udev_settle_timeout_seconds}" || true

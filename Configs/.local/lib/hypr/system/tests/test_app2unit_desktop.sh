#!/usr/bin/env sh
set -eu

N='
'
OIFS=$IFS
RSEP=$(printf '\036')
USEP=$(printf '\037')
PSEP=$(printf '\035')
debug() { :; }
error() { printf '%s\n' "$*" >&2; }
. "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)/app2unit.desktop.sh"

ENTRY_ID=test.desktop
ENTRY_NAME=Fallback
ENTRY_LNAME=Localized
DE_ENTRY_PATH=/tmp/test.desktop
ENTRY_ICON=test-icon

check() { [ "$1" = "$2" ] || { printf 'failed: %s\n' "$3" >&2; exit 1; }; }
inject() { EXEC_RSEP_USEP=$1; shift; de_inject_fields "$@"; }
reject() {
	old_ifs=$IFS
	EXEC_RSEP_USEP="cmd${USEP}$1"
	if de_inject_fields one 2>/dev/null; then
		printf 'accepted: %s\n' "$1" >&2
		exit 1
	fi
	check "$IFS" "$old_ifs" "accepted or leaked IFS: $1"
}

LC_ALL=en_US.utf8 de_initialize_locale
check "$LCODES" 'en_US:en' locale-order
inject "cmd${USEP}--label=%c:%k"
check "$EXEC_RSEP_USEP" "cmd${USEP}--label=Localized:/tmp/test.desktop" mixed-scalars
inject "cmd${USEP}--open=%u:%c" '/tmp/日本 語'
check "$EXEC_RSEP_USEP" "cmd${USEP}--open=file:///tmp/%E6%97%A5%E6%9C%AC%20%E8%AA%9E:Localized" mixed-uri
check "$(urlencode 'mailto:user@example.com')" 'mailto:user@example.com' scheme-uri
inject "cmd${USEP}literal=%%c:%%k:%%f"
check "$EXEC_RSEP_USEP" "cmd${USEP}literal=%c:%k:%f" escaped-fields
inject "cmd${USEP}x%d%c%k%D%n%N%v%m"
check "$EXEC_RSEP_USEP" "cmd${USEP}xLocalized/tmp/test.desktop" deprecated-fields
inject "cmd${USEP}%i"
check "$EXEC_RSEP_USEP" "cmd${USEP}--icon${USEP}test-icon" icon
inject "cmd${USEP}%F" one 'two three'
check "$EXEC_RSEP_USEP" "cmd${USEP}one${USEP}two three" multi-file
inject "cmd${USEP}open=%f" one two
check "$EXEC_RSEP_USEP" "cmd${USEP}open=one${RSEP}cmd${USEP}open=two" iterations
inject "cmd${USEP}drop=%f"
check "$EXEC_RSEP_USEP" cmd empty-file
for field in 'x%i' 'x%F' '%F%d' '%f%f' '%f%u' '%' '%z'; do reject "$field"; done

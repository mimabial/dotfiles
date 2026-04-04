#!/usr/bin/env sh
# Main-argument and association resolution helpers for app2unit.
reset_main_arg_state() {
	ENTRY_ID=''
	ENTRY_ACTION=''
	ENTRY_PATH=''
	EXEC_NAME=''
	EXEC_PATH=''
}

parse_desktop_entry_ref() {
	case "$1" in
	*.desktop:*)
		IFS=':' read -r ENTRY_ID ENTRY_ACTION <<-EOA
			$1
		EOA
		;;
	*.desktop)
		ENTRY_ID=$1
		ENTRY_ACTION=''
		;;
	esac
}

resolve_desktop_entry_ref() {
	case "$ENTRY_ID" in
	*/*)
		ENTRY_PATH=$ENTRY_ID
		ENTRY_ID=${ENTRY_ID##*/}
		if [ ! -f "$ENTRY_PATH" ]; then
			error "File not found: '$ENTRY_PATH'"
			return 1
		fi
		return 0
		;;
	esac

	if ! validate_entry_id "$ENTRY_ID"; then
		error "Invalid Entry ID '$ENTRY_ID'!"
		return 1
	fi
	if ! validate_action_id "$ENTRY_ACTION"; then
		error "Invalid Entry Action ID '$ENTRY_ACTION'!"
		return 1
	fi
}

resolve_executable_ref() {
	case "$MAIN_ARG" in
	*/*)
		EXEC_PATH=$MAIN_ARG
		EXEC_NAME=${EXEC_PATH##*/}
		debug "EXEC_PATH: $EXEC_PATH" "EXEC_NAME: $EXEC_NAME"
		if [ ! -f "$EXEC_PATH" ]; then
			error "File not found: '$EXEC_PATH'"
			return 1
		fi
		if [ ! -x "$EXEC_PATH" ]; then
			error "File is not executable: '$EXEC_PATH'"
			return 1
		fi
		return 0
		;;
	esac

	EXEC_NAME=$MAIN_ARG
	debug "EXEC_NAME: $EXEC_NAME"
	if ! type "$EXEC_NAME" >/dev/null 2>&1; then
		error "Executable not found: '$EXEC_NAME'"
		return 1
	fi
}

parse_main_arg() {
	# fills some of global variables depending on main arg $1
	MAIN_ARG=$1
	reset_main_arg_state

	case "$MAIN_ARG" in
	'')
		error "Empty main argument"
		return 1
		;;
	esac
	parse_desktop_entry_ref "$MAIN_ARG"
	debug "ENTRY_ID: $ENTRY_ID" "ENTRY_ACTION: $ENTRY_ACTION"

	if [ -n "$ENTRY_ID" ]; then
		resolve_desktop_entry_ref
		return $?
	fi

	resolve_executable_ref
}

check_terminal_handler() {
	# checks terminal handler availability
	if ! command -v "$TERMINAL_HANDLER" >/dev/null; then
		error "Terminal launch requested but '$TERMINAL_HANDLER' is unavailable!"
		return 1
	fi
}

get_mime() {
	# prints mime type of file or url
	app2unit_resolve_mime=
	case "$1" in
	[a-zA-Z]*:*)
		IFS=':' read -r app2unit_resolve_scheme _rest <<-EOF
			$1
		EOF
		debug "potential scheme '$app2unit_resolve_scheme'"
		case "$app2unit_resolve_scheme" in
		*[!a-zA-Z0-9+.-]*)
			debug "not a valid scheme '$app2unit_resolve_scheme', assuming file"
			app2unit_resolve_mime=$(xdg-mime query filetype "$1")
			;;
		*) app2unit_resolve_mime=x-scheme-handler/$app2unit_resolve_scheme ;;
		esac
		;;
	*) app2unit_resolve_mime=$(xdg-mime query filetype "$1") ;;
	esac

	case "$app2unit_resolve_mime" in
	'' | 'x-scheme-handler/')
		error "Could not query mime type for '$1'"
		return 1
		;;
	*)
		debug "got mime '$app2unit_resolve_mime' for '$1'"
		printf '%s\n' "$app2unit_resolve_mime"
		return 0
		;;
	esac
}

get_assoc() {
	# prints file association for mime type
	app2unit_resolve_assoc=$(xdg-mime query default "$1")
	case "$app2unit_resolve_assoc" in
	?*.desktop)
		debug "got association '$app2unit_resolve_assoc' for mime '$1'"
		printf '%s\n' "$app2unit_resolve_assoc"
		return 0
		;;
	*)
		error "Could not query association for mime '$1'"
		return 1
		;;
	esac
}

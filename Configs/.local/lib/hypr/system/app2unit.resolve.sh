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
		exit 1
	fi
}

get_mime() {
	# prints mime type of file or url
	mime=
	case "$1" in
	[a-zA-Z]*:*)
		IFS=':' read -r scheme _rest <<-EOF
			$1
		EOF
		debug "potential scheme '$scheme'"
		case "$scheme" in
		*[!a-zA-Z0-9+.-]*)
			debug "not a valid scheme '$scheme', assuming file"
			mime=$(xdg-mime query filetype "$1")
			;;
		*) mime=x-scheme-handler/$scheme ;;
		esac
		;;
	*) mime=$(xdg-mime query filetype "$1") ;;
	esac

	case "$mime" in
	'' | 'x-scheme-handler/')
		error "Could not query mime type for '$1'"
		return 1
		;;
	*)
		debug "got mime '$mime' for '$1'"
		echo "$mime"
		return 0
		;;
	esac
}

get_assoc() {
	# prints file association for mime type
	assoc=$(xdg-mime query default "$1")
	case "$assoc" in
	?*.desktop)
		debug "got association '$assoc' for mime '$1'"
		echo "$assoc"
		return 0
		;;
	*)
		error "Could not query association for mime '$1'"
		return 1
		;;
	esac
}

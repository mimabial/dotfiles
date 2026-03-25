#!/usr/bin/env sh
# Systemd launch/unit helpers for app2unit.
gen_unit_id() {
	# generate Unit ID based on Entry ID or exec name if UNIT_ID is not already set
	# sets UNIT_ID

	if [ -z "$UNIT_ID" ]; then
		if [ -z "$UNIT_APP_SUBSTRING" ] && [ -n "${ENTRY_ID}" ]; then
			UNIT_APP_SUBSTRING=${ENTRY_ID%.desktop}
		elif [ -z "$UNIT_APP_SUBSTRING" ]; then
			UNIT_APP_SUBSTRING=${EXEC_NAME}
		fi
		if [ -n "${XDG_SESSION_DESKTOP:-}" ]; then
			UNIT_DESKTOP_SUBSTRING=${XDG_SESSION_DESKTOP}
		elif [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
			UNIT_DESKTOP_SUBSTRING=${XDG_CURRENT_DESKTOP%%:*}
		else
			UNIT_DESKTOP_SUBSTRING=NoDesktop
		fi
		# escape substrings if needed
		case "${UNIT_DESKTOP_SUBSTRING}${UNIT_APP_SUBSTRING}" in
		*[!a-zA-Z:_.]*)
			# prepend a character to shield potential . from being first
			read -r UNIT_DESKTOP_SUBSTRING UNIT_APP_SUBSTRING <<-EOL
				$(systemd-escape "A$UNIT_DESKTOP_SUBSTRING" "A$UNIT_APP_SUBSTRING")
			EOL
			# remove character
			UNIT_DESKTOP_SUBSTRING=${UNIT_DESKTOP_SUBSTRING#A}
			UNIT_APP_SUBSTRING=${UNIT_APP_SUBSTRING#A}
			;;
		esac

		RANDOM_STRING=$(random_string)
		case "$UNIT_TYPE" in
		service)
			UNIT_ID="app-${UNIT_DESKTOP_SUBSTRING}-${UNIT_APP_SUBSTRING}@${RANDOM_STRING}.service"
			;;
		scope)
			UNIT_ID="app-${UNIT_DESKTOP_SUBSTRING}-${UNIT_APP_SUBSTRING}-${RANDOM_STRING}.scope"
			;;
		*)
			error "Unsupported unit type '$UNIT_TYPE'!"
			return 1
			;;
		esac
	else
		case "$UNIT_ID" in
		*?".$UNIT_TYPE") true ;;
		*)
			error "Unit ID '$UNIT_ID' is not of type '$UNIT_TYPE'"
			return 1
			;;
		esac
	fi
	if [ "${#UNIT_ID}" -gt "254" ]; then
		error "Unit ID too long (${#UNIT_ID})!: $UNIT_ID"
		return 1
	fi
	case "$UNIT_ID" in
	.service | .scope | '')
		error "Unit ID is empty!"
		return 1
		;;
	*.service | *.scope) true ;;
	*)
		error "Invalid Unit ID '$UNIT_ID'!"
		return 1
		;;
	esac
}

randomize_unit_id() {
	# updates random string in existing UNIT_ID

	if [ -z "$RANDOM_STRING" ]; then
		debug "refusing to randomize unit ID"
		return 0
	fi
	NEW_RANDOM_STRING=$(random_string)
	debug "new random string: $NEW_RANDOM_STRING"
	UNIT_ID=${UNIT_ID%"${RANDOM_STRING}.${UNIT_TYPE}"}${NEW_RANDOM_STRING}.${UNIT_TYPE}
	#"
	RANDOM_STRING=${NEW_RANDOM_STRING}
}

systemd_run() {
	# wrapper for systemd-run
	# prepend common args
	UNIT_SLICE_ID=${UNIT_SLICE_ID:-app-graphical.slice}
	if [ -z "$UNIT_DESCRIPTION" ] && [ -n "${ENTRY_LNAME:-$ENTRY_NAME}" ] && [ -n "${ENTRY_LCOMMENT:-$ENTRY_COMMENT}" ]; then
		UNIT_DESCRIPTION="${ENTRY_LNAME:-$ENTRY_NAME} - ${ENTRY_LCOMMENT:-$ENTRY_COMMENT}"
	elif [ -z "$UNIT_DESCRIPTION" ] && [ -n "${ENTRY_LNAME:-$ENTRY_NAME}" ]; then
		UNIT_DESCRIPTION="${ENTRY_LNAME:-$ENTRY_NAME}"
	elif [ -z "$UNIT_DESCRIPTION" ] && [ -n "$EXEC_NAME" ]; then
		UNIT_DESCRIPTION=${EXEC_NAME}
	fi

	set -- \
		--slice="$UNIT_SLICE_ID" \
		--unit="$UNIT_ID" \
		--description="$UNIT_DESCRIPTION" \
		--quiet \
		--collect \
		-- "$@"

	if [ "$PART_OF_GST" = "true" ]; then
		# prepend graphical session dependency/ordering args
		set -- \
			--property=After=graphical-session.target \
			--property=PartOf=graphical-session.target \
			"$@"
	fi

	if [ -n "$ENTRY_WORKDIR" ]; then
		# prepend requested Path or samedir
		set -- "--working-directory=${ENTRY_WORKDIR}" "$@"
	else
		set -- --same-dir "$@"
	fi

	# prepend unit type-dependent args
	case "$UNIT_TYPE" in
	scope) set -- --scope "$@" ;;
	service)
		set -- --property=Type=exec --property=ExitType=cgroup "$@"
		# silence service
		case "$SILENT" in
		# silence out
		out)
			set -- --property=StandardOutput=null "$@"
			# unsilence stderr if it is inheriting
			dso=''
			dse=''
			while IFS='=' read -r key value; do
				case "$key" in
				DefaultStandardOutput) dso=$value ;;
				DefaultStandardError) dse=$value ;;
				esac
			done <<-EOF
				$(systemctl --user show --property DefaultStandardOutput --property DefaultStandardError)
			EOF
			case "$dse" in
			inherit) set -- --property=StandardError="$dso" "$@" ;;
			esac
			;;
		# silence err
		err) set -- --property=StandardError=null "$@" ;;
		# silence both
		both) set -- --property=StandardOutput=null --property=StandardError=null "$@" ;;
		esac
		;;
	esac

	debug "systemd run" "$(printf '  >%s<\n' systemd-run "$@")"

	# print args in test mode
	case "$TEST_MODE" in
	true)
		printf '%s\n' 'Command and arguments:'
		printf '  >%s<\n' systemd-run --user "$@"
		exit 0
		;;
	esac

	# silence scope output
	case "${UNIT_TYPE}_${SILENT}" in
	scope_out) exec >/dev/null ;;
	scope_err) exec 2>/dev/null ;;
	scope_both) exec >/dev/null 2>&1 ;;
	esac

	# exec
	exec systemd-run --user "$@"
}

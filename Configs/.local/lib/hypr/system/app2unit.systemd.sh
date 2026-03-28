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

systemd_effective_unit_description() {
	if [ -n "$UNIT_DESCRIPTION" ]; then
		printf '%s\n' "$UNIT_DESCRIPTION"
	elif [ -n "${ENTRY_LNAME:-$ENTRY_NAME}" ] && [ -n "${ENTRY_LCOMMENT:-$ENTRY_COMMENT}" ]; then
		printf '%s - %s\n' "${ENTRY_LNAME:-$ENTRY_NAME}" "${ENTRY_LCOMMENT:-$ENTRY_COMMENT}"
	elif [ -n "${ENTRY_LNAME:-$ENTRY_NAME}" ]; then
		printf '%s\n' "${ENTRY_LNAME:-$ENTRY_NAME}"
	elif [ -n "$EXEC_NAME" ]; then
		printf '%s\n' "$EXEC_NAME"
	fi
}

systemd_default_stderr_target() {
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
	inherit) printf '%s\n' "$dso" ;;
	esac
}

systemd_apply_service_silence() {
	case "$SILENT" in
	out)
		set -- --property=StandardOutput=null "$@"
		dse_target=$(systemd_default_stderr_target)
		case "$dse_target" in
		'') ;;
		*) set -- --property=StandardError="$dse_target" "$@" ;;
		esac
		;;
	err) set -- --property=StandardError=null "$@" ;;
	both) set -- --property=StandardOutput=null --property=StandardError=null "$@" ;;
	esac
	pack_args_usep "$@"
	SYSTEMD_RUN_ARGS_USEP=$PACKED_ARGS
}

systemd_apply_unit_type_args() {
	case "$UNIT_TYPE" in
	scope)
		pack_args_usep --scope "$@"
		;;
	service)
		systemd_apply_service_silence --property=Type=exec --property=ExitType=cgroup "$@"
		return 0
		;;
	esac
	SYSTEMD_RUN_ARGS_USEP=$PACKED_ARGS
}

systemd_maybe_print_test_command() {
	case "$TEST_MODE" in
	true)
		printf '%s\n' 'Command and arguments:'
		printf '  >%s<\n' systemd-run --user "$@"
		exit 0
		;;
	esac
}

systemd_apply_scope_output_silence() {
	case "${UNIT_TYPE}_${SILENT}" in
	scope_out) exec >/dev/null ;;
	scope_err) exec 2>/dev/null ;;
	scope_both) exec >/dev/null 2>&1 ;;
	esac
}

systemd_run() {
	# wrapper for systemd-run
	# prepend common args
	UNIT_SLICE_ID=${UNIT_SLICE_ID:-app-graphical.slice}
	UNIT_DESCRIPTION="${UNIT_DESCRIPTION:-$(systemd_effective_unit_description)}"

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

	systemd_apply_unit_type_args "$@"
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $SYSTEMD_RUN_ARGS_USEP
	IFS=$OIFS

	debug "systemd run" "$(printf '  >%s<\n' systemd-run "$@")"

	systemd_maybe_print_test_command "$@"

	systemd_apply_scope_output_silence

	# exec
	exec systemd-run --user "$@"
}

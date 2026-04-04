#!/usr/bin/env sh

N='
'
OIFS=$IFS
RSEP=$(printf '%b' '\036')
USEP=$(printf '%b' '\037')
TERMINAL_HANDLER=xdg-terminal-exec
SELF_NAME=${0##*/}

# Treat non-zero exit status from simple commands as an error
# Treat unset variables as errors when performing parameter expansion
# Disable pathname expansion
set -euf

shcat() {
	while IFS='' read -r line; do
		printf '%s\n' "$line"
	done
}

usage() {
	shcat <<-EOF
		Usage:
		  $SELF_NAME \\
		    [-h | --help]
		    [-s a|b|s|custom.slice] \\$(
			case "$SELF_NAME" in
			*-scope | *-service) true ;;
			*)
				printf '\n'
				# shellcheck disable=SC1003
				printf '    %s\n' '[-t scope|service] \'
				;;
			esac
		)
		    [{-a app_name | -u unit_id}] \\
		    [-d description] \\
		    [-S {out|err|both}] \\
		    [{-c|-C}] \\
		    [-T] \\$(
			case "$SELF_NAME" in
			*-open | *-open-scope | *-open-service) true ;;
			*)
				printf '\n'
				# shellcheck disable=SC1003
				printf '    %s\n' '[-O | --open ] \'
				;;
			esac
		)
		    [--test] \\
		    [--] $(
			case "$SELF_NAME" in
			*-open | *-open-scope | *-open-service) printf '%s\n' '{file|URL ...}' ;;
			*-term | *-terminal | *-term-scope | *-terminal-scope | *-term-service | *-terminal-service)
				printf '%s\n' '[entry-id.desktop | entry-id.desktop:action-id | command] [args ...]'
				;;
			*)
				printf '%s\n' '{entry-id.desktop | entry-id.desktop:action-id | command} [args ...]'
				;;
			esac
		)
	EOF
}

help() {
	shcat <<-EOF
		$SELF_NAME - Application launcher, file opener, default terminal launcher
		for systemd environments.

		Launches applications from Desktop Entries or arbitrary
		command lines, as systemd user scopes or services.

		$(usage)

		Options:

		  -s a|b|s|custom.slice
		    Select slice among short references:
		    a=app.slice b=background.slice s=session.slice
		    Or set slice explicitly.
		    Default and short references can be preset via APP2UNIT_SLICES env var in
		    the format above.

		  -t scope|service
		    Type of unit to launch. Can be preselected via APP2UNIT_TYPE env var and
		    if \$0 ends with '-scope' or '-service'.

		  -a app_name
		    Override substring of Unit ID representing application name.
		    Defaults to Entry ID without extension, or executable name.

		  -u unit_id
		    Override the whole Unit ID. Must match type. Defaults to recommended
		    templates:
		      app-\${desktop}-\${app_name}@\${random}.service
		      app-\${desktop}-\${app_name}-\${random}.scope

		  -d description
		    Set/override unit description. By default description is generated from
		    Entry's "Name=" and "GenericName=" keys.

	EOF
	case "$SELF_NAME" in
	*-term | *-terminal | *-term-scope | *-terminal-scope | *-term-service | *-terminal-service) true ;;
	*)
		shcat <<-EOF
			  -T
			    Force launch in terminal (${TERMINAL_HANDLER} is used). Any unknown option
			    starting with '-' after this will be passed to ${TERMINAL_HANDLER}.
			    Command may be omitted to just launch default terminal.
			    This mode can also be selected if \$0 ends with '-term' or '-terminal',
			    also optionally followed by '-scope' or '-service' unit type suffixes.

		EOF
		;;
	esac
	shcat <<-EOF
		  -S out|err|both
		    Silence stdout stderr or both.

		  -c
		    Do not add graphical-session.target dependency and ordering.
		    Also can be preset with APP2UNIT_PART_OF_GST=false.

		  -C
		    Add graphical-session.target dependency and ordering.
		    Also can be preset with APP2UNIT_PART_OF_GST=true.

	EOF
	case "$SELF_NAME" in
	*-open | *-open-scope | *-open-service) true ;;
	*)
		shcat <<-EOF
			  -O | --open (also selected by default if \$0 ends with '-open')
			    Opener mode: argument(s) are treated as file(s) or URL(s) to open.
			    Desktop Entry for them is found via xdg-mime. Only single association
			    is supported.
			    This mode can also be selected if \$0 ends with '-open', also optionally
			    followed by '-scope' or '-service' unit type suffixes.

			EOF
			;;
	esac

	shcat <<-EOF
		  --test
		    Do not run anything, print command.

		  --
		    Disambiguate command from options.

	EOF

	case "$SELF_NAME" in
	*-open | *-open-scope | *-open-service)
		shcat <<-EOF
			File(s)|URL(s):

			  Objects to query xdg-mime for associations and open. The only
			  restriction is: all given objects should have the same association.
		EOF
		;;
	*)
		shcat <<-EOF
			Desktop Entry or Command:

			  Use Desktop Entry ID, optionally suffixed with Action ID:
			    entry-id.desktop
			    entry-id.desktop:action-id
			  Arguments should be supported by Desktop Entry.

			  Or use a custom command, arguments will be passed as is.
		EOF
		;;
	esac
}

error() {
	# Print messages to stderr, send notification (only first arg) if stderr is not interactive
	printf '%s\n' "$@" >&2
	# if dunstify is installed and stderr is not a terminal, also send notification
	if [ ! -t 2 ] && command -v dunstify >/dev/null; then
		dunstify -u critical -i error -a "${SELF_NAME}" "Error" "$1"
	fi
}

message() {
	# Print messages to stdout, send notification (only first arg) if stdout is not interactive
	printf '%s\n' "$@"
	# if dunstify is installed and stdout is not a terminal, also send notification
	if [ ! -t 1 ] && command -v dunstify >/dev/null; then
		dunstify -u normal -i info -a "${SELF_NAME}" "Info" "$1"
	fi
}

check_bool() {
	case "$1" in
	true | True | TRUE | yes | Yes | YES | 1) return 0 ;;
	false | False | FALSE | no | No | NO | 0) return 1 ;;
	*)
		error "Assuming '$1' means no"
		return 1
		;;
	esac
}

# Utility function to print debug messages to stderr (or not)
if check_bool "${DEBUG-0}"; then
	debug() {
		# print each arg at new line, prefix each printed line with 'D: '
		while IFS='' read -r debug_line; do
			printf 'D: %s\n' "$debug_line"
		done <<-EOF >&2
			$(printf '%s\n' "$@")
		EOF
	}
else
	debug() { :; }
fi

# shellcheck source=/dev/null
. "$HOME/.local/lib/hypr/system/app2unit.desktop.sh"
# shellcheck source=/dev/null
. "$HOME/.local/lib/hypr/system/app2unit.systemd.sh"
# shellcheck source=/dev/null
. "$HOME/.local/lib/hypr/system/app2unit.resolve.sh"

pack_args_usep() {
	[ "$#" -gt "0" ] || return 0

	printf '%s' "$1"
	shift
	for app2unit_packed_arg in "$@"; do
		printf '%s%s' "$USEP" "$app2unit_packed_arg"
	done
}

usage_error() {
	error "$@" "$(usage)"
	exit 1
}

resolve_slice_choice() {
	for cli_resolve_choice in $UNIT_SLICE_CHOICES; do
		IFS='=' read -r cli_resolve_abbr cli_resolve_id <<-EOF
			$cli_resolve_choice
		EOF
		case "$cli_resolve_abbr" in
		"$1")
			printf '%s\n' "$cli_resolve_id"
			return 0
			;;
		esac
	done
	return 1
}

resolve_required_option_value() {
	[ -n "$2" ] || usage_error "Expected $3 for $1!"
	printf '%s' "$2"
}

resolve_allowed_option_value() {
	app2unit_option_value=$(resolve_required_option_value "$1" "$2" "$3")
	shift 3
	for app2unit_allowed_value in "$@"; do
		case "$app2unit_option_value" in
		"$app2unit_allowed_value")
			printf '%s' "$app2unit_option_value"
			return 0
			;;
		esac
	done
	usage_error "Expected $3 for $1, got '$app2unit_option_value'!"
}

resolve_exclusive_option_value() {
	app2unit_option_value=$(resolve_required_option_value "$1" "$2" "$3")
	[ -z "$5" ] || usage_error "Conflicting options: $1, $4!"
	printf '%s' "$app2unit_option_value"
}

resolve_slice_option_value() {
	app2unit_slice_value=$2
	case "$app2unit_slice_value" in
	.slice | '') usage_error "Empty slice id '$app2unit_slice_value'" ;;
	*[!a-zA-Z0-9_.-]*) usage_error "Invalid slice id '$app2unit_slice_value'" ;;
	*.slice)
		printf '%s' "$app2unit_slice_value"
		return 0
		;;
	esac

	if app2unit_resolved_slice_id=$(resolve_slice_choice "$app2unit_slice_value"); then
		printf '%s' "$app2unit_resolved_slice_id"
		return 0
	fi

	usage_error "'$app2unit_slice_value' does not point to a slice choice!" "Choices: $UNIT_SLICE_CHOICES"
}

apply_part_of_gst_flag() {
	case "$PART_OF_GST_SET" in
	true) usage_error "$1 conflicts with $2" ;;
	esac
	PART_OF_GST=$3
	PART_OF_GST_SET=true
}

resolve_default_terminal_target() {
	if app2unit_terminal_target=$(
		IFS=$USEP
		# shellcheck disable=SC2086
		set -- $TERMINAL_ARGS_USEP
		IFS=$OIFS
		unset DISPLAY WAYLAND_DISPLAY
		"$TERMINAL_HANDLER" --print-path --print-cmd='\037' "$@"
	) && case "$app2unit_terminal_target" in '/'*".desktop$N"* | '/'*'.desktop:'*"$N"*) true ;; *) false ;; esac then
		MAIN_ARG=${app2unit_terminal_target%%"$N"*}
		EXEC_RSEP_USEP=${app2unit_terminal_target#*"$N"}
		# shellcheck disable=SC2086
		debug "replaced MAIN_ARG with '$MAIN_ARG'" "populated EXEC_RSEP_USEP with:" "$(
			IFS=$USEP
			printf '  > %s\n' $EXEC_RSEP_USEP
		)"
		return 0
	fi

	{
		echo "Could not determine default terminal entry via '$TERMINAL_HANDLER --print-path --print-cmd=\037'!"
		echo "Falling back to injecting '$TERMINAL_HANDLER' as the main argument."
	} >&2
	MAIN_ARG="$TERMINAL_HANDLER"
}

parse_cli_option() {
	CLI_SHIFT=0
	case "$1" in
	-h | --help)
		help
		exit 0
		;;
	-s)
		debug "arg '$1' '${2:-}'"
		UNIT_SLICE_ID=$(resolve_slice_option_value "$1" "${2:-}")
		CLI_SHIFT=2
		;;
	-t)
		debug "arg '$1' '${2:-}'"
		UNIT_TYPE=$(resolve_allowed_option_value "$1" "${2:-}" "unit type scope|service" scope service)
		CLI_SHIFT=2
		;;
	-a)
		debug "arg '$1' '${2:-}'"
		UNIT_APP_SUBSTRING=$(resolve_exclusive_option_value "$1" "${2:-}" "app name" "-u" "$UNIT_ID")
		CLI_SHIFT=2
		;;
	-u)
		debug "arg '$1' '${2:-}'"
		UNIT_ID=$(resolve_exclusive_option_value "$1" "${2:-}" "Unit ID" "-a" "$UNIT_APP_SUBSTRING")
		CLI_SHIFT=2
		;;
	-d)
		debug "arg '$1' '${2:-}'"
		UNIT_DESCRIPTION=$(resolve_required_option_value "$1" "${2:-}" "unit description")
		CLI_SHIFT=2
		;;
	-S)
		debug "arg '$1' '${2:-}'"
		SILENT=$(resolve_allowed_option_value "$1" "${2:-}" "silent mode out|err|both" out err both)
		CLI_SHIFT=2
		;;
	-c)
		debug "arg '$1'"
		apply_part_of_gst_flag "-c" "-C" false
		CLI_SHIFT=1
		;;
	-C)
		debug "arg '$1'"
		apply_part_of_gst_flag "-C" "-c" true
		CLI_SHIFT=1
		;;
	-T)
		TERMINAL=true
		CAPTURE_TERMINAL_ARGS=true
		debug "arg '$1'"
		check_terminal_handler
		CLI_SHIFT=1
		;;
	-O | --open)
		OPENER_MODE=true
		debug "arg '$1'"
		CLI_SHIFT=1
		;;
	--test)
		TEST_MODE=true
		debug "arg '$1'"
		CLI_SHIFT=1
		;;
	--)
		debug "arg '$1', breaking"
		CLI_SHIFT=-1
		;;
	-*)
		case "$CAPTURE_TERMINAL_ARGS" in
		false) usage_error "Unknown option '$1'!" ;;
		true)
			debug "storing unknown opt '$1' for terminal"
			TERMINAL_ARGS_USEP=${TERMINAL_ARGS_USEP}${TERMINAL_ARGS_USEP:+$USEP}${1}
			CLI_SHIFT=1
			;;
		esac
		;;
	*)
		debug "arg '$1', breaking"
		return 1
		;;
	esac
	return 0
}

initialize_state() {
	debug "initial args:" "$(printf '  >%s<\n' "$@")"

	EXEC_NAME=''
	EXEC_PATH=''
	EXEC_RSEP_USEP=''
	ENTRY_PATH=''
	ENTRY_ID=''
	ENTRY_TYPE=''
	ENTRY_URL=''
	ENTRY_COMMENT=''
	ENTRY_NAME=''
	ENTRY_ICON=''
	ENTRY_WORKDIR=''
	UNIT_DESCRIPTION=''
	UNIT_ID=''
	UNIT_APP_SUBSTRING=''
	SILENT=''
	TEST_MODE=false
	EXPANDED_STR=''
	EXEC_USEP=''
	TERMINAL_ARGS_USEP=''
	MAIN_ARG=''
	PARSED_ARGS_USEP=''
	RESOLVED_ARGS_USEP=''

	UNIT_TYPE=${APP2UNIT_TYPE:-scope}
	case "$UNIT_TYPE" in
	service | scope) true ;;
		*)
			error "Unsupported unit type '$UNIT_TYPE'!"
			return 1
			;;
	esac

	UNIT_SLICE_ID=''
	UNIT_SLICE_CHOICES=${APP2UNIT_SLICES:-"a=app.slice b=background.slice s=session.slice"}
	PART_OF_GST=true
	TERMINAL=false
	OPENER_MODE=false
	CAPTURE_TERMINAL_ARGS=false
	RANDOM_STRING=
	LCODE=${LANGUAGE:-"$LANG"}
	LCODE=${LCODE%_*}
	LCODE=${LCODE:-NOLCODE}
}

configure_unit_slice_choices() {
	for CLI_SLICE_CHOICE in $UNIT_SLICE_CHOICES; do
		debug "evaluating slice choice '$CLI_SLICE_CHOICE'"
		CLI_SLICE_ABBR=
		CLI_SLICE_ID=
		case "$CLI_SLICE_CHOICE" in
		*[!a-zA-Z0-9=._-]* | *=*=* | *[!a-z]*=* | *=[!a-zA-Z0-9._-]* | *[!.][!s][!l][!i][!c][!e])
			error "Invalid slice choice '$CLI_SLICE_CHOICE', ignoring."
			continue
			;;
		[a-z]*=[a-zA-Z0-9_.-]*.slice)
			IFS='=' read -r CLI_SLICE_ABBR CLI_SLICE_ID <<-EOF
				$CLI_SLICE_CHOICE
			EOF
			;;
		*)
			error "Invalid slice choice '$CLI_SLICE_CHOICE', ignoring."
			continue
			;;
		esac
		if [ -z "$UNIT_SLICE_ID" ]; then
			UNIT_SLICE_CHOICES=
			UNIT_SLICE_ID="${CLI_SLICE_ID}"
			debug "reset default slice as '${CLI_SLICE_ID}'"
		fi
		debug "adding choice ${CLI_SLICE_ABBR}=${CLI_SLICE_ID}"
		UNIT_SLICE_CHOICES=${UNIT_SLICE_CHOICES}${UNIT_SLICE_CHOICES:+ }${CLI_SLICE_ABBR}=${CLI_SLICE_ID}
	done
	if [ -z "$UNIT_SLICE_ID" ]; then
		UNIT_SLICE_ID=app.slice
		debug "falling back to default slice 'app.slice'"
	fi
}

configure_part_of_gst() {
	if [ -z "${APP2UNIT_PART_OF_GST:-}" ]; then
		PART_OF_GST=true
	elif check_bool "$APP2UNIT_PART_OF_GST"; then
		PART_OF_GST=true
	else
		PART_OF_GST=false
	fi
}

configure_invocation_mode() {
	case "$SELF_NAME" in
	*-open | *-open-scope | *-open-service)
		OPENER_MODE=true
		case "$SELF_NAME" in
		*-scope) UNIT_TYPE=scope ;;
		*-service) UNIT_TYPE=service ;;
		esac
		;;
		*-term | *-terminal | *-term-scope | *-terminal-scope | *-term-service | *-terminal-service)
			TERMINAL=true
			CAPTURE_TERMINAL_ARGS=true
			case "$SELF_NAME" in
			*-scope) UNIT_TYPE=scope ;;
			*-service) UNIT_TYPE=service ;;
		esac
		;;
	esac
}

expand_short_args() {
	first=true
	found_delim=false
	for arg in "$@"; do
		case "$first" in
		true)
			set --
			first=false
			;;
		esac
		case "$found_delim" in
		true)
			set -- "$@" "$arg"
			continue
			;;
		esac
		case "$arg" in
		--)
			found_delim=true
			set -- "$@" "$arg"
			;;
		-[a-zA-Z][a-zA-Z]*)
			arg=${arg#-}
			while [ -n "$arg" ]; do
				cut=${arg#?}
				char=${arg%"$cut"}
				set -- "$@" "-$char"
				arg=$cut
			done
			;;
		*) set -- "$@" "$arg" ;;
		esac
	done
	EXPANDED_ARGS_USEP=$(pack_args_usep "$@")
}

parse_cli_options() {
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $1
	IFS=$OIFS

	PART_OF_GST_SET=false
	while [ "$#" -gt "0" ]; do
		parse_cli_option "$@" || break
		case "$CLI_SHIFT" in
		-1)
			shift
			break
			;;
		*)
			shift "$CLI_SHIFT"
			;;
		esac
	done

	PARSED_ARGS_USEP=$(pack_args_usep "$@")
}

resolve_open_mode_main_target() {
	if [ "$#" = "0" ]; then
		error "File(s) or URL(s) expected for open mode."
		return 1
	fi

	MAIN_ARG=
	for app2unit_open_arg in "$@"; do
		app2unit_open_mime=$(get_mime "$app2unit_open_arg")
		app2unit_open_assoc=$(get_assoc "$app2unit_open_mime")
		if [ -z "$MAIN_ARG" ]; then
			debug "setting MAIN_ARG from association for '$app2unit_open_arg': '$app2unit_open_assoc'"
			MAIN_ARG=$app2unit_open_assoc
		elif [ "$MAIN_ARG" = "$app2unit_open_assoc" ]; then
			debug "arg '$app2unit_open_arg' has the same association"
		else
			error "Can not open multiple files/URLs with different associations"
			return 1
		fi
	done
}

resolve_terminal_mode_main_target() {
	resolve_default_terminal_target
	TERMINAL=false
}

resolve_direct_main_target() {
	MAIN_ARG=$1
	shift
	RESOLVED_ARGS_USEP=$(pack_args_usep "$@")
}

resolve_main_target() {
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $1
	IFS=$OIFS

	if [ "$#" -eq "0" ] && [ "$TERMINAL" = "false" ]; then
		usage_error "Arguments expected"
	fi

	if [ "$OPENER_MODE" = "true" ]; then
		resolve_open_mode_main_target "$@"
	elif [ "$#" -eq "0" ] && [ "$TERMINAL" = "true" ]; then
		resolve_terminal_mode_main_target
	else
		resolve_direct_main_target "$@"
		parse_main_arg "$MAIN_ARG"
		return 0
	fi

	RESOLVED_ARGS_USEP=$(pack_args_usep "$@")
	parse_main_arg "$MAIN_ARG"
}

resolve_entry_context() {
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $1
	IFS=$OIFS
	ENTRY_CONTEXT_ARGS_USEP=$(pack_args_usep "$@")

	resolve_entry_path_id
	resolve_entry_path_from_id
	read_entry_context_path
	resolve_link_entry_context

	gen_unit_id
	RESOLVED_ARGS_USEP=$ENTRY_CONTEXT_ARGS_USEP
}

inject_terminal_handler_args() {
	if [ "$TERMINAL" = "true" ]; then
		debug "injected $TERMINAL_HANDLER"
		IFS=$USEP
		# shellcheck disable=SC2086
		set -- "$TERMINAL_HANDLER" $TERMINAL_ARGS_USEP "$@"
		IFS=$OIFS
	fi
	RUN_ARGS_USEP=$(pack_args_usep "$@")
}

resolve_entry_path_id() {
	[ -n "$ENTRY_PATH" ] || return 0

	make_paths
	IFS=':'
	for dir in $APPLICATIONS_DIRS; do
		if [ "$ENTRY_PATH" != "${ENTRY_PATH#"$dir"}" ]; then
			ENTRY_ID_PRE=${ENTRY_PATH#"$dir"}
			case "$ENTRY_ID_PRE" in
			*/*)
				de_replace_str "$ENTRY_ID_PRE" "/" "-"
				ENTRY_ID_PRE=$DE_REPLACED_STR
				;;
			esac
			if validate_entry_id "$ENTRY_ID_PRE"; then
				ENTRY_ID=$ENTRY_ID_PRE
			else
				error "Deduced Entry ID '$ENTRY_ID_PRE' is invalid!"
			fi
			break
		fi
	done
}

resolve_entry_path_from_id() {
	[ -n "$ENTRY_PATH" ] && return 0
	[ -n "$ENTRY_ID" ] || return 0

	make_paths
	ENTRY_PATH=$(find_entry "$ENTRY_ID")
}

read_entry_context_path() {
	[ -n "$ENTRY_PATH" ] || return 0
	read_entry_path "$ENTRY_PATH" "$ENTRY_ACTION"
}

resolve_link_entry_context() {
	[ -n "$ENTRY_URL" ] || return 0

	debug "re-parsing for Link entry URL: $ENTRY_URL"
	app2unit_link_mime=$(get_mime "$ENTRY_URL")
	app2unit_link_assoc=$(get_assoc "$app2unit_link_mime")
	ENTRY_ID=$app2unit_link_assoc
	ENTRY_CONTEXT_ARGS_USEP=$(pack_args_usep "$ENTRY_URL")
	ENTRY_URL=
	ENTRY_PATH=$(find_entry "$ENTRY_ID")
	read_entry_path "$ENTRY_PATH"
}

run_entry_command() {
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $2
	IFS=$OIFS
	inject_terminal_handler_args "$@"
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $RUN_ARGS_USEP
	IFS=$OIFS
	debug "entry $1" "$(printf '  >%s<\n' "$@")"
	systemd_run "$@"
}

execute_entry_iterations() {
	IFS=$RSEP
	first=true
	for cmd in $EXEC_RSEP_USEP; do
		if [ "$first" = "false" ]; then
			randomize_unit_id
		fi
		case "$TEST_MODE" in
		true) run_entry_command iteration "$cmd" ;;
		*) run_entry_command iteration "$cmd" & ;;
		esac
		first=false
	done
	case "$TEST_MODE" in
	false) wait ;;
	esac
}

execute_entry_target() {
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $1
	IFS=$OIFS

	de_inject_fields "$@"
	case "$EXEC_RSEP_USEP" in
	*"$RSEP"*) execute_entry_iterations ;;
	*) run_entry_command single "$EXEC_RSEP_USEP" ;;
	esac
}

execute_direct_target() {
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $1
	IFS=$OIFS
	set -- "${EXEC_PATH:-$EXEC_NAME}" "$@"
	inject_terminal_handler_args "$@"
	IFS=$USEP
	# shellcheck disable=SC2086
	set -- $RUN_ARGS_USEP
	IFS=$OIFS
	debug "command" "$(printf '  >%s<\n' "$@")"
	systemd_run "$@"
}

main() {
	initialize_state "$@"
	configure_unit_slice_choices
	configure_part_of_gst
	configure_invocation_mode
	expand_short_args "$@"
	parse_cli_options "$EXPANDED_ARGS_USEP"
	resolve_main_target "$PARSED_ARGS_USEP"
	resolve_entry_context "$RESOLVED_ARGS_USEP"
	if [ -n "$ENTRY_ID" ]; then
		execute_entry_target "$RESOLVED_ARGS_USEP"
	else
		execute_direct_target "$RESOLVED_ARGS_USEP"
	fi
}

main "$@"

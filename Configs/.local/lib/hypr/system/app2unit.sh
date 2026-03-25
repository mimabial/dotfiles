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

replace() {
	# takes $1, replaces $2 with $3
	# does it in large chunks
	# writes result to global REPLACED_STR to avoid $() newline issues

	# right part of string
	r_remainder=${1}
	REPLACED_STR=
	while [ -n "$r_remainder" ]; do
		# left part before first encounter of $2
		r_left=${r_remainder%%"$2"*}
		# append
		REPLACED_STR=${REPLACED_STR}$r_left
		case "$r_left" in
		# nothing left to cut
		"$r_remainder") break ;;
		esac
		# append replace substring
		REPLACED_STR=${REPLACED_STR}$3
		# cut remainder
		r_remainder=${r_remainder#*"$2"}
	done
}

# shellcheck source=/dev/null
. "$HOME/.local/lib/hypr/system/app2unit.desktop.sh"
# shellcheck source=/dev/null
. "$HOME/.local/lib/hypr/system/app2unit.systemd.sh"
# shellcheck source=/dev/null
. "$HOME/.local/lib/hypr/system/app2unit.resolve.sh"

########################

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

# vars for expander, tokenizer, injector output
EXPANDED_STR=''
EXEC_USEP=''
REPLACED_STR=''

UNIT_TYPE=${APP2UNIT_TYPE:-scope}
case "$UNIT_TYPE" in
service | scope) true ;;
*)
	error "Unsupported unit type '$UNIT_TYPE'!"
	exit 1
	;;
esac

# deal with unit slice choices and default
UNIT_SLICE_ID=''
UNIT_SLICE_CHOICES=${APP2UNIT_SLICES:-"a=app.slice b=background.slice s=session.slice"}
for choice in $UNIT_SLICE_CHOICES; do
	debug "evaluating slice choice '$choice'"
	slice_abbr=
	slice_id=
	case "$choice" in
	*[!a-zA-Z0-9=._-]* | *=*=* | *[!a-z]*=* | *=[!a-zA-Z0-9._-]* | *[!.][!s][!l][!i][!c][!e])
		error "Invalid slice choice '$choice', ignoring."
		continue
		;;
	[a-z]*=[a-zA-Z0-9_.-]*.slice)
		IFS='=' read -r slice_abbr slice_id <<-EOF
			$choice
		EOF
		;;
	*)
		error "Invalid slice choice '$choice', ignoring."
		continue
		;;
	esac
	if [ -z "$UNIT_SLICE_ID" ]; then
		UNIT_SLICE_CHOICES=
		UNIT_SLICE_ID="${slice_id}"
		debug "reset default slice as '${slice_id}'"
	fi
	debug "adding choice ${slice_abbr}=${slice_id}"
	UNIT_SLICE_CHOICES=${UNIT_SLICE_CHOICES}${UNIT_SLICE_CHOICES:+ }${slice_abbr}=${slice_id}
done
if [ -z "$UNIT_SLICE_ID" ]; then
	UNIT_SLICE_ID=app.slice
	debug "falling back to default slice 'app.slice'"
fi

PART_OF_GST=true
if [ -z "${APP2UNIT_PART_OF_GST:-}" ]; then
	PART_OF_GST=true
else
	if check_bool "$APP2UNIT_PART_OF_GST"; then
		PART_OF_GST=true
	else
		PART_OF_GST=false
	fi
fi

TERMINAL=false
OPENER_MODE=false

capture_terminal_args=false
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
	capture_terminal_args=true
	case "$SELF_NAME" in
	*-scope) UNIT_TYPE=scope ;;
	*-service) UNIT_TYPE=service ;;
	esac
	;;
esac

# will be set where needed
RANDOM_STRING=

LCODE=${LANGUAGE:-"$LANG"}
LCODE=${LCODE%_*}
LCODE=${LCODE:-NOLCODE}

# expand short args
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

part_of_gst_set=false
# parse args
TERMINAL_ARGS_USEP=
while [ "$#" -gt "0" ]; do
	case "$1" in
	-h | --help)
		help
		exit 0
		;;
	-s)
		debug "arg '$1' '${2:-}'"
		case "${2:-}" in
		.slice | '')
			error "Empty slice id '${2:-}'" "$(usage)"
			exit 1
			;;
		*[!a-zA-Z0-9_.-]*)
			error "Invalid slice id '$2'" "$(usage)"
			exit 1
			;;
		*.slice)
			UNIT_SLICE_ID=$2
			shift 2
			continue
			;;
		*)
			for choice in $UNIT_SLICE_CHOICES; do
				IFS='=' read -r slice_abbr slice_id <<-EOF
					$choice
				EOF
				case "$slice_abbr" in
				"$2")
					UNIT_SLICE_ID=$slice_id
					shift 2
					continue 2
					;;
				esac
			done
			error "'$2' does not point to a slice choice!" "Choices: $UNIT_SLICE_CHOICES" "$(usage)"
			exit 1
			;;
		esac
		error "Failed to parse '-s' argument" "$(usage)"
		exit 1
		;;
	-t)
		debug "arg '$1' '${2:-}'"
		case "${2:-}" in
		scope | service) UNIT_TYPE=$2 ;;
		*)
			error "Expected unit type scope|service for -t, got '${2:-}'!" "$(usage)"
			exit 1
			;;
		esac
		shift 2
		;;
	-a)
		debug "arg '$1' '${2:-}'"
		if [ -z "${2:-}" ]; then
			error "Expected app name for -a!" "$(usage)"
			exit 1
		elif [ -n "$UNIT_ID" ]; then
			error "Conflicting options: -a, -u!" "$(usage)"
			exit 1
		else
			UNIT_APP_SUBSTRING=$2
		fi
		shift 2
		;;
	-u)
		debug "arg '$1' '${2:-}'"
		if [ -z "${2:-}" ]; then
			error "Expected Unit ID for -u!" "$(usage)"
			exit 1
		elif [ -n "$UNIT_APP_SUBSTRING" ]; then
			error "Conflicting options: -u, -a!" "$(usage)"
			exit 1
		else
			UNIT_ID=$2
		fi
		shift 2
		;;
	-d)
		debug "arg '$1' '${2:-}'"
		if [ -z "${2:-}" ]; then
			error "Expected unit description for -d!" "$(usage)"
			exit 1
		else
			UNIT_DESCRIPTION="$2"
		fi
		shift 2
		;;
	-c)
		case "$part_of_gst_set" in
		true)
			error "-c conflicts with -C" "$(usage)"
			exit 1
			;;
		esac
		debug "arg '$1'"
		PART_OF_GST=false
		part_of_gst_set=true
		shift
		;;
	-C)
		case "$part_of_gst_set" in
		true)
			error "-C conflicts with -c" "$(usage)"
			exit 1
			;;
		esac
		debug "arg '$1'"
		PART_OF_GST=true
		part_of_gst_set=true
		shift
		;;
	-S)
		debug "arg '$1' '${2:-}'"
		case "${2:-}" in
		out | err | both) SILENT=$2 ;;
		*)
			error "Expected silent mode out|err|both for -S, got '${2:-}'!" "$(usage)"
			exit 1
			;;
		esac
		shift 2
		;;
	-T)
		TERMINAL=true
		capture_terminal_args=true
		debug "arg '$1'"
		check_terminal_handler
		shift
		;;
	-O | --open)
		OPENER_MODE=true
		debug "arg '$1'"
		shift
		;;
		--test)
			TEST_MODE=true
		debug "arg '$1'"
		shift
		;;
	--)
		debug "arg '$1', breaking"
		shift
		break
		;;
	-*)
		case "$capture_terminal_args" in
		false)
			error "Unknown option '$1'!" "$(usage)"
			exit 1
			;;
		true)
			debug "storing unknown opt '$1' for terminal"
			TERMINAL_ARGS_USEP=${TERMINAL_ARGS_USEP}${TERMINAL_ARGS_USEP:+$USEP}${1}
			shift
			;;
		esac
		;;
	*)
		debug "arg '$1', breaking"
		break
		;;
	esac
done

if [ "$#" -eq "0" ] && [ "$TERMINAL" = "false" ]; then
	error "Arguments expected" "$(usage)"
	exit 1
fi

if [ "$OPENER_MODE" = "true" ]; then
	if [ "$#" = "0" ]; then
		error "File(s) or URL(s) expected for open mode."
		exit 1
	fi
	MAIN_ARG=
	# determine if file or URL, get associations for MAIN_ARG
	for arg in "$@"; do
		mime=$(get_mime "$arg")
		assoc=$(get_assoc "$mime")
		if [ -z "$MAIN_ARG" ]; then
			debug "setting MAIN_ARG from association for '$arg': '$assoc'"
			MAIN_ARG=$assoc
		elif [ "$MAIN_ARG" = "$assoc" ]; then
			debug "arg '$arg' has the same association"
			true
		else
			error "Can not open multiple files/URLs with different associations"
			exit 1
		fi
	done
elif [ "$#" -eq "0" ] && [ "$TERMINAL" = "true" ]; then
	# special case for launching just terminal

	# get entry path and cmdline from terminal handler
	if path_and_cmd=$(
		IFS=$USEP
		# shellcheck disable=SC2086
		set -- $TERMINAL_ARGS_USEP
		IFS=$OIFS
		# prevent old xdg-terminal-exec from running anything
		unset DISPLAY WAYLAND_DISPLAY
		"$TERMINAL_HANDLER" --print-path --print-cmd='\037' "$@"
	) && case "$path_and_cmd" in '/'*".desktop$N"* | '/'*'.desktop:'*"$N"*) true ;; *) false ;; esac then
		# entry path and action before newline
		MAIN_ARG=${path_and_cmd%%"$N"*}
		# cmd after newline, fill exec array right away
		EXEC_RSEP_USEP=${path_and_cmd#*"$N"}
		# shellcheck disable=SC2086
		debug "initial args:" "$(printf '  >%s<\n' "$@")"
		# shellcheck disable=SC2086
		debug "replaced MAIN_ARG with '$MAIN_ARG'" "populated EXEC_RSEP_USEP with:" "$(
			IFS=$USEP
			printf '  > %s\n' $EXEC_RSEP_USEP
		)"
	else
		# issue a warning
		{
			# shellcheck disable=SC2028
			echo "Could not determine default terminal entry via '$TERMINAL_HANDLER --print-path --print-cmd=\037'!"
			echo "Falling back to injecting '$TERMINAL_HANDLER' as the main argument."
		} >&2
		MAIN_ARG="$TERMINAL_HANDLER"
	fi
	TERMINAL=false
else
	MAIN_ARG=$1
	shift
fi
parse_main_arg "$MAIN_ARG"

if [ -n "$ENTRY_PATH" ]; then
	# reverse-deduce and correct Entry ID against applications dirs
	make_paths
	IFS=':'
	for dir in $APPLICATIONS_DIRS; do
		if [ "$ENTRY_PATH" != "${ENTRY_PATH#"$dir"}" ]; then
			ENTRY_ID_PRE=${ENTRY_PATH#"$dir"}
			case "$ENTRY_ID_PRE" in
			*/*)
				replace "$ENTRY_ID_PRE" "/" "-"
				ENTRY_ID_PRE=$REPLACED_STR
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
elif [ -n "$ENTRY_ID" ]; then
	make_paths
	ENTRY_PATH=$(find_entry "$ENTRY_ID")
fi

# read and parse entry, fill ENTRY_* vars and EXEC_RSEP_USEP
if [ -n "$ENTRY_PATH" ]; then
	read_entry_path "$ENTRY_PATH" "$ENTRY_ACTION"
fi

# handle Link type URL
if [ -n "$ENTRY_URL" ]; then
	debug "re-parsing for Link entry URL: $ENTRY_URL"
	mime=$(get_mime "$ENTRY_URL")
	assoc=$(get_assoc "$mime")
	# replace initial vars and arg
	ENTRY_ID=$assoc
	set -- "$ENTRY_URL"
	ENTRY_URL=
	# re-parse new entry
	ENTRY_PATH=$(find_entry "$ENTRY_ID")
	read_entry_path "$ENTRY_PATH"
fi

# generate Unit ID as UNIT_ID
gen_unit_id

# compose and execute arguments
if [ -n "$ENTRY_ID" ]; then

	de_inject_fields "$@"

	# deal with potential multiple iterations
	case "$EXEC_RSEP_USEP" in
	*"$RSEP"*)
		IFS=$RSEP
		first=true
		for cmd in $EXEC_RSEP_USEP; do
			IFS=$USEP
			# shellcheck disable=SC2086
			set -- $cmd
			IFS=$OIFS
			case "$TERMINAL" in
			true)
				# inject terminal handler
				debug "injected $TERMINAL_HANDLER"
				IFS=$USEP
				# shellcheck disable=SC2086
				set -- "$TERMINAL_HANDLER" $TERMINAL_ARGS_USEP "$@"
				IFS=$OIFS
				;;
			esac
			debug "entry iteration" "$(printf '  >%s<\n' "$@")"
			if [ "$first" = "false" ]; then
				randomize_unit_id
			fi
			systemd_run "$@" &
			first=false
		done
		wait
		exit
		;;
	*)
		IFS=$USEP
		# shellcheck disable=SC2086
		set -- $EXEC_RSEP_USEP
		IFS=$OIFS
		case "$TERMINAL" in
		true)
			# inject terminal handler
			debug "injected $TERMINAL_HANDLER"
			IFS=$USEP
			# shellcheck disable=SC2086
			set -- "$TERMINAL_HANDLER" $TERMINAL_ARGS_USEP "$@"
			IFS=$OIFS
			;;
		esac
		debug "entry single" "$(printf '  >%s<\n' "$@")"
		systemd_run "$@"
		;;
	esac
else
	set -- "${EXEC_PATH:-$EXEC_NAME}" "$@"
	IFS=$OIFS
	case "$TERMINAL" in
	true)
		# inject terminal handler
		debug "injected $TERMINAL_HANDLER"
		IFS=$USEP
		# shellcheck disable=SC2086
		set -- "$TERMINAL_HANDLER" $TERMINAL_ARGS_USEP "$@"
		IFS=$OIFS
		;;
	esac
	debug "command" "$(printf '  >%s<\n' "$@")"
	systemd_run "$@"
fi

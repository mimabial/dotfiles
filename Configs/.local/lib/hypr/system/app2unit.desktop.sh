#!/usr/bin/env sh
# Desktop entry parsing helpers for app2unit.
make_paths() {
	# constructs normalized APPLICATIONS_DIRS
	IFS=':'
	APPLICATIONS_DIRS=''
	# Populate list of directories to search for entries in, in descending order of preference
	for dir in ${XDG_DATA_HOME:-${HOME}/.local/share}${IFS}${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
		# Normalise base path and append the data subdirectory with a trailing '/'
		APPLICATIONS_DIRS=${APPLICATIONS_DIRS:+${APPLICATIONS_DIRS}${IFS}}${dir%/}/applications/
	done
}
# Mask IFS change
alias make_paths='IFS= make_paths'

find_entry() {
	# finds entry by ID
	ENTRY_ID=$1

	# start assembling find args
	set --
	OIFS=$IFS
	IFS=':'

	# Append application directory paths to be searched
	IFS=':'
	for directory in $APPLICATIONS_DIRS; do
		# Append '.' to delimit start of Entry ID
		set -- "$@" "$directory".
	done

	# Find all files
	set -- "$@" -type f

	# Append path conditions per directory
	or_arg=''
	for directory in $APPLICATIONS_DIRS; do
		# Match full path with proper first character of Entry ID and .desktop extension
		# Reject paths with invalid characters in Entry ID
		set -- "$@" ${or_arg} '(' -path "$directory"'./[a-zA-Z0-9_]*.desktop' ! -path "$directory"'./*[^a-zA-Z0-9_./-]*' ')'
		or_arg='-o'
	done

	# iterate over found paths
	IFS=$OIFS
	while read -r entry_path <&3; do
		# raw drop or parse and separate data dir path from entry
		case "$entry_path" in
		# empties, just in case
		'' | */./) continue ;;
		# subdir, also replace / with -
		*/./*/*)
			replace "${entry_path#*/./}" "/" "-"
			entry_id=$REPLACED_STR
			;;
		# normal separation
		*/./*) entry_id=${entry_path#*/./} ;;
		esac
		# check ID
		case "$entry_id" in
		"$ENTRY_ID")
			printf '%s' "$entry_path"
			return 0
			;;
		esac
	done 3<<-EOP
		$(find -L "$@" 2>/dev/null)
	EOP

	error "Could not find entry '$ENTRY_ID'!"
	return 1
}
alias find_entry='IFS= find_entry'

de_expand_str() {
	# expands \s, \n, \t, \r, \\
	# https://specifications.freedesktop.org/desktop-entry-spec/latest/value-types.html
	# writes result to global $EXPANDED_STR in place to avoid $() expansion newline issues
	debug "expander received: $1"
	EXPANDED_STR=
	exp_remainder=$1
	while [ -n "$exp_remainder" ]; do
		# left is substring of remainder before the first encountered backslash
		exp_left=${exp_remainder%%\\*}

		# append left to EXPANDED_STR
		EXPANDED_STR=${EXPANDED_STR}${exp_left}
		debug "expander appended: $exp_left"

		case "$exp_left" in
		"$exp_remainder")
			debug "expander ended: $EXPANDED_STR"
			# no more backslashes left
			break
			;;
		esac

		# remove left substring and backslash from remainder
		exp_remainder=${exp_remainder#"$exp_left"\\}

		case "$exp_remainder" in
		# expand and append to EXPANDED_STR
		s*)
			EXPANDED_STR=${EXPANDED_STR}' '
			exp_remainder=${exp_remainder#?}
			debug "expander substituted space"
			;;
		n*)
			EXPANDED_STR=${EXPANDED_STR}$N
			exp_remainder=${exp_remainder#?}
			debug "expander substituted newline"
			;;
		t*)
			EXPANDED_STR=${EXPANDED_STR}'	'
			exp_remainder=${exp_remainder#?}
			debug "expander substituted tab"
			;;
		r*)
			EXPANDED_STR=${EXPANDED_STR}$(printf '%b' '\r')
			exp_remainder=${exp_remainder#?}
			debug "expander substituted caret return"
			;;
		\\*)
			EXPANDED_STR=${EXPANDED_STR}\\
			exp_remainder=${exp_remainder#?}
			debug "expander substituted backslash"
			;;
		# unsupported sequence, reappend backslash
		#*)
		#	EXPANDED_STR=${EXPANDED_STR}\\
		#	debug 'expander reappended backslash'
		#	;;
		esac
	done
}

de_tokenize_exec() {
	# Shell-based DE Exec string tokenizer.
	# https://specifications.freedesktop.org/desktop-entry-spec/latest/exec-variables.html
	# How hard can it be?
	# Fills global EXEC_USEP var with $USEP-separated command array in place to avoid $() expansion newline issues
	debug "tokenizer received: $1"
	EXEC_USEP=
	tok_remainder=$1
	tok_quoted=0
	tok_in_space=0
	while [ -n "$tok_remainder" ]; do
		# left is substring of remainder before the first encountered special char
		tok_left=${tok_remainder%%[[:space:]\"\`\$\\\'\>\<\~\|\&\;\*\?\#\(\)]*}

		# left should be safe to append right away
		EXEC_USEP=${EXEC_USEP}${tok_left}
		debug "tokenizer appended: >$tok_left<"

		# end of the line
		case "$tok_remainder" in
		"$tok_left")
			debug "tokenizer is out of special chars"
			break
			;;
		esac

		# isolate special char
		tok_remainder=${tok_remainder#"$tok_left"}
		cut=${tok_remainder#?}
		tok_char=${tok_remainder%"$cut"}
		unset cut
		# cut it from remainder
		tok_remainder=${tok_remainder#"$tok_char"}

		# check if still in space
		case "${tok_in_space}${tok_left}${tok_char}" in
		1[[:space:]])
			debug "tokenizer still in space :) skipping space character"
			continue
			;;
		1*)
			debug "tokenizer no longer in space :("
			tok_in_space=0
			;;
		esac

		## decide what to do with the character
		# doublequote while quoted
		case "${tok_quoted}${tok_char}" in
		'1"')
			tok_quoted=0
			debug "tokenizer closed double quotes"
			continue
			;;
		# doublequote while unquoted
		'0"')
			tok_quoted=1
			debug "tokenizer opened double quotes"
			continue
			;;
		# error out on unquoted special chars
		0[\`\$\\\'\>\<\~\|\&\;\*\?\#\(\)])
			error "${ENTRY_ID}: Encountered unquoted character: '$tok_char'"
			return 1
			;;
		# error out on quoted but unescaped chars
		1[\`\$])
			error "${ENTRY_ID}: Encountered unescaped quoted character: '$tok_char'"
			return 1
			;;
		# process quoted escapes
		1\\)
			case "$tok_remainder" in
			# if there is no next char, fail
			'')
				error "${ENTRY_ID}: Dangling backslash encountered!"
				return 1
				;;
			# cut and append the next char right away
			# or a half of multibyte char, the other half should go into the next
			# 'tok_left' hopefully...
			*)
				cut=${tok_remainder#?}
				tok_char=${tok_remainder%"$cut"}
				tok_remainder=${cut}
				unset cut
				EXEC_USEP=${EXEC_USEP}${tok_char}
				debug "tokenizer appended escaped: >$tok_char<"
				;;
			esac
			;;
		# Consider Cosmos
		0[[:space:]])
			case "${tok_remainder}" in
			# there is non-space to follow
			*[![:space:]]*)
				# append separator
				EXEC_USEP=${EXEC_USEP}${USEP}
				tok_in_space=1
				debug "tokenizer entered spaaaaaace!!!! separator appended"
				;;
			# ignore unquoted space at the end of string
			*)
				debug "tokenizer entered outer spaaaaaace!!!! separator skipped, this is the end"
				break
				;;
			esac
			;;
		# append quoted chars
		1[[:space:]\'\>\<\~\|\&\;\*\?\#\(\)])
			EXEC_USEP=${EXEC_USEP}${tok_char}
			debug "tokenizer appended quoted char: >$tok_char<"
			;;
		# this should not happen
		*)
			error "${ENTRY_ID}: parsing error at char '$tok_char', (quoted: $tok_quoted)"
			return 1
			;;
		esac
	done
	case "$tok_quoted" in
	1)
		error "${ENTRY_ID}: Double quote was not closed!"
		return 1
		;;
	esac
	# shellcheck disable=SC2086
	debug "tokenizer ended:" "$(
		IFS=$USEP
		printf '  >%s<\n' $EXEC_USEP
	)"
}

de_inject_fields() {
	# Operates on argument array and $EXEC_RSEP_USEP from entry
	# modifies $EXEC_RSEP_USEP according to args/fields
	# no arguments, erase fields from $EXEC_RSEP_USEP
	exec_usep=''
	fu_found=false
	exec_iter_usep=''
	IFS=$USEP
	for arg in $EXEC_RSEP_USEP; do
		case "$arg" in
		# treat file fields
		*[!%]'%'[fFuU]* | '%'[fFuU]*)
			case "$fu_found" in
			true)
				error "${ENTRY_ID}: Encountered more than one %[fFuU] field!"
				return 1
				;;
			esac
			fu_found=true
			if [ "$#" -eq "0" ]; then
				debug "injector removed '$arg'"
				continue
			fi
			case "$arg" in
			*[!%]'%F'* | *'%F'?* | *[!%]'%U'* | *'%U'?*)
				error "${ENTRY_ID}: Encountered non-standalone field '$arg'"
				return 1
				;;
			*[!%]'%f'* | '%f'*)
				for carg in "$@"; do
					replace "$arg" "%f" "$carg"
					carg=$REPLACED_STR
					debug "injector adding '$arg' iteration as '$carg'"
					exec_iter_usep=${exec_iter_usep}${exec_iter_usep:+$USEP}${carg}
				done
				# placeholder arg
				exec_usep=${exec_usep}${exec_usep:+$USEP}%%__ITER__%%
				;;
			'%F')
				for carg in "$@"; do
					debug "injector extending '$arg' with '$carg'"
					exec_usep=${exec_usep}${exec_usep:+$USEP}${carg}
				done
				;;
			*[!%]'%u'* | '%u'*)
				for carg in "$@"; do
					carg=$(urlencode "$carg")
					replace "$arg" "%u" "$carg"
					carg=$REPLACED_STR
					debug "injector adding '$arg' iteration as '$carg'"
					exec_iter_usep=${exec_iter_usep}${exec_iter_usep:+$USEP}${carg}
				done
				# placeholder arg
				exec_usep=${exec_usep}${exec_usep:+$USEP}%%__ITER__%%
				;;
			'%U')
				for carg in "$@"; do
					carg=$(urlencode "$carg")
					debug "injector extending '$arg' with '$carg'"
					exec_usep=${exec_usep}${exec_usep:+$USEP}${carg}
				done
				;;
			*) error "${ENTRY_ID}: not implemented '$arg'" ;;
			esac
			;;
		# icon field
		*[!%]'%i'* | '%i'*)
			if [ -n "$ENTRY_ICON" ]; then
				replace "$arg" "%i" "$ENTRY_ICON"
				rarg=$REPLACED_STR
				debug "injector replacing '%i': '$arg' -> '$rarg'"
				exec_usep=${exec_usep}${exec_usep:+$USEP}${rarg}
			else
				debug "injector removed '$arg'"
			fi
			;;
		# name field
		*[!%]'%c'* | '%c'*)
			replace "$arg" "%c" "$ENTRY_NAME"
			rarg=$REPLACED_STR
			debug "injector replacing '%c': '$arg' -> '$rarg'"
			exec_usep=${exec_usep}${exec_usep:+$USEP}${rarg}
			;;
		# literal %
		*[!%]%%* | %%*)
			replace "$arg" "%%" "%"
			rarg=$REPLACED_STR
			debug "injector replacing '%%': '$arg' -> '$rarg'"
			exec_usep=${exec_usep}${exec_usep:+$USEP}${rarg}
			;;
		# invalid field
		*%?* | *[!%]%)
			error "${ENTRY_ID}: unknown % field in argument '${arg}'"
			return 1
			;;
		*)
			debug "injector keeped: '$arg'"
			exec_usep=${exec_usep}${exec_usep:+$USEP}${arg}
			;;
		esac
	done
	# fill EXEC_RSEP_USEP with argument iterations
	if [ -n "$exec_iter_usep" ]; then
		EXEC_RSEP_USEP=''
		for arg in $exec_iter_usep; do
			replace "$exec_usep" "%%__ITER__%%" "$arg"
			cmd=$REPLACED_STR
			EXEC_RSEP_USEP=${EXEC_RSEP_USEP}${EXEC_RSEP_USEP:+$RSEP}${cmd}
		done
	else
		EXEC_RSEP_USEP=$exec_usep
	fi
	IFS=$OIFS
}

parse_entry_key() {
	# set global vars or fail entry
	key=$1
	value=$2
	action=$3
	read_exec=$4
	in_main=$5
	in_action=$6

	case "${in_action};${key}" in
	'false;'* | 'true;Name' | 'true;Name['*']' | 'true;Exec' | 'true;Icon') true ;;
	*)
		error "${ENTRY_ID}: Encountered '$key' key inside action!"
		return 1
		;;
	esac

	case "$key" in
	Type)
		debug "captured '$key' '$value'"
		case "$value" in
		Application | Link) ENTRY_TYPE=$value ;;
		*)
			error "${ENTRY_ID}: Unsupported type '$value'!"
			return 1
			;;
		esac
		;;
	Actions)
		# `It is not valid to have an action group for an action identifier not mentioned in the Actions key.
		# Such an action group must be ignored by implementors.`
		# ignore if no action requested
		[ -z "$action" ] && return 0
		debug "checking for '$action' in Actions '$value'"
		IFS=';'
		for check_action in $value; do
			case "$check_action" in
			"$action")
				action_listed=true
				return 0
				;;
			esac
		done
		error "${ENTRY_ID}: Action '$action' is not listed in entry!"
		return 1
		;;
	TryExec)
		debug "checking TryExec executable '$value'"
		de_expand_str "$value"
		value=$EXPANDED_STR
		if ! type "$value" >/dev/null 2>&1; then
			error "${ENTRY_ID}: TryExec '$value' failed!"
			return 1
		fi
		;;
	Hidden)
		debug "checking boolean Hidden '$value'"
		case "$value" in
		true)
			error "${ENTRY_ID}: Entry is Hidden"
			return 1
			;;
		esac
		;;
	Exec)
		case "$read_exec" in
		false)
			debug "ignored Exec from wrong section"
			return 0
			;;
		esac
		case "$in_action" in
		true) action_exec=true ;;
		esac
		debug "read Exec '$value'"
		# skip actual reading if array is already filled
		if [ -n "$EXEC_RSEP_USEP" ]; then
			debug "skipping re-filling exec array"
			return 0
		fi
		# expand string-level escape sequences
		de_expand_str "$value"
		# Split Exec and save as string delimited by unit separator
		de_tokenize_exec "$EXPANDED_STR"
		EXEC_RSEP_USEP=$EXEC_USEP
		# get Exec[0]
		IFS=$USEP read -r exec0 _rest <<-EOCMD
			$EXEC_RSEP_USEP
		EOCMD
		case "$exec0" in
		'')
			error "${ENTRY_ID}: Could not extract Exec[0]!"
			return 1
			;;
		*/*)
			EXEC_NAME=${exec0##*/}
			EXEC_PATH=${exec0}
			;;
		*) EXEC_NAME=${exec0} ;;
		esac
		debug "checking Exec[0] executable '${EXEC_PATH:-$EXEC_NAME}'"
		if ! type "${EXEC_PATH:-$EXEC_NAME}" >/dev/null 2>&1; then
			error "${ENTRY_ID}: Exec command '${EXEC_PATH:-$EXEC_NAME}' not found"
			return 1
		fi
		;;
	URL)
		debug "captured '$key' '$value'"
		de_expand_str "$value"
		ENTRY_URL=$EXPANDED_STR
		;;
	"Name[${LCODE}]")
		case "${in_main}_${in_action}" in
		true_false)
			debug "captured '$key' '$value'"
			de_expand_str "$value"
			ENTRY_LNAME=$EXPANDED_STR
			;;
		false_true)
			debug "captured '$key' '$value'"
			de_expand_str "$value"
			ENTRY_LNAME_ACTION=$EXPANDED_STR
			;;
		*) debug "discarded '$key' '$value'" ;;
		esac
		;;
	Name)
		case "${in_main}_${in_action}" in
		true_false)
			debug "captured '$key' '$value'"
			de_expand_str "$value"
			ENTRY_NAME=$EXPANDED_STR
			;;
		false_true)
			debug "captured '$key' '$value'"
			de_expand_str "$value"
			ENTRY_NAME_ACTION=$EXPANDED_STR
			;;
		*) debug "discarded '$key' '$value'" ;;
		esac
		;;
	"GenericName[${LCODE}]")
		debug "captured '$key' '$value'"
		de_expand_str "$value"
		ENTRY_LCOMMENT=$EXPANDED_STR
		;;
	GenericName)
		debug "captured '$key' '$value'"
		de_expand_str "$value"
		ENTRY_COMMENT=$EXPANDED_STR
		;;
	Icon)
		if [ "$in_main" = "true" ] || [ "$in_action" = "true" ]; then
			debug "captured '$key' '$value'"
			de_expand_str "$value"
			ENTRY_ICON=$EXPANDED_STR
		else
			debug "discarded '$key' '$value'"
		fi
		;;
	Path)
		debug "captured '$key' '$value'"
		de_expand_str "$value"
		ENTRY_WORKDIR=$EXPANDED_STR
		if [ ! -e "$ENTRY_WORKDIR" ]; then
			error "${ENTRY_ID}: Requested 'Path' '${ENTRY_WORKDIR}' does not exist!"
			return 1
		elif [ ! -d "$ENTRY_WORKDIR" ]; then
			error "${ENTRY_ID}: Requested 'Path' '${ENTRY_WORKDIR}' is not a directory!"
			return 1
		fi
		;;
		Terminal)
			debug "captured '$key' '$value'"
			case "$value" in
			true)
			# if terminal was not requested explicitly, check terminal handler
			case "$TERMINAL" in
			false) check_terminal_handler ;;
			esac
			TERMINAL=true
			;;
		esac
		;;
	esac
	# By default unrecognised keys, empty lines and comments get ignored
}
# Mask IFS within function to allow temporary changes
alias parse_entry_key='IFS= parse_entry_key'

read_entry_path() {
	# Read entry from given path
	entry_path="$1"
	entry_action="${2-}"
	read_exec=false
	action_listed=false
	in_main=false
	in_action=false
	action_exec=false
	break_on_next_section=false
	# shellcheck disable=SC2016
	debug "reading desktop entry '$entry_path'${entry_action:+ action '$entry_action'}"
	# Let `read` trim leading/trailing whitespace from the line
	while read -r line; do
		case $line in
		# `There should be nothing preceding [the Desktop Entry group] in the desktop entry file but [comments]`
		# if entry_action is not requested, allow reading Exec right away from the main group
		'[Desktop Entry]'*)
			debug "entered section: $line"
			in_main=true
			if [ -z "$entry_action" ]; then
				read_exec=true
				break_on_next_section=true
			fi
			;;
		# A `Key=Value` pair
		[a-zA-Z0-9-]*=*)
			# Split
			IFS='=' read -r key value <<-EOL
				$line
			EOL
			# Trim
			{ read -r key && read -r value; } <<-EOL
				$key
				$value
			EOL
			# Parse key, or abort
			parse_entry_key "$key" "$value" "$entry_action" "$read_exec" "$in_main" "$in_action" || return 1
			;;
		# found requested action, allow reading Exec
		"[Desktop Action ${entry_action}]"*)
			debug "entered section: $line"
			in_main=false
			break_on_next_section=true
			case "$action_listed" in
			true)
				read_exec=true
				in_action=true
				;;
			*)
				error "${ENTRY_ID}: Action '$entry_action' is not listed in Actions key!"
				return 1
				;;
			esac
			;;
		# Start of the next group header, stop if already read exec
		'['*)
			debug "entered section: $line"
			[ "$break_on_next_section" = "true" ] && break
			in_main=false
			in_action=false
			read_exec=false
			;;
		esac
		# By default empty lines and comments get ignored
	done <"$entry_path"

	# check for required things for action
	if [ -n "$entry_action" ]; then
		case "$action_listed" in
		true) true ;;
		*)
			error "${ENTRY_ID}: Action '$entry_action' is not listed in Actions key or does not exist!"
			return 1
			;;
		esac
		if [ "$action_exec" != "true" ] || [ -z "${ENTRY_LNAME_ACTION:-$ENTRY_NAME_ACTION}" ]; then
			error "${ENTRY_ID}: Action '$entry_action' is incomplete"
			return 1
		fi
	fi

	# check for required things for types
	case "${ENTRY_TYPE};;${EXEC_RSEP_USEP};;${ENTRY_URL}" in
	'Application;;'?*';;' | 'Link;;;;'?*) true ;;
	';;'*)
		error "${ENTRY_ID}: type not specified!"
		return 1
		;;
	*)
		error "${ENTRY_ID}: type and keys mismatch: '$ENTRY_TYPE', Exec is$([ -z "${EXEC_RSEP_USEP}" ] && echo ' not') set, URL is$([ -z "${ENTRY_URL}" ] && echo ' not') set"
		return 1
		;;
	esac
}

random_string() {
	# gets random 8 hex characters
	tr -dc '0-9a-f' </dev/urandom 2>/dev/null | head -c 8
}

validate_entry_id() {
	# validates Entry ID ($1)

	case "$1" in
	# invalid characters or degrees of emptiness
	*[!a-zA-Z0-9_.-]* | *[!a-zA-Z0-9_.-] | [!a-zA-Z0-9_.-]* | [!a-zA-Z0-9_.-] | '' | .desktop)
		debug "string not valid as Entry ID: '$1'"
		return 1
		;;
	# all that left with .desktop
	*.desktop) return 0 ;;
	# and without
	*)
		debug "string not valid as Entry ID '$1'"
		return 1
		;;
	esac
}

validate_action_id() {
	# validates action ID ($1)

	case "$1" in
	# empty is ok
	'') return 0 ;;
	# invalid characters
	*[!a-zA-Z0-9-]* | *[!a-zA-Z0-9-] | [!a-zA-Z0-9-]* | [!a-zA-Z0-9-])
		debug "string not valid as Action ID: '$1'"
		return 1
		;;
	# all that left
	*) return 0 ;;
	esac
}

urlencode() {
	string=$1
	case "$string" in
	# assuming already url
	*[a-zA-Z0-9_-]://*)
		echo "$string"
		return
		;;
	# assuming absolute path
	/*) true ;;
	# assuming relative path
	*) string=$(pwd)/$string ;;
	esac

	printf '%s' 'file://'

	case "$string" in
	# if contains extra chars, encode
	*[!._~0-9A-Za-z/-]*)
		while [ -n "$string" ]; do
			right=${string#?}
			char=${string%"$right"}
			debug "urlencode string $string" "urlencode right $right" "urlencode char $char"
			case $char in
			[._~0-9A-Za-z/-]) printf '%s' "$char" ;;
			*) printf '%%%02x' "'$char" ;;
			esac
			string=$right
		done
		;;
	*) printf '%s' "$string" ;;
	esac
}

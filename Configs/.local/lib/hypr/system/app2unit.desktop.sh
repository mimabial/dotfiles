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
alias make_paths='IFS= make_paths'

find_entry() {
	ENTRY_ID=$1
	IFS=$OIFS
	set --
	IFS=':'
	for directory in $APPLICATIONS_DIRS; do
		set -- "$@" "$directory".
	done

	set -- "$@" -type f
	de_find_or_arg=''
	for directory in $APPLICATIONS_DIRS; do
		set -- "$@" ${de_find_or_arg} '(' -path "$directory"'./[a-zA-Z0-9_]*.desktop' ! -path "$directory"'./*[^a-zA-Z0-9_./-]*' ')'
		de_find_or_arg='-o'
	done
	IFS=$OIFS

	while read -r entry_path <&3; do
		case "$entry_path" in
		'' | */./) continue ;;
		*/./*/*)
			de_replace_str "${entry_path#*/./}" "/" "-"
			de_found_entry_id=$DE_REPLACED_STR
			;;
		*/./*)
			de_found_entry_id=${entry_path#*/./}
			;;
		*)
			continue
			;;
		esac
		case "$de_found_entry_id" in
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

de_replace_str() {
	DE_REPLACED_STR=
	de_replace_remainder=$1
	de_replace_needle=$2
	de_replace_replacement=$3

	[ -n "$de_replace_needle" ] || {
		DE_REPLACED_STR=$de_replace_remainder
		return 0
	}

	while [ -n "$de_replace_remainder" ]; do
		de_replace_left=${de_replace_remainder%%"$de_replace_needle"*}
		DE_REPLACED_STR=${DE_REPLACED_STR}${de_replace_left}
		case "$de_replace_left" in
		"$de_replace_remainder") break ;;
		esac
		DE_REPLACED_STR=${DE_REPLACED_STR}${de_replace_replacement}
		de_replace_remainder=${de_replace_remainder#*"$de_replace_needle"}
	done
}

de_expand_escape_sequence() {
	case "$exp_remainder" in
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
	esac
}

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
		de_expand_escape_sequence
	done
}

de_tokenizer_pop_char() {
	cut=${tok_remainder#?}
	tok_char=${tok_remainder%"$cut"}
	tok_remainder=${cut}
	unset cut
}

de_tokenizer_consume_space_state() {
	case "${tok_in_space}${tok_left}${tok_char}" in
	1[[:space:]])
		debug "tokenizer still in space :) skipping space character"
		return 1
		;;
	1*)
		debug "tokenizer no longer in space :("
		tok_in_space=0
		;;
	esac
}

de_tokenizer_append_escaped_char() {
	case "$tok_remainder" in
	'')
		error "${ENTRY_ID}: Dangling backslash encountered!"
		return 1
		;;
	esac

	de_tokenizer_pop_char
	EXEC_USEP=${EXEC_USEP}${tok_char}
	debug "tokenizer appended escaped: >$tok_char<"
}

de_tokenizer_handle_char() {
	case "${tok_quoted}${tok_char}" in
	'1"')
		tok_quoted=0
		debug "tokenizer closed double quotes"
		return 1
		;;
	'0"')
		tok_quoted=1
		debug "tokenizer opened double quotes"
		return 1
		;;
	0[\`\$\\\'\>\<\~\|\&\;\*\?\#\(\)])
		error "${ENTRY_ID}: Encountered unquoted character: '$tok_char'"
		return 2
		;;
	1[\`\$])
		error "${ENTRY_ID}: Encountered unescaped quoted character: '$tok_char'"
		return 2
		;;
	1\\)
		de_tokenizer_append_escaped_char || return 2
		return 0
		;;
	0[[:space:]])
		case "${tok_remainder}" in
		*[![:space:]]*)
			EXEC_USEP=${EXEC_USEP}${USEP}
			tok_in_space=1
			debug "tokenizer entered spaaaaaace!!!! separator appended"
			return 1
			;;
		*)
			debug "tokenizer entered outer spaaaaaace!!!! separator skipped, this is the end"
			return 3
			;;
		esac
		;;
	1[[:space:]\'\>\<\~\|\&\;\*\?\#\(\)])
		EXEC_USEP=${EXEC_USEP}${tok_char}
		debug "tokenizer appended quoted char: >$tok_char<"
		return 0
		;;
	*)
		error "${ENTRY_ID}: parsing error at char '$tok_char', (quoted: $tok_quoted)"
		return 2
		;;
	esac
}

de_tokenize_exec() {
	# Shell-based DE Exec string tokenizer.
	# https://specifications.freedesktop.org/desktop-entry-spec/latest/exec-variables.html
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
		de_tokenizer_pop_char

		de_tokenizer_consume_space_state
		case "$?" in
		1) continue ;;
		esac

		de_tokenizer_handle_char
		case "$?" in
		0) ;;
		1) continue ;;
		2) return 1 ;;
		3) break ;;
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

de_inject_apply_args() {
	de_inject_mode=$1
	de_inject_encoded=$2
	de_inject_template=$3
	de_inject_field=$4
	shift 4
	for de_inject_arg in "$@"; do
		case "$de_inject_encoded" in
		true) de_inject_arg=$(urlencode "$de_inject_arg") ;;
		esac
		case "$de_inject_mode" in
		append)
			debug "injector extending with '$de_inject_arg'"
			de_exec_append_arg "$de_inject_arg"
			;;
		expand)
			de_exec_append_iter_replaced_arg "$de_inject_template" "$de_inject_field" "$de_inject_arg"
			;;
		esac
	done
	case "$de_inject_mode" in
	append) ;;
	expand) de_exec_append_iter_placeholder ;;
	esac
}

de_inject_optional_replaced_field() {
	if [ -n "$3" ]; then
		de_exec_append_replaced_arg "$1" "$2" "$3"
	else
		debug "injector removed '$1'"
	fi
}

de_inject_file_field() {
	case "$DE_INJECT_FILE_FIELD_SEEN" in
	true)
		error "${ENTRY_ID}: Encountered more than one %[fFuU] field!"
		return 1
		;;
	esac
	DE_INJECT_FILE_FIELD_SEEN=true

	if [ "$#" -eq "1" ]; then
		debug "injector removed '$1'"
		return 0
	fi

	de_inject_exec_field=$1
	shift
	case "$de_inject_exec_field" in
	*[!%]'%F'* | *'%F'?* | *[!%]'%U'* | *'%U'?*)
		error "${ENTRY_ID}: Encountered non-standalone field '$de_inject_exec_field'"
		return 1
		;;
	*[!%]'%f'* | '%f'*)
		de_inject_apply_args expand false "$de_inject_exec_field" "%f" "$@"
		;;
	'%F')
		de_inject_apply_args append false '' '' "$@"
		;;
	*[!%]'%u'* | '%u'*)
		de_inject_apply_args expand true "$de_inject_exec_field" "%u" "$@"
		;;
	'%U')
		de_inject_apply_args append true '' '' "$@"
		;;
	*)
		error "${ENTRY_ID}: not implemented '$de_inject_exec_field'"
		return 1
		;;
	esac
}

de_inject_fields() {
	# Operates on argument array and $EXEC_RSEP_USEP from entry
	# modifies $EXEC_RSEP_USEP according to args/fields
	# no arguments, erase fields from $EXEC_RSEP_USEP
	DE_EXEC_USEP_TMP=''
	DE_INJECT_FILE_FIELD_SEEN=false
	DE_EXEC_ITER_USEP_TMP=''
	IFS=$USEP
	for de_inject_arg in $EXEC_RSEP_USEP; do
		case "$de_inject_arg" in
		*[!%]'%'[fFuU]* | '%'[fFuU]*)
			de_inject_file_field "$de_inject_arg" "$@" || return 1
			;;
		*[!%]'%i'* | '%i'*)
			de_inject_optional_replaced_field "$de_inject_arg" "%i" "$ENTRY_ICON"
			;;
		*[!%]'%c'* | '%c'*)
			de_exec_append_replaced_arg "$de_inject_arg" "%c" "$ENTRY_NAME"
			;;
		*[!%]%%* | %%*)
			de_exec_append_replaced_arg "$de_inject_arg" "%%" "%"
			;;
		*%?* | *[!%]%)
			error "${ENTRY_ID}: unknown % field in argument '${de_inject_arg}'"
			return 1
			;;
		*)
			debug "injector keeped: '$de_inject_arg'"
			de_exec_append_arg "$de_inject_arg"
			;;
		esac
	done
	de_exec_finalize_iterations
	IFS=$OIFS
}

de_exec_append_arg() {
	DE_EXEC_USEP_TMP=${DE_EXEC_USEP_TMP}${DE_EXEC_USEP_TMP:+$USEP}${1}
}

de_exec_resolve_replaced_arg() {
	de_replace_str "$1" "$2" "$3"
	debug "injector replacing '$2': '$1' -> '$DE_REPLACED_STR'"
}

de_exec_append_replaced_arg() {
	de_exec_resolve_replaced_arg "$@"
	de_exec_append_arg "$DE_REPLACED_STR"
}

de_exec_append_iter_arg() {
	debug "injector adding '$1' iteration as '$2'"
	DE_EXEC_ITER_USEP_TMP=${DE_EXEC_ITER_USEP_TMP}${DE_EXEC_ITER_USEP_TMP:+$USEP}${2}
}

de_exec_append_iter_replaced_arg() {
	de_exec_resolve_replaced_arg "$@"
	de_exec_append_iter_arg "$1" "$DE_REPLACED_STR"
}

de_exec_append_iter_placeholder() {
	de_exec_append_arg '%%__ITER__%%'
}

de_exec_finalize_iterations() {
	if [ -n "$DE_EXEC_ITER_USEP_TMP" ]; then
		EXEC_RSEP_USEP=''
		for de_exec_iter_arg in $DE_EXEC_ITER_USEP_TMP; do
			de_replace_str "$DE_EXEC_USEP_TMP" "%%__ITER__%%" "$de_exec_iter_arg"
			de_exec_cmd=$DE_REPLACED_STR
			EXEC_RSEP_USEP=${EXEC_RSEP_USEP}${EXEC_RSEP_USEP:+$RSEP}${de_exec_cmd}
		done
	else
		EXEC_RSEP_USEP=$DE_EXEC_USEP_TMP
	fi
}

de_capture_expanded_value() {
	debug "captured '$1' '$2'"
	de_expand_str "$2"
	DE_CAPTURED_VALUE=$EXPANDED_STR
}

de_parse_type_key() {
	debug "captured 'Type' '$1'"
	case "$1" in
	Application | Link) ENTRY_TYPE=$1 ;;
	*)
		error "${ENTRY_ID}: Unsupported type '$1'!"
		return 1
		;;
	esac
}

de_parse_actions_key() {
	[ -z "$1" ] && return 0
	debug "checking for '$1' in Actions '$2'"
	IFS=';'
	for de_check_action in $2; do
		case "$de_check_action" in
		"$1")
			DE_ACTION_LISTED=true
			return 0
			;;
		esac
	done
	error "${ENTRY_ID}: Action '$1' is not listed in entry!"
	return 1
}

de_parse_exec_key() {
	case "$1" in
	false)
		debug "ignored Exec from wrong section"
		return 0
		;;
	esac
	case "$2" in
	true) DE_ACTION_EXEC=true ;;
	esac
	debug "read Exec '$3'"
	[ -z "$EXEC_RSEP_USEP" ] || {
		debug "skipping re-filling exec array"
		return 0
	}
	de_expand_str "$3"
	de_tokenize_exec "$EXPANDED_STR"
	EXEC_RSEP_USEP=$EXEC_USEP
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
}

de_parse_path_key() {
	de_capture_expanded_value "Path" "$1"
	ENTRY_WORKDIR=$DE_CAPTURED_VALUE
	if [ ! -e "$ENTRY_WORKDIR" ]; then
		error "${ENTRY_ID}: Requested 'Path' '${ENTRY_WORKDIR}' does not exist!"
		return 1
	elif [ ! -d "$ENTRY_WORKDIR" ]; then
		error "${ENTRY_ID}: Requested 'Path' '${ENTRY_WORKDIR}' is not a directory!"
		return 1
	fi
}

de_parse_terminal_key() {
	debug "captured 'Terminal' '$1'"
	case "$1" in
	true)
		case "$TERMINAL" in
		false) check_terminal_handler ;;
		esac
		TERMINAL=true
		;;
		esac
}

de_validate_action_key_context() {
	case "${2};${1}" in
	'false;'* | 'true;Name' | 'true;Name['*']' | 'true;Exec' | 'true;Icon') return 0 ;;
	esac

	error "${ENTRY_ID}: Encountered '$1' key inside action!"
	return 1
}

de_parse_tryexec_key() {
	debug "checking TryExec executable '$1'"
	de_expand_str "$1"
	if ! type "$EXPANDED_STR" >/dev/null 2>&1; then
		error "${ENTRY_ID}: TryExec '$EXPANDED_STR' failed!"
		return 1
	fi
}

de_parse_hidden_key() {
	debug "checking boolean Hidden '$1'"
	case "$1" in
	true)
		error "${ENTRY_ID}: Entry is Hidden"
		return 1
		;;
	esac
}

de_parse_url_key() {
	de_capture_expanded_value "URL" "$1"
	ENTRY_URL=$DE_CAPTURED_VALUE
}

de_parse_name_key() {
	de_capture_expanded_value "$1" "$2"
	case "${3}_${4}_${1}" in
	true_false_Name)
		ENTRY_NAME=$DE_CAPTURED_VALUE
		;;
	false_true_Name)
		ENTRY_NAME_ACTION=$DE_CAPTURED_VALUE
		;;
	true_false_"Name[${LCODE}]")
		ENTRY_LNAME=$DE_CAPTURED_VALUE
		;;
	false_true_"Name[${LCODE}]")
		ENTRY_LNAME_ACTION=$DE_CAPTURED_VALUE
		;;
	*)
		debug "discarded '$1' '$2'"
		;;
	esac
}

de_parse_generic_name_key() {
	de_capture_expanded_value "$1" "$2"
	case "$1" in
	"GenericName[${LCODE}]") ENTRY_LCOMMENT=$DE_CAPTURED_VALUE ;;
	GenericName) ENTRY_COMMENT=$DE_CAPTURED_VALUE ;;
	esac
}

de_parse_icon_key() {
	if [ "$2" = "true" ] || [ "$3" = "true" ]; then
		de_capture_expanded_value "Icon" "$1"
		ENTRY_ICON=$DE_CAPTURED_VALUE
		return 0
	fi

	debug "discarded 'Icon' '$1'"
}

parse_entry_key() {
	# set global vars or fail entry
	de_validate_action_key_context "$1" "$6" || return 1

	case "$1" in
	Type) de_parse_type_key "$2" ;;
	Actions) de_parse_actions_key "$3" "$2" ;;
	TryExec) de_parse_tryexec_key "$2" ;;
	Hidden) de_parse_hidden_key "$2" ;;
	Exec) de_parse_exec_key "$4" "$6" "$2" ;;
	URL) de_parse_url_key "$2" ;;
	"Name[${LCODE}]" | Name) de_parse_name_key "$1" "$2" "$5" "$6" ;;
	"GenericName[${LCODE}]" | GenericName) de_parse_generic_name_key "$1" "$2" ;;
	Icon) de_parse_icon_key "$2" "$5" "$6" ;;
	Path) de_parse_path_key "$2" ;;
	Terminal) de_parse_terminal_key "$2" ;;
	esac
	# By default unrecognised keys, empty lines and comments get ignored
}
# Mask IFS within function to allow temporary changes
alias parse_entry_key='IFS= parse_entry_key'

de_validate_requested_action() {
	[ -n "$DE_ENTRY_ACTION" ] || return 0

	case "$DE_ACTION_LISTED" in
	true) true ;;
	*)
		error "${ENTRY_ID}: Action '$DE_ENTRY_ACTION' is not listed in Actions key or does not exist!"
		return 1
		;;
	esac

	if [ "$DE_ACTION_EXEC" != "true" ] || [ -z "${ENTRY_LNAME_ACTION:-$ENTRY_NAME_ACTION}" ]; then
		error "${ENTRY_ID}: Action '$DE_ENTRY_ACTION' is incomplete"
		return 1
	fi
}

de_validate_entry_payload() {
	case "${ENTRY_TYPE};;${EXEC_RSEP_USEP};;${ENTRY_URL}" in
	'Application;;'?*';;' | 'Link;;;;'?*) return 0 ;;
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

read_entry_path() {
	# Read entry from given path
	DE_ENTRY_PATH=$1
	DE_ENTRY_ACTION=${2-}
	DE_READ_EXEC=false
	DE_ACTION_LISTED=false
	DE_IN_MAIN=false
	DE_IN_ACTION=false
	DE_ACTION_EXEC=false
	DE_BREAK_ON_NEXT_SECTION=false
	# shellcheck disable=SC2016
	debug "reading desktop entry '$DE_ENTRY_PATH'${DE_ENTRY_ACTION:+ action '$DE_ENTRY_ACTION'}"
	# Let `read` trim leading/trailing whitespace from the line
	while read -r line; do
		case $line in
		'[Desktop Entry]'*)
			debug "entered section: [Desktop Entry]"
			DE_IN_MAIN=true
			if [ -z "$DE_ENTRY_ACTION" ]; then
				DE_READ_EXEC=true
				DE_BREAK_ON_NEXT_SECTION=true
			fi
			;;
		[a-zA-Z0-9-]*=*)
			IFS='=' read -r de_parse_key de_parse_value <<-EOL
				$line
			EOL
			{ read -r de_parse_key && read -r de_parse_value; } <<-EOL
				$de_parse_key
				$de_parse_value
			EOL
			parse_entry_key "$de_parse_key" "$de_parse_value" "$DE_ENTRY_ACTION" "$DE_READ_EXEC" "$DE_IN_MAIN" "$DE_IN_ACTION" || return 1
			;;
		"[Desktop Action ${DE_ENTRY_ACTION}]"*)
			debug "entered section: [Desktop Action ${DE_ENTRY_ACTION}]"
			DE_IN_MAIN=false
			DE_BREAK_ON_NEXT_SECTION=true
			case "$DE_ACTION_LISTED" in
			true)
				DE_READ_EXEC=true
				DE_IN_ACTION=true
				;;
			*)
				error "${ENTRY_ID}: Action '$DE_ENTRY_ACTION' is not listed in Actions key!"
				return 1
				;;
			esac
			;;
		'['*)
			debug "entered section: $line"
			[ "$DE_BREAK_ON_NEXT_SECTION" = "true" ] && break
			DE_IN_MAIN=false
			DE_IN_ACTION=false
			DE_READ_EXEC=false
			;;
		esac
		# By default empty lines and comments get ignored
	done <"$DE_ENTRY_PATH"

	de_validate_requested_action || return 1
	de_validate_entry_payload
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
	de_urlencode_string=$1
	case "$de_urlencode_string" in
	# assuming already url
	*[a-zA-Z0-9_-]://*)
		echo "$de_urlencode_string"
		return
		;;
	# assuming absolute path
	/*) true ;;
	# assuming relative path
	*) de_urlencode_string=$(pwd)/$de_urlencode_string ;;
	esac

	printf '%s' 'file://'

	case "$de_urlencode_string" in
	# if contains extra chars, encode
	*[!._~0-9A-Za-z/-]*)
		while [ -n "$de_urlencode_string" ]; do
			de_urlencode_right=${de_urlencode_string#?}
			de_urlencode_char=${de_urlencode_string%"$de_urlencode_right"}
			debug "urlencode string $de_urlencode_string" "urlencode right $de_urlencode_right" "urlencode char $de_urlencode_char"
			case $de_urlencode_char in
			[._~0-9A-Za-z/-]) printf '%s' "$de_urlencode_char" ;;
			*) printf '%%%02x' "'$de_urlencode_char" ;;
			esac
			de_urlencode_string=$de_urlencode_right
		done
		;;
	*) printf '%s' "$de_urlencode_string" ;;
	esac
}

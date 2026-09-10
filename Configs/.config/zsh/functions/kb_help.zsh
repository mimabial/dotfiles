append_help_and_run() {
  local single_quotes="${BUFFER//[^']}" double_quotes="${BUFFER//[^\"]}"
  if [[ -z "${BUFFER// /}" ||
        ( $LBUFFER == *\"* && $RBUFFER == *\"* ) ||
        ( $LBUFFER == *\'* && $RBUFFER == *\'* ) ||
        ( ${LBUFFER[-1]:- } != ' ' && -n ${LBUFFER[-1]:-} ) ||
        ( ${RBUFFER[1]:- } != ' ' && -n ${RBUFFER[1]:-} ) ]] ||
     (( ${#single_quotes} % 2 || ${#double_quotes} % 2 )); then
    zle self-insert
    return
  fi
  [[ $BUFFER == *--help* ]] || BUFFER+=" --help"
  zle end-of-line
  zle accept-line
}

zle -N append_help_and_run
bindkey '?' append_help_and_run

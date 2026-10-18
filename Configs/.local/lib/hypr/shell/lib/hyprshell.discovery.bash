#!/usr/bin/env bash

hyprshell_is_internal_script() {
  case "$1" in
    core/* | runtime/* | pyutils/* | shell/*) return 0 ;;
    _* | */_*) return 0 ;;
    *.lib.sh | *.lib.bash | *.lib.py) return 0 ;;
    *.common.sh | *.common.bash | *.common.py) return 0 ;;
    *_lib.sh | *_lib.bash | *_lib.py) return 0 ;;
    *_common.sh | *_common.bash | *_common.py) return 0 ;;
    *__init__.py) return 0 ;;
  esac
  return 1
}

hyprshell_print_entrypoint_records() {
  local relative_path script_path
  while IFS=$'\t' read -r relative_path script_path; do
    hyprshell_is_internal_script "${relative_path}" && continue
    # Python: list entrypoints only, not import-only modules.
    if [[ "${script_path}" == *.py && ! -x "${script_path}" ]]; then
      grep -qs '__name__ == .__main__.' "${script_path}" || continue
    fi
    printf '%s\t%s\n' "${relative_path}" "${script_path}"
  done < <(find -L "${HYPR_LIB_DIR}" -maxdepth 2 -type f \
    \( -name '*.sh' -o -name '*.py' \) -printf '%P\t%p\n' 2>/dev/null)
}

hyprshell_print_script_names() {
  local -A relative_paths=()
  local relative_path script_path
  while IFS=$'\t' read -r relative_path script_path; do
    relative_paths["${relative_path}"]=1
  done < <(hyprshell_print_entrypoint_records)
  ((${#relative_paths[@]})) || return 0
  while IFS= read -r relative_path; do
    relative_path="${relative_path%.sh}"
    printf '%s\n' "${relative_path%.py}"
  done < <(printf '%s\n' "${!relative_paths[@]}" | sort)
}

hyprshell_print_script_paths() {
  find -L "${HYPR_LIB_DIR}" \
    -path '*/__pycache__' -prune -o \
    -type f \( -name '*.sh' -o -name '*.py' \) -print
}

# A script that declares hypr_help_guard is announcing itself as user-facing;
# the line after its "Usage:" is its summary. Scripts without one are pipeline
# hooks other scripts invoke. One awk pass over every candidate, not one grep
# per file.
hyprshell_extract_script_summaries() {
  awk '
    FNR == 1 { seen[FILENAME] = 1; in_help_function = 0 }
    # A "Usage:" inside a help/usage function is a declared contract; the same
    # string in an error message is not, so only the former is trusted.
    /^[a-zA-Z_]*(usage|help)[a-zA-Z_]*\(\) *\{/ { in_help_function = 1 }
    /description="/ && /ArgumentParser|^ *description="/ && !(FILENAME in summaries) {
      line = $0
      sub(/^.*description="/, "", line)
      sub(/".*$/, "", line)
      if (line != "") summaries[FILENAME] = line
      next
    }
    (/hypr_help_guard "Usage:/ || (in_help_function && /Usage:/)) && !(FILENAME in summaries) {
      summary_text = ""
      usage_text = substr($0, index($0, "Usage:"))
      quote = substr($0, index($0, "Usage:") - 1, 1)
      if ((quote == "\"" || quote == "\047") && index(substr(usage_text, 7), quote)) {
        if (match(usage_text, /\\n\\n[^\\]+/)) summary_text = substr(usage_text, RSTART + 4, RLENGTH - 4)
      } else if (usage_text !~ /^Usage:[ \t]*$/) {
        # the summary runs until the closing quote of the usage string
        while ((getline line) > 0) {
          if (line ~ /^[ \t]*\}/) { in_help_function = 0; break }
          # only a prose summary counts: an options table or another heading is not one
          if (line ~ /^[ \t]*-/ && line ~ /[ \t][ \t]/) break
          if (line ~ /^[ \t]+[^ \t]/ && line ~ /[^ \t][ \t][ \t]+[^ \t]/) break
          if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*(cat|printf|echo|EOF|HELP|EOT)/) break
          if (line ~ /^[ \t]*(Options|Usage|Commands|Arguments|Examples|Flags)[: ]/) break
          summary_finished = (line ~ /" *"\$@"/)
          sub(/" *"\$@".*$/, "", line)
          gsub(/^[ \t]+|[ \t]+$/, "", line)
          summary_text = (summary_text == "" ? line : summary_text " " line)
          if (summary_finished) break
        }
      }
      if (summary_text != "") summaries[FILENAME] = summary_text
    }
    in_help_function && /\}[ \t]*$/ { in_help_function = 0 }
    END { for (source_file in seen) printf "%s\t%s\n", source_file, (source_file in summaries ? summaries[source_file] : "") }
  ' "$@"
}

hyprshell_print_described_scripts() {
  local -a command_names=() script_paths=() pipeline_hooks=()
  local -A summaries=()
  local relative_path="" script_path="" summary_text="" index

  while IFS=$'\t' read -r relative_path script_path; do
    command_names+=("${relative_path%.*}")
    script_paths+=("${script_path}")
  done < <(hyprshell_print_entrypoint_records | sort -u)
  [[ ${#script_paths[@]} -gt 0 ]] || return 0

  while IFS=$'\t' read -r script_path summary_text; do
    summaries["${script_path}"]="${summary_text}"
  done < <(hyprshell_extract_script_summaries "${script_paths[@]}")
  printf 'Commands:\n'
  for ((index = 0; index < ${#script_paths[@]}; index++)); do
    script_path="${script_paths[index]}"
    summary_text="${summaries["${script_path}"]:-}"
    if [[ -n "${summary_text}" ]]; then
      printf '  %-34s %s\n' "${command_names[index]}" "${summary_text}"
    else
      pipeline_hooks+=("${command_names[index]}")
    fi
  done
  [[ ${#pipeline_hooks[@]} -gt 0 ]] || return 0
  printf '\nNo --help text (mostly pipeline hooks; run with care):\n'
  printf '  %s\n' "${pipeline_hooks[@]}"
}

#!/usr/bin/env bash
usage() {
  cat <<EOF
Usage: $(basename "$0") [--app-id ID] [--title TITLE] -- <command>
EOF
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit; }

app_id=""
title=""
cmd=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --app-id) app_id="$2"; shift 2 ;;
    --title)  title="$2";  shift 2 ;;
    --)
      shift
      cmd=("$@")
      break
      ;;
    *)
      cmd+=("$1")
      shift
      ;;
  esac
done

if [[ "${#cmd[@]}" -eq 0 ]]; then
  usage >&2
  exit 2
fi
[[ -n "${app_id}" ]] || app_id="org.tui.$(basename "${cmd[0]}")"

launch_args=(--hypr-profile tui --app-id "${app_id}")
unit_env=()
[[ -n "${title}" ]] && launch_args+=(--title "${title}")
[[ -z "${HYPR_SUMMON_EXPECTED_FLOAT:-}" ]] || unit_env=(env "HYPR_SUMMON_EXPECTED_FLOAT=${HYPR_SUMMON_EXPECTED_FLOAT}")

exec setsid uwsm-app -- tui-terminal-exec "${launch_args[@]}" -- "${unit_env[@]}" "${cmd[@]}"

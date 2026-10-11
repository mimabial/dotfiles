managed_parse_options_into() {
  local -n options_ref="$1" arguments_ref="$2"
  shift 2
  options_ref=([mode]="${options_ref[mode]:-}" [show_diff]=0 [quiet]=0 [dry_run]=0 [backup_label]="" [backup_root]="")
  arguments_ref=()
  while (($#)); do
    case "$1" in
      -h | --help) arguments_ref+=("$1") ;;
      -q | --quiet) options_ref[quiet]=1 ;;
      -n | --dry-run) options_ref[dry_run]=1 ;;
      --diff) options_ref[show_diff]=1 ;;
      --no-diff) options_ref[show_diff]=0 ;;
      --backup-label)
        shift
        [[ "$#" -gt 0 ]] || managed_fail "Missing value for --backup-label"
        options_ref[backup_label]="$1"
        ;;
      --)
        shift
        arguments_ref+=("$@")
        break
        ;;
      -*) managed_fail "Unknown option: $1" ;;
      *) arguments_ref+=("$1") ;;
    esac
    shift
  done
}

# shellcheck disable=SC2034 # Nameref outputs are assigned for service entrypoints.
managed_parse_mode_into() {
  local -n mode_options_ref="$1" forwarded_ref="$2"
  local usage_fn="$3"
  shift 3
  mode_options_ref[mode]=""
  forwarded_ref=()
  while (($#)); do
    case "$1" in
      --mode)
        shift
        [[ "$#" -gt 0 ]] || managed_fail "Missing value for --mode"
        mode_options_ref[mode]="$1"
        ;;
      -h | --help | help)
        "${usage_fn}"
        exit 0
        ;;
      *) forwarded_ref+=("$1") ;;
    esac
    shift
  done
}

managed_mode_is_valid() {
  case "${1:-}" in
    refresh | restore) return 0 ;;
    *) return 1 ;;
  esac
}

#!/usr/bin/env bash

# Shared helpers for hypr service scripts.

HYPR_SERVICE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly HYPR_SERVICE_LIB_DIR

hypr_service_default_root() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/hypr/default"
}

hypr_service_default_state_root() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/hypr/default/state"
}

hypr_service_manifest_path() {
  printf '%s/refresh.manifest.psv\n' "${HYPR_SERVICE_LIB_DIR}"
}

hypr_service_backup_base() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/cfg_backups"
}

hypr_service_backup_root() {
  if [[ -z "${HYPR_SERVICE_BACKUP_ROOT:-}" ]]; then
    local label="${HYPR_SERVICE_BACKUP_LABEL:-refresh}"
    label="${label//[^A-Za-z0-9._-]/-}"
    HYPR_SERVICE_BACKUP_ROOT="$(hypr_service_backup_base)/$(date +%Y%m%d_%H%M%S)_${label}"
  fi
  printf '%s\n' "${HYPR_SERVICE_BACKUP_ROOT}"
}

hypr_service_target_relpath() {
  local target_path="$1"

  if [[ "${target_path}" == "${HOME}" ]]; then
    printf '/\n'
  elif [[ "${target_path}" == "${HOME}/"* ]]; then
    printf '%s\n' "${target_path#${HOME}}"
  else
    printf '%s\n' "${target_path}"
  fi
}

hypr_service_backup_target() {
  local target_path="$1"
  local backup_root backup_path

  [[ -e "${target_path}" || -L "${target_path}" ]] || return 1

  backup_root="$(hypr_service_backup_root)"
  backup_path="${backup_root}$(hypr_service_target_relpath "${target_path}")"
  mkdir -p "$(dirname "${backup_path}")"
  rm -rf "${backup_path}"
  cp -a "${target_path}" "${backup_path}"
}

hypr_service_file_changed() {
  local source_path="$1"
  local target_path="$2"

  [[ -e "${target_path}" || -L "${target_path}" ]] || return 0
  cmp -s "${source_path}" "${target_path}" >/dev/null 2>&1 && return 1
  return 0
}

hypr_service_tree_itemized_output() {
  local source_dir="$1"
  local target_dir="$2"
  local parent_dir

  parent_dir="$(dirname "${target_dir}")"
  mkdir -p "${parent_dir}"
  rsync -ani --delete "${source_dir}/" "${target_dir}/" 2>/dev/null || true
}

hypr_service_tree_changed() {
  local source_dir="$1"
  local target_dir="$2"
  local output=""

  output="$(hypr_service_tree_itemized_output "${source_dir}" "${target_dir}")"
  [[ -n "${output}" ]]
}

hypr_service_is_dry_run() {
  [[ "${HYPR_SERVICE_DRY_RUN:-0}" -eq 1 ]]
}

hypr_service_backup_root_has_content() {
  local backup_root first_entry

  backup_root="$(hypr_service_backup_root)"
  [[ -d "${backup_root}" ]] || return 1
  first_entry="$(find "${backup_root}" -mindepth 1 -print -quit 2>/dev/null || true)"
  [[ -n "${first_entry}" ]]
}

hypr_service_maybe_report_backup_root() {
  hypr_service_is_dry_run && return 0
  if hypr_service_backup_root_has_content; then
    printf 'Backups: %s\n' "$(hypr_service_backup_root)"
  fi
}

hypr_service_should_backup_file() {
  local source_path="$1"
  local target_path="$2"
  local backup_policy="$3"

  [[ -e "${target_path}" || -L "${target_path}" ]] || return 1

  case "${backup_policy}" in
    always) return 0 ;;
    changed) hypr_service_file_changed "${source_path}" "${target_path}" ;;
    never) return 1 ;;
    *) hypr_service_die "Unsupported backup policy for file: ${backup_policy}" ;;
  esac
}

hypr_service_should_backup_tree() {
  local source_dir="$1"
  local target_dir="$2"
  local backup_policy="$3"

  [[ -d "${target_dir}" ]] || return 1

  case "${backup_policy}" in
    always) return 0 ;;
    changed) hypr_service_tree_changed "${source_dir}" "${target_dir}" ;;
    never) return 1 ;;
    *) hypr_service_die "Unsupported backup policy for tree: ${backup_policy}" ;;
  esac
}

hypr_service_init() {
  source "$(command -v hyprshell)" || return 1
}

hypr_service_die() {
  printf '%s\n' "$*" >&2
  exit 1
}

hypr_service_usage_refresh_config() {
  cat <<'USAGE'
Usage: hyprshell service/refresh-config.sh [options] <relative-path-under-config>

Options:
  -n, --dry-run          preview without changing files
  -q, --quiet            suppress per-entry status lines
  --diff                 show unified diffs for changed files
  --no-diff              skip file diffs
  --backup-label <name>  override backup folder suffix

Example:
  hyprshell service/refresh-config.sh hypr/hyprlock.conf
USAGE
}

hypr_service_parse_refresh_args() {
  hypr_service_cli_show_diff=0
  hypr_service_cli_quiet=0
  hypr_service_cli_dry_run=0
  hypr_service_cli_backup_label=""
  hypr_service_cli_args=()

  while (($#)); do
    case "$1" in
      -h | --help)
        hypr_service_cli_args+=("$1")
        ;;
      -q | --quiet)
        hypr_service_cli_quiet=1
        ;;
      -n | --dry-run)
        hypr_service_cli_dry_run=1
        ;;
      --diff)
        hypr_service_cli_show_diff=1
        ;;
      --no-diff)
        hypr_service_cli_show_diff=0
        ;;
      --backup-label)
        shift
        [[ "$#" -gt 0 ]] || hypr_service_die "Missing value for --backup-label"
        hypr_service_cli_backup_label="$1"
        ;;
      --)
        shift
        while (($#)); do
          hypr_service_cli_args+=("$1")
          shift
        done
        break
        ;;
      -*)
        hypr_service_die "Unknown option: $1"
        ;;
      *)
        hypr_service_cli_args+=("$1")
        ;;
    esac
    shift
  done
}

hypr_service_apply_cli_env() {
  export HYPR_SERVICE_DRY_RUN="${hypr_service_cli_dry_run:-0}"
  if [[ -n "${hypr_service_cli_backup_label:-}" ]]; then
    export HYPR_SERVICE_BACKUP_LABEL="${hypr_service_cli_backup_label}"
  else
    unset HYPR_SERVICE_BACKUP_LABEL
  fi
  unset HYPR_SERVICE_BACKUP_ROOT
}

hypr_service_is_safe_relpath() {
  local rel_path="$1"
  [[ -n "${rel_path}" ]] || return 1
  [[ "${rel_path}" != /* ]] || return 1
  [[ "${rel_path}" != *".."* ]] || return 1
  return 0
}

hypr_service_template_path() {
  local rel_path="$1"
  printf '%s/%s\n' "$(hypr_service_default_root)" "${rel_path}"
}

hypr_service_state_template_path() {
  local rel_path="$1"
  printf '%s/%s\n' "$(hypr_service_default_state_root)" "${rel_path}"
}

hypr_service_has_template() {
  local rel_path="$1"
  local template_path
  template_path="$(hypr_service_template_path "${rel_path}")"
  [[ -f "${template_path}" ]]
}

hypr_service_apply_file_mode() {
  local source_path="$1"
  local target_path="$2"
  local rel_path="$3"
  local mode="$4"
  local backup_policy="$5"
  local show_diff="${6:-1}"
  local quiet="${7:-0}"
  local backup_path=""
  local target_exists=0

  [[ "${mode}" == "trash" ]] || [[ -f "${source_path}" ]] || hypr_service_die "No template found for ${rel_path}: ${source_path}"

  mkdir -p "$(dirname "${target_path}")"
  [[ -e "${target_path}" || -L "${target_path}" ]] && target_exists=1

  case "${mode}" in
    preserve)
      if [[ "${target_exists}" -eq 1 ]]; then
        [[ "${quiet}" -eq 1 ]] || printf 'Preserved: %s\n' "${target_path}"
        return 0
      fi
      if hypr_service_is_dry_run; then
        [[ "${quiet}" -eq 1 ]] || printf 'Would populate: %s\n' "${target_path}"
        return 0
      fi
      cp -a "${source_path}" "${target_path}"
      [[ "${quiet}" -eq 1 ]] || printf 'Populated: %s\n' "${target_path}"
      return 0
      ;;
    overwrite)
      if [[ "${target_exists}" -eq 1 ]] && ! hypr_service_file_changed "${source_path}" "${target_path}"; then
        [[ "${quiet}" -eq 1 ]] || printf 'Unchanged: %s\n' "${target_path}"
        return 0
      fi

      if hypr_service_is_dry_run; then
        if hypr_service_should_backup_file "${source_path}" "${target_path}" "${backup_policy}"; then
          [[ "${quiet}" -eq 1 ]] || printf 'Would back up: %s\n' "${target_path}"
        fi
        if [[ "${target_exists}" -eq 1 ]]; then
          [[ "${quiet}" -eq 1 ]] || printf 'Would overwrite: %s\n' "${target_path}"
          if [[ "${show_diff}" -eq 1 ]]; then
            printf 'Changes for %s:\n' "${rel_path}"
            diff -u "${target_path}" "${source_path}" || true
          fi
        else
          [[ "${quiet}" -eq 1 ]] || printf 'Would populate: %s\n' "${target_path}"
        fi
        return 0
      fi

      if hypr_service_should_backup_file "${source_path}" "${target_path}" "${backup_policy}"; then
        hypr_service_backup_target "${target_path}"
        backup_path="$(hypr_service_backup_root)$(hypr_service_target_relpath "${target_path}")"
      fi

      cp -a "${source_path}" "${target_path}"
      if [[ "${target_exists}" -eq 1 ]]; then
        [[ "${quiet}" -eq 1 ]] || printf 'Overwritten: %s\n' "${target_path}"
      else
        [[ "${quiet}" -eq 1 ]] || printf 'Populated: %s\n' "${target_path}"
      fi
      if [[ "${show_diff}" -eq 1 ]] && [[ -n "${backup_path}" ]] && [[ -f "${backup_path}" ]]; then
        printf 'Changes for %s:\n' "${rel_path}"
        diff -u "${backup_path}" "${target_path}" || true
      fi
      return 0
      ;;
    trash)
      if [[ "${target_exists}" -eq 0 ]]; then
        [[ "${quiet}" -eq 1 ]] || printf 'Missing: %s\n' "${target_path}"
        return 0
      fi

      if hypr_service_is_dry_run; then
        [[ "${backup_policy}" != "never" && "${quiet}" -ne 1 ]] && printf 'Would back up: %s\n' "${target_path}"
        [[ "${quiet}" -eq 1 ]] || printf 'Would trash: %s\n' "${target_path}"
        return 0
      fi

      if [[ "${backup_policy}" != "never" ]]; then
        hypr_service_backup_target "${target_path}"
      fi
      rm -rf "${target_path}"
      [[ "${quiet}" -eq 1 ]] || printf 'Trashed: %s\n' "${target_path}"
      return 0
      ;;
    *)
      hypr_service_die "Unsupported file mode: ${mode} (${rel_path})"
      ;;
  esac
}

hypr_service_apply_tree_mode() {
  local source_dir="$1"
  local target_dir="$2"
  local rel_path="$3"
  local mode="$4"
  local backup_policy="$5"
  local quiet="${6:-0}"
  local sync_plan=""
  local target_exists=0

  [[ "${mode}" == "trash" ]] || [[ -d "${source_dir}" ]] || hypr_service_die "No template directory found for ${rel_path}: ${source_dir}"
  [[ -d "${target_dir}" ]] && target_exists=1

  case "${mode}" in
    sync)
      sync_plan="$(hypr_service_tree_itemized_output "${source_dir}" "${target_dir}")"
      if [[ -z "${sync_plan}" ]]; then
        [[ "${quiet}" -eq 1 ]] || printf 'Unchanged: %s/\n' "${target_dir}"
        return 0
      fi

      if hypr_service_is_dry_run; then
        if hypr_service_should_backup_tree "${source_dir}" "${target_dir}" "${backup_policy}"; then
          [[ "${quiet}" -eq 1 ]] || printf 'Would back up: %s/\n' "${target_dir}"
        fi
        [[ "${quiet}" -eq 1 ]] || printf 'Would sync: %s/\n' "${target_dir}"
        [[ "${quiet}" -eq 1 ]] || printf '%s\n' "${sync_plan}"
        return 0
      fi

      if hypr_service_should_backup_tree "${source_dir}" "${target_dir}" "${backup_policy}"; then
        hypr_service_backup_target "${target_dir}"
      fi

      mkdir -p "${target_dir}"
      rsync -a --delete "${source_dir}/" "${target_dir}/" || hypr_service_die "Failed to sync directory ${rel_path}"
      [[ "${quiet}" -eq 1 ]] || printf 'Synced: %s/\n' "${target_dir}"
      return 0
      ;;
    preserve)
      if [[ "${target_exists}" -eq 1 ]]; then
        [[ "${quiet}" -eq 1 ]] || printf 'Preserved: %s/\n' "${target_dir}"
        return 0
      fi
      if hypr_service_is_dry_run; then
        [[ "${quiet}" -eq 1 ]] || printf 'Would populate: %s/\n' "${target_dir}"
        return 0
      fi
      mkdir -p "$(dirname "${target_dir}")"
      cp -a "${source_dir}" "${target_dir}"
      [[ "${quiet}" -eq 1 ]] || printf 'Populated: %s/\n' "${target_dir}"
      return 0
      ;;
    trash)
      if [[ "${target_exists}" -eq 0 ]]; then
        [[ "${quiet}" -eq 1 ]] || printf 'Missing: %s/\n' "${target_dir}"
        return 0
      fi
      if hypr_service_is_dry_run; then
        [[ "${backup_policy}" != "never" && "${quiet}" -ne 1 ]] && printf 'Would back up: %s/\n' "${target_dir}"
        [[ "${quiet}" -eq 1 ]] || printf 'Would trash: %s/\n' "${target_dir}"
        return 0
      fi
      if [[ "${backup_policy}" != "never" ]]; then
        hypr_service_backup_target "${target_dir}"
      fi
      rm -rf "${target_dir}"
      [[ "${quiet}" -eq 1 ]] || printf 'Trashed: %s/\n' "${target_dir}"
      return 0
      ;;
    *)
      hypr_service_die "Unsupported tree mode: ${mode} (${rel_path})"
      ;;
  esac
}

hypr_service_refresh_config() {
  local rel_path="$1"
  local show_diff="${2:-1}"
  local quiet="${3:-0}"
  local source_path target_path

  if ! hypr_service_is_safe_relpath "${rel_path}"; then
    hypr_service_die "Invalid config path: ${rel_path}"
  fi

  source_path="$(hypr_service_template_path "${rel_path}")"
  target_path="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"
  hypr_service_apply_file_mode "${source_path}" "${target_path}" "${rel_path}" overwrite changed "${show_diff}" "${quiet}"
}

hypr_service_refresh_state() {
  local rel_path="$1"
  local show_diff="${2:-1}"
  local quiet="${3:-0}"
  local source_path target_path

  if ! hypr_service_is_safe_relpath "${rel_path}"; then
    hypr_service_die "Invalid state path: ${rel_path}"
  fi

  source_path="$(hypr_service_state_template_path "${rel_path}")"
  target_path="${XDG_STATE_HOME:-$HOME/.local/state}/${rel_path}"
  hypr_service_apply_file_mode "${source_path}" "${target_path}" "${rel_path}" overwrite changed "${show_diff}" "${quiet}"
}

hypr_service_manifest_entries() {
  local manifest_path="$1"
  shift
  local selected_domains=("$@")
  local line domain layer kind mode backup rel_path wanted

  [[ -f "${manifest_path}" ]] || hypr_service_die "Missing refresh manifest: ${manifest_path}"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue

    IFS='|' read -r domain layer kind mode backup rel_path <<<"${line}"
    [[ -n "${domain}" && -n "${layer}" && -n "${kind}" && -n "${mode}" && -n "${backup}" && -n "${rel_path}" ]] || continue

    if [[ "${#selected_domains[@]}" -gt 0 ]]; then
      wanted=0
      local selected
      for selected in "${selected_domains[@]}"; do
        if [[ "${domain}" == "${selected}" ]]; then
          wanted=1
          break
        fi
      done
      [[ "${wanted}" -eq 1 ]] || continue
    fi

    printf '%s|%s|%s|%s|%s|%s\n' "${domain}" "${layer}" "${kind}" "${mode}" "${backup}" "${rel_path}"
  done < "${manifest_path}"
}

hypr_service_refresh_manifest_entry() {
  local layer="$1"
  local kind="$2"
  local mode="$3"
  local backup_policy="$4"
  local rel_path="$5"
  local show_diff="${6:-1}"
  local quiet="${7:-0}"
  local source_path target_path

  case "${layer}:${kind}" in
    config:file)
      source_path="$(hypr_service_template_path "${rel_path}")"
      target_path="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"
      hypr_service_apply_file_mode "${source_path}" "${target_path}" "${rel_path}" "${mode}" "${backup_policy}" "${show_diff}" "${quiet}"
      ;;
    config:tree)
      source_path="$(hypr_service_template_path "${rel_path}")"
      target_path="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"
      hypr_service_apply_tree_mode "${source_path}" "${target_path}" "${rel_path}" "${mode}" "${backup_policy}" "${quiet}"
      ;;
    state:file)
      source_path="$(hypr_service_state_template_path "${rel_path}")"
      target_path="${XDG_STATE_HOME:-$HOME/.local/state}/${rel_path}"
      hypr_service_apply_file_mode "${source_path}" "${target_path}" "${rel_path}" "${mode}" "${backup_policy}" "${show_diff}" "${quiet}"
      ;;
    state:tree)
      source_path="$(hypr_service_state_template_path "${rel_path}")"
      target_path="${XDG_STATE_HOME:-$HOME/.local/state}/${rel_path}"
      hypr_service_apply_tree_mode "${source_path}" "${target_path}" "${rel_path}" "${mode}" "${backup_policy}" "${quiet}"
      ;;
    *)
      hypr_service_die "Unsupported manifest entry: ${layer}|${kind}|${mode}|${backup_policy}|${rel_path}"
      ;;
  esac
}

hypr_service_restore_manifest_entry() {
  local layer="$1"
  local kind="$2"
  local rel_path="$3"
  local show_diff="${4:-1}"
  local quiet="${5:-0}"
  local source_path target_path

  case "${layer}:${kind}" in
    config:file)
      source_path="$(hypr_service_template_path "${rel_path}")"
      target_path="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"
      hypr_service_apply_file_mode "${source_path}" "${target_path}" "${rel_path}" overwrite always "${show_diff}" "${quiet}"
      ;;
    config:tree)
      source_path="$(hypr_service_template_path "${rel_path}")"
      target_path="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"
      hypr_service_apply_tree_mode "${source_path}" "${target_path}" "${rel_path}" sync always "${quiet}"
      ;;
    state:file)
      source_path="$(hypr_service_state_template_path "${rel_path}")"
      target_path="${XDG_STATE_HOME:-$HOME/.local/state}/${rel_path}"
      hypr_service_apply_file_mode "${source_path}" "${target_path}" "${rel_path}" overwrite always "${show_diff}" "${quiet}"
      ;;
    state:tree)
      source_path="$(hypr_service_state_template_path "${rel_path}")"
      target_path="${XDG_STATE_HOME:-$HOME/.local/state}/${rel_path}"
      hypr_service_apply_tree_mode "${source_path}" "${target_path}" "${rel_path}" sync always "${quiet}"
      ;;
    *)
      hypr_service_die "Unsupported restore entry: ${layer}|${kind}|${rel_path}"
      ;;
  esac
}

hypr_service_refresh_manifest_domains() {
  local show_diff="$1"
  local quiet="$2"
  shift 2

  local manifest_path domain layer kind mode backup rel_path matched=0
  manifest_path="$(hypr_service_manifest_path)"
  if [[ -z "${HYPR_SERVICE_BACKUP_LABEL:-}" ]]; then
    HYPR_SERVICE_BACKUP_LABEL="${1:-refresh}"
  fi
  export HYPR_SERVICE_BACKUP_LABEL
  unset HYPR_SERVICE_BACKUP_ROOT

  while IFS='|' read -r domain layer kind mode backup rel_path; do
    matched=1
    hypr_service_refresh_manifest_entry "${layer}" "${kind}" "${mode}" "${backup}" "${rel_path}" "${show_diff}" "${quiet}"
  done < <(hypr_service_manifest_entries "${manifest_path}" "$@")

  [[ "${matched}" -eq 1 ]] || hypr_service_die "No manifest entries matched: $*"
}

hypr_service_restore_manifest_domains() {
  local show_diff="$1"
  local quiet="$2"
  shift 2

  local manifest_path domain layer kind mode backup rel_path matched=0
  manifest_path="$(hypr_service_manifest_path)"
  if [[ -z "${HYPR_SERVICE_BACKUP_LABEL:-}" ]]; then
    HYPR_SERVICE_BACKUP_LABEL="${1:-restore}"
  fi
  export HYPR_SERVICE_BACKUP_LABEL
  unset HYPR_SERVICE_BACKUP_ROOT

  while IFS='|' read -r domain layer kind mode backup rel_path; do
    matched=1
    hypr_service_restore_manifest_entry "${layer}" "${kind}" "${rel_path}" "${show_diff}" "${quiet}"
  done < <(hypr_service_manifest_entries "${manifest_path}" "$@")

  [[ "${matched}" -eq 1 ]] || hypr_service_die "No manifest entries matched: $*"
}

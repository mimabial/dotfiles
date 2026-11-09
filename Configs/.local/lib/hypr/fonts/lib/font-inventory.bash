require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    return 1
  }
}

collect_search_roots_into() {
  local -n roots_ref=$1
  local root
  roots_ref=()
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -e "$root" ]] && roots_ref+=("$root")
  done
}

build_rg_args_into() {
  local -n rg_args_ref=$1
  local glob
  rg_args_ref=(-n -i --color=never)
  for glob in "${SEARCH_GLOBS[@]}"; do
    rg_args_ref+=(--glob "$glob")
  done
}

collect_live_font_refs_into() {
  local -n live_refs_ref=$1
  live_refs_ref=()
  command -v gsettings >/dev/null 2>&1 || return 0

  local entry schema key raw_value
  for entry in "${GSETTINGS_FONT_KEYS[@]}"; do
    schema="${entry%% *}"
    key="${entry#* }"
    raw_value="$(gsettings get "${schema}" "${key}" 2>/dev/null || true)"
    [[ -n "${raw_value}" && "${raw_value}" != "''" ]] || continue
    live_refs_ref+=("gsettings: ${schema} ${key} = ${raw_value}")
  done
}

is_required_by() {
  local pkg="$1"
  local required_by
  required_by=$(pacman -Qi "$pkg" 2>/dev/null | awk -F ': ' '/^Required By/ {print $2}')
  [[ -n "$required_by" && "$required_by" != "None" ]]
}

required_by_list() {
  pacman -Qi "$1" 2>/dev/null | awk -F ': ' '/^Required By/ {print $2; exit}'
}

installed_size() {
  pacman -Qi "$1" 2>/dev/null | awk -F ': +' '/^Installed Size/ {print $2; exit}'
}

package_families() {
  local pkg="$1"
  local font_file families_text=""
  local -a font_files=()

  if [[ -n "${PACKAGE_FAMILY_CACHE[$pkg]+x}" ]]; then
    [[ -n "${PACKAGE_FAMILY_CACHE[$pkg]}" ]] && printf '%s\n' "${PACKAGE_FAMILY_CACHE[$pkg]}"
    return
  fi

  while IFS= read -r font_file; do
    if [[ -f "$font_file" ]]; then font_files+=("$font_file"); fi
  done <<<"${PACKAGE_FONT_FILES[$pkg]:-}"
  ((${#font_files[@]} == 0)) \
    || families_text="$(fc-scan --format '%{family}\n' "${font_files[@]}" 2>/dev/null | unique_family_names)" || true

  PACKAGE_FAMILY_CACHE["$pkg"]="${families_text}"
  [[ -n "${families_text}" ]] && printf '%s\n' "${families_text}"
}

summarize_families() {
  local pkg="$1"
  local -a families=()
  local family

  while IFS= read -r family; do
    [[ -n "$family" ]] && families+=("$family")
  done < <(package_families "$pkg")

  if ((${#families[@]} == 0)); then
    printf 'unknown family'
    return
  fi

  local joined=""
  printf -v joined '%s, ' "${families[@]:0:FAMILY_SUMMARY_LIMIT}"
  if ((${#families[@]} > FAMILY_SUMMARY_LIMIT)); then
    printf '%s...' "${joined}"
  else
    printf '%s' "${joined%, }"
  fi
}

collect_installed_font_packages_into() {
  local -n packages_ref=$1 package_files_ref=$2
  local pkg line
  local -a candidates=()
  packages_ref=()
  package_files_ref=()

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && candidates+=("$pkg")
  done < <(
    pacman -Qq \
      | awk 'BEGIN { IGNORECASE = 1 } /(^|[-_])(font|fonts|ttf|otf|nerd)([-_]|$)/' \
      | sort
  )

  ((${#candidates[@]})) || return 0
  while IFS= read -r line; do
    if [[ "${line#* }" =~ ${FONT_EXT_REGEX} ]]; then package_files_ref["${line%% *}"]+="${line#* }"$'\n'; fi
  done < <(pacman -Ql "${candidates[@]}" 2>/dev/null)
  for pkg in "${candidates[@]}"; do
    if [[ -n "${package_files_ref[$pkg]:-}" ]]; then packages_ref+=("$pkg"); fi
  done
}

collect_local_font_families_into() {
  local -n families_ref=$1 family_files_ref=$2 file_families_ref=$3
  local font_file family_list family
  local -a font_files=() family_names=()
  local -A seen_families=() seen_file_families=()

  families_ref=()
  family_files_ref=()
  file_families_ref=()
  [[ -d "${LOCAL_FONT_ROOT}" ]] || return 0

  mapfile -d '' -t font_files < <(
    find "${LOCAL_FONT_ROOT}" -type f -regextype posix-extended -iregex ".*${FONT_EXT_REGEX}" -print0 2>/dev/null | sort -z
  )
  ((${#font_files[@]})) || return 0
  while IFS=$'\t' read -r font_file family_list; do
    IFS=, read -ra family_names <<<"${family_list}"
    for family in "${family_names[@]}"; do
      family="${family#"${family%%[![:space:]]*}"}"
      family="${family%"${family##*[![:space:]]}"}"
      [[ -n "${family}" && -z "${seen_file_families["${font_file}"$'\t'"${family,,}"]:-}" ]] || continue
      seen_file_families["${font_file}"$'\t'"${family,,}"]=1
      family_files_ref["${family}"]+="${font_file}"$'\n'
      file_families_ref["${font_file}"]+="${family}"$'\n'
      if [[ -z "${seen_families[$family]:-}" ]]; then
        seen_families["${family}"]=1
        families_ref+=("${family}")
      fi
    done
  done < <(fc-scan --format '%{file}\t%{family}\n' "${font_files[@]}" 2>/dev/null)
}

family_files() {
  printf '%s' "${LOCAL_FAMILY_FILES[$1]}" | sed '/^$/d' | sort -u
}

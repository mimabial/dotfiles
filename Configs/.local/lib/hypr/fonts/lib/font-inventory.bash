require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
}

collect_search_roots() {
  ACTIVE_SEARCH_ROOTS=()
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -e "$root" ]] && ACTIVE_SEARCH_ROOTS+=("$root")
  done
}

build_rg_args() {
  RG_ARGS=(-n -i --color=never)
  for glob in "${SEARCH_GLOBS[@]}"; do
    RG_ARGS+=(--glob "$glob")
  done
}

collect_live_font_refs() {
  LIVE_FONT_REFS=()
  command -v gsettings >/dev/null 2>&1 || return 0

  local entry schema key raw_value
  for entry in "${GSETTINGS_FONT_KEYS[@]}"; do
    schema="${entry%% *}"
    key="${entry#* }"
    raw_value="$(gsettings get "${schema}" "${key}" 2>/dev/null || true)"
    [[ -n "${raw_value}" && "${raw_value}" != "''" ]] || continue
    LIVE_FONT_REFS+=("gsettings: ${schema} ${key} = ${raw_value}")
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

package_font_files() {
  local pkg="$1"
  pacman -Qlq "$pkg" 2>/dev/null | grep -E "$FONT_EXT_REGEX" || true
}

package_families() {
  local pkg="$1"
  local font_file families_text

  if [[ -n "${PACKAGE_FAMILY_CACHE[$pkg]+x}" ]]; then
    [[ -n "${PACKAGE_FAMILY_CACHE[$pkg]}" ]] && printf '%s\n' "${PACKAGE_FAMILY_CACHE[$pkg]}"
    return
  fi

  families_text="$(
    while IFS= read -r font_file; do
      [[ -f "$font_file" ]] || continue
      fc-scan --format '%{family}\n' "$font_file" 2>/dev/null || true
    done < <(package_font_files "$pkg") | unique_family_names
  )"

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

collect_installed_font_packages() {
  local pkg
  local -a candidates=()
  INSTALLED_FONT_PACKAGES=()

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && candidates+=("$pkg")
  done < <(
    pacman -Qq \
      | awk 'BEGIN { IGNORECASE = 1 } /(^|[-_])(font|fonts|ttf|otf|nerd)([-_]|$)/' \
      | sort
  )

  for pkg in "${candidates[@]}"; do
    if package_font_files "$pkg" | grep -q .; then
      INSTALLED_FONT_PACKAGES+=("$pkg")
    fi
  done
}

collect_local_font_families() {
  local font_file family
  declare -A seen_families=()

  LOCAL_FONT_FAMILIES=()
  LOCAL_FAMILY_FILES=()
  LOCAL_FILE_FAMILIES=()
  [[ -d "${LOCAL_FONT_ROOT}" ]] || return 0

  while IFS= read -r font_file; do
    while IFS= read -r family; do
      [[ -n "${family}" ]] || continue
      LOCAL_FAMILY_FILES["${family}"]+="${font_file}"$'\n'
      LOCAL_FILE_FAMILIES["${font_file}"]+="${family}"$'\n'
      if [[ -z "${seen_families[$family]:-}" ]]; then
        seen_families["${family}"]=1
        LOCAL_FONT_FAMILIES+=("${family}")
      fi
    done < <(fc-scan --format '%{family}\n' "${font_file}" 2>/dev/null | unique_family_names)
  done < <(
    find "${LOCAL_FONT_ROOT}" -type f -regextype posix-extended -iregex ".*${FONT_EXT_REGEX}" 2>/dev/null | sort
  )
}

family_files() {
  printf '%s' "${LOCAL_FAMILY_FILES[$1]}" | sed '/^$/d' | sort -u
}

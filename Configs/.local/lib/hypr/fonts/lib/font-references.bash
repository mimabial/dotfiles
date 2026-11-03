REFERENCE_RANK_RADIX=10
declare -gA REFERENCE_SCOPE_RANK=([active]=2 [config]=1 [installed-config]=0)
declare -gA MATCH_KIND_RANK=([explicit]=2 [fallback]=1)

normalize_name_into() {
  local -n normalized_name_ref="$1"
  normalized_name_ref="${2//[^a-zA-Z0-9]/}"
  normalized_name_ref="${normalized_name_ref,,}"
}

font_reference_regex_into() {
  local -n reference_regex_ref="$1"
  printf -v reference_regex_ref '(^|[^[:alnum:]])%s([^[:alnum:]]|$)' "${2//[][(){\}.^\$*+?|\\\/]/\\&}"
}

family_aliases_into() {
  local -n family_aliases_ref="$1"
  local family="$2"
  local normalized alias key
  local -A seen_aliases=()

  family_aliases_ref=()
  normalize_name_into normalized "${family}"
  for alias in "${family}" "${family//[$' \t\n\v\f\r'\/_-]/}" "${normalized}"; do
    [[ -n "$alias" ]] || continue
    key="${alias,,}"
    [[ -n "${seen_aliases[$key]:-}" ]] && continue
    seen_aliases["$key"]=1
    family_aliases_ref+=("$alias")
  done
}

classify_match_kind_into() {
  local -n match_kind_ref="$1"
  local family="$2"
  local match="$3"
  local content stack item family_norm item_norm
  local position=0
  local -a stack_items=()

  match_kind_ref=explicit
  normalize_name_into family_norm "$family"
  content="${match#*:*:}"
  [[ "${content}" == *"font-family"* ]] || return 0

  stack="${content#*font-family}"
  stack="${stack#*:}"
  stack="${stack%%;*}"
  IFS=, read -r -a stack_items <<<"${stack}"
  for item in "${stack_items[@]}"; do
    item="${item//[\"\']/}"
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "${item}" ]] || continue
    position=$((position + 1))
    normalize_name_into item_norm "${item}"
    if [[ "${item_norm}" == *"${family_norm}"* || "${family_norm}" == *"${item_norm}"* ]]; then
      ((position == 1)) || match_kind_ref=fallback
      return 0
    fi
  done
}

matches_ignoring_case() {
  local status=1

  shopt -s nocasematch
  [[ "$1" =~ $2 ]] && status=0
  shopt -u nocasematch
  return "${status}"
}

record_best_match() {
  local -n best_score_ref="$1" best_kind_ref="$2" best_match_ref="$3"
  local kind="$4"
  local match="$5"
  local score=""

  reference_rank score "${kind}" "${match}"
  ((score > best_score_ref)) || return 0
  best_score_ref=${score}
  best_kind_ref="${kind}"
  best_match_ref="${match}"
}

is_commented_match() {
  local match="$1"
  local content="${match#*:*:}"

  [[ "${content}" =~ ^[[:space:]]*(#|//|/\*|\*) ]]
}

reference_location_rank() {
  local out_name="$1" path="${2%%:*}"

  case "${path}" in
    gsettings) printf -v "${out_name}" 3 ;;
    "${XDG_CONFIG_HOME:-$HOME/.config}/"*) printf -v "${out_name}" 2 ;;
    "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/"*) printf -v "${out_name}" 1 ;;
    *) printf -v "${out_name}" 0 ;;
  esac
}

reference_rank() {
  local out_name="$1" kind="$2" match="$3"
  local scope="" location_rank=0

  reference_scope scope "${match}"
  reference_location_rank location_rank "${match}"
  printf -v "${out_name}" '%d' $((
    (REFERENCE_SCOPE_RANK[${scope}] * REFERENCE_RANK_RADIX + location_rank) * REFERENCE_RANK_RADIX
      + MATCH_KIND_RANK[${kind}]
  ))
}

reference_scope() {
  local out_name="$1" match="$2"
  local path="${match%%:*}"
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

  if [[ "${path}" == "gsettings" ]]; then
    printf -v "${out_name}" active
    return 0
  fi

  case "${path}" in
    "${config_home}/hypr/userprefs.lua" | \
      "${config_home}/hypr/userfonts.lua" | \
      "${config_home}/hypr/themes/theme.meta" | \
      "${config_home}/hypr/vars.lua" | \
      "${data_home}/hypr/vars.lua" | \
      "${config_home}/rofi/"* | \
      "${config_home}/dunst/"* | \
      "${config_home}/kitty/"* | \
      "${config_home}/alacritty/"* | \
      "${config_home}/qutebrowser/"* | \
      "${config_home}/swappy/"*)
      printf -v "${out_name}" active
      ;;
    "${config_home}/hypr/themes/"* | \
      "${config_home}/hypr/templates/"* | \
      "${data_home}/rofi/"* | \
      "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/"*)
      printf -v "${out_name}" installed-config
      ;;
    *)
      printf -v "${out_name}" config
      ;;
  esac
}

collect_font_reference_lines() {
  local pkg family alias alias_regex path line_number content reference_text=""
  local -a aliases=() patterns=()
  local -A seen_patterns=() reference_contents=()

  FONT_REFERENCE_LINES=()
  FONT_REFERENCE_CONTENT_FILE="$(mktemp)"
  trap 'rm -f -- "${FONT_REFERENCE_CONTENT_FILE}"' EXIT

  for pkg in "${INSTALLED_FONT_PACKAGES[@]}"; do
    package_families "$pkg" >/dev/null
  done
  while IFS= read -r family; do
    [[ -n "$family" ]] || continue
    family_aliases_into aliases "$family"
    for alias in "${aliases[@]}"; do
      [[ ${#alias} -ge "${MIN_ALIAS_LENGTH}" ]] || continue
      font_reference_regex_into alias_regex "${alias}"
      [[ -z "${seen_patterns[$alias_regex]:-}" ]] || continue
      seen_patterns["$alias_regex"]=1
      patterns+=(-e "${alias_regex}")
    done
  done < <(printf '%s\n' "${PACKAGE_FAMILY_CACHE[@]}" "${LOCAL_FONT_FAMILIES[@]}")
  ((${#patterns[@]})) || return 0

  while IFS=$'\x1f' read -r path line_number content; do
    reference_contents["${path}:${line_number}:${content}"]="${content}"
  done < <(rg "${RG_ARGS[@]}" --field-match-separator=$'\x1f' "${patterns[@]}" -- "${ACTIVE_SEARCH_ROOTS[@]}" 2>/dev/null || true)
  ((${#reference_contents[@]})) || return 0
  mapfile -t FONT_REFERENCE_LINES < <(printf '%s\n' "${!reference_contents[@]}" | sort)
  for content in "${FONT_REFERENCE_LINES[@]}"; do
    reference_text+="${reference_contents[$content]}"$'\n'
  done
  printf '%s' "${reference_text}" >"${FONT_REFERENCE_CONTENT_FILE}"
  reference_text="${reference_text//$'\u212a'/k}"
  FONT_REFERENCE_CASEFOLDED_TEXT="${reference_text//$'\u017f'/s}"
  FONT_REFERENCE_CASEFOLDED_TEXT="${FONT_REFERENCE_CASEFOLDED_TEXT,,}"
}

may_reference_alias() {
  [[ "$1" == *[!\ -~]* || "${FONT_REFERENCE_CASEFOLDED_TEXT}" == *"${1,,}"* ]]
}

find_best_reference_for_family_into() {
  local -n best_reference_ref="$1"
  local family="$2"
  local alias alias_regex match key kind score line_number
  local best_kind=""
  local best_match=""
  local best_score=0
  local -a aliases=()
  local -A seen_matches=()

  best_reference_ref=""
  [[ -n "$family" ]] || return 1
  family_aliases_into aliases "$family"
  for alias in "${aliases[@]}"; do
    [[ ${#alias} -ge "${MIN_ALIAS_LENGTH}" ]] || continue
    font_reference_regex_into alias_regex "${alias}"
    for match in "${LIVE_FONT_REFS[@]:-}"; do
      [[ -n "${match}" ]] && matches_ignoring_case "${match}" "${alias_regex}" || continue
      key="${match}"
      [[ -n "${seen_matches[$key]:-}" ]] && continue
      seen_matches["$key"]=1
      record_best_match best_score best_kind best_match explicit "${match}"
    done
    ((${#FONT_REFERENCE_LINES[@]})) && may_reference_alias "${alias}" || continue
    while IFS=: read -r line_number _; do
      match="${FONT_REFERENCE_LINES[line_number - 1]}"
      [[ -n "${match}" ]] || continue
      is_commented_match "${match}" && continue
      key="${match}"
      [[ -n "${seen_matches[$key]:-}" ]] && continue
      seen_matches["$key"]=1
      classify_match_kind_into kind "$family" "$match"
      record_best_match best_score best_kind best_match "${kind}" "${match}"
    done < <(rg -i -n --no-filename --color=never -e "${alias_regex}" -- "${FONT_REFERENCE_CONTENT_FILE}" 2>/dev/null || true)
  done

  [[ -n "${best_match}" ]] || return 1
  printf -v best_reference_ref '%s\t%s\t%s\t%s' "${best_score}" "${best_kind}" "${family}" "${best_match}"
}

find_best_reference_for_package() {
  local pkg="$1"
  local family reference score match_kind match_family match_path
  local best_kind=""
  local best_family=""
  local best_match=""
  local best_score=0

  while IFS= read -r family; do
    [[ -n "$family" ]] || continue
    find_best_reference_for_family_into reference "$family" || continue
    IFS=$'\t' read -r score match_kind match_family match_path <<<"$reference"
    if ((score > best_score)); then
      best_score=${score}
      best_kind="${match_kind}"
      best_family="${match_family}"
      best_match="${match_path}"
    fi
  done < <(package_families "$pkg")

  if [[ -n "${best_match}" ]]; then
    printf '%s\t%s\t%s\n' "${best_kind}" "${best_family}" "${best_match}"
    return 0
  fi

  return 1
}

classify_packages() {
  ACTIVE_PACKAGES=()
  INSTALLED_CONFIG_PACKAGES=()
  FALLBACK_PACKAGES=()
  UNUSED_PACKAGES=()
  REQUIRED_PACKAGES=()
  PACKAGE_MATCHES=()
  PACKAGE_MATCH_FAMILIES=()

  local pkg reference match_kind match_family match_path match_scope
  for pkg in "${INSTALLED_FONT_PACKAGES[@]}"; do
    [[ "$pkg" =~ $SKIP_PACKAGES_REGEX ]] && continue

    reference=$(find_best_reference_for_package "$pkg" || true)
    if [[ -z "${reference}" ]]; then
      if is_required_by "$pkg"; then
        REQUIRED_PACKAGES+=("$pkg")
      else
        UNUSED_PACKAGES+=("$pkg")
      fi
      continue
    fi

    IFS=$'\t' read -r match_kind match_family match_path <<<"${reference}"
    reference_scope match_scope "${match_path}"
    if [[ "${match_kind}" == "fallback" ]]; then
      FALLBACK_PACKAGES+=("$pkg")
    elif [[ "${match_scope}" == "active" ]]; then
      ACTIVE_PACKAGES+=("$pkg")
    else
      INSTALLED_CONFIG_PACKAGES+=("$pkg")
    fi
    PACKAGE_MATCH_FAMILIES["$pkg"]="${match_family}"
    PACKAGE_MATCHES["$pkg"]="${match_path}"
  done
}

classify_local_families() {
  LOCAL_ACTIVE_FAMILIES=()
  LOCAL_INSTALLED_CONFIG_FAMILIES=()
  LOCAL_FALLBACK_FAMILIES=()
  LOCAL_UNUSED_FAMILIES=()
  LOCAL_MATCHES=()
  UNUSED_LOCAL_FAMILY_MAP=()

  local family reference score match_kind match_family match_path match_scope
  for family in "${LOCAL_FONT_FAMILIES[@]}"; do
    if ! find_best_reference_for_family_into reference "${family}"; then
      LOCAL_UNUSED_FAMILIES+=("${family}")
      UNUSED_LOCAL_FAMILY_MAP["${family}"]=1
      continue
    fi

    IFS=$'\t' read -r score match_kind match_family match_path <<<"${reference}"
    reference_scope match_scope "${match_path}"
    if [[ "${match_kind}" == "fallback" ]]; then
      LOCAL_FALLBACK_FAMILIES+=("${family}")
    elif [[ "${match_scope}" == "active" ]]; then
      LOCAL_ACTIVE_FAMILIES+=("${family}")
    else
      LOCAL_INSTALLED_CONFIG_FAMILIES+=("${family}")
    fi
    LOCAL_MATCHES["${family}"]="${match_path}"
  done
}

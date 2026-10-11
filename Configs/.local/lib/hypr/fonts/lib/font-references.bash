REFERENCE_RANK_RADIX=10
declare -gA REFERENCE_SCOPE_RANK=([active]=2 [config]=1 [installed-config]=0)
declare -gA MATCH_KIND_RANK=([explicit]=2 [fallback]=1)

normalize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

regex_escape() {
  sed 's/[][(){}.^$*+?|\\/]/\\&/g' <<<"$1"
}

font_reference_regex() {
  local escaped=""
  escaped="$(regex_escape "$1")"
  printf '(^|[^[:alnum:]])%s([^[:alnum:]]|$)' "${escaped}"
}

family_aliases() {
  local family="$1"
  local normalized compact alias key
  declare -A seen_aliases=()

  normalized=$(normalize_name "$family")
  compact=$(printf '%s' "$family" | tr -d '[:space:]-_/')

  for alias in "$family" "$compact" "$normalized"; do
    [[ -n "$alias" ]] || continue
    key="${alias,,}"
    [[ -n "${seen_aliases[$key]:-}" ]] && continue
    seen_aliases["$key"]=1
    printf '%s\n' "$alias"
  done
}

classify_match_kind() {
  local family="$1"
  local match="$2"
  local content stack item family_norm item_norm
  local position=0

  family_norm=$(normalize_name "$family")
  content="${match#*:*:}"

  if [[ "${content}" == *"font-family"* ]]; then
    stack="${content#*font-family}"
    stack="${stack#*:}"
    stack="${stack%%;*}"

    while IFS= read -r item; do
      item="$(printf '%s' "${item}" | sed 's/["'\'']//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -n "${item}" ]] || continue
      position=$((position + 1))
      item_norm=$(normalize_name "${item}")
      if [[ "${item_norm}" == *"${family_norm}"* || "${family_norm}" == *"${item_norm}"* ]]; then
        if ((position == 1)); then
          printf 'explicit\n'
        else
          printf 'fallback\n'
        fi
        return 0
      fi
    done < <(printf '%s' "${stack}" | tr ',' '\n')
  fi

  printf 'explicit\n'
}

# The best_* variables belong to the caller.
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

find_best_reference_for_family() {
  local family="$1"
  local alias alias_regex match key kind score
  local best_kind=""
  local best_match=""
  local best_score=0
  local -A seen_matches=()

  [[ -n "$family" ]] || return 1
  while IFS= read -r alias; do
    [[ ${#alias} -ge "${MIN_ALIAS_LENGTH}" ]] || continue
    alias_regex="$(font_reference_regex "${alias}")"
    for match in "${LIVE_FONT_REFS[@]:-}"; do
      [[ -n "${match}" ]] || continue
      if ! grep -Eqi -- "${alias_regex}" <<<"${match}"; then
        continue
      fi
      key="${match}"
      [[ -n "${seen_matches[$key]:-}" ]] && continue
      seen_matches["$key"]=1
      record_best_match best_score best_kind best_match explicit "${match}"
    done
    while IFS= read -r match; do
      [[ -n "${match}" ]] || continue
      is_commented_match "${match}" && continue
      key="${match}"
      [[ -n "${seen_matches[$key]:-}" ]] && continue
      seen_matches["$key"]=1
      record_best_match best_score best_kind best_match "$(classify_match_kind "$family" "$match")" "${match}"
      # rg searches the roots in parallel, so equal-ranked references would
      # otherwise be reported from whichever file happened to match first.
    done < <({ rg "${RG_ARGS[@]}" -- "${alias_regex}" "${ACTIVE_SEARCH_ROOTS[@]}" 2>/dev/null || true; } | sort)
  done < <(family_aliases "$family")

  if [[ -n "${best_match}" ]]; then
    printf '%s\t%s\t%s\t%s\n' "${best_score}" "${best_kind}" "${family}" "${best_match}"
    return 0
  fi

  return 1
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
    reference=$(find_best_reference_for_family "$family" || true)
    [[ -n "${reference}" ]] || continue
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
    reference=$(find_best_reference_for_family "${family}" || true)
    if [[ -z "${reference}" ]]; then
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

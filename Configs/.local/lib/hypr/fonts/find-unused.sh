#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell fonts/find-unused
Audit installed and local fonts not referenced by your config, then optionally remove them." "$@"

FONT_EXT_REGEX='\.(ttf|otf|ttc|otb|pfa|pfb|woff2?)$'
LOCAL_FONT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
SEARCH_ROOTS=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
  "${XDG_CONFIG_HOME:-$HOME/.config}/rofi"
  "${XDG_DATA_HOME:-$HOME/.local/share}/rofi"
  "${XDG_CONFIG_HOME:-$HOME/.config}/dunst"
  "${XDG_CONFIG_HOME:-$HOME/.config}/wlogout"
  "${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
  "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty"
  "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig"
  "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0"
  "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0"
  "${XDG_CONFIG_HOME:-$HOME/.config}/Kvantum"
  "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  "${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
  "${XDG_CONFIG_HOME:-$HOME/.config}/wal"
  "${XDG_CONFIG_HOME:-$HOME/.config}/satty"
  "${LIB_DIR:-$HOME/.local/lib}/hypr"
)
SEARCH_GLOBS=(
  '!**/.git/**'
  '!**/plugins/**'
  '!**/nvm/**'
  '!**/chromium/**'
  '!**/GIMP/**'
  '!**/libreoffice/**'
  '!**/__pycache__/**'
  '!**/tags.xml'
  '!**/shema.toml'
)
GSETTINGS_FONT_KEYS=(
  "org.gnome.desktop.interface font-name"
  "org.gnome.desktop.interface document-font-name"
  "org.gnome.desktop.interface monospace-font-name"
  "org.gnome.desktop.wm.preferences titlebar-font"
)
SKIP_PACKAGES_REGEX='^(fontconfig|lib32-fontconfig|libfontenc|libxfont2|xorg-fonts-encodings)$'
declare -gA PACKAGE_FAMILY_CACHE=()
declare -gA LOCAL_FAMILY_FILES=()
declare -gA LOCAL_FILE_FAMILIES=()
declare -ga ACTIVE_PACKAGES=() INSTALLED_CONFIG_PACKAGES=() FALLBACK_PACKAGES=()
declare -ga UNUSED_PACKAGES=() REQUIRED_PACKAGES=()
declare -gA PACKAGE_MATCHES=() PACKAGE_MATCH_FAMILIES=()
declare -ga LOCAL_ACTIVE_FAMILIES=() LOCAL_INSTALLED_CONFIG_FAMILIES=()
declare -ga LOCAL_FALLBACK_FAMILIES=() LOCAL_UNUSED_FAMILIES=()
declare -gA LOCAL_MATCHES=() UNUSED_LOCAL_FAMILY_MAP=()
declare -ga LOCAL_REMOVABLE_FAMILIES=() LOCAL_KEPT_PROVIDER_FAMILIES=()
declare -gA LOCAL_REMOVABLE_FILE_COUNTS=() LOCAL_PROVIDER_FILE_COUNTS=()
declare -ga REMOVABLE_LOCAL_FILES=()

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
}

normalize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
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

regex_escape() {
  sed 's/[][(){}.^$*+?|\\/]/\\&/g' <<<"$1"
}

font_reference_regex() {
  local escaped=""
  escaped="$(regex_escape "$1")"
  printf '(^|[^[:alnum:]])%s([^[:alnum:]]|$)' "${escaped}"
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
    done < <(package_font_files "$pkg") \
      | tr ',' '\n' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
      | awk 'NF && !seen[tolower($0)]++'
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

  if ((${#families[@]} <= 3)); then
    local joined=""
    printf -v joined '%s, ' "${families[@]}"
    printf '%s' "${joined%, }"
    return
  fi

  printf '%s, %s, %s, ...' "${families[0]}" "${families[1]}" "${families[2]}"
}

family_aliases() {
  local family="$1"
  local normalized compact
  declare -A seen_aliases=()
  local -a aliases=()

  add_alias() {
    local alias="$1"
    local key
    [[ -n "$alias" ]] || return
    key=$(printf '%s' "$alias" | tr '[:upper:]' '[:lower:]')
    [[ -n "${seen_aliases[$key]:-}" ]] && return
    seen_aliases[$key]=1
    aliases+=("$alias")
  }

  normalized=$(normalize_name "$family")
  compact=$(printf '%s' "$family" | tr -d '[:space:]-_/')

  add_alias "$family"
  add_alias "$compact"
  add_alias "$normalized"

  printf '%s\n' "${aliases[@]}"
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

# Keeps the highest-ranked reference seen so far; best_* belong to the caller.
record_best_match() {
  local kind="$1"
  local match="$2"
  local score=""

  score=$(reference_rank "${kind}" "${match}")
  ((score > best_score)) || return 0
  best_score=${score}
  best_kind="${kind}"
  best_match="${match}"
}

is_commented_match() {
  local match="$1"
  local content="${match#*:*:}"

  [[ "${content}" =~ ^[[:space:]]*(#|//|/\*|\*) ]]
}

reference_rank() {
  local kind="$1"
  local match="$2"
  local path="${match%%:*}"
  local base=0

  if [[ "${path}" == "gsettings" ]]; then
    base=30
  elif [[ "${path}" == "${HOME}/.config/"* ]]; then
    base=20
  elif [[ "${path}" == "${HOME}/.local/lib/hypr/"* ]]; then
    base=10
  fi

  # Scope outranks location, so a font carried by both the config in force and
  # an installed theme is reported from the active one. Without this the two
  # score equally and the winner -- and with it the ACTIVE/INSTALLED split the
  # report is built on -- comes down to which file rg happened to match first.
  case "$(reference_scope "${match}")" in
    active) base=$((base + 100)) ;;
    config) base=$((base + 50)) ;;
  esac

  if [[ "${kind}" == "explicit" ]]; then
    printf '%s\n' $((base + 2))
  else
    printf '%s\n' $((base + 1))
  fi
}

reference_scope() {
  local match="$1"
  local path="${match%%:*}"
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

  if [[ "${path}" == "gsettings" ]]; then
    printf 'active\n'
    return 0
  fi

  case "${path}" in
    "${config_home}/hypr/userfonts.lua" | \
      "${config_home}/hypr/themes/theme.meta" | \
      "${config_home}/hypr/variables.meta" | \
      "${data_home}/hypr/variables.meta" | \
      "${config_home}/rofi/"* | \
      "${config_home}/dunst/"* | \
      "${config_home}/wlogout/"* | \
      "${config_home}/kitty/"* | \
      "${config_home}/alacritty/"* | \
      "${config_home}/qutebrowser/"* | \
      "${config_home}/satty/"*)
      printf 'active\n'
      ;;
    "${config_home}/hypr/themes/"* | \
      "${config_home}/wal/templates/"* | \
      "${data_home}/rofi/"* | \
      "${LIB_DIR:-$HOME/.local/lib}/hypr/"*)
      printf 'installed-config\n'
      ;;
    *)
      printf 'config\n'
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
    [[ ${#alias} -ge 4 ]] || continue
    alias_regex="$(font_reference_regex "${alias}")"
    for match in "${LIVE_FONT_REFS[@]:-}"; do
      [[ -n "${match}" ]] || continue
      if ! grep -Eqi -- "${alias_regex}" <<<"${match}"; then
        continue
      fi
      key="${match}"
      [[ -n "${seen_matches[$key]:-}" ]] && continue
      seen_matches["$key"]=1
      record_best_match explicit "${match}"
    done
    while IFS= read -r match; do
      [[ -n "${match}" ]] || continue
      is_commented_match "${match}" && continue
      key="${match}"
      [[ -n "${seen_matches[$key]:-}" ]] && continue
      seen_matches["$key"]=1
      record_best_match "$(classify_match_kind "$family" "$match")" "${match}"
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
    done < <(
      fc-scan --format '%{family}\n' "${font_file}" 2>/dev/null \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | awk 'NF && !seen[tolower($0)]++'
    )
  done < <(
    find "${LOCAL_FONT_ROOT}" -type f \
      \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' -o -iname '*.otb' -o -iname '*.pfa' -o -iname '*.pfb' -o -iname '*.woff' -o -iname '*.woff2' \) \
      2>/dev/null | sort
  )
}

print_header() {
  echo "Finding fonts referenced by your runtime config..."
  echo
  if ((${#LIVE_FONT_REFS[@]} > 0)); then
    echo "Inspecting live gsettings font keys:"
    local live_ref
    for live_ref in "${LIVE_FONT_REFS[@]}"; do
      echo "  • ${live_ref#gsettings: }"
    done
    echo
  fi
  echo "Scanning these roots:"
  local root
  for root in "${ACTIVE_SEARCH_ROOTS[@]}"; do
    echo "  • $root"
  done
  echo
  echo "Scanning installed font packages..."
  if [[ -d "${LOCAL_FONT_ROOT}" ]]; then
    echo "Scanning local font families in ${LOCAL_FONT_ROOT}..."
  fi
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
    match_scope="$(reference_scope "${match_path}")"
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
    match_scope="$(reference_scope "${match_path}")"
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

family_files() {
  printf '%s' "${LOCAL_FAMILY_FILES[$1]}" | sed '/^$/d' | sort -u
}

# A file is only safe to delete when every family it provides is itself
# unreferenced -- one live alias keeps the whole file. This is the sole
# criterion for both the count that is reported and the files that are removed.
file_is_removable() {
  local file_family
  while IFS= read -r file_family; do
    [[ -n "${file_family}" ]] || continue
    [[ -n "${UNUSED_LOCAL_FAMILY_MAP[$file_family]:-}" ]] || return 1
  done <<<"${LOCAL_FILE_FAMILIES[$1]}"
}

partition_unused_local_families() {
  LOCAL_REMOVABLE_FAMILIES=()
  LOCAL_KEPT_PROVIDER_FAMILIES=()
  LOCAL_REMOVABLE_FILE_COUNTS=()
  LOCAL_PROVIDER_FILE_COUNTS=()

  local family file_path file_count safe_file_count
  for family in "${LOCAL_UNUSED_FAMILIES[@]}"; do
    file_count=0
    safe_file_count=0
    while IFS= read -r file_path; do
      [[ -n "${file_path}" ]] || continue
      file_count=$((file_count + 1))
      file_is_removable "${file_path}" && safe_file_count=$((safe_file_count + 1))
    done < <(family_files "${family}")

    LOCAL_REMOVABLE_FILE_COUNTS["${family}"]="${safe_file_count}"
    LOCAL_PROVIDER_FILE_COUNTS["${family}"]="${file_count}"
    if ((safe_file_count > 0)); then
      LOCAL_REMOVABLE_FAMILIES+=("${family}")
    else
      LOCAL_KEPT_PROVIDER_FAMILIES+=("${family}")
    fi
  done
}

collect_removable_local_files() {
  REMOVABLE_LOCAL_FILES=()
  local -A seen=()
  local family file_path
  for family in "${LOCAL_REMOVABLE_FAMILIES[@]}"; do
    while IFS= read -r file_path; do
      [[ -n "${file_path}" ]] || continue
      [[ -n "${seen[$file_path]:-}" ]] && continue
      file_is_removable "${file_path}" || continue
      seen["${file_path}"]=1
      REMOVABLE_LOCAL_FILES+=("${file_path}")
    done < <(family_files "${family}")
  done
}

section_header() {
  echo
  echo "======================================"
  echo "$1"
  echo "======================================"
}

# Renders one classified package list; the array is passed by name because the
# four lists differ only in their heading and bullet.
print_package_section() {
  local heading="$1" empty_message="$2" bullet="$3"
  local -n packages_ref="$4"
  local pkg

  section_header "${heading}"
  if ((${#packages_ref[@]} == 0)); then
    echo "  ${empty_message}"
    return
  fi
  for pkg in "${packages_ref[@]}"; do
    echo "  ${bullet} $pkg (${PACKAGE_MATCH_FAMILIES[$pkg]})"
    echo "    ↳ ${PACKAGE_MATCHES[$pkg]}"
  done
}

print_local_family_group() {
  local heading="$1" bullet="$2"
  local -n families_ref="$3"
  local family

  ((${#families_ref[@]} > 0)) || return 0
  echo "  ${heading}"
  for family in "${families_ref[@]}"; do
    echo "    ${bullet} ${family}"
    echo "      ↳ ${LOCAL_MATCHES[$family]}"
  done
}

report_unused_packages() {
  local pkg reply

  section_header "UNREFERENCED PACKAGE FONTS:"
  if ((${#UNUSED_PACKAGES[@]} == 0)); then
    echo "  No unreferenced removable font packages found."
    return
  fi

  for pkg in "${UNUSED_PACKAGES[@]}"; do
    echo "  ✗ $pkg ($(installed_size "$pkg"))"
    echo "    families: $(summarize_families "$pkg")"
  done

  echo
  echo "Total likely unused font packages: ${#UNUSED_PACKAGES[@]}"
  echo

  if [[ -t 0 ]]; then
    read -r -p "Remove all unreferenced package fonts with pacman? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      echo
      echo "Removing unreferenced package fonts..."
      sudo pacman -Rns "${UNUSED_PACKAGES[@]}"
      echo
      echo "Unreferenced package fonts removed."
      return
    fi
    echo
  fi

  echo "To remove them manually, run:"
  echo "  sudo pacman -Rns ${UNUSED_PACKAGES[*]}"
}

report_unused_local_families() {
  local family reply safe_file_count file_count

  if ((${#LOCAL_UNUSED_FAMILIES[@]} == 0)); then
    echo "  No unreferenced local font families found."
    return
  fi

  partition_unused_local_families

  if ((${#LOCAL_REMOVABLE_FAMILIES[@]} == 0)); then
    echo "  No unreferenced removable local font files found."
  else
    echo "  Unreferenced removable files:"
    for family in "${LOCAL_REMOVABLE_FAMILIES[@]}"; do
      safe_file_count="${LOCAL_REMOVABLE_FILE_COUNTS[$family]}"
      file_count="${LOCAL_PROVIDER_FILE_COUNTS[$family]}"
      if ((safe_file_count == file_count)); then
        echo "    ✗ ${family} (${safe_file_count} files)"
      else
        echo "    ✗ ${family} (${safe_file_count} removable files, ${file_count} provider files)"
      fi
    done
  fi

  if ((${#LOCAL_KEPT_PROVIDER_FAMILIES[@]} > 0)); then
    echo "  Unreferenced aliases in kept font files:"
    for family in "${LOCAL_KEPT_PROVIDER_FAMILIES[@]}"; do
      echo "    • ${family} (${LOCAL_PROVIDER_FILE_COUNTS[$family]} provider files)"
    done
  fi

  ((${#LOCAL_REMOVABLE_FAMILIES[@]} > 0)) || return 0

  if [[ ! -t 0 ]]; then
    echo
    echo "Run this script interactively to remove unreferenced local font files."
    return 0
  fi

  read -r -p "Remove unreferenced local font files from ${LOCAL_FONT_ROOT}? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo
    echo "No local font files removed."
    return 0
  fi

  collect_removable_local_files
  if ((${#REMOVABLE_LOCAL_FILES[@]} > 0)); then
    rm -f -- "${REMOVABLE_LOCAL_FILES[@]}"
    fc-cache -fq 2>/dev/null || true
    echo
    echo "Removed ${#REMOVABLE_LOCAL_FILES[@]} unreferenced local font files."
  fi
}

report_local_families() {
  section_header "LOCAL FONT FAMILIES:"
  if ((${#LOCAL_FONT_FAMILIES[@]} == 0)); then
    echo "  No local font families found in ${LOCAL_FONT_ROOT}."
    return
  fi

  print_local_family_group "Active:" "✓" LOCAL_ACTIVE_FAMILIES
  print_local_family_group "Used by installed themes/templates:" "•" LOCAL_INSTALLED_CONFIG_FAMILIES
  print_local_family_group "Fallback-only:" "•" LOCAL_FALLBACK_FAMILIES
  report_unused_local_families
}

report_required_packages() {
  local pkg

  ((${#REQUIRED_PACKAGES[@]} > 0)) || return 0
  section_header "REQUIRED BY APPS OR LIBRARIES:"
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    echo "  • $pkg (required by: $(required_by_list "$pkg"))"
  done
}

print_notes() {
  section_header "NOTES:"
  echo "  • Active references are current live config, generated app config, or gsettings."
  echo "  • Installed theme/template references are not active now, but removing them can break that theme later."
  echo "  • Matches are based on actual font family names referenced in your config roots."
  echo "  • Live gsettings font keys are audited as explicit desktop-font usage when available."
  echo "  • Fallback-only means the family appears later in a CSS font stack; other matches count as explicit."
  echo "  • Local font removal deletes font files only; empty directories are left in place."
}

main() {
  require_cmd pacman
  require_cmd rg
  require_cmd fc-scan

  collect_search_roots
  build_rg_args
  collect_live_font_refs
  collect_installed_font_packages
  print_header
  collect_local_font_families

  classify_packages
  classify_local_families

  print_package_section "ACTIVE PACKAGE FONT REFERENCES:" \
    "No active package font references found." "✓" ACTIVE_PACKAGES
  print_package_section "INSTALLED THEME/TEMPLATE PACKAGE REFERENCES:" \
    "No package fonts are kept only by installed themes/templates." "•" INSTALLED_CONFIG_PACKAGES
  print_package_section "FALLBACK-ONLY FONT REFERENCES:" \
    "No fallback-only font references found." "•" FALLBACK_PACKAGES

  report_unused_packages
  report_local_families
  report_required_packages
  print_notes
}

main "$@"

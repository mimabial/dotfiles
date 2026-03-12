#!/usr/bin/env bash

set -euo pipefail

FONT_EXT_REGEX='\.(ttf|otf|ttc|otb|pfa|pfb|woff2?)$'
SEARCH_ROOTS=(
  "$HOME/.config/hypr"
  "$HOME/.config/rofi"
  "$HOME/.config/waybar"
  "$HOME/.config/swaync"
  "$HOME/.config/wlogout"
  "$HOME/.config/kitty"
  "$HOME/.config/alacritty"
  "$HOME/.config/qutebrowser"
  "$HOME/.config/qt5ct"
  "$HOME/.config/qt6ct"
  "$HOME/.config/wal"
  "$HOME/.config/satty"
  "$HOME/.local/lib/hypr"
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
  RG_ARGS=(-n -i -F --color=never)
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
        if (( position == 1 )); then
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

  if [[ "${kind}" == "explicit" ]]; then
    printf '%s\n' $((base + 2))
  else
    printf '%s\n' $((base + 1))
  fi
}

find_best_reference_for_package() {
  local pkg="$1"
  local family alias match key kind score
  local best_kind=""
  local best_family=""
  local best_match=""
  local best_score=0
  local -A seen_matches=()

  while IFS= read -r family; do
    [[ -n "$family" ]] || continue
    while IFS= read -r alias; do
      [[ ${#alias} -ge 4 ]] || continue
      for match in "${LIVE_FONT_REFS[@]:-}"; do
        [[ -n "${match}" ]] || continue
        if ! grep -Fqi -- "${alias}" <<<"${match}"; then
          continue
        fi
        key="${match}"
        [[ -n "${seen_matches[$key]:-}" ]] && continue
        seen_matches["$key"]=1
        kind="explicit"
        score=$(reference_rank "${kind}" "${match}")
        if (( score > best_score )); then
          best_score=${score}
          best_kind="${kind}"
          best_family="${family}"
          best_match="${match}"
        fi
      done
      while IFS= read -r match; do
        [[ -n "${match}" ]] || continue
        key="${match}"
        [[ -n "${seen_matches[$key]:-}" ]] && continue
        seen_matches["$key"]=1
        kind=$(classify_match_kind "$family" "$match")
        score=$(reference_rank "${kind}" "${match}")
        if (( score > best_score )); then
          best_score=${score}
          best_kind="${kind}"
          best_family="${family}"
          best_match="${match}"
        fi
      done < <(rg "${RG_ARGS[@]}" -- "$alias" "${ACTIVE_SEARCH_ROOTS[@]}" 2>/dev/null || true)
    done < <(family_aliases "$family")
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
  done < <(pacman -Qq | grep -Ei 'font|ttf|otf|nerd' | sort)

  for pkg in "${candidates[@]}"; do
    if package_font_files "$pkg" | grep -q .; then
      INSTALLED_FONT_PACKAGES+=("$pkg")
    fi
  done
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

  local -a explicit_packages=()
  local -a fallback_packages=()
  local -a unused_packages=()
  local -a required_packages=()
  declare -A package_matches=()
  declare -A package_match_families=()
  declare -A package_match_kinds=()

  local pkg reference match_kind match_family match_path
  for pkg in "${INSTALLED_FONT_PACKAGES[@]}"; do
    if [[ "$pkg" =~ $SKIP_PACKAGES_REGEX ]]; then
      continue
    fi

    reference=$(find_best_reference_for_package "$pkg" || true)
    if [[ -n "$reference" ]]; then
      IFS=$'\t' read -r match_kind match_family match_path <<<"$reference"
      if [[ "${match_kind}" == "explicit" ]]; then
        explicit_packages+=("$pkg")
      else
        fallback_packages+=("$pkg")
      fi
      package_match_kinds["$pkg"]="$match_kind"
      package_match_families["$pkg"]="$match_family"
      package_matches["$pkg"]="$match_path"
      continue
    fi

    if is_required_by "$pkg"; then
      required_packages+=("$pkg")
      continue
    fi

    unused_packages+=("$pkg")
  done

  echo
  echo "======================================"
  echo "EXPLICIT FONT REFERENCES:"
  echo "======================================"
  if ((${#explicit_packages[@]} == 0)); then
    echo "  No explicit font references found."
  else
    for pkg in "${explicit_packages[@]}"; do
      echo "  ✓ $pkg (${package_match_families[$pkg]})"
      echo "    ↳ ${package_matches[$pkg]}"
    done
  fi

  echo
  echo "======================================"
  echo "FALLBACK-ONLY FONT REFERENCES:"
  echo "======================================"
  if ((${#fallback_packages[@]} == 0)); then
    echo "  No fallback-only font references found."
  else
    for pkg in "${fallback_packages[@]}"; do
      echo "  • $pkg (${package_match_families[$pkg]})"
      echo "    ↳ ${package_matches[$pkg]}"
    done
  fi

  echo
  echo "======================================"
  echo "LIKELY UNUSED FONT PACKAGES:"
  echo "======================================"
  if ((${#unused_packages[@]} == 0)); then
    echo "  No removable font packages found."
  else
    for pkg in "${unused_packages[@]}"; do
      echo "  ✗ $pkg ($(installed_size "$pkg"))"
      echo "    families: $(summarize_families "$pkg")"
    done

    echo
    echo "Total likely unused font packages: ${#unused_packages[@]}"
    echo

    if [[ -t 0 ]]; then
      read -r -p "Do you want to remove all likely unused font packages? [y/N] " reply
      if [[ "$reply" =~ ^[Yy]$ ]]; then
        echo
        echo "Removing unused font packages..."
        sudo pacman -Rns "${unused_packages[@]}"
        echo
        echo "Unused font packages removed."
      else
        echo
        echo "To remove them manually, run:"
        echo "  sudo pacman -Rns ${unused_packages[*]}"
      fi
    else
      echo "To remove them manually, run:"
      echo "  sudo pacman -Rns ${unused_packages[*]}"
    fi
  fi

  if ((${#required_packages[@]} > 0)); then
    echo
    echo "======================================"
    echo "REQUIRED BY APPS OR LIBRARIES:"
    echo "======================================"
    for pkg in "${required_packages[@]}"; do
      echo "  • $pkg (required by: $(required_by_list "$pkg"))"
    done
  fi

  echo
  echo "======================================"
  echo "NOTES:"
  echo "======================================"
  echo "  • This audit only checks package-managed fonts."
  echo "  • Local fonts under ~/.local/share/fonts are not candidates for pacman removal."
  echo "  • Matches are based on actual font family names referenced in your config roots."
  echo "  • Live gsettings font keys are audited as explicit desktop-font usage when available."
  echo "  • Fallback-only means the family appears later in a CSS font stack; other matches count as explicit."
}

main "$@"

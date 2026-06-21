#!/usr/bin/env bash

set -euo pipefail

FONT_EXT_REGEX='\.(ttf|otf|ttc|otb|pfa|pfb|woff2?)$'
LOCAL_FONT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
SEARCH_ROOTS=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
  "${XDG_CONFIG_HOME:-$HOME/.config}/rofi"
  "${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
  "${XDG_DATA_HOME:-$HOME/.local/share}/rofi"
  "${XDG_DATA_HOME:-$HOME/.local/share}/waybar"
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
    "${config_home}/hypr/userfonts.conf" | \
      "${config_home}/hypr/themes/theme.conf" | \
      "${config_home}/hypr/variables.conf" | \
      "${data_home}/hypr/variables.conf" | \
      "${config_home}/waybar/"* | \
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
      "${data_home}/waybar/"* | \
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
      kind="explicit"
      score=$(reference_rank "${kind}" "${match}")
      if ((score > best_score)); then
        best_score=${score}
        best_kind="${kind}"
        best_match="${match}"
      fi
    done
    while IFS= read -r match; do
      [[ -n "${match}" ]] || continue
      is_commented_match "${match}" && continue
      key="${match}"
      [[ -n "${seen_matches[$key]:-}" ]] && continue
      seen_matches["$key"]=1
      kind=$(classify_match_kind "$family" "$match")
      score=$(reference_rank "${kind}" "${match}")
      if ((score > best_score)); then
        best_score=${score}
        best_kind="${kind}"
        best_match="${match}"
      fi
    done < <(rg "${RG_ARGS[@]}" -- "${alias_regex}" "${ACTIVE_SEARCH_ROOTS[@]}" 2>/dev/null || true)
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

  local -a active_packages=()
  local -a installed_config_packages=()
  local -a fallback_packages=()
  local -a unused_packages=()
  local -a required_packages=()
  declare -A package_matches=()
  declare -A package_match_families=()
  declare -A package_match_kinds=()
  declare -A package_match_scopes=()

  local pkg reference match_kind match_family match_path match_scope
  for pkg in "${INSTALLED_FONT_PACKAGES[@]}"; do
    if [[ "$pkg" =~ $SKIP_PACKAGES_REGEX ]]; then
      continue
    fi

    reference=$(find_best_reference_for_package "$pkg" || true)
    if [[ -n "$reference" ]]; then
      IFS=$'\t' read -r match_kind match_family match_path <<<"$reference"
      match_scope="$(reference_scope "${match_path}")"
      if [[ "${match_kind}" == "fallback" ]]; then
        fallback_packages+=("$pkg")
      elif [[ "${match_scope}" == "active" ]]; then
        active_packages+=("$pkg")
      else
        installed_config_packages+=("$pkg")
      fi
      package_match_kinds["$pkg"]="$match_kind"
      package_match_families["$pkg"]="$match_family"
      package_match_scopes["$pkg"]="$match_scope"
      package_matches["$pkg"]="$match_path"
      continue
    fi

    if is_required_by "$pkg"; then
      required_packages+=("$pkg")
      continue
    fi

    unused_packages+=("$pkg")
  done

  local -a local_active_families=()
  local -a local_installed_config_families=()
  local -a local_fallback_families=()
  local -a local_unused_families=()
  declare -A local_matches=()
  declare -A local_match_kinds=()
  declare -A local_match_scopes=()

  local family score
  for family in "${LOCAL_FONT_FAMILIES[@]:-}"; do
    reference=$(find_best_reference_for_family "${family}" || true)
    if [[ -n "${reference}" ]]; then
      IFS=$'\t' read -r score match_kind match_family match_path <<<"${reference}"
      match_scope="$(reference_scope "${match_path}")"
      if [[ "${match_kind}" == "fallback" ]]; then
        local_fallback_families+=("${family}")
      elif [[ "${match_scope}" == "active" ]]; then
        local_active_families+=("${family}")
      else
        local_installed_config_families+=("${family}")
      fi
      local_match_kinds["${family}"]="${match_kind}"
      local_match_scopes["${family}"]="${match_scope}"
      local_matches["${family}"]="${match_path}"
      continue
    fi

    local_unused_families+=("${family}")
  done

  declare -A unused_local_family_map=()
  for family in "${local_unused_families[@]}"; do
    unused_local_family_map["${family}"]=1
  done

  echo
  echo "======================================"
  echo "ACTIVE PACKAGE FONT REFERENCES:"
  echo "======================================"
  if ((${#active_packages[@]} == 0)); then
    echo "  No active package font references found."
  else
    for pkg in "${active_packages[@]}"; do
      echo "  ✓ $pkg (${package_match_families[$pkg]})"
      echo "    ↳ ${package_matches[$pkg]}"
    done
  fi

  echo
  echo "======================================"
  echo "INSTALLED THEME/TEMPLATE PACKAGE REFERENCES:"
  echo "======================================"
  if ((${#installed_config_packages[@]} == 0)); then
    echo "  No package fonts are kept only by installed themes/templates."
  else
    for pkg in "${installed_config_packages[@]}"; do
      echo "  • $pkg (${package_match_families[$pkg]})"
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
  echo "UNREFERENCED PACKAGE FONTS:"
  echo "======================================"
  if ((${#unused_packages[@]} == 0)); then
    echo "  No unreferenced removable font packages found."
  else
    for pkg in "${unused_packages[@]}"; do
      echo "  ✗ $pkg ($(installed_size "$pkg"))"
      echo "    families: $(summarize_families "$pkg")"
    done

    echo
    echo "Total likely unused font packages: ${#unused_packages[@]}"
    echo

    if [[ -t 0 ]]; then
      read -r -p "Remove all unreferenced package fonts with pacman? [y/N] " reply
      if [[ "$reply" =~ ^[Yy]$ ]]; then
        echo
        echo "Removing unreferenced package fonts..."
        sudo pacman -Rns "${unused_packages[@]}"
        echo
        echo "Unreferenced package fonts removed."
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

  echo
  echo "======================================"
  echo "LOCAL FONT FAMILIES:"
  echo "======================================"
  if ((${#LOCAL_FONT_FAMILIES[@]} == 0)); then
    echo "  No local font families found in ${LOCAL_FONT_ROOT}."
  else
    if ((${#local_active_families[@]} > 0)); then
      echo "  Active:"
      for family in "${local_active_families[@]}"; do
        echo "    ✓ ${family}"
        echo "      ↳ ${local_matches[$family]}"
      done
    fi

    if ((${#local_installed_config_families[@]} > 0)); then
      echo "  Used by installed themes/templates:"
      for family in "${local_installed_config_families[@]}"; do
        echo "    • ${family}"
        echo "      ↳ ${local_matches[$family]}"
      done
    fi

    if ((${#local_fallback_families[@]} > 0)); then
      echo "  Fallback-only:"
      for family in "${local_fallback_families[@]}"; do
        echo "    • ${family}"
        echo "      ↳ ${local_matches[$family]}"
      done
    fi

    if ((${#local_unused_families[@]} == 0)); then
      echo "  No unreferenced local font families found."
    else
      local -a local_removable_families=()
      local -a local_kept_provider_families=()
      declare -A local_removable_file_counts=()
      declare -A local_provider_file_counts=()
      local file_count safe_file_count file_path file_family file_is_unreferenced

      for family in "${local_unused_families[@]}"; do
        file_count="$(printf '%s' "${LOCAL_FAMILY_FILES[$family]}" | sed '/^$/d' | sort -u | wc -l)"
        safe_file_count=0
        while IFS= read -r file_path; do
          [[ -n "${file_path}" ]] || continue
          file_is_unreferenced=1
          while IFS= read -r file_family; do
            [[ -n "${file_family}" ]] || continue
            if [[ -z "${unused_local_family_map[$file_family]:-}" ]]; then
              file_is_unreferenced=0
              break
            fi
          done <<<"${LOCAL_FILE_FAMILIES[$file_path]}"
          if ((file_is_unreferenced == 1)); then
            safe_file_count=$((safe_file_count + 1))
          fi
        done < <(printf '%s' "${LOCAL_FAMILY_FILES[$family]}" | sed '/^$/d' | sort -u)

        local_removable_file_counts["${family}"]="${safe_file_count}"
        local_provider_file_counts["${family}"]="${file_count}"
        if ((safe_file_count > 0)); then
          local_removable_families+=("${family}")
        else
          local_kept_provider_families+=("${family}")
        fi
      done

      if ((${#local_removable_families[@]} > 0)); then
        echo "  Unreferenced removable files:"
        for family in "${local_removable_families[@]}"; do
          safe_file_count="${local_removable_file_counts[$family]}"
          file_count="${local_provider_file_counts[$family]}"
          if ((safe_file_count == file_count)); then
            echo "    ✗ ${family} (${safe_file_count} files)"
          else
            echo "    ✗ ${family} (${safe_file_count} removable files, ${file_count} provider files)"
          fi
        done
      else
        echo "  No unreferenced removable local font files found."
      fi

      if ((${#local_kept_provider_families[@]} > 0)); then
        echo "  Unreferenced aliases in kept font files:"
        for family in "${local_kept_provider_families[@]}"; do
          echo "    • ${family} (${local_provider_file_counts[$family]} provider files)"
        done
      fi

      if ((${#local_removable_families[@]} > 0)) && [[ -t 0 ]]; then
        read -r -p "Remove unreferenced local font files from ${LOCAL_FONT_ROOT}? [y/N] " reply
        if [[ "$reply" =~ ^[Yy]$ ]]; then
          local -a local_remove_files=()
          declare -A seen_local_remove_files=()

          for family in "${local_removable_families[@]}"; do
            while IFS= read -r file_path; do
              [[ -n "${file_path}" ]] || continue
              [[ -n "${seen_local_remove_files[$file_path]:-}" ]] && continue

              file_is_unreferenced=1
              while IFS= read -r file_family; do
                [[ -n "${file_family}" ]] || continue
                if [[ -z "${unused_local_family_map[$file_family]:-}" ]]; then
                  file_is_unreferenced=0
                  break
                fi
              done <<<"${LOCAL_FILE_FAMILIES[$file_path]}"
              ((file_is_unreferenced == 1)) || continue

              seen_local_remove_files["$file_path"]=1
              local_remove_files+=("${file_path}")
            done <<<"${LOCAL_FAMILY_FILES[$family]}"
          done

          if ((${#local_remove_files[@]} > 0)); then
            rm -f -- "${local_remove_files[@]}"
            fc-cache -fq 2>/dev/null || true
            echo
            echo "Removed ${#local_remove_files[@]} unreferenced local font files."
          fi
        else
          echo
          echo "No local font files removed."
        fi
      elif ((${#local_removable_families[@]} > 0)); then
        echo
        echo "Run this script interactively to remove unreferenced local font files."
      fi
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
  echo "  • Active references are current live config, generated app config, or gsettings."
  echo "  • Installed theme/template references are not active now, but removing them can break that theme later."
  echo "  • Matches are based on actual font family names referenced in your config roots."
  echo "  • Live gsettings font keys are audited as explicit desktop-font usage when available."
  echo "  • Fallback-only means the family appears later in a CSS font stack; other matches count as explicit."
  echo "  • Local font removal deletes font files only; empty directories are left in place."
}

main "$@"

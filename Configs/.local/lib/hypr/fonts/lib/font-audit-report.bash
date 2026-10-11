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

section_header() {
  echo
  echo "======================================"
  echo "$1"
  echo "======================================"
}

# The array goes by name because the four lists differ only in their heading and
# bullet.
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
  local pkg

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
}

offer_unused_package_removal() {
  local reply=""

  ((${#UNUSED_PACKAGES[@]} > 0)) || return 0
  if [[ -t 0 ]]; then
    read -r -p "Remove all unreferenced package fonts with pacman? [y/N] " reply
    echo
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      echo "Removing unreferenced package fonts..."
      if sudo pacman -Rns "${UNUSED_PACKAGES[@]}"; then
        echo
        echo "Unreferenced package fonts removed."
        return 0
      fi
      echo
      echo "pacman did not remove the unreferenced package fonts."
    fi
  fi

  echo "To remove them manually, run:"
  echo "  sudo pacman -Rns ${UNUSED_PACKAGES[*]}"
}

report_unused_local_families() {
  local family safe_file_count file_count

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

}

offer_unused_local_file_removal() {
  local reply=""

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
  ((${#REMOVABLE_LOCAL_FILES[@]} > 0)) || return 0
  echo
  if rm -f -- "${REMOVABLE_LOCAL_FILES[@]}"; then
    echo "Removed ${#REMOVABLE_LOCAL_FILES[@]} unreferenced local font files."
  else
    echo "Some unreferenced local font files could not be removed."
  fi
  fc-cache -fq 2>/dev/null || true
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

#!/usr/bin/env bash
# pywal16.vscode.sh - Install and activate pywal16 theme in VSCode variants

confDir="${XDG_CONFIG_HOME:-$HOME/.config}"
cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
THEME_NAME="pywal16"
THEME_JSON="${cacheDir}/colors-vscode.json"

# Exit if theme JSON doesn't exist
[ ! -f "${THEME_JSON}" ] && exit 0

# Find all VSCode-like editors (with timeout protection)
readarray -t code_dirs < <(find -L "$confDir" -mindepth 1 -maxdepth 1 -type d \( -name "Code*" -o -name "VSCodium*" -o -name "Cursor*" \) 2>/dev/null | sort)

# Exit early if no editors found
[ ${#code_dirs[@]} -eq 0 ] && exit 0

for dir in "${code_dirs[@]}"; do
  # Skip empty entries
  [ -z "$dir" ] && continue
  # Determine extensions directory based on editor type
  if [[ "$(basename "$dir")" == *"OSS"* ]] || [[ "$(basename "$dir")" == *"VSCodium"* ]]; then
    ext_dir="$dir/extensions/pywal16-theme"
  else
    ext_dir="$HOME/.vscode/extensions/pywal16-theme"
  fi

  # Create extension directory
  mkdir -p "$ext_dir/themes" 2>/dev/null || continue

  # Copy theme JSON
  cp "${THEME_JSON}" "$ext_dir/themes/pywal16.json" 2>/dev/null || continue

  # Create package.json manifest
  cat > "$ext_dir/package.json" <<'EOF'
{
  "name": "pywal16-theme",
  "displayName": "Pywal16 Theme",
  "description": "Dynamic color theme generated from pywal16",
  "version": "1.0.0",
  "publisher": "pywal16",
  "engines": {
    "vscode": "^1.60.0"
  },
  "categories": [
    "Themes"
  ],
  "contributes": {
    "themes": [
      {
        "label": "Pywal16",
        "uiTheme": "vs-dark",
        "path": "./themes/pywal16.json"
      }
    ]
  }
}
EOF

  # Set theme preference in settings
  settings_file="$dir/User/settings.json"

  # Create settings file if doesn't exist
  if [ ! -f "$settings_file" ]; then
    mkdir -p "$dir/User"
    echo '{"workbench.colorTheme": "Pywal16"}' >"$settings_file"
    continue
  fi

  # Check if theme is already set
  if grep -q '"workbench.colorTheme".*"Pywal16"' "$settings_file"; then
    continue
  fi

  # Set theme using jq if available, otherwise manual
  if command -v jq &>/dev/null; then
    tmp=$(mktemp)
    if jq '.["workbench.colorTheme"] = "Pywal16"' "$settings_file" >"$tmp" 2>/dev/null; then
      mv "$tmp" "$settings_file" 2>/dev/null || rm -f "$tmp"
    else
      rm -f "$tmp" 2>/dev/null
    fi
  else
    # Simple sed replacement
    if grep -q '"workbench.colorTheme"' "$settings_file" 2>/dev/null; then
      sed -i 's/"workbench.colorTheme".*/"workbench.colorTheme": "Pywal16",/' "$settings_file" 2>/dev/null
    else
      sed -i '1 a\  "workbench.colorTheme": "Pywal16",' "$settings_file" 2>/dev/null
    fi
  fi
done

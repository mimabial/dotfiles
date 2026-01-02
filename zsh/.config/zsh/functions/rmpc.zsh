function rmpc() {
  local config_path="$HOME/.config/rmpc/config.ron"
  local theme_dir="$HOME/.config/rmpc/themes"
  local backup_path="${config_path}.bak"
  local rows=""
  local cols=""
  local size=""

  if [[ -f "$backup_path" ]] && [[ -f "$config_path" ]] && [[ "$config_path" -nt "$backup_path" ]]; then
    rm -f "$backup_path"
  fi

  size="$(stty size </dev/tty 2>/dev/null)"
  if [[ -n "$size" ]]; then
    read -r rows cols <<< "$size"
  fi
  rows="${rows:-${LINES:-24}}"
  cols="${cols:-${COLUMNS:-80}}"

  local base_theme="pywal16"
  local small_theme="pywal16-small"
  local big_theme="pywal16-big"

  local target_theme=""
  if (( cols < 90 && rows < 30 )); then
    target_theme="$small_theme"
  elif (( cols < 90 || rows < 30 )); then
    target_theme="$base_theme"
  else
    target_theme="$big_theme"
  fi

  local target_theme_path="${theme_dir}/${target_theme}.ron"

  if [[ -f "$config_path" ]] && [[ -f "$target_theme_path" ]]; then
    local current_theme=""
    current_theme="$(grep -oP 'theme:\s*Some\("\K[^"]+' "$config_path" 2>/dev/null || true)"
    if [[ "$current_theme" != "$target_theme" ]]; then
      cp "$config_path" "$backup_path"
      sed -i "s/theme: Some(\"[^\"]*\")/theme: Some(\"$target_theme\")/" "$config_path"

      local tabs_file=""
      tabs_file="$(mktemp)"
      awk '
        /^    tabs:[[:space:]]*\[/ { in_tabs=1 }
        in_tabs { print }
        in_tabs && /^    \],?[[:space:]]*$/ { exit }
      ' "$target_theme_path" > "$tabs_file"

      if [[ -s "$tabs_file" ]] && command -v python3 &>/dev/null; then
        TABS_PATH="$tabs_file" python3 << 'PYEOF'
import os

config_path = os.path.expanduser("~/.config/rmpc/config.ron")
tabs_path = os.environ["TABS_PATH"]

with open(config_path, "r") as f:
    lines = f.readlines()

with open(tabs_path, "r") as f:
    tabs_content = f.read()

new_lines = []
in_tabs = False
tabs_indent_level = None

for line in lines:
    if "    tabs:" in line and "[" in line:
        in_tabs = True
        tabs_indent_level = len(line) - len(line.lstrip())
        continue

    if in_tabs:
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == tabs_indent_level and stripped in ("],", "]"):
            in_tabs = False
            continue

    if not in_tabs:
        new_lines.append(line)

for i in range(len(new_lines) - 1, -1, -1):
    if new_lines[i].strip() == ")":
        while i > 0 and new_lines[i - 1].strip() == "":
            i -= 1
            new_lines.pop(i)
        new_lines.insert(i, "\n")
        new_lines.insert(i, tabs_content + "\n")
        new_lines.insert(i, "\n")
        break

with open(config_path, "w") as f:
    f.writelines(new_lines)
PYEOF
        if [[ $? -ne 0 ]]; then
          mv "$backup_path" "$config_path"
        else
          rm -f "$backup_path"
        fi
      else
        rm -f "$backup_path"
      fi

      rm -f "$tabs_file"
    fi
  fi

  command rmpc "$@"
}

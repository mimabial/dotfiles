#!/usr/bin/env bash

set -euo pipefail

DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
LAUNCHER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hypr/webapps"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications/icons"

read_desktop_field() {
  sed -n "s/^$1=//p" "$2" | head -n 1
}

collect_webapp_records() {
  local file=""
  local app_id=""
  local app_name=""
  local icon_path=""

  while IFS= read -r -d '' file; do
    if grep -q '^X-Hypr-WebApp=true$' "$file"; then
      app_id="$(read_desktop_field "X-Hypr-WebApp-Id" "$file")"
      app_name="$(read_desktop_field "Name" "$file")"
      icon_path="$(read_desktop_field "Icon" "$file")"
    elif grep -q '^Exec=.*hyprshell launch/webapp\.sh.*' "$file"; then
      app_id="$(basename "${file%.desktop}")"
      app_name="$app_id"
      icon_path="$(read_desktop_field "Icon" "$file")"
    else
      continue
    fi

    app_id="${app_id:-$(basename "${file%.desktop}")}"
    app_name="${app_name:-$app_id}"
    printf '%s\t%s\t%s\t%s\n' "$app_id" "$app_name" "$icon_path" "$file"
  done < <(find "$DESKTOP_DIR" -maxdepth 1 -name '*.desktop' -print0)
}

select_requests() {
  if [[ "$#" -gt 0 ]]; then
    printf '%s\n' "$@"
    return 0
  fi

  if ((${#WEBAPP_RECORDS[@]} == 0)); then
    echo "No web apps to remove."
    exit 1
  fi

  printf '%s\n' "${WEBAPP_RECORDS[@]}" \
    | cut -f2 \
    | sort -f \
    | fzf --multi --prompt="Select web apps to remove (TAB to select) > " --header="Select web apps to remove" --reverse
}

remove_webapp_record() {
  local record="$1"
  local app_id=""
  local app_name=""
  local icon_path=""
  local desktop_file=""

  IFS=$'\t' read -r app_id app_name icon_path desktop_file <<<"$record"
  rm -f "$desktop_file" "$LAUNCHER_DIR/$app_id"
  [[ "$icon_path" == "${ICON_DIR}/"* ]] && rm -f "$icon_path"
  echo "Removed $app_id"
}

mapfile -t WEBAPP_RECORDS < <(collect_webapp_records)
mapfile -t REQUESTS < <(select_requests "$@")

if ((${#REQUESTS[@]} == 0)); then
  echo "You must select at least one web app to remove."
  exit 1
fi

for request in "${REQUESTS[@]}"; do
  for record in "${WEBAPP_RECORDS[@]}"; do
    IFS=$'\t' read -r app_id app_name _icon_path _desktop_file <<<"$record"
    [[ "$request" == "$app_id" || "$request" == "$app_name" ]] || continue
    remove_webapp_record "$record"
  done
done

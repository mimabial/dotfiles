#!/usr/bin/env bash

set -e

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"
_rofi_opacity="$(rofi_active_opacity_override)"

cached_search_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/landing/websearch"

declare -A SITES SITES_ICON
search_file=(
  "${XDG_CONFIG_HOME}/hypr/websearch.lst"
)

# Load search engines from .lst file
load_search_engines() {
  local lst_files=()
  for f in "${search_file[@]}"; do
    [[ $f == *.lst && -f $f ]] && lst_files+=("$f")
  done
  if [[ ${#lst_files[@]} -eq 0 ]]; then
    print_log +r "[error] " +y "No search engine files found."
    exit 1
  fi

  trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf "%s" "$s"
  }

  local icon key url
  for f in "${lst_files[@]}"; do
    while IFS='|' read -r icon key url _; do
      icon="$(trim "${icon}")"
      key="$(trim "${key}")"
      url="$(trim "${url}")"
      [[ -z "${key}" || -z "${url}" ]] && continue
      SITES["${key}"]="${url}"
      SITES_ICON["${key}"]="${icon}"
    done < "${f}"
  done
}

# Generate the list of sites
get_sites_list() {
  # Show recent sites first, then the rest, with icons
  {
    local cache="${cached_search_dir}/recent.sites"
    [[ -f "$cache" ]] && awk -F '|' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}' "$cache" | while read -r key; do
      [[ -n "$key" && -n "${SITES_ICON[$key]}" ]] && printf "%s \t%s\n" "${SITES_ICON[$key]}" "$key"
    done

    for key in "${!SITES[@]}"; do
      [[ -n "${SITES_ICON[$key]}" ]] && printf "%s \t%s\n" "${SITES_ICON[$key]}" "$key"
    done | sort -u
  } | awk '!seen[$0]++'
}

# Generate the list of previously used search queries
get_queries_list() {
  site=$1
  cat "$cached_search_dir/$site.txt" 2>/dev/null || true
}

write_to_top() {
  local file="$1"
  local content="$2"
  local file_dir=""
  local tmp_file=""
  local tmp_recent=""
  file_dir="$(dirname "${file}")"
  mkdir -p "${file_dir}"
  # Only save valid keys from SITES to recent.sites
  if [[ "$file" == *"recent.sites" ]]; then
    local key
    key="$(awk -F '|' '{print $1}' <<<"$content" | xargs)"
    if [[ -n "${SITES[$key]}" ]]; then
      tmp_recent="$(mktemp "${file_dir}/.recent.XXXXXX")"
      grep -vx "$key" "$file" 2>/dev/null >"${tmp_recent}" || true
      printf "%s\n" "$key" >"$file"
      cat "${tmp_recent}" >>"$file"
      rm -f "${tmp_recent}"
    fi
  else
    # Prepend the new line to the file
    tmp_file="$(mktemp "${file_dir}/.websearch.XXXXXX")"
    {
      printf "%s\n" "$content"
      cat "$file" 2>/dev/null
    } >"${tmp_file}" && mv "${tmp_file}" "$file"
    # Remove duplicates and empty lines, keeping the first occurrence (most recent)
    tmp_file="$(mktemp "${file_dir}/.websearch.XXXXXX")"
    awk 'NF' "$file" | awk '!seen[$0]++' >"${tmp_file}" && mv "${tmp_file}" "$file"
  fi
}

handle_query() {
  site=$1
  query=$2
  [ -z "$site" ] && exit 0
  [ -z "$query" ] && exit 0
  mkdir -p "$cached_search_dir"
  touch "$cached_search_dir/$site.txt"
  if grep -Fxq "$query" "$cached_search_dir/$site.txt"; then
    printf "%s\n" "$(grep -xv "$query" "$cached_search_dir/$site.txt")" >"$cached_search_dir/$site.txt"
  fi
  write_to_top "$cached_search_dir/$site.txt" "$query"
  write_to_top "$cached_search_dir/recent.sites" "$site | ${SITES[$site]}"

  if [ -n "$BROWSER" ]; then
    printf "Using browser: %s %s\n" "$BROWSER" "${SITES[$site]}$query"
    nohup "$BROWSER" "${SITES[$site]}$query" >/dev/null 2>&1 &
  else
    printf "Using default browser: xdg-open %s\n" "${SITES[$site]}$query"
    [ -z "$BROWSER" ] && nohup xdg-open "${SITES[$site]}$query" >/dev/null 2>&1 &
  fi
}

smart_input() {
  # Handles input like 'goog: some query' with fast fuzzy matching
  local input="$1"
  local site_raw
  local query

  if [[ "$input" == *:* ]]; then
    site_raw="${input%%:*}"
    query="${input#*:}"
  else
    site_raw=$(printf "%s\t" "$input" | cut -f2)
    query=""
  fi

  local site

  # Fast fuzzy match: exact first, then substring (case-insensitive)
  [[ -n "${SITES[$site_raw]}" ]] && site="$site_raw"
  if [[ -z "$site" ]]; then
    for candidate in "${!SITES[@]}"; do
      [[ "${candidate,,}" == *"${site_raw,,}"* ]] && site="$candidate" && break
    done
  fi
  [[ -z "$site" ]] && {
    printf "Unknown site: %s\n" "$site_raw"
    exit 1
  }
  export FINAL_QUERY="$query" FINAL_SITE="$site"
}

# setup rofi configuration
setup_rofi_config() {
  local font_scale
  local font_name
  font_scale="$(rofi_effective_font_scale "${ROFI_WEBSEARCH_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_WEBSEARCH_FONT:-$ROFI_FONT}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  r_override="$(rofi_standard_window_theme wallbox min5)"
}

usage() {
  cat <<EOF
--clear-cache               Reset cache
--browser | -b [browser]    Browser to use, defaults to xdg browser
--site | -s [search engine] Search-engine to use
-h | --help                 Show this help message
Available:
$(
    for site in "${!SITES[@]}"; do
      echo -e "\t${SITES_ICON[$site]} $site"
    done | sort
  )
EOF
  exit 0
}

rofi_interactive() {
  unset FINAL_SITE FINAL_QUERY
  setup_rofi_config
  local rofi_style
  rofi_style="$(rofi_resolve_theme "${ROFI_WEBSEARCH_STYLE:-clipboard}")"

  if [[ -n "${SITE_TO_USE}" ]]; then
    if [[ -z "${SITES[$SITE_TO_USE]}" ]]; then
      printf "Invalid site: %s\n" "$FINAL_SITE"
      exit 1
    else
      printf "Using site: %s\n" "$SITE_TO_USE"
      FINAL_SITE="${SITE_TO_USE}"
    fi
  else

    text_input=$(
      get_sites_list \
        | rofi -dmenu -i "${ROFI_WEBSEARCH_ARGS[@]}" \
          -p "🔎 Select engine" \
          -theme-str "${r_override}" \
          -config "${rofi_style}" \
          -theme-str "entry { placeholder: \"🔎 Search engine...\";}" \
          -theme-str "${font_override}" \
          -theme-str "window {width: 30%;}" \
          -theme-str 'listview { columns: 1; }' \
          ${_rofi_opacity:+-theme-str "${_rofi_opacity}"}
    )
    [[ -z "$text_input" ]] && exit 0
    printf "Input: %s\n" "$text_input"
    smart_input "${text_input[@]}"
  fi

  if [[ -z ${FINAL_SITE} ]]; then
    FINAL_SITE=$(awk '{print $1}' <<<"$text_input")
    if [[ -z "${SITES[$FINAL_SITE]}" ]]; then
      printf "Invalid FINAL_SITE: %s\n" "$FINAL_SITE"
      exit 1
    fi
  fi

  if [[ -z ${FINAL_QUERY} ]]; then
    FINAL_QUERY=$(
      get_queries_list "$FINAL_SITE" \
        | rofi -dmenu -i "${ROFI_WEBSEARCH_ARGS[@]}" \
          -theme-str "${r_override}" \
          -config "${rofi_style}" \
          -theme-str "entry { placeholder: \"🔎 Query...\";}" \
          -theme-str "${font_override}" \
          -theme-str "window {width: 30%;}" \
          ${_rofi_opacity:+-theme-str "${_rofi_opacity}"}
    )
  fi
  printf "Final site: %s\n" "$FINAL_SITE"
  printf "Final query: %s\n" "$FINAL_QUERY"
  if [[ -n "${FINAL_QUERY}" ]] && [[ -n "${FINAL_SITE}" ]]; then
    handle_query "$FINAL_SITE" "$FINAL_QUERY"
  fi

}

main() {

  while (($# > 0)); do
    case $1 in
      --site | -s)
        if (($# > 1)); then
          SITE_TO_USE="$2"
          shift
        else
          print_log +r "[error] " +y "--site requires an argument."
          usage
        fi
        ;;
      --browser | -b)
        if (($# > 1)); then
          BROWSER="$2"
          shift
        else
          print_log +r "[error] " +y "--browser requires an argument."
          usage
        fi
        ;;
      --clear-cache)
        rm -fr "${cached_search_dir}"
        print_log +g "[ok] " +y "cleared cache"
        exit 0
        ;;
      -h | --help)
        usage
        ;;
      *)
        printf "Unknown option: %s\n" "$1"
        usage
        ;;
    esac
    shift
  done

  load_search_engines
  rofi_interactive
}

main "$@"

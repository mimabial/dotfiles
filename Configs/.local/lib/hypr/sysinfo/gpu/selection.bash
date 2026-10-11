gpu_load_state_helpers() {
  declare -F state_get >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/state.bash" 2>/dev/null || return 1
}

gpu_cache_set() {
  local key="$1" value="$2" cache_line found=false

  [[ -z "${key}" ]] && return
  while IFS= read -r cache_line; do
    [[ "$cache_line" == "$key="* ]] || continue
    found=true
    break
  done <"$gpu_cache_file"
  if "$found"; then
    sed -i "s/^${key}=.*/${key}=${value}/" "$gpu_cache_file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$gpu_cache_file"
  fi
}

gpu_activate_selection() {
  local selected_flag="$1"
  sed -i -e 's/^\(GPUINFO_NVIDIA_ENABLE=1\|GPUINFO_AMD_ENABLE=1\|GPUINFO_INTEL_ENABLE=1\)/#\1/' \
    -e "s/^#${selected_flag}=1/${selected_flag}=1/" "$gpu_cache_file"
  gpu_cache_set GPUINFO_PRIORITY "$selected_flag"
  GPUINFO_NVIDIA_ENABLE=0 GPUINFO_AMD_ENABLE=0 GPUINFO_INTEL_ENABLE=0
  source "$gpu_cache_file"
}

gpu_restore_selection() {
  local saved_flag
  gpu_load_state_helpers || return 1
  saved_flag="$(state_get GPUINFO_PRIORITY)"
  [[ -n "$saved_flag" ]] && grep -q "^#\?${saved_flag}=1" "$gpu_cache_file" || return 1
  gpu_activate_selection "$saved_flag"
}

gpu_select_vendor() {
  local cache_line cache_entry selected_flag current_index=0 index
  local -a available_flags=()
  while IFS= read -r cache_line; do
    cache_entry="${cache_line#\#}"
    [[ "$cache_entry" == GPUINFO_*_ENABLE=1 ]] && available_flags+=("${cache_entry%=1}")
  done <"$gpu_cache_file"

  if [[ -n "${1:-}" ]]; then
    selected_flag="GPUINFO_${1^^}_ENABLE"
    [[ " ${available_flags[*]} " == *" $selected_flag "* ]] || { printf 'Error: %s not found in %s\n' "$selected_flag" "$gpu_cache_file" >&2; return 1; }
  else
    ((${#available_flags[@]})) || { printf 'Error: no GPU found\n' >&2; return 1; }
    if [[ -z "${GPUINFO_AVAILABLE:-}" ]]; then
      printf 'GPUINFO_AVAILABLE=%q\n' "${available_flags[*]}" >>"$gpu_cache_file"
    fi
    GPUINFO_PRIORITY="${GPUINFO_PRIORITY:-${available_flags[0]}}"
    for index in "${!available_flags[@]}"; do
      [[ "${available_flags[$index]}" == "$GPUINFO_PRIORITY" ]] && current_index=$index
    done
    selected_flag="${available_flags[$(((current_index + 1) % ${#available_flags[@]}))]}"
  fi

  gpu_activate_selection "$selected_flag"
  gpu_load_state_helpers && state_set GPUINFO_PRIORITY "$selected_flag" >/dev/null 2>&1
}

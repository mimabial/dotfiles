#!/usr/bin/env bash
#
# theme/pairs.sh — light/dark theme polarity + pairing resolver.
#
# Sourceable library (defines theme_polarity/theme_pair_for) and CLI:
#   hyprshell theme/pairs --polarity <theme>
#   hyprshell theme/pairs --pair-for <theme> <dark|light>
#
# Polarity comes from each theme's $COLOR_SCHEME (prefer-light => light, else
# dark). Pairs and defaults come from themes/theme-pairs.conf.
#
# No top-level `set` on purpose: this file is sourced into scripts that own
# their own shell options.

_PAIRS_THEMES_DIR="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/themes"
_PAIRS_FILE="${_PAIRS_THEMES_DIR}/theme-pairs.conf"

declare -gA _PAIRS_MAP=()
_PAIRS_DEFAULT_DARK=""
_PAIRS_DEFAULT_LIGHT=""
_PAIRS_LOADED=0

theme_polarity() {
  local theme="${1:-}"
  local file="${_PAIRS_THEMES_DIR}/${theme}/hypr.theme"
  local scheme=""
  [[ -n "${theme}" && -r "${file}" ]] || { echo "dark"; return 0; }
  scheme="$(grep -m1 -E '^[[:space:]]*\$COLOR_SCHEME[[:space:]]*=' "${file}" 2>/dev/null | sed -E 's/.*=[[:space:]]*//')" || scheme=""
  scheme="${scheme%%[[:space:]]*}"
  [[ "${scheme}" == "prefer-light" ]] && { echo "light"; return 0; }
  echo "dark"
}

_pairs_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

_pairs_load() {
  [[ "${_PAIRS_LOADED}" -eq 1 ]] && return 0
  _PAIRS_LOADED=1
  [[ -r "${_PAIRS_FILE}" ]] || return 0

  local line key val
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    [[ "${line}" == *=* ]] || continue
    key="$(_pairs_trim "${line%%=*}")"
    val="$(_pairs_trim "${line#*=}")"
    [[ -n "${key}" && -n "${val}" ]] || continue
    case "${key}" in
      default-dark) _PAIRS_DEFAULT_DARK="${val}" ;;
      default-light) _PAIRS_DEFAULT_LIGHT="${val}" ;;
      *)
        _PAIRS_MAP["${key}"]="${val}"
        _PAIRS_MAP["${val}"]="${key}"
        ;;
    esac
  done <"${_PAIRS_FILE}"
}

# theme_pair_for <theme> <dark|light>
# Echoes the theme to use so the active theme matches the requested polarity:
# the theme itself if it already matches, else its explicit pair, else the
# configured default for that polarity.
theme_pair_for() {
  local theme="${1:-}"
  local target="${2:-}"
  local cand="" def=""

  [[ "${target}" =~ ^(dark|light)$ ]] || { echo "${theme}"; return 1; }
  [[ "$(theme_polarity "${theme}")" == "${target}" ]] && { echo "${theme}"; return 0; }

  _pairs_load
  cand="${_PAIRS_MAP[${theme}]:-}"
  if [[ -n "${cand}" && "$(theme_polarity "${cand}")" == "${target}" ]]; then
    echo "${cand}"
    return 0
  fi

  [[ "${target}" == "light" ]] && def="${_PAIRS_DEFAULT_LIGHT}" || def="${_PAIRS_DEFAULT_DARK}"
  if [[ -n "${def}" ]]; then
    echo "${def}"
    return 0
  fi

  echo "${theme}"
  return 1
}

_pairs_main() {
  case "${1:-}" in
    --polarity)
      [[ -n "${2:-}" ]] || { echo "usage: pairs.sh --polarity <theme>" >&2; return 2; }
      theme_polarity "$2"
      ;;
    --pair-for)
      [[ -n "${2:-}" && -n "${3:-}" ]] || { echo "usage: pairs.sh --pair-for <theme> <dark|light>" >&2; return 2; }
      theme_pair_for "$2" "$3"
      ;;
    -h | --help | "")
      cat <<'EOF'
Usage: hyprshell theme/pairs --polarity <theme>
       hyprshell theme/pairs --pair-for <theme> <dark|light>
EOF
      ;;
    *)
      echo "pairs.sh: unknown argument '$1'" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _pairs_main "$@"
fi

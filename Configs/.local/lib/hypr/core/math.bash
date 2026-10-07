#!/usr/bin/env bash

hypr_clamp() {
  local value="$1" min="$2" max="$3"
  (( value < min )) && value="${min}"
  (( value > max )) && value="${max}"
  printf '%s\n' "${value}"
}

hypr_now_ms() {
  printf '%s\n' "$((${EPOCHREALTIME//[!0-9]/} / 1000))"
}

hypr_elapsed_label() {
  local started_ms="$1" elapsed_ms=0 centiseconds=0

  [[ "${started_ms}" =~ ^[0-9]+$ ]] || return 1
  elapsed_ms=$(($(hypr_now_ms) - started_ms))
  ((elapsed_ms >= 0)) || elapsed_ms=0
  centiseconds=$(((elapsed_ms + 5) / 10))
  printf '%d.%02ds' "$((centiseconds / 100))" "$((centiseconds % 100))"
}

#!/usr/bin/env bash

hypr_clamp_into() {
  local -n clamped_ref="$1"
  local value="$2" min="$3" max="$4"
  (( value < min )) && value="${min}"
  (( value > max )) && value="${max}"
  clamped_ref="${value}"
}

hypr_now_ms_into() {
  local -n now_ms_ref="$1"
  now_ms_ref=$((${EPOCHREALTIME//[!0-9]/} / 1000))
}

hypr_elapsed_label_into() {
  local -n elapsed_label_ref="$1"
  local started_ms="$2" elapsed_ms=0 centiseconds=0

  [[ "${started_ms}" =~ ^[0-9]+$ ]] || return 1
  elapsed_ms=$((${EPOCHREALTIME//[!0-9]/} / 1000 - started_ms))
  ((elapsed_ms >= 0)) || elapsed_ms=0
  centiseconds=$(((elapsed_ms + 5) / 10))
  printf -v elapsed_label_ref '%d.%02ds' "$((centiseconds / 100))" "$((centiseconds % 100))"
}

#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Fixed-point milli arithmetic used by font, geometry, and wallpaper helpers.

rofi_decimal_milli() {
  local value="${1:-0}"
  local sign=""
  local whole="0"
  local fraction="000"
  local milli=0

  [[ "${value}" =~ ^(-?)([0-9]+)([.][0-9]+)?$ ]] || return 1
  sign="${BASH_REMATCH[1]}"
  whole="${BASH_REMATCH[2]}"
  if [[ -n "${BASH_REMATCH[3]:-}" ]]; then
    fraction="${BASH_REMATCH[3]#.}"
    fraction="${fraction}000"
    fraction="${fraction:0:3}"
  fi

  milli=$((10#${whole} * 1000 + 10#${fraction}))
  [[ -n "${sign}" ]] && milli=$((-milli))
  printf '%s\n' "${milli}"
}

rofi_decimal_milli_or_zero() {
  local milli=0

  milli="$(rofi_decimal_milli "${1:-0}" 2>/dev/null || true)"
  [[ "${milli}" =~ ^-?[0-9]+$ ]] || milli=0
  printf '%s\n' "${milli}"
}

rofi_positive_decimal() {
  local milli=0

  milli="$(rofi_decimal_milli "${1:-}" 2>/dev/null || true)"
  [[ "${milli}" =~ ^-?[0-9]+$ ]] || return 1
  ((milli > 0))
}

rofi_mul_milli() {
  local left_milli="${1:-0}"
  local right_milli="${2:-0}"
  local product=0

  [[ "${left_milli}" =~ ^-?[0-9]+$ ]] || return 1
  [[ "${right_milli}" =~ ^-?[0-9]+$ ]] || return 1

  product=$((left_milli * right_milli))
  if ((product >= 0)); then
    printf '%s\n' $(((product + 500) / 1000))
  else
    printf '%s\n' $(((product - 500) / 1000))
  fi
}

rofi_divide_milli() {
  local dividend_milli="${1:-0}"
  local divisor_milli="${2:-0}"
  local abs_divisor=0
  local scaled_dividend=0

  [[ "${dividend_milli}" =~ ^-?[0-9]+$ ]] || return 1
  [[ "${divisor_milli}" =~ ^-?[0-9]+$ ]] || return 1
  ((divisor_milli != 0)) || return 1

  abs_divisor=$((divisor_milli < 0 ? -divisor_milli : divisor_milli))
  scaled_dividend=$((dividend_milli * 1000))
  if ((scaled_dividend >= 0)); then
    printf '%s\n' $(((scaled_dividend + (abs_divisor / 2)) / divisor_milli))
  else
    printf '%s\n' $(((scaled_dividend - (abs_divisor / 2)) / divisor_milli))
  fi
}

rofi_milli_to_fixed2() {
  local milli="${1:-0}"
  local sign=""
  local abs_milli=0
  local centi=0
  local whole=0
  local fraction=0

  [[ "${milli}" =~ ^-?[0-9]+$ ]] || return 1
  if ((milli < 0)); then
    sign="-"
    abs_milli=$((-milli))
  else
    abs_milli="${milli}"
  fi

  centi=$(((abs_milli + 5) / 10))
  whole=$((centi / 100))
  fraction=$((centi % 100))
  printf '%s%s.%02d\n' "${sign}" "${whole}" "${fraction}"
}

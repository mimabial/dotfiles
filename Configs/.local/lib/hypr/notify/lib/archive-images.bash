# Package-owned theme icons stay valid; copy only sender-owned pictures.
is_theme_owned_icon() {
  local path="$1" root=""
  for root in \
    "${XDG_DATA_HOME:-$HOME/.local/share}/icons" \
    "$HOME/.icons" \
    /usr/share/icons \
    /usr/share/pixmaps; do
    [[ "${path}" == "${root}/"* ]] && return 0
  done
  return 1
}

store_notification_image() {
  local src="$1" size="" mime="" ext="" hash="" dest=""

  [[ -f "${src}" && -r "${src}" ]] || return 1
  size="$(stat -c %s -- "${src}" 2>/dev/null)" || return 1
  ((size <= ARCHIVE_IMAGE_MAX_BYTES)) || return 1
  mime="$(file --brief --mime-type -- "${src}" 2>/dev/null || true)"
  [[ "${mime}" == image/* ]] || return 1

  case "${mime}" in
    image/png) ext="png" ;;
    image/jpeg) ext="jpg" ;;
    image/gif) ext="gif" ;;
    image/webp) ext="webp" ;;
    image/svg+xml) ext="svg" ;;
    *) ext="img" ;;
  esac

  hash="$("${HYPR_HASH_COMMAND:-xxh64sum}" <"${src}" 2>/dev/null)"
  hash="${hash%%[[:space:]]*}"
  [[ -n "${hash}" ]] || return 1

  dest="${images}/${hash}.${ext}"
  if [[ ! -f "${dest}" ]]; then
    # Shrink large previews on ingestion; `>` leaves small images untouched.
    if [[ "${ext}" != "svg" ]] && command -v magick >/dev/null 2>&1; then
      magick "${src}" -auto-orient -resize "${ARCHIVE_IMAGE_MAX_EDGE_PX}x${ARCHIVE_IMAGE_MAX_EDGE_PX}>" -strip "${dest}" 2>/dev/null \
        || cp -- "${src}" "${dest}" 2>/dev/null || return 1
    else
      cp -- "${src}" "${dest}" 2>/dev/null || return 1
    fi
    chmod 600 "${dest}" 2>/dev/null || true
  fi
  printf '%s\n' "${dest}"
}

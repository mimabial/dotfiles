#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/notify.bash" || exit 1

readonly USAGE="Usage: hyprshell media/transcode <file> <format> <resolution>
       hyprshell media/transcode --presets <file>
Transcode a picture (jpg or png at high, medium or low) or a video (mp4 or gif at
4k, 1080p or 720p) for sharing. The result lands next to the original as
<name>-<resolution>.<format> and is copied to the clipboard as a file.
--presets prints the '<format> <resolution>' pairs the file accepts."
hypr_help_guard "${USAGE}" "$@"

readonly -a PICTURE_FORMATS=(jpg png) PICTURE_RESOLUTIONS=(high medium low)
readonly -a VIDEO_FORMATS=(mp4 gif) VIDEO_RESOLUTIONS=(4k 1080p 720p)
readonly JPEG_QUALITY=85
readonly H264_CRF=23 H265_CRF=24 AAC_BITRATE=192k
readonly GIF_FPS=10

media_kind_into() {
  local -n kind_ref="$1"
  local mime=""

  mime="$(file -b --mime-type -- "$2")"
  case "${mime}" in
    image/*) kind_ref=picture ;;
    video/*) kind_ref=video ;;
    *)
      printf 'Unsupported file type: %s\n' "${mime}" >&2
      return 1
      ;;
  esac
}

print_presets() {
  local kind="" format="" resolution=""

  media_kind_into kind "$1" || return 1
  local -n formats="${kind^^}_FORMATS" resolutions="${kind^^}_RESOLUTIONS"
  for format in "${formats[@]}"; do
    for resolution in "${resolutions[@]}"; do
      printf '%s %s\n' "${format}" "${resolution}"
    done
  done
}

invalid_choice() {
  printf 'Invalid %s: %s\n' "$1" "$2" >&2
  return 2
}

transcode_picture() {
  local input="$1" format="$2" resolution="$3" output="$4" max_width=""

  case "${resolution}" in
    high) max_width=3160 ;;
    medium) max_width=2160 ;;
    low) max_width=1080 ;;
    *) invalid_choice "picture resolution" "${resolution}" || return ;;
  esac

  case "${format}" in
    jpg) magick "${input}[0]" -resize "${max_width}x>" -quality "${JPEG_QUALITY}" -strip "${output}" ;;
    png)
      magick "${input}[0]" -resize "${max_width}x>" -strip \
        -define png:compression-filter=5 -define png:compression-level=9 \
        -define png:compression-strategy=1 -define png:exclude-chunk=all "${output}"
      ;;
    *) invalid_choice "picture format" "${format}" ;;
  esac
}

transcode_video() {
  local input="$1" format="$2" resolution="$3" output="$4" scale=""
  local -a ffmpeg=(ffmpeg -nostdin -loglevel error -y -i "${input}")

  case "${resolution}" in
    4k) scale="scale=-2:2160" ;;
    1080p) scale="scale=-2:1080" ;;
    720p) scale="scale=-2:720" ;;
    *) invalid_choice "video resolution" "${resolution}" || return ;;
  esac

  case "${format}" in
    mp4)
      if [[ "${resolution}" == 4k ]]; then
        ffmpeg+=(-vf "${scale}" -c:v libx265 -preset slow -crf "${H265_CRF}")
      else
        ffmpeg+=(-vf "${scale}" -c:v libx264 -preset fast -crf "${H264_CRF}")
      fi
      "${ffmpeg[@]}" -c:a aac -b:a "${AAC_BITRATE}" -movflags +faststart "${output}"
      ;;
    gif)
      "${ffmpeg[@]}" -vf "fps=${GIF_FPS},${scale}:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "${output}"
      ;;
    *) invalid_choice "video format" "${format}" ;;
  esac
}

transcode() {
  local input="$1" format="$2" resolution="$3" kind="" output="" name=""

  [[ -f "${input}" ]] || {
    printf 'File not found: %s\n' "${input}" >&2
    return 1
  }
  media_kind_into kind "${input}" || return 1
  name="${input##*/}"
  output="${input%/*}/${name%.*}-${resolution}.${format}"

  [[ "${kind}" == video ]] && notify_send_safe -e -a hyprshell "Transcoding ${name}" "To ${format} at ${resolution}"
  if ! "transcode_${kind}" "${input}" "${format}" "${resolution}" "${output}"; then
    notify_send_safe -u critical -a hyprshell "Transcode failed" "${name} to ${format} at ${resolution}"
    return 1
  fi
  python3 -I -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "${output}" \
    | wl-copy --type text/uri-list
  notify_send_safe -a hyprshell "Transcoded ${name}" "${output##*/} copied to the clipboard"
}

case "$#:${1:-}" in
  2:--presets) print_presets "$2" ;;
  3:*) transcode "$@" ;;
  *)
    printf '%s\n' "${USAGE}" >&2
    exit 2
    ;;
esac

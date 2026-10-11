#!/usr/bin/env bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_render_job.bash"
declare -A render_job=()
render_job_into render_job "${1:-}" chrome Hypr-chrome-theme/manifest.json ""

chrome_theme_dir="${render_job[output_file]%/*}"
chrome_render_dir="${chrome_theme_dir%/*}"
mkdir -p "${chrome_render_dir}"

wallpaper_file="${WALLPAPER_CURRENT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current}/wall.set.png"

render_fold_stdin_into_input_digest render_job < <([[ ! -f "${wallpaper_file}" ]] || md5sum "${wallpaper_file}")
render_output_is_current render_job && exit 0

chrome_rgb_components() {
  local color_hex="${1#\#}"
  printf '%d, %d, %d' "0x${color_hex:0:2}" "0x${color_hex:2:2}" "0x${color_hex:4:2}"
}

render_read_palette_into render_job
background="$(chrome_rgb_components "${render_job[color0]}")"
foreground="$(chrome_rgb_components "${render_job[color15]}")"
accent="$(chrome_rgb_components "${render_job[color4]}")"
secondary="$(chrome_rgb_components "${render_job[color8]}")"

staged_theme_dir="$(mktemp -d "${chrome_render_dir}/.staging.XXXXXX")"
trap 'rm -rf -- "${staged_theme_dir}"' EXIT
mkdir -p "${staged_theme_dir}/images"
[[ -f "${wallpaper_file}" ]] && cp -f "${wallpaper_file}" "${staged_theme_dir}/images/theme_ntp_background_norepeat.png"

cat > "${staged_theme_dir}/manifest.json" <<EOF
{
  "manifest_version": 3,
  "version": "1.0",
  "name": "Hypr Theme",
  "theme": {
    "images": { "theme_ntp_background": "images/theme_ntp_background_norepeat.png" },
    "colors": {
      "frame": [${background}],
      "frame_inactive": [${background}],
      "toolbar": [${accent}],
      "ntp_text": [${foreground}],
      "ntp_link": [${accent}],
      "ntp_section": [${secondary}],
      "button_background": [${foreground}],
      "toolbar_button_icon": [${foreground}],
      "toolbar_text": [${foreground}],
      "omnibox_background": [${background}],
      "omnibox_text": [${foreground}]
    },
    "properties": { "ntp_background_alignment": "bottom" }
  }
}
EOF

rm -rf -- "${chrome_theme_dir}"
mv -f "${staged_theme_dir}" "${chrome_theme_dir}"
trap - EXIT
render_store_input_digest render_job

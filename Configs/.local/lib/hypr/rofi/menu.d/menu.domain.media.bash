#!/usr/bin/env bash

media_pick_album_genres() {
  local empty_label="Music library is empty"
  local library=""
  local albums=""
  local selection=""

  library="$(hyprshell media/music_library_config 2>/dev/null | tail -n1)"
  # tag_genres reads one directory without descending, so only offer the
  # directories that actually hold tracks
  if [[ -n "${library}" && -d "${library}" ]]; then
    albums="$(
      find "${library}" -mindepth 1 -type f \
        \( -iname '*.mp3' -o -iname '*.opus' -o -iname '*.flac' \) \
        -printf '%h\n' 2>/dev/null | sed "s|^${library}/\?||" | sed '/^$/d' | sort -u
    )"
  fi

  if [[ -n "${albums}" ]]; then
    selection="$(menu "Album" "${albums}")"
  else
    selection="$(menu "Album" "${empty_label}")"
  fi

  case "${selection}" in
    "${empty_label}" | "")
      menu_show_then_exit media
      ;;
    *)
      menu_present_terminal hyprshell media/tag_genres "${library}/${selection}"
      ;;
  esac
}

media_pick_transcode() {
  local empty_label="No pictures or videos in ~/Pictures or ~/Videos"
  local files="" input="" preset="" format="" resolution=""

  files="$(
    find "${HOME}/Pictures" "${HOME}/Videos" -name '.*' -prune -o -type f -regextype posix-extended \
      -iregex '.*\.(jpe?g|png|webp|gif|heic|avif|mp4|mov|m4v|mkv|webm|avi)' -printf '%T@\t%p\n' 2>/dev/null |
      sort -rn | cut -f2-
  )"
  input="$(menu "Transcode" "${files:-${empty_label}}")"
  [[ -f "${input}" ]] || menu_show_then_exit media
  preset="$(menu "Transcode to" "$(hyprshell media/transcode --presets "${input}")")"
  [[ -n "${preset}" ]] || menu_show_then_exit media
  read -r format resolution <<<"${preset}"
  exec hyprshell media/transcode "${input}" "${format}" "${resolution}"
}

menu_register_domain_media() {
  menu_define media "Media"
  menu_add_item media "󰓹  Auto-Tag Library" action media_autotag
  menu_add_item media "󰓻  Set Album Genres" action media_genres
  menu_add_item media "󰑕  Rename From Tags" action media_rename
  menu_add_item media "󰈔  Fetch Lyrics" action media_fetch_lyrics
  menu_add_item media "󰚰  Relink Orphan Lyrics" action media_relink_lyrics
  menu_add_item media "󰉋  Library Folder" action media_library
  menu_add_item media "󰈫  Transcode" action media_transcode
}

menu_run_action_media() {
  local action_id="$1"

  case "${action_id}" in
    media_genres) media_pick_album_genres ;;
    media_autotag) menu_present_terminal hyprshell media/autotag ;;
    media_rename) menu_present_terminal hyprshell media/rename_from_tags ;;
    media_fetch_lyrics) menu_present_terminal hyprshell media/fetch_all_lyrics ;;
    media_relink_lyrics) menu_present_terminal hyprshell media/lyrics_relink ;;
    media_library) menu_present_terminal hyprshell media/music_library_config ;;
    media_transcode) media_pick_transcode ;;
    *) return "${MENU_ACTION_UNKNOWN}" ;;
  esac
}

menu_register_action_handler menu_run_action_media

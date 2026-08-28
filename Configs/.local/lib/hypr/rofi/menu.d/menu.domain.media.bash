#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

menu_register_domain_media() {
  menu_define media "Media"
  menu_add_item media "󰓹  Auto-Tag Library" action media_autotag
  menu_add_item media "󰓻  Set Album Genres" action media_genres
  menu_add_item media "󰑕  Rename From Tags" action media_rename
  menu_add_item media "󰈔  Fetch Lyrics" action media_fetch_lyrics
  menu_add_item media "󰚰  Relink Orphan Lyrics" action media_relink_lyrics
  menu_add_item media "󰉋  Library Folder" action media_library
}

menu_run_action_media() {
  local action_id="$1"

  case "${action_id}" in
    media_autotag) present_terminal hyprshell media/autotag ;;
    media_rename) present_terminal hyprshell media/rename_from_tags ;;
    media_fetch_lyrics) present_terminal hyprshell media/fetch_all_lyrics ;;
    media_relink_lyrics) present_terminal hyprshell media/lyrics_relink ;;
    media_library) present_terminal hyprshell media/music_library_config ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_media

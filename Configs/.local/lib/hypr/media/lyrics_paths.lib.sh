# Where .lrc files live. Sourced by the rmpc fetch hook and fetch_all_lyrics.sh;
# mirrored in Python by lrc_path_for() in fetch_album_lyrics.py.
#
# rmpc resolves lyrics by indexing lyrics_dir and reading each file's own tags,
# not by deriving a path from the song, so the files can sit in one hidden
# directory instead of beside every track.

LYRICS_ROOT="${RMPC_LYRICS_DIR:-$HOME/Music}"
LYRICS_HIDDEN_DIR="${LYRICS_ROOT}/.lyrics"

# lyrics_lrc_path <path> -> the .lrc that belongs to it
lyrics_lrc_path() {
  lyrics_target="$1"
  [ -n "$lyrics_target" ] || return 1

  case "$lyrics_target" in
    "${LYRICS_HIDDEN_DIR}/"*) ;;
    "${LYRICS_ROOT}/"*)
      lyrics_target="${LYRICS_HIDDEN_DIR}/${lyrics_target#"${LYRICS_ROOT}/"}"
      ;;
  esac

  printf '%s.lrc' "${lyrics_target%.*}"
}

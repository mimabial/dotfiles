# Where .lrc files live. Sourced by the rmpc fetch hook and mirrored in Python
# by lyrics_paths.py.
#
# rmpc resolves lyrics by indexing lyrics_dir and reading each file's own tags,
# not by deriving a path from the song, so the files can sit in one hidden
# directory instead of beside every track.

if [ -z "${XDG_MUSIC_DIR:-}" ]; then
  user_dirs_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
  if [ -r "$user_dirs_file" ]; then
    # shellcheck source=/dev/null
    . "$user_dirs_file"
  fi
fi

MUSIC_LIBRARY_ROOT="${XDG_MUSIC_DIR:-$HOME/Music}"
LYRICS_HIDDEN_DIR="${MUSIC_LIBRARY_ROOT}/.lyrics"

# lyrics_lrc_path <path> -> the .lrc that belongs to it
lyrics_lrc_path() {
  lyrics_target="$1"
  [ -n "$lyrics_target" ] || return 1

  case "$lyrics_target" in
    "${LYRICS_HIDDEN_DIR}/"*) ;;
    "${MUSIC_LIBRARY_ROOT}/"*)
      lyrics_target="${LYRICS_HIDDEN_DIR}/${lyrics_target#"${MUSIC_LIBRARY_ROOT}/"}"
      ;;
  esac

  printf '%s.lrc' "${lyrics_target%.*}"
}

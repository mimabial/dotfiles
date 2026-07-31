# Add user configurations here
# Edit $ZDOTDIR/startup.zsh to customize behavior before loading zshrc
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
typeset -g ZSHRC_LOADED=1
# Ignore commands that start with spaces and consecutive duplicates.
setopt HIST_IGNORE_SPACE HIST_IGNORE_DUPS
# Typing a directory path as a command cds into it.
setopt AUTO_CD
# Don't add certain commands to the history file.
zshaddhistory() {
  emulate -L zsh
  local line=${1%%$'\n'}
  case $line in
    ("&"|bg|fg|c|clear|history|exit|q|pwd) return 1 ;;
    (*" --help") return 1 ;;
  esac
  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  Plugins 
# zinit plugins are loaded in $ZDOTDIR/startup.zsh file, see the file for more information
#  Aliases 
# Override aliases here in '$ZDOTDIR/.zshrc' (already set in .zshenv)
music-library() {
  if [[ ${1:-} == '-s' || ${1:-} == '--set' || ${1:-} == --set=* ]]; then
    local library
    library=$(hyprshell media/music_library_config "$@") || return
    export XDG_MUSIC_DIR=$library
    print -r -- "$library"
    return
  fi
  hyprshell media/music_library_config "$@"
}

# Extract audio into $XDG_MUSIC_DIR. See `yt -h`.
yt() {
  local usage="usage: yt [-p] [-s] [-n] [-d <subdir>] [--] <url...>"
  local music_dir=${XDG_MUSIC_DIR:-$HOME/Music}
  local playlist=0 split=0 nothumb=0 sub=""
  while (( $# )); do
    case $1 in
      '-h'|'--help')
        print -r -- "$usage
  -p, --playlist    follow the playlist, numbering files 01, 02, … for albums
  -s, --split       split an \"Artist - Title\" upload title into real tags.
                    Wrong for the reversed \"Title - Artist\" form, so opt-in;
                    media/autotag derives the artist more reliably afterwards.
  -n, --no-thumb    skip the cover art, for live sets and non-music uploads
                    where the thumbnail is a video frame rather than a sleeve
  -d, --dir <sub>   download into $music_dir/<sub>, created on demand. One level
                    names the artist, two name the album, and a [G] or [C]
                    bucket names neither — media/autotag reads all of them.

-p, -s and -n shadow yt-dlp's --password, --simulate and --netrc; reach those
with --. Unrecognised options go to yt-dlp and stop the parsing above, so one of
ours placed after them is read by yt-dlp instead. Use -- when mixing:
  yt -p -d Kaey -- --playlist-items 1-3 <url>

Repeated artist credits are removed before filenames and tags are generated.
Filename template, noise stripping and cover art: ~/.config/yt-dlp/config"
        return 0 ;;
      '-p'|'--playlist') playlist=1; shift ;;
      '-s'|'--split')    split=1; shift ;;
      '-n'|'--no-thumb') nothumb=1; shift ;;
      '-d'|'--dir')      sub=$2; shift 2 ;;
      '--')               shift; break ;;
      *)             break ;;
    esac
  done
  (( $# )) || { print -u2 "\n$usage"; return 2 }

  local -a opts=(
    -x
    --audio-format best
    --use-postprocessor 'DeduplicateArtists:when=pre_process'
  )
  if (( playlist )); then
    opts+=(--yes-playlist
      -o "%(playlist_index&{:02d} - |)s%(artist&{} - |)s%(track,title,id).200B.%(ext)s")
  else
    opts+=(--no-playlist)
  fi
  (( split )) && opts+=(--parse-metadata 'title:^(?P<artist>.+?)\s*-\s*(?P<title>.+)$')
  (( nothumb )) && opts+=(--no-embed-thumbnail)
  [[ -n $sub ]] && opts+=(-P "$music_dir/$sub")

  yt-dlp "${opts[@]}" "$@"
}
export EDITOR=nvim
# export EDITOR=code
# unset -f command_not_found_handler # Uncomment to prevent searching for commands not found in package manager
#  Bindings 
bindkey "^[[3~" delete-char

# Enable vi mode
bindkey -v
bindkey -M viins "^[[3~" delete-char
bindkey -M vicmd "^[[3~" delete-char

# Keep useful emacs bindings in insert mode
bindkey "^A" beginning-of-line
bindkey "^E" end-of-line
bindkey "^K" kill-line
bindkey "^U" backward-kill-line
bindkey "^W" backward-kill-word
bindkey "^Y" yank

# Change cursor shape for different vi modes
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'  # Block cursor for normal mode
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] || [[ ${KEYMAP} = '' ]] || [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'  # Beam cursor for insert mode
  fi
}
zle -N zle-keymap-select

# Start with beam cursor
echo -ne '\e[5 q'

# Use beam cursor before each command without clobbering other preexec hooks
autoload -Uz add-zsh-hook
_cursor_beam_preexec() { echo -ne '\e[5 q'; }
add-zsh-hook preexec _cursor_beam_preexec

# Reduce ESC delay to 0.1s (default is 0.4s)
export KEYTIMEOUT=1

if [[ ${ZSH_NO_PLUGINS} != "1" && ${ZSH_DEFER} != "1" ]] && ! (( ${+functions[zinit]} )); then
    ### Added by Zinit's installer
    if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
        print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
        command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
        command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
            print -P "%F{33} %F{34}Installation successful.%f%b" || \
            print -P "%F{160} The clone has failed.%f%b"
    fi

    source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
    autoload -Uz _zinit
    (( ${+_comps} )) && _comps[zinit]=_zinit
    ### End of Zinit's installer chunk
fi

typeset -gU path PATH
path=("$HOME/.npm-global/bin" $path)

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

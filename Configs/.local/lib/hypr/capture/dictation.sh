#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require system || exit 1

readonly USAGE="Usage: hyprshell capture/dictation <start|stop|toggle|setup>
Record speech from the default microphone, transcribe it locally with whisper.cpp
and paste the text into the focused window (terminals included).
  start   begin recording
  stop    end the recording, then transcribe and paste it
  toggle  start or stop, whichever applies
  setup   install whisper-cpp and download the English speech and voice-activity models"
hypr_help_guard "${USAGE}" "$@"

readonly WHISPER_MODEL_DIR="${XDG_DATA_HOME}/whisper-cpp"
readonly WHISPER_MODEL="${WHISPER_MODEL_DIR}/ggml-base.en.bin"
readonly WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${WHISPER_MODEL##*/}"
readonly WHISPER_VAD_MODEL="${WHISPER_MODEL_DIR}/ggml-silero-v6.2.0.bin"
readonly WHISPER_VAD_MODEL_URL="https://huggingface.co/ggml-org/whisper-vad/resolve/main/${WHISPER_VAD_MODEL##*/}"
readonly WHISPER_SAMPLE_RATE=16000
readonly DICTATION_DIR="${HYPR_RUNTIME_DIR}/dictation"
readonly DICTATION_AUDIO="${DICTATION_DIR}/speech.wav"
readonly DICTATION_LOCK="${DICTATION_DIR}/recorder.lock"
readonly DICTATION_PID="${DICTATION_DIR}/recorder.pid"

notify_dictation() {
  local timeout_ms="$1"
  shift
  dunstify -a Dictation -r "${NOTIFY_ID_DICTATION}" -t "${timeout_ms}" -e -i audio-input-microphone "$@"
}

dictation_recording() {
  [[ -e "${DICTATION_LOCK}" ]] && ! flock -n "${DICTATION_LOCK}" true
}

dictation_start() {
  if [[ ! -s "${WHISPER_MODEL}" || ! -s "${WHISPER_VAD_MODEL}" ]]; then
    notify_dictation "${NOTIFY_ERROR_MS}" "Dictation is not set up" "Run Install > AI > Dictation from the menu"
    return 1
  fi
  dictation_recording && return 0

  mkdir -p "${DICTATION_DIR}"
  flock -n --no-fork "${DICTATION_LOCK}" \
    pw-record --rate "${WHISPER_SAMPLE_RATE}" --channels 1 --format s16 "${DICTATION_AUDIO}" </dev/null &
  printf '%s\n' "$!" >"${DICTATION_PID}"
  notify_dictation "${NOTIFY_STICKY_MS}" "Listening" "Toggle dictation again to paste the text"
}

transcribe_into() {
  local -n transcript_ref="$1"
  local raw=""
  local -a words=()

  raw="$(whisper-cli -m "${WHISPER_MODEL}" --vad -vm "${WHISPER_VAD_MODEL}" -f "${DICTATION_AUDIO}" \
    -l en -nt -np -sns 2>/dev/null)" || return 1
  read -r -d '' -a words <<<"${raw}" || true
  transcript_ref="${words[*]}"
}

dictation_stop() {
  local transcript=""

  dictation_recording || return 0
  kill -TERM "$(<"${DICTATION_PID}")"
  flock "${DICTATION_LOCK}" true
  notify_dictation "${NOTIFY_STICKY_MS}" "Transcribing"

  if ! transcribe_into transcript; then
    rm -f "${DICTATION_AUDIO}"
    notify_dictation "${NOTIFY_ERROR_MS}" -u critical "Dictation failed" "whisper-cli could not transcribe the recording"
    return 1
  fi
  rm -f "${DICTATION_AUDIO}"

  if [[ -z "${transcript}" ]]; then
    notify_dictation "${NOTIFY_BRIEF_MS}" "Nothing heard"
    return 0
  fi
  dunstify -C "${NOTIFY_ID_DICTATION}"
  wl-copy -- "${transcript}"
  paste_clipboard --into-terminals
}

download_model() {
  local url="$1" path="$2"

  [[ -s "${path}" ]] && return 0
  mkdir -p "${path%/*}"
  printf 'Downloading %s\n' "${path##*/}"
  curl -fL --progress-bar -o "${path}.part" "${url}" && mv -f "${path}.part" "${path}"
}

dictation_setup() {
  command -v whisper-cli >/dev/null || hyprshell package-manager add whisper-cpp || return 1
  download_model "${WHISPER_MODEL_URL}" "${WHISPER_MODEL}" || return 1
  download_model "${WHISPER_VAD_MODEL_URL}" "${WHISPER_VAD_MODEL}" || return 1
  printf 'Dictation is ready: toggle it from the Insert submap.\n'
}

case "$#:${1:-}" in
  1:start) dictation_start ;;
  1:stop) dictation_stop ;;
  1:toggle)
    if dictation_recording; then
      dictation_stop
    else
      dictation_start
    fi
    ;;
  1:setup) dictation_setup ;;
  *)
    printf '%s\n' "${USAGE}" >&2
    exit 2
    ;;
esac

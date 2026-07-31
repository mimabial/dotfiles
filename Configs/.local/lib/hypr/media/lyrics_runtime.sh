#!/usr/bin/env sh

resolve_lyrics_python() {
    managed_python="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/pip_env/bin/python"

    if [ -n "${LYRICS_PYTHON:-}" ] && [ -x "${LYRICS_PYTHON}" ]; then
        printf '%s' "${LYRICS_PYTHON}"
        return 0
    fi

    if [ -x "$managed_python" ]; then
        printf '%s' "$managed_python"
        return 0
    fi

    return 1
}

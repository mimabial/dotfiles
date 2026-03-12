#!/usr/bin/env sh

resolve_lyrics_python() {
    if [ -n "${LYRICS_PYTHON:-}" ] && [ -x "${LYRICS_PYTHON}" ]; then
        printf '%s' "${LYRICS_PYTHON}"
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        command -v python3
        return 0
    fi

    return 1
}

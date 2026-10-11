#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import sys
import shutil
import subprocess
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils import child_process
from pyutils.xdg_base_dirs import xdg_config_home
from lyrics_text import ProviderResult, build_result, lrc_header, to_lrc_from_plain
from lyrics_http import DEFAULT_TIMEOUT


try:
    from lyricsgenius import Genius

    HAS_GENIUS = True
except ImportError:
    HAS_GENIUS = False


_GENIUS_CLIENT = None


_GENIUS_TOKEN_KEYS = ("GENIUS_TOKEN", "GENIUS_ACCESS_TOKEN")


_GENIUS_WORKER_FLAG = "--genius-worker"


GENIUS_WORKER_TIMEOUT = DEFAULT_TIMEOUT * 4 + 5


def _parse_env_value(raw_value: str) -> str:
    """Parse the limited value syntax needed by the private Genius env file."""
    value = raw_value.strip()
    if not value:
        return ""

    if value[0] in {"'", '"'}:
        quote = value[0]
        closing_quote = value.find(quote, 1)
        if closing_quote == -1:
            return ""
        remainder = value[closing_quote + 1 :].strip()
        if remainder and not remainder.startswith("#"):
            return ""
        return value[1:closing_quote]

    return value.split(" #", 1)[0].strip()


def _genius_token_from_file() -> str:
    config_home = xdg_config_home()
    env_file = config_home / "genius" / "env"

    try:
        if env_file.stat().st_mode & 0o077:
            print(
                f"  [genius] Ignoring {env_file} "
                "(group/other permissions are not allowed)",
                file=sys.stderr,
            )
            return ""
        lines = env_file.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return ""
    except OSError as error:
        print(f"  [genius] Cannot read {env_file}: {error}", file=sys.stderr)
        return ""

    values: dict[str, str] = {}
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        line = line.removeprefix("export ").lstrip()

        key, separator, raw_value = line.partition("=")
        key = key.strip()
        if not separator or key not in _GENIUS_TOKEN_KEYS:
            continue

        value = _parse_env_value(raw_value)
        if value:
            values[key] = value

    return next((values[key] for key in _GENIUS_TOKEN_KEYS if values.get(key)), "")


def get_genius_token() -> str:
    return next(
        (
            token
            for key in _GENIUS_TOKEN_KEYS
            if (token := os.environ.get(key, "").strip())
        ),
        "",
    ) or _genius_token_from_file()


def get_genius_client():
    global _GENIUS_CLIENT

    if _GENIUS_CLIENT is not None:
        return _GENIUS_CLIENT
    if not HAS_GENIUS:
        return None

    token = get_genius_token()
    if not token:
        return None

    try:
        try:
            _GENIUS_CLIENT = Genius(
                token,
                skip_non_songs=True,
                remove_section_headers=True,
                timeout=DEFAULT_TIMEOUT,
            )
        except TypeError as error:
            if "timeout" not in str(error):
                raise
            # Older lyricsgenius versions may not support timeout kwarg.
            _GENIUS_CLIENT = Genius(
                token,
                skip_non_songs=True,
                remove_section_headers=True,
            )
        return _GENIUS_CLIENT
    except Exception as e:  # noqa: BLE001 - third-party client boundary
        print(f"  [genius] Client init failed: {e}", file=sys.stderr)
        return None


def _fetch_lyrics_genius_direct(artist: str, title: str) -> ProviderResult | None:
    if not HAS_GENIUS:
        print("  [genius] Skipped (lyricsgenius not installed)", file=sys.stderr)
        return None

    client = get_genius_client()
    if client is None:
        print("  [genius] Skipped (token/client unavailable)", file=sys.stderr)
        return None

    try:
        print(f"  [genius] Searching for: {artist} - {title}", file=sys.stderr)
        song = client.search_song(title, artist)
        if song is None or not getattr(song, "lyrics", None):
            print("  [genius] No lyrics found", file=sys.stderr)
            return None

        lyrics_text = str(song.lyrics).strip()
        lyrics_text = re.sub(r"\n?\d*Embed\s*$", "", lyrics_text, flags=re.IGNORECASE).strip()
        if not lyrics_text:
            print("  [genius] Empty lyrics payload", file=sys.stderr)
            return None

        result_artist = str(getattr(song, "artist", "") or artist).strip()
        result_title = str(getattr(song, "title", "") or title).strip()
        lrc_lines = lrc_header(result_artist, result_title)
        lrc_lines.append(to_lrc_from_plain(lyrics_text))

        print("  [genius] Found plain lyrics", file=sys.stderr)
        return build_result(
            "genius",
            "\n".join(lrc_lines),
            result_artist,
            result_title,
            False,
        )

    except Exception as error:  # noqa: BLE001 - third-party client boundary
        message = str(error).split("Response body:", 1)[0].strip()
        print(f"  [genius] Error: {message or type(error).__name__}", file=sys.stderr)
        return None


def _fetch_lyrics_genius_excluded(
    mullvad_exclude: str,
    artist: str,
    title: str,
) -> ProviderResult | None:
    command = [
        mullvad_exclude,
        sys.executable,
        str(Path(__file__).resolve()),
        _GENIUS_WORKER_FLAG,
        artist,
        title,
    ]
    try:
        completed = child_process.run(
            command,
            capture_output=True,
            text=True,
            timeout=GENIUS_WORKER_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"  [genius] Split-tunnel worker failed: {error}", file=sys.stderr)
        return None

    if completed.stderr:
        print(completed.stderr.rstrip(), file=sys.stderr)
    if completed.returncode != 0:
        print(
            f"  [genius] Split-tunnel worker exited with status "
            f"{completed.returncode}",
            file=sys.stderr,
        )
        return None

    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        print(f"  [genius] Invalid worker response: {error}", file=sys.stderr)
        return None

    if result is None:
        return None
    if not isinstance(result, dict) or not isinstance(result.get("lyrics"), str):
        print("  [genius] Invalid worker result", file=sys.stderr)
        return None
    return result


def fetch_lyrics_genius(artist: str, title: str) -> ProviderResult | None:
    mullvad_exclude = shutil.which("mullvad-exclude")
    if mullvad_exclude:
        return _fetch_lyrics_genius_excluded(mullvad_exclude, artist, title)
    return _fetch_lyrics_genius_direct(artist, title)


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 3 or args[0] != _GENIUS_WORKER_FLAG:
        print("This module provides internal lyrics fetchers.", file=sys.stderr)
        return 2

    result = _fetch_lyrics_genius_direct(args[1], args[2])
    json.dump(result, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


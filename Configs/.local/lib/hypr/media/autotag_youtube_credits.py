from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils import child_process
from autotag_identity import CREDIT_NAME_SIMILARITY, CREDIT_RECOVERY_TITLE_SIMILARITY, existing, missing_credit_names, parse_filename, similarity, title_similarity, track_identity
from ytdlp_config import ytdlp_auth_args
from autotag_models import Unidentified


def youtube_credit_metadata(url: str, timeout: int = 45) -> dict[str, str]:
    """Metadata only; nothing is downloaded."""
    if not re.match(r"^https?://(?:www\.|music\.)?(?:youtube\.com|youtu\.be)/", url, re.I):
        raise Unidentified("no supported YouTube purl")
    executable = shutil.which("yt-dlp")
    if executable is None:
        raise Unidentified("yt-dlp is unavailable")
    try:
        proc = child_process.run(
            [
                executable,
                "--ignore-config",
                *ytdlp_auth_args(),
                "--no-playlist",
                "--skip-download",
                "--dump-single-json",
                "--no-warnings",
                url,
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise Unidentified("YouTube metadata lookup timed out") from exc
    except OSError as exc:
        raise Unidentified(f"YouTube metadata lookup failed: {exc}") from exc
    if proc.returncode != 0:
        detail = proc.stderr.strip() or f"yt-dlp exited {proc.returncode}"
        raise Unidentified(f"YouTube metadata lookup failed: {detail}")
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise Unidentified("yt-dlp returned invalid metadata") from exc

    raw_artists = data.get("artists")
    artists: list[str] = []
    if isinstance(raw_artists, (list, tuple)):
        for value in raw_artists:
            name = str(value or "").strip()
            if name and not any(
                similarity(name, present) >= CREDIT_NAME_SIMILARITY
                for present in artists
            ):
                artists.append(name)
    artist = ", ".join(artists) or str(data.get("artist") or "").strip()
    title = str(data.get("track") or data.get("title") or "").strip()
    if not artist or not title:
        raise Unidentified("YouTube metadata has no structured artist/title")
    return {"artist": artist, "title": title}


def filename_credit_loss(path: Path, tags) -> list[str]:
    file_artist, file_title = parse_filename(path)
    if not file_artist or not file_title:
        return []
    return missing_credit_names(
        file_artist,
        file_title,
        existing(tags, "artist"),
        existing(tags, "title"),
    )


def recovered_youtube_artist(path: Path, tags) -> str:
    purl = existing(tags, "purl")
    if not purl:
        raise Unidentified("file has no YouTube purl")
    source = youtube_credit_metadata(purl)
    file_artist, file_title = parse_filename(path)
    reference_title = file_title or existing(tags, "title")
    if (
        not reference_title
        or title_similarity(source["title"], reference_title)
        < CREDIT_RECOVERY_TITLE_SIMILARITY
    ):
        raise Unidentified("YouTube purl title does not match the file")

    _, source_credit, _ = track_identity(source["artist"], source["title"])
    unverified = missing_credit_names(
        file_artist,
        file_title,
        source_credit,
        source["title"],
    )
    if unverified:
        raise Unidentified(
            "YouTube purl does not verify: " + ", ".join(unverified)
        )
    return source_credit


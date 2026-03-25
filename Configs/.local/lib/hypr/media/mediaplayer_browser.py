#!/usr/bin/env python3
import os
import re
import shlex
import shutil
import subprocess
import time
from dataclasses import dataclass
from urllib.parse import parse_qs, urlparse

_ytdlp_inflight = {}
_ytdlp_timeout_seconds = 20.0
_ytdlp_auth_args_cache = None
_youtube_page_timeout_seconds = 2.5
_current_track_media_info = {"media_url": "", "info": None}


def set_ytdlp_timeout_seconds(value: float) -> None:
    global _ytdlp_timeout_seconds
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return
    if parsed > 0:
        _ytdlp_timeout_seconds = parsed


def get_ytdlp_timeout_seconds() -> float:
    raw = os.getenv("MEDIAPLAYER_YTDLP_TIMEOUT", "").strip()
    if raw:
        try:
            value = float(raw)
            if value > 0:
                return value
        except ValueError:
            pass
    return 20.0


def is_youtube_url(url: str) -> bool:
    if not url:
        return False
    return (
        "youtube.com/watch" in url
        or "youtube.com/shorts/" in url
        or "music.youtube.com/watch" in url
        or "youtu.be/" in url
    )


def canonicalize_youtube_url(url: str) -> str:
    if not is_youtube_url(url):
        return url

    try:
        parsed = urlparse(url)
    except Exception:
        return url

    host = parsed.netloc.lower()
    query = parse_qs(parsed.query)
    video_id = query.get("v", [""])[0]

    if "youtu.be" in host:
        video_id = parsed.path.lstrip("/")

    if video_id:
        return f"https://www.youtube.com/watch?v={video_id}"

    return url


def title_looks_live(title: str) -> bool:
    normalized = (title or "").upper()
    return any(
        marker in normalized
        for marker in (
            "[LIVE]",
            " LIVE",
            "EN DIRECT",
            "EN VIVO",
            "AO VIVO",
            "🔴",
        )
    )


def _parse_ytdlp_duration(stdout: str) -> float | None:
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            parsed = float(line)
            if parsed > 0:
                return parsed
        except ValueError:
            continue
    return None


@dataclass(frozen=True)
class YtDlpMediaInfo:
    duration_seconds: float | None = None
    live_status: str = ""

    @property
    def is_live(self) -> bool:
        return self.live_status == "is_live"


def _parse_ytdlp_media_info(stdout: str) -> YtDlpMediaInfo:
    lines = [line.strip() for line in stdout.splitlines()]
    live_status = lines[0] if lines else ""
    duration_seconds = _parse_ytdlp_duration("\n".join(lines[1:]))
    return YtDlpMediaInfo(duration_seconds=duration_seconds, live_status=live_status)


def _parse_youtube_watch_page_media_info(html: str) -> YtDlpMediaInfo:
    live_match = re.search(r'"isLiveContent":(true|false)', html)
    if not live_match:
        live_match = re.search(r'"isLiveNow":(true|false)', html)
    if live_match and live_match.group(1) == "true":
        return YtDlpMediaInfo(live_status="is_live")

    duration_match = re.search(r'"lengthSeconds":"(\d+)"', html)
    if duration_match:
        try:
            duration_seconds = float(duration_match.group(1))
            if duration_seconds > 0:
                return YtDlpMediaInfo(
                    duration_seconds=duration_seconds,
                    live_status="not_live",
                )
        except ValueError:
            pass

    return YtDlpMediaInfo()


def _build_youtube_watch_page_probe_command(url: str) -> list[str] | None:
    url = canonicalize_youtube_url(url)
    curl_bin = shutil.which("curl")
    if not curl_bin:
        return None
    return [
        curl_bin,
        "-L",
        "-A",
        (
            "Mozilla/5.0 (X11; Linux x86_64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/133.0.0.0 Safari/537.36"
        ),
        "-H",
        "Accept-Language: en-US,en;q=0.9",
        "-sS",
        url,
    ]


def _get_ytdlp_auth_args() -> list[str]:
    global _ytdlp_auth_args_cache
    if _ytdlp_auth_args_cache is not None:
        return list(_ytdlp_auth_args_cache)

    config_home = os.path.expanduser(os.getenv("XDG_CONFIG_HOME", "~/.config"))
    config_path = os.path.join(config_home, "yt-dlp", "config")
    args = []

    try:
        tokens = []
        with open(config_path, encoding="utf-8") as file:
            for raw_line in file:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                tokens.extend(shlex.split(line))

        idx = 0
        while idx < len(tokens):
            token = tokens[idx]
            if token in ("--cookies-from-browser", "--cookies"):
                if idx + 1 < len(tokens):
                    args.extend((token, tokens[idx + 1]))
                idx += 2
                continue
            if token.startswith("--cookies-from-browser=") or token.startswith(
                "--cookies="
            ):
                args.append(token)
            idx += 1
    except (FileNotFoundError, OSError, ValueError):
        args = []

    _ytdlp_auth_args_cache = tuple(args)
    return list(_ytdlp_auth_args_cache)


def _build_ytdlp_probe_command(url: str) -> list[str] | None:
    url = canonicalize_youtube_url(url)
    ytdlp_bin = shutil.which("yt-dlp")
    if not ytdlp_bin:
        return None
    return [
        ytdlp_bin,
        "--ignore-config",
        "--quiet",
        "--no-progress",
        "--no-warnings",
        "--skip-download",
        "--no-playlist",
        "--print",
        "live_status",
        "--print",
        "duration",
        url,
    ]


def _start_media_info_probe_command(url: str, command: list[str], kind: str) -> None:
    if url in _ytdlp_inflight:
        return

    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except Exception:
        return

    _ytdlp_inflight[url] = {
        "process": process,
        "started_at": time.time(),
        "kind": kind,
    }


def _start_ytdlp_fallback_probe(url: str) -> None:
    if url in _ytdlp_inflight:
        return

    command = _build_ytdlp_probe_command(url)
    if not command:
        return
    _start_media_info_probe_command(url, command, "ytdlp")


def _start_ytdlp_media_info_probe(url: str) -> None:
    if url in _ytdlp_inflight:
        return

    command = _build_youtube_watch_page_probe_command(url)
    if command:
        _start_media_info_probe_command(url, command, "page")
        return
    _start_ytdlp_fallback_probe(url)


def _poll_ytdlp_media_info_probe(url: str) -> YtDlpMediaInfo | None:
    probe = _ytdlp_inflight.get(url)
    if not probe:
        return None

    process = probe["process"]
    started_at = float(probe["started_at"])
    probe_kind = str(probe.get("kind", "ytdlp"))
    if process.poll() is None:
        timeout_seconds = (
            _youtube_page_timeout_seconds
            if probe_kind == "page"
            else _ytdlp_timeout_seconds
        )
        if time.time() - started_at > timeout_seconds:
            try:
                process.kill()
            except Exception:
                pass
            _ytdlp_inflight.pop(url, None)
            if probe_kind == "page":
                _start_ytdlp_fallback_probe(url)
        return None

    stdout = ""
    try:
        stdout, _ = process.communicate()
    except Exception:
        pass

    _ytdlp_inflight.pop(url, None)
    if probe_kind == "page":
        page_info = _parse_youtube_watch_page_media_info(stdout)
        if page_info.duration_seconds is not None or page_info.live_status:
            return page_info
        _start_ytdlp_fallback_probe(url)
        return None
    if process.returncode == 0:
        return _parse_ytdlp_media_info(stdout)
    return YtDlpMediaInfo()


def get_ytdlp_media_info(
    url: str,
    *,
    same_track_as_last: bool = False,
    last_duration_seconds: float = 0.0,
    last_live_status: str = "",
) -> YtDlpMediaInfo:
    global _current_track_media_info
    if not is_youtube_url(url):
        return YtDlpMediaInfo()
    url = canonicalize_youtube_url(url)

    current_track_info = _current_track_media_info.get("info")
    if (
        _current_track_media_info.get("media_url") == url
        and isinstance(current_track_info, YtDlpMediaInfo)
        and (
            current_track_info.duration_seconds is not None
            or current_track_info.live_status
        )
    ):
        return current_track_info

    if same_track_as_last:
        if last_live_status == "is_live":
            return YtDlpMediaInfo(live_status="is_live")
        if last_duration_seconds > 0:
            return YtDlpMediaInfo(
                duration_seconds=last_duration_seconds,
                live_status="not_live",
            )

    completed_probe = _poll_ytdlp_media_info_probe(url)
    if completed_probe is not None:
        if completed_probe.duration_seconds is not None or completed_probe.live_status:
            _current_track_media_info = {"media_url": url, "info": completed_probe}
        return completed_probe

    if url in _ytdlp_inflight:
        if same_track_as_last:
            if last_live_status == "is_live":
                return YtDlpMediaInfo(live_status="is_live")
            if last_duration_seconds > 0:
                return YtDlpMediaInfo(
                    duration_seconds=last_duration_seconds,
                    live_status="not_live",
                )
        return YtDlpMediaInfo()

    if _current_track_media_info.get("media_url") != url:
        _current_track_media_info = {"media_url": url, "info": None}
    _start_ytdlp_media_info_probe(url)
    if same_track_as_last:
        if last_live_status == "is_live":
            return YtDlpMediaInfo(live_status="is_live")
        if last_duration_seconds > 0:
            return YtDlpMediaInfo(
                duration_seconds=last_duration_seconds,
                live_status="not_live",
            )
    return YtDlpMediaInfo()


def youtube_position_is_untrusted(
    *,
    resolved_metadata,
    raw_metadata,
    reported_position_seconds: float,
    duration_seconds: float,
    is_playing: bool,
    recent_seek_to_end: bool,
    previous_track_key: str,
    current_track_key: str,
    previous_raw_position: float,
) -> bool:
    if (
        not is_playing
        or not resolved_metadata.is_youtube
        or duration_seconds <= 0
        or recent_seek_to_end
    ):
        return False

    browser_duration_seconds = max(0.0, round(raw_metadata.duration_seconds, 2))
    terminal_against_duration = reported_position_seconds >= max(
        0.0, duration_seconds - 1.0
    )
    terminal_against_browser_duration = (
        browser_duration_seconds > 0
        and reported_position_seconds >= max(0.0, browser_duration_seconds - 1.0)
    )
    browser_duration_mismatch = (
        browser_duration_seconds > 0
        and duration_seconds > (browser_duration_seconds + 15.0)
        and terminal_against_browser_duration
    )
    same_track_terminal_jump = (
        previous_track_key == current_track_key
        and previous_raw_position < max(0.0, duration_seconds - 15.0)
        and terminal_against_duration
        and reported_position_seconds > (previous_raw_position + 15.0)
    )
    fresh_track_terminal_snapshot = (
        previous_track_key != current_track_key and terminal_against_duration
    )
    return (
        browser_duration_mismatch
        or same_track_terminal_jump
        or fresh_track_terminal_snapshot
    )

#!/usr/bin/env python3
import os
import sys

import gi

gi.require_version("Playerctl", "2.0")
import argparse
import json
import logging
import math
import re
import shlex
import shutil
import signal
import subprocess
import time
from urllib.parse import parse_qs, urlparse
from dataclasses import dataclass, replace

from gi.repository import GLib, Playerctl

players_data = {}
current_player = None
_timer_id = None  # Track the timer source ID
_runtime_state_file = None
_recover_max_age_seconds = 20.0
_ytdlp_inflight = {}
_ytdlp_timeout_seconds = 20.0
_ytdlp_auth_args_cache = None
_youtube_page_timeout_seconds = 2.5
_current_track_media_info = {"media_url": "", "info": None}


def load_env_file(filepath: str) -> None:
    try:
        with open(filepath, encoding="utf-8") as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    if line.startswith("export "):
                        line = line[len("export ") :]
                    key, value = line.strip().split("=", 1)
                    os.environ[key] = value.strip('"')
    except (FileNotFoundError, OSError) as e:
        print(f"ERROR: Error loading environment file {filepath}: {e}", file=sys.stderr)


def load_pywal_colors(cache_root: str) -> dict:
    colors = {}
    colors_json = os.path.join(cache_root, "wal", "colors.json")
    try:
        with open(colors_json, encoding="utf-8") as f:
            data = json.load(f)
        colors.update(data.get("special", {}))
        colors.update(data.get("colors", {}))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return {}
    return colors


def normalize_color(value: str, wal_colors: dict, fallback: str) -> str:
    if not value:
        return fallback
    value = value.strip()
    if not value:
        return fallback
    lookup = wal_colors.get(value) or wal_colors.get(value.lower())
    if lookup:
        return lookup
    if value.startswith("#"):
        return value
    if len(value) in (3, 6, 8):
        return f"#{value}"
    return fallback


def emit_json_output(output: dict) -> None:
    """Write one JSON line to stdout, exiting immediately if the pipe is gone."""
    try:
        sys.stdout.write(json.dumps(output, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except (BrokenPipeError, OSError):
        os._exit(0)


def load_runtime_position_state() -> dict:
    if not _runtime_state_file or not os.path.exists(_runtime_state_file):
        return {
            "track_key": "",
            "position": 0.0,
            "duration": 0.0,
            "wall_time": 0.0,
            "trusted": False,
        }

    try:
        with open(_runtime_state_file, "r", encoding="utf-8") as file:
            data = json.load(file)
        if isinstance(data, dict):
            return {
                "track_key": str(data.get("track_key", "")),
                "position": float(data.get("position", 0.0)),
                "duration": float(data.get("duration", 0.0)),
                "wall_time": float(data.get("wall_time", 0.0)),
                "trusted": bool(data.get("trusted", False)),
            }
    except (FileNotFoundError, OSError, ValueError, json.JSONDecodeError):
        pass

    return {
        "track_key": "",
        "position": 0.0,
        "duration": 0.0,
        "wall_time": 0.0,
        "trusted": False,
    }


def save_runtime_position_state(
    track_key: str, position: float, duration: float, trusted: bool = True
) -> None:
    if not _runtime_state_file:
        return

    directory = os.path.dirname(_runtime_state_file)
    tmp_file = f"{_runtime_state_file}.tmp"
    try:
        os.makedirs(directory, exist_ok=True)
        payload = {
            "track_key": track_key,
            "position": float(position),
            "duration": float(duration),
            "wall_time": float(time.time()),
            "trusted": bool(trusted),
        }
        with open(tmp_file, "w", encoding="utf-8") as file:
            json.dump(payload, file)
        os.replace(tmp_file, _runtime_state_file)
    except OSError:
        pass
    finally:
        try:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)
        except OSError:
            pass


def get_recover_max_age_seconds() -> float:
    raw = os.getenv("MEDIAPLAYER_RECOVER_MAX_AGE", "").strip()
    if raw:
        try:
            value = float(raw)
            if value >= 0:
                return value
        except ValueError:
            pass
    return 20.0


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


def _probe_youtube_watch_page_media_info_once(url: str) -> YtDlpMediaInfo:
    command = _build_youtube_watch_page_probe_command(url)
    if not command:
        return YtDlpMediaInfo()

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=_youtube_page_timeout_seconds,
        )
    except Exception:
        return YtDlpMediaInfo()

    return _parse_youtube_watch_page_media_info(result.stdout)


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


def _probe_ytdlp_media_info(url: str) -> YtDlpMediaInfo:
    url = canonicalize_youtube_url(url)
    ytdlp_bin = shutil.which("yt-dlp")
    if not ytdlp_bin:
        return YtDlpMediaInfo()

    base_cmd = [
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

    auth_args = _get_ytdlp_auth_args()
    probe_variants = [base_cmd]
    if auth_args:
        probe_variants.append(
            [
                ytdlp_bin,
                "--ignore-config",
                *auth_args,
                "--no-warnings",
                "--skip-download",
                "--no-playlist",
                "--print",
                "live_status",
                "--print",
                "duration",
                url,
            ]
        )

    for command in probe_variants:
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=_ytdlp_timeout_seconds,
            )
        except Exception:
            continue
        if result.returncode == 0:
            return _parse_ytdlp_media_info(result.stdout)

    return YtDlpMediaInfo()


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
            _youtube_page_timeout_seconds if probe_kind == "page" else _ytdlp_timeout_seconds
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
        and (current_track_info.duration_seconds is not None or current_track_info.live_status)
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
        return YtDlpMediaInfo()

    if _current_track_media_info.get("media_url") != url:
        _current_track_media_info = {"media_url": url, "info": None}
    immediate_page_info = _probe_youtube_watch_page_media_info_once(url)
    if immediate_page_info.duration_seconds is not None or immediate_page_info.live_status:
        _current_track_media_info = {"media_url": url, "info": immediate_page_info}
        return immediate_page_info
    _start_ytdlp_media_info_probe(url)
    return YtDlpMediaInfo()


@dataclass
class MediaMetadata:
    track: str = ""
    artist: str = ""
    track_id: str = ""
    media_url: str = ""
    duration_seconds: float = 0.0
    ytdlp_duration_seconds: float | None = None
    ytdlp_live_status: str = ""

    @property
    def identity_present(self) -> bool:
        return bool(self.media_url or self.track_id or self.track or self.artist)

    @property
    def is_youtube(self) -> bool:
        return is_youtube_url(self.media_url)

    @property
    def is_live_stream(self) -> bool:
        return self.ytdlp_live_status == "is_live"

    def same_track_as(self, previous: dict) -> bool:
        if self.media_url and previous["media_url"]:
            return self.media_url == previous["media_url"]
        if self.track and previous["track"]:
            same_track = self.track == previous["track"]
            if self.artist and previous["artist"]:
                same_track = same_track and self.artist == previous["artist"]
            return same_track
        if self.track_id and previous["track_id"]:
            return self.track_id == previous["track_id"]
        return False


def build_track_identity_key(
    player_name: str,
    track_id: str,
    media_url: str,
    track: str,
    artist: str,
) -> str:
    return f"{player_name}|{track_id}|{media_url}|{track}|{artist}"


def saved_state_matches_track(saved_track_key: str, current_track_key: str) -> bool:
    if not saved_track_key or not current_track_key:
        return False
    return saved_track_key == current_track_key or saved_track_key.startswith(
        f"{current_track_key}|"
    )


def predict_saved_position(
    saved_state: dict,
    *,
    now_wall: float,
    duration_seconds: float,
    playback_rate: float,
    playing: bool,
) -> float:
    predicted = max(0.0, float(saved_state.get("position", 0.0)))
    if playing:
        predicted += (
            max(0.0, now_wall - float(saved_state.get("wall_time", 0.0)))
            * playback_rate
        )
    if duration_seconds > 0:
        predicted = min(duration_seconds, predicted)
    return max(0.0, predicted)


def read_player_metadata(current_player) -> MediaMetadata:
    snapshot = MediaMetadata()
    try:
        metadata = current_player.props.metadata
        if metadata:
            data = metadata.unpack()
            snapshot.track = data.get("xesam:title", "") or ""
            snapshot.artist = (
                data.get("xesam:artist", [""])[0] if "xesam:artist" in data else ""
            )
            snapshot.track_id = str(data.get("mpris:trackid", "") or "")
            snapshot.media_url = str(data.get("xesam:url", "") or "")
            snapshot.duration_seconds = data.get("mpris:length", 0) / 1e6
    except Exception:
        pass
    return snapshot


def resolve_metadata_duration(snapshot: MediaMetadata, last_metadata: dict) -> MediaMetadata:
    same_track_as_last = snapshot.same_track_as(last_metadata)
    last_duration_seconds = max(0.0, float(last_metadata.get("duration", 0.0)))
    last_live_status = str(last_metadata.get("live_status", ""))
    ytdlp_info = get_ytdlp_media_info(
        snapshot.media_url,
        same_track_as_last=same_track_as_last,
        last_duration_seconds=last_duration_seconds,
        last_live_status=last_live_status,
    )
    ytdlp_duration = ytdlp_info.duration_seconds
    resolved_duration = snapshot.duration_seconds

    if snapshot.is_youtube:
        if ytdlp_info.is_live:
            resolved_duration = 0.0
        elif ytdlp_duration and ytdlp_duration > 0:
            resolved_duration = ytdlp_duration
        elif resolved_duration >= 4 * 3600:
            resolved_duration = 0.0
    elif ytdlp_duration and ytdlp_duration > 0 and resolved_duration <= 0:
        resolved_duration = ytdlp_duration

    return replace(
        snapshot,
        duration_seconds=resolved_duration,
        ytdlp_duration_seconds=ytdlp_duration,
        ytdlp_live_status=ytdlp_info.live_status,
    )


def resolve_browser_metadata_fallbacks(
    raw_metadata: MediaMetadata,
    *,
    player_status: str,
    position_seconds: float,
    seek_position,
    seek_age: float,
    last_metadata: dict,
    position_state: dict,
) -> tuple[MediaMetadata, dict]:
    resolved = replace(raw_metadata)
    is_playing = player_status == "Playing"
    previous_raw_position = float(position_state.get("raw_position", 0.0))

    recent_seek_to_start = (
        seek_position is not None
        and 0.0 <= seek_age <= 2.5
        and float(seek_position) <= 3.0
    )
    likely_track_rollover = (
        not raw_metadata.track
        and not raw_metadata.artist
        and not raw_metadata.track_id
        and is_playing
        and previous_raw_position > 5.0
        and position_seconds <= 3.0
    )

    same_track_as_last = raw_metadata.same_track_as(last_metadata)
    youtube_url_changed = (
        raw_metadata.is_youtube
        and bool(last_metadata["media_url"])
        and raw_metadata.media_url != last_metadata["media_url"]
    )

    allow_text_fallback = not (recent_seek_to_start or likely_track_rollover)
    allow_duration_fallback = not likely_track_rollover
    if recent_seek_to_start and not same_track_as_last:
        allow_duration_fallback = False

    if allow_text_fallback and not resolved.track and last_metadata["track"]:
        resolved.track = last_metadata["track"]
    if allow_text_fallback and not resolved.artist and last_metadata["artist"]:
        resolved.artist = last_metadata["artist"]

    if (
        allow_duration_fallback
        and resolved.duration_seconds <= 0
        and last_metadata["duration"] > 0
        and (not raw_metadata.identity_present or same_track_as_last)
    ):
        resolved.duration_seconds = last_metadata["duration"]

    if youtube_url_changed and not (
        raw_metadata.ytdlp_duration_seconds and raw_metadata.ytdlp_duration_seconds > 0
    ):
        resolved.duration_seconds = 0.0

    updated_last_metadata = last_metadata
    if resolved.track or resolved.artist or resolved.duration_seconds > 0:
        cached_track_id = raw_metadata.track_id
        if not cached_track_id and same_track_as_last:
            cached_track_id = last_metadata["track_id"]
        cached_live_status = raw_metadata.ytdlp_live_status
        if not cached_live_status and same_track_as_last:
            cached_live_status = str(last_metadata.get("live_status", ""))
        updated_last_metadata = {
            "track": resolved.track,
            "artist": resolved.artist,
            "track_id": cached_track_id,
            "media_url": raw_metadata.media_url,
            "duration": resolved.duration_seconds
            if resolved.duration_seconds > 0
            else 0.0,
            "live_status": cached_live_status,
        }

    return resolved, updated_last_metadata


def validate_config() -> None:
    """Validate and sanitize configuration values"""
    global \
        max_length_module, \
        prefix_playing, \
        prefix_paused, \
        standby_text, \
        artist_track_separator

    # Validate max_length_module
    try:
        max_length_module = int(os.getenv("MEDIAPLAYER_MAX_LENGTH", "70"))
        max_length_module = max(10, min(200, max_length_module))  # Clamp between 10-200
    except (ValueError, TypeError):
        print(
            "WARNING: Invalid MEDIAPLAYER_MAX_LENGTH, using default 70", file=sys.stderr
        )
        max_length_module = 70

    # Validate text configurations
    prefix_playing = str(os.getenv("MEDIAPLAYER_PREFIX_PLAYING", ""))[
        :20
    ]  # Limit length
    prefix_paused = str(os.getenv("MEDIAPLAYER_PREFIX_PAUSED", ""))[:20]
    standby_text = str(os.getenv("MEDIAPLAYER_STANDBY_TEXT", " MPlayer"))[:50]
    artist_track_separator = str(os.getenv("MEDIAPLAYER_ARTIST_TRACK_SEPARATOR", "  "))[
        :10
    ]

    # Validate color formats
    xdg_cache = os.path.expanduser(os.getenv("XDG_CACHE_HOME", "~/.cache"))
    wal_colors = load_pywal_colors(xdg_cache)
    default_artist = wal_colors.get("color4", "#FFFFFF")
    default_track = wal_colors.get("foreground", "#FFFFFF")
    default_progress = wal_colors.get("color2", default_artist)
    default_empty = wal_colors.get("color8", wal_colors.get("color0", "#666666"))
    default_time = wal_colors.get("foreground", "#FFFFFF")

    color_vars = {
        "artist_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_ARTIST_COLOR", ""),
            wal_colors,
            default_artist,
        ),
        "track_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_TRACK_COLOR", ""), wal_colors, default_track
        ),
        "progress_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_PROGRESS_COLOR", ""),
            wal_colors,
            default_progress,
        ),
        "empty_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_EMPTY_COLOR", ""), wal_colors, default_empty
        ),
        "time_color": normalize_color(
            os.getenv("MEDIAPLAYER_TOOLTIP_TIME_COLOR", ""), wal_colors, default_time
        ),
    }

    for var_name, color_value in color_vars.items():
        if not color_value.startswith("#") or len(color_value) not in [4, 7, 9]:
            print(
                f"WARNING: Invalid color format for {var_name}: {color_value}",
                file=sys.stderr,
            )
            # Set safe fallback
            globals()[var_name] = "#FFFFFF"
        else:
            globals()[var_name] = color_value


def quantize_display_seconds(seconds: float, *, countdown: bool = False) -> int:
    seconds = max(0.0, float(seconds))
    if countdown:
        return max(0, int(math.ceil(seconds - 1e-9)))
    return max(0, int(math.floor(seconds + 1e-9)))


def format_time(seconds: float, *, countdown: bool = False) -> str:
    """Stable and consistent time formatter (HH:MM:SS or MM:SS)."""
    try:
        total = quantize_display_seconds(seconds, countdown=countdown)
        h, m = divmod(total, 3600)
        m, s = divmod(m, 60)
        return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"
    except Exception:
        return "00:00"


def format_time_multiple_lines(
    seconds: float, playing: bool, *, countdown: bool = False
) -> str:
    """Multi-line timer with consistent alignment and no float artifacts."""
    try:
        total = quantize_display_seconds(seconds, countdown=countdown)
        h, m = divmod(total, 3600)
        m, s = divmod(m, 60)
        icon = "󰼛" if playing else " "
        if h:
            return f"{icon}{h:02d}\n:{m:02d}\n:{s:02d}"
        else:
            return f"{icon}{m:02d}\n:{s:02d}"
    except Exception:
        return " \n:00"


def format_live_multiple_lines(playing: bool) -> str:
    icon = "󰼛" if playing else " "
    return f"{icon}LI\n:VE"


def create_tooltip_text(
    artist,
    track,
    current_position_seconds,
    duration_seconds,
    p_name,
    is_live_stream=False,
    loop_status=None,
    shuffle_status=None,
) -> str:
    tooltip = ""
    if artist or track:
        tooltip += f'<span foreground="{track_color}"><b>{track}</b></span>'
        tooltip += f'\n<span foreground="{artist_color}"><i>{artist}</i></span>\n'
        if is_live_stream:
            tooltip += (
                f'<span foreground="{progress_color}"><b>LIVE</b></span>'
                f' <span foreground="{time_color}">{format_time(current_position_seconds)}</span>'
            )
        elif duration_seconds > 0:
            progress = int((current_position_seconds / duration_seconds) * 20)
            bar = f'<span foreground="{progress_color}">{"█" * progress}</span><span foreground="{empty_color}">{"─" * (20 - progress)}</span>'
            tooltip += (
                f'<span foreground="{time_color}">{format_time(current_position_seconds)}</span> '
                f"{bar} "
                f'<span foreground="{time_color}">{format_time(duration_seconds)}</span>'
            )
            if loop_status is not None:
                loop_glyphs = {
                    "None": "󰑗 No Loop",
                    "Track": "󰑖 Loop Once",
                    "Playlist": "󰑘 Loop Playlist",
                }
                tooltip += f"\n<span foreground='{track_color}'>{loop_glyphs.get(loop_status, str(loop_status))}</span>"
            if shuffle_status is not None:
                shuffle_glyph = "󰒟 Shuffle On" if shuffle_status else "󰒞 Shuffle Off"
                tooltip += f"\n<span foreground='{track_color}'>{shuffle_glyph}</span>"
        tooltip += f"\n<span>{p_name}</span>"
    tooltip += (
        f"\n<span size='x-small' foreground='{track_color}'>"
        f"\n󰐎 click to play/pause\n scroll to seek\n󱥣 rightclick for options</span>"
    )
    return tooltip


def format_artist_track(artist, track, playing, max_length):
    prefix = prefix_playing if playing else prefix_paused
    prefix_separator = "  "
    full_length = len(artist + track)

    if track and not artist:
        if len(track) > max_length:
            track = track[:max_length].rstrip() + "…"
        output_text = f"{prefix}{prefix_separator}<b>{track}</b>"
    elif track and artist:
        artist = artist.split(",")[0].split("&")[0].strip()
        if full_length > max_length:
            artist_weight = 0.65
            artist_limit = min(int(max_length * artist_weight), len(artist))
            a_gain = max(0, artist_weight - (artist_limit / max_length))
            track_weight = 1 - artist_weight + a_gain
            track_limit = min(int(max_length * track_weight), len(track))
            t_gain = max(0, track_weight - (track_limit / max_length))

            if a_gain == 0 and t_gain > 0:
                gain = int(max_length * t_gain)
                artist_limit = artist_limit + gain
            elif a_gain > 0 and t_gain == 0:
                gain = int(max_length * a_gain)
                track_limit = track_limit + gain

            if len(artist) > artist_limit:
                artist = artist[:artist_limit].rstrip() + "…"
            if len(track) > track_limit:
                track = track[:track_limit].rstrip() + "…"

        output_text = f"{prefix}{prefix_separator}<i>{artist}</i>{artist_track_separator}<b>{track}</b>"
    else:
        if (
            current_player
            and hasattr(current_player, "props")
            and hasattr(current_player.props, "player_name")
        ):
            output_text = f"<b>{standby_text} {current_player.props.player_name}</b>"
        else:
            output_text = f"<b>{standby_text}</b>"
    return output_text


_last_metadata = {
    "track": "",
    "artist": "",
    "track_id": "",
    "media_url": "",
    "duration": 0.0,
    "live_status": "",
}
_last_valid_player = None
_last_seek_event = {"at": 0.0, "position": None}
_position_state = {
    "track_key": "",
    "anchor_position": 0.0,
    "anchor_monotonic": 0.0,
    "raw_position": 0.0,
    "timestamp": 0.0,
    "status": "Stopped",
    "rate": 1.0,
    "ignore_terminal_raw": False,
}
_persisted_position_state = {
    "track_key": "",
    "position": 0.0,
    "duration": 0.0,
    "wall_time": 0.0,
    "trusted": False,
}


def write_output(current_player):
    """Get current state and write JSON output safely, even if Firefox changes song naturally."""
    global \
        _last_metadata, \
        _last_valid_player, \
        _last_seek_event, \
        _position_state, \
        _persisted_position_state

    # --- Detect missing or invalid player ---
    if not current_player:
        output = {
            "text": standby_text,
            "class": "custom-nothing-playing",
            "alt": "",
            "tooltip": "",
        }
        emit_json_output(output)
        return

    # Firefox sometimes respawns MPRIS under a new instance name.
    try:
        _ = current_player.props.player_name
        _last_valid_player = current_player
    except Exception:
        if _last_valid_player:
            current_player = _last_valid_player
        else:
            return

    p_name = current_player.props.player_name

    # --- Position ---
    try:
        position_seconds = current_player.get_position() / 1e6
    except Exception:
        position_seconds = 0.0
    now_mono = time.monotonic()
    seek_position = _last_seek_event.get("position")
    seek_age = now_mono - float(_last_seek_event.get("at", 0.0))
    if (
        seek_position is not None
        and 0.0 <= seek_age <= 2.0
        and abs(float(seek_position) - position_seconds) > 1.0
    ):
        # Some MPRIS providers lag after jumps; trust the fresh seek event.
        position_seconds = max(0.0, float(seek_position))

    player_status = current_player.props.status
    is_playing = player_status == "Playing"
    is_stopped = player_status == "Stopped"
    raw_metadata = resolve_metadata_duration(
        read_player_metadata(current_player),
        _last_metadata,
    )
    resolved_metadata, _last_metadata = resolve_browser_metadata_fallbacks(
        raw_metadata,
        player_status=player_status,
        position_seconds=position_seconds,
        seek_position=seek_position,
        seek_age=seek_age,
        last_metadata=_last_metadata,
        position_state=_position_state,
    )
    track = resolved_metadata.track
    artist = resolved_metadata.artist
    track_id = resolved_metadata.track_id
    media_url = resolved_metadata.media_url
    duration_seconds = resolved_metadata.duration_seconds
    is_live_stream = resolved_metadata.is_live_stream

    try:
        playback_rate = float(current_player.get_rate())
    except Exception:
        try:
            playback_rate = float(current_player.props.rate)
        except Exception:
            playback_rate = 1.0
    if playback_rate <= 0:
        playback_rate = 1.0

    # --- If stopped, clear cache and output nothing (hide module) ---
    if is_stopped:
        _last_metadata = {
            "track": "",
            "artist": "",
            "track_id": "",
            "media_url": "",
            "duration": 0.0,
            "live_status": "",
        }
        output = {
            "text": "",
            "class": "custom-stopped",
            "alt": "",
            "tooltip": "",
        }
        emit_json_output(output)
        save_runtime_position_state("", 0.0, 0.0)
        _position_state = {
            "track_key": "",
            "anchor_position": 0.0,
            "anchor_monotonic": 0.0,
            "raw_position": 0.0,
            "timestamp": 0.0,
            "status": "Stopped",
            "rate": 1.0,
            "ignore_terminal_raw": False,
        }
        return

    # --- Normalize raw values ---
    reported_position_seconds = max(0.0, position_seconds)
    position_seconds = reported_position_seconds
    duration_seconds = max(0.0, round(duration_seconds, 2))
    if duration_seconds and position_seconds > duration_seconds:
        position_seconds = duration_seconds

    if (
        not is_live_stream
        and resolved_metadata.is_youtube
        and not resolved_metadata.ytdlp_live_status
        and title_looks_live(track)
        and duration_seconds > 0
        and abs(position_seconds - duration_seconds) <= 1.0
    ):
        is_live_stream = True
        duration_seconds = 0.0

    # --- Anchored playback clock ---
    now = now_mono
    now_wall = time.time()
    track_key = build_track_identity_key(p_name, track_id, media_url, track, artist)
    raw_position = max(0.0, position_seconds)

    previous_track_key = str(_position_state.get("track_key", ""))
    previous_anchor_position = float(_position_state.get("anchor_position", 0.0))
    previous_anchor_monotonic = float(_position_state.get("anchor_monotonic", 0.0))
    previous_raw = float(_position_state.get("raw_position", 0.0))
    previous_status = str(_position_state.get("status", "Stopped"))
    previous_rate = float(_position_state.get("rate", 1.0) or 1.0)
    previous_ignore_terminal_raw = bool(_position_state.get("ignore_terminal_raw", False))
    if previous_rate <= 0:
        previous_rate = 1.0

    predicted_from_previous = previous_anchor_position
    if previous_track_key == track_key and previous_status == "Playing":
        predicted_from_previous += (
            max(0.0, now - previous_anchor_monotonic) * previous_rate
        )
    if duration_seconds > 0:
        predicted_from_previous = min(duration_seconds, predicted_from_previous)

    persisted_recent = (
        float(_persisted_position_state.get("wall_time", 0.0)) > 0
        and max(0.0, now_wall - float(_persisted_position_state.get("wall_time", 0.0)))
        <= _recover_max_age_seconds
    )
    persisted_same_track = saved_state_matches_track(
        str(_persisted_position_state.get("track_key", "")),
        track_key,
    )
    persisted_duration_seconds = max(
        0.0, float(_persisted_position_state.get("duration", 0.0))
    )
    persisted_position_seconds = max(
        0.0, float(_persisted_position_state.get("position", 0.0))
    )
    persisted_reports_terminal_snapshot = (
        persisted_duration_seconds > 0
        and persisted_position_seconds >= max(0.0, persisted_duration_seconds - 1.0)
    )
    persisted_trusted = bool(_persisted_position_state.get("trusted", False)) and not (
        resolved_metadata.is_youtube and persisted_reports_terminal_snapshot
    )
    predicted_from_persisted = None
    if persisted_recent and persisted_same_track and persisted_trusted:
        predicted_from_persisted = predict_saved_position(
            _persisted_position_state,
            now_wall=now_wall,
            duration_seconds=duration_seconds,
            playback_rate=playback_rate,
            playing=is_playing,
        )

    recent_seek = seek_position is not None and 0.0 <= seek_age <= 2.5
    recent_seek_to_end = (
        recent_seek
        and duration_seconds > 0
        and float(seek_position) >= max(0.0, duration_seconds - 5.0)
    )
    browser_duration_seconds = max(0.0, round(raw_metadata.duration_seconds, 2))
    browser_reports_terminal_snapshot = (
        (
            browser_duration_seconds > 0
            and reported_position_seconds
            >= max(0.0, browser_duration_seconds - 1.0)
        )
        or (
            duration_seconds > 0
            and reported_position_seconds >= max(0.0, duration_seconds - 1.0)
        )
    )
    browser_duration_mismatch_terminal_snapshot = (
        is_playing
        and resolved_metadata.is_youtube
        and browser_duration_seconds > 0
        and duration_seconds > (browser_duration_seconds + 15.0)
        and reported_position_seconds >= max(0.0, browser_duration_seconds - 1.0)
        and not recent_seek_to_end
    )
    ignore_terminal_raw = previous_ignore_terminal_raw
    if previous_track_key != track_key:
        ignore_terminal_raw = False

    persisted_duration_override = (
        resolved_metadata.is_youtube
        and persisted_recent
        and persisted_same_track
        and persisted_trusted
        and persisted_duration_seconds > max(duration_seconds + 15.0, 0.0)
        and browser_reports_terminal_snapshot
        and not recent_seek_to_end
    )
    if persisted_duration_override:
        duration_seconds = persisted_duration_seconds

    # Firefox/YouTube can transiently report "position == duration" mid-track.
    # Prefer a recent same-track anchor instead of snapping the timer to 00:00.
    browser_end_glitch = (
        is_playing
        and resolved_metadata.is_youtube
        and duration_seconds > 0
        and reported_position_seconds >= max(0.0, duration_seconds - 1.0)
        and not recent_seek_to_end
        and (
            (
                previous_track_key == track_key
                and predicted_from_previous < max(0.0, duration_seconds - 15.0)
                and reported_position_seconds > (predicted_from_previous + 15.0)
            )
            or (
                predicted_from_persisted is not None
                and predicted_from_persisted < max(0.0, duration_seconds - 15.0)
                and reported_position_seconds > (predicted_from_persisted + 15.0)
            )
        )
    )
    if browser_end_glitch:
        if not (resolved_metadata.ytdlp_duration_seconds or persisted_duration_override):
            duration_seconds = 0.0
        ignore_terminal_raw = True

    fresh_track_end_glitch = (
        is_playing
        and resolved_metadata.is_youtube
        and duration_seconds > 0
        and previous_track_key != track_key
        and reported_position_seconds >= max(0.0, duration_seconds - 1.0)
        and not recent_seek_to_end
    )
    if fresh_track_end_glitch:
        if not (resolved_metadata.ytdlp_duration_seconds or persisted_duration_override):
            duration_seconds = 0.0
        ignore_terminal_raw = True

    if browser_duration_mismatch_terminal_snapshot:
        ignore_terminal_raw = True

    use_synthetic_browser_position = False
    if ignore_terminal_raw and resolved_metadata.is_youtube:
        if recent_seek and not recent_seek_to_end:
            ignore_terminal_raw = False
        elif not recent_seek_to_end and browser_reports_terminal_snapshot:
            use_synthetic_browser_position = True
            if previous_track_key == track_key:
                anchor_position = previous_anchor_position
                anchor_monotonic = previous_anchor_monotonic
            elif predicted_from_persisted is not None:
                anchor_position = max(0.0, predicted_from_persisted)
                anchor_monotonic = now
            else:
                anchor_position = 0.0
                anchor_monotonic = now
            raw_position = anchor_position
        else:
            ignore_terminal_raw = False

    if use_synthetic_browser_position:
        pass
    elif previous_track_key != track_key:
        anchor_position = raw_position
        anchor_monotonic = now
    else:
        predicted_from_anchor = predicted_from_previous

        status_changed = player_status != previous_status
        raw_advanced = raw_position > (previous_raw + 0.2)
        raw_rewound = raw_position < (previous_raw - 0.5)
        raw_stalled = abs(raw_position - previous_raw) <= 0.5
        jump_detected = abs(raw_position - predicted_from_anchor) > 2.0

        if status_changed:
            # On pause/resume transitions, never snap backward if MPRIS reports
            # a stale position (common with browser MPRIS providers).
            anchor_position = max(raw_position, predicted_from_anchor)
            anchor_monotonic = now
        elif raw_rewound:
            anchor_position = raw_position
            anchor_monotonic = now
        elif jump_detected and not raw_stalled:
            anchor_position = raw_position
            anchor_monotonic = now
        elif raw_advanced and is_playing:
            # Keep anchor aligned when source position progresses normally.
            anchor_position = raw_position
            anchor_monotonic = now
        elif not is_playing:
            # While paused, ignore minor raw jitter to prevent drift accumulation.
            anchor_position = previous_anchor_position
            anchor_monotonic = previous_anchor_monotonic
        else:
            # Preserve anchor while raw position stalls.
            anchor_position = previous_anchor_position
            anchor_monotonic = previous_anchor_monotonic

    if is_playing:
        position_seconds = anchor_position + (
            max(0.0, now - anchor_monotonic) * playback_rate
        )
    else:
        position_seconds = anchor_position

    position_seconds = max(0.0, round(position_seconds, 2))
    if duration_seconds and position_seconds > duration_seconds:
        position_seconds = duration_seconds

    _position_state = {
        "track_key": track_key,
        "anchor_position": anchor_position,
        "anchor_monotonic": anchor_monotonic,
        "raw_position": raw_position,
        "timestamp": now,
        "status": player_status,
        "rate": playback_rate,
        "ignore_terminal_raw": ignore_terminal_raw,
    }
    persisted_state_trusted = not (
        use_synthetic_browser_position
        or (
            resolved_metadata.is_youtube
            and browser_reports_terminal_snapshot
            and not recent_seek_to_end
        )
    )

    _persisted_position_state = {
        "track_key": track_key,
        "position": position_seconds,
        "duration": duration_seconds,
        "wall_time": now_wall,
        "trusted": persisted_state_trusted,
    }
    save_runtime_position_state(
        track_key,
        position_seconds,
        duration_seconds,
        trusted=persisted_state_trusted,
    )

    # --- Compute displayed time ---
    countdown_display = bool(duration_seconds and not is_live_stream)
    time_display_seconds = (
        max(0.0, round(duration_seconds - position_seconds, 2))
        if countdown_display
        else max(0.0, round(position_seconds, 2))
    )

    # --- Loop & shuffle status (safe queries) ---
    try:
        loop_status = current_player.get_loop_status()
    except Exception:
        loop_status = None
    try:
        shuffle_status = current_player.get_shuffle()
    except Exception:
        shuffle_status = None

    # --- Tooltip ---
    tooltip_text = create_tooltip_text(
        artist,
        track,
        position_seconds,
        duration_seconds,
        p_name,
        is_live_stream=is_live_stream,
        loop_status=loop_status,
        shuffle_status=shuffle_status,
    )

    # --- Output ---
    output_data = {
        "text": escape(
            format_artist_track(artist, track, is_playing, max_length_module)
        ),
        "class": f"custom-{p_name}",
        "alt": (
            format_live_multiple_lines(is_playing)
            if is_live_stream
            else format_time_multiple_lines(
                time_display_seconds,
                is_playing,
                countdown=countdown_display,
            )
        ),
        "tooltip": escape(tooltip_text),
    }
    emit_json_output(output_data)


def on_play(player, status, manager):
    set_player(manager, player)


def on_playback_changed(player, status, manager):
    if status == "Playing":
        set_player(manager, player)
    write_output(player)


def on_metadata(player, metadata, manager):
    write_output(player)


def on_seeked(player, position, manager):
    global _last_seek_event
    try:
        seek_seconds = max(0.0, float(position) / 1e6)
    except Exception:
        seek_seconds = None
    _last_seek_event = {"at": time.monotonic(), "position": seek_seconds}
    write_output(player)


def on_player_appeared(manager, player, selected_players=None):
    if player is not None and (
        selected_players is None or player.name in selected_players
    ):
        p = init_player(manager, player)
        set_player(manager, p)
        if not hasattr(manager, "_polling") or not manager._polling:
            manager._polling = True
            # Store timer ID for potential cleanup
            global _timer_id
            if _timer_id:
                GLib.source_remove(_timer_id)
            _timer_id = GLib.timeout_add(950, timer_tick, manager)


def on_player_vanished(manager, player, loop):
    global current_player, _timer_id
    p_name = player.props.player_name

    if current_player and current_player.props.player_name == p_name:
        if manager.props.players:
            set_player(manager, manager.props.players[0])
        else:
            current_player = None
            # Stop timer when no players left to prevent memory leaks
            if _timer_id:
                GLib.source_remove(_timer_id)
                _timer_id = None
                manager._polling = False
            output = {
                "text": standby_text,
                "class": "custom-nothing-playing",
                "alt": "",
                "tooltip": "",
            }
            emit_json_output(output)


def init_player(manager, name):
    player = Playerctl.Player.new_from_name(name)
    player.connect("playback-status", on_playback_changed, manager)
    player.connect("playback-status::playing", on_play, manager)
    player.connect("metadata", on_metadata, manager)
    player.connect("seeked", on_seeked, manager)
    manager.manage_player(player)
    return player


def timer_tick(manager):
    """Called every second to update display - with memory leak prevention"""
    # Stop timer if no players are available
    if not manager.props.players or not current_player:
        global _timer_id
        _timer_id = None
        manager._polling = False
        return False  # This stops the timer

    if current_player and current_player.props.status == "Playing":
        write_output(current_player)
    return True  # Continue the timer


def set_player(manager, player):
    global current_player
    if current_player and current_player.props.player_name != player.props.player_name:
        try:
            current_player.pause()
        except Exception:
            pass
    current_player = player
    manager.move_player_to_top(player)
    write_output(player)


def signal_handler(sig, frame):
    global _timer_id
    if sig == signal.SIGPIPE:
        os._exit(0)
    # Clean up timer on exit
    if _timer_id:
        GLib.source_remove(_timer_id)
    sys.exit(0)


def parse_arguments():
    parser = argparse.ArgumentParser(description="A media player status tool")
    parser.add_argument("--players", nargs="*", type=str)
    parser.add_argument("--player", type=str)
    return parser.parse_args()


def escape(string):
    return string.replace("&", "&amp;")


def main():
    global \
        prefix_playing, \
        prefix_paused, \
        max_length_module, \
        standby_text, \
        artist_track_separator
    global artist_color, track_color, progress_color, empty_color, time_color, _timer_id
    global _runtime_state_file, _persisted_position_state, _recover_max_age_seconds
    global _ytdlp_timeout_seconds

    xdg_state = os.path.expanduser(os.getenv("XDG_STATE_HOME", "~/.local/state"))
    xdg_cache = os.path.expanduser(os.getenv("XDG_CACHE_HOME", "~/.cache"))
    xdg_runtime = os.path.expanduser(
        os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    )
    _runtime_state_file = os.path.join(xdg_runtime, "hypr", "mediaplayer-position.json")
    _persisted_position_state = load_runtime_position_state()
    _recover_max_age_seconds = get_recover_max_age_seconds()
    _ytdlp_timeout_seconds = get_ytdlp_timeout_seconds()
    config_file = os.path.join(xdg_state, "hypr", "config")
    if os.path.exists(config_file):
        load_env_file(config_file)

    # Validate all configuration values
    validate_config()

    players = os.getenv("MEDIAPLAYER_PLAYERS", None)
    if players:
        players = players.split(",")

    arguments = parse_arguments()

    logging.basicConfig(stream=sys.stderr, level=logging.WARNING, format="%(message)s")

    manager = Playerctl.PlayerManager()
    choose = False
    if not (arguments.players or arguments.player) and not players:
        players = [name.name for name in manager.props.player_names]
    else:
        choose = True
        if arguments.players:
            players = arguments.players
        elif arguments.player:
            players = [arguments.player]

    loop = GLib.MainLoop()

    manager.connect(
        "name-appeared",
        lambda *args: on_player_appeared(*args, players if choose else None),
    )
    manager.connect("player-vanished", lambda *args: on_player_vanished(*args, loop))

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGPIPE, signal_handler)

    found = [None] * len(players)
    for player in manager.props.player_names:
        if (
            players is not None and player.name not in players
        ) or player.name == "plasma-browser-integration":
            continue
        p = init_player(manager, player)
        found[players.index(player.name)] = p

    if found:
        found = list(filter(lambda x: x is not None, found))
        if found:
            try:
                p = next(player for player in found if player.props.status == "Playing")
            except StopIteration:
                p = found[0]
            set_player(manager, p)
        else:
            write_output(current_player)
    else:
        write_output(current_player)

    if manager.props.players:
        manager._polling = True
        _timer_id = GLib.timeout_add_seconds(1, timer_tick, manager)

    try:
        loop.run()
    except KeyboardInterrupt:
        print("INFO: Received interrupt, shutting down...", file=sys.stderr)
    finally:
        # Final cleanup
        if _timer_id:
            GLib.source_remove(_timer_id)


if __name__ == "__main__":
    main()

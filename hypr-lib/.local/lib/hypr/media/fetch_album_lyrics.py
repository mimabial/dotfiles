#!/usr/bin/env python3
"""
Enhanced lyrics fetcher for rmpc using multiple sources.
Based on Lyrica's methodology: https://github.com/Wilooper/Lyrica
"""

import sys
import os
import re
import json
import argparse
from pathlib import Path
from typing import Optional, Dict, Any
import requests

# Try importing ytmusicapi for YouTube Music fallback
try:
    from ytmusicapi import YTMusic
    HAS_YTMUSIC = True
except ImportError:
    HAS_YTMUSIC = False

LRCLIB_API_SEARCH = "https://lrclib.net/api/search"
LRCLIB_API_GET = "https://lrclib.net/api/get"
LYRICSOVH_API = "https://api.lyrics.ovh/v1"


def get_audio_metadata(file_path: str) -> Dict[str, str]:
    """Extract metadata from audio file using ffprobe."""
    import subprocess

    try:
        result = subprocess.run(
            [
                "ffprobe", "-v", "quiet",
                "-show_entries", "format_tags=title,artist,album",
                "-of", "json",
                file_path
            ],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)
        tags = data.get("format", {}).get("tags", {})

        return {
            "title": tags.get("TITLE") or tags.get("title") or "",
            "artist": tags.get("ARTIST") or tags.get("artist") or "",
            "album": tags.get("ALBUM") or tags.get("album") or ""
        }
    except Exception as e:
        print(f"Warning: Could not extract metadata: {e}", file=sys.stderr)
        return {"title": "", "artist": "", "album": ""}


def fetch_lyrics_lrclib(artist: str, title: str, album: str = "", use_local_album: bool = True) -> Optional[str]:
    """
    Fetch synced lyrics from lrclib.net using two-step process.
    This mirrors Lyrica's implementation (lines 242-334).
    Returns lyrics with proper LRC metadata headers.
    """
    try:
        print(f"  [lrclib] Searching for: {artist} - {title}", file=sys.stderr)

        # Step 1: Search for the track
        search_params = {
            "track_name": title,
            "artist_name": artist
        }
        search_resp = requests.get(LRCLIB_API_SEARCH, params=search_params, timeout=10)

        if search_resp.status_code != 200:
            print(f"  [lrclib] Search failed with status {search_resp.status_code}", file=sys.stderr)
            return None

        results = search_resp.json()
        if not results:
            print(f"  [lrclib] No search results", file=sys.stderr)
            return None

        # Find best match (prefer exact album match if available)
        best_match = None
        for track in results:
            if album and track.get("albumName", "").lower() == album.lower():
                best_match = track
                break
        if not best_match:
            best_match = results[0]

        # Step 2: Get detailed lyrics with exact metadata
        get_params = {
            "track_name": best_match["trackName"],
            "artist_name": best_match["artistName"],
            "album_name": best_match["albumName"],
            "duration": best_match["duration"]
        }
        get_resp = requests.get(LRCLIB_API_GET, params=get_params, timeout=10)

        if get_resp.status_code != 200:
            print(f"  [lrclib] Get lyrics failed with status {get_resp.status_code}", file=sys.stderr)
            return None

        data = get_resp.json()
        synced_lyrics = data.get("syncedLyrics")

        if not synced_lyrics:
            print(f"  [lrclib] No synced lyrics available", file=sys.stderr)
            return None

        # Build LRC file with metadata headers
        lrc_lines = []
        lrc_lines.append(f"[ar:{data.get('artistName', artist)}]")
        lrc_lines.append(f"[ti:{data.get('trackName', title)}]")
        # Use local album name if provided, since lrclib often has bad album metadata
        if use_local_album and album:
            lrc_lines.append(f"[al:{album}]")
        elif data.get('albumName'):
            lrc_lines.append(f"[al:{data.get('albumName')}]")
        if data.get('duration'):
            duration_sec = data['duration']
            minutes = int(duration_sec // 60)
            seconds = duration_sec % 60
            lrc_lines.append(f"[length:{minutes:02d}:{seconds:05.2f}]")
        lrc_lines.append("")  # Empty line after metadata
        lrc_lines.append(synced_lyrics)

        print(f"  [lrclib] ✓ Found synced lyrics", file=sys.stderr)
        return "\n".join(lrc_lines)

    except Exception as e:
        print(f"  [lrclib] Error: {e}", file=sys.stderr)
        return None


def fetch_lyrics_youtube(artist: str, title: str) -> Optional[str]:
    """Fetch lyrics from YouTube Music using ytmusicapi."""
    if not HAS_YTMUSIC:
        print(f"  [ytmusic] Skipped (ytmusicapi not installed)", file=sys.stderr)
        return None

    try:
        print(f"  [ytmusic] Searching for: {artist} - {title}", file=sys.stderr)
        ytmusic = YTMusic()
        search_query = f"{title} {artist}"
        search_results = ytmusic.search(query=search_query, filter="songs", limit=1)

        if not search_results:
            print(f"  [ytmusic] No search results", file=sys.stderr)
            return None

        song_info = search_results[0]
        video_id = song_info.get('videoId')
        if not video_id:
            print(f"  [ytmusic] No videoId found", file=sys.stderr)
            return None

        watch_playlist = ytmusic.get_watch_playlist(videoId=video_id)
        lyrics_browse_id = watch_playlist.get('lyrics')

        if not lyrics_browse_id:
            print(f"  [ytmusic] No lyrics browseId", file=sys.stderr)
            return None

        lyrics_data = ytmusic.get_lyrics(browseId=lyrics_browse_id)
        if not lyrics_data or not lyrics_data.get('lyrics'):
            print(f"  [ytmusic] No lyrics data", file=sys.stderr)
            return None

        # Build LRC with metadata headers
        lrc_lines = []
        lrc_lines.append(f"[ar:{artist}]")
        lrc_lines.append(f"[ti:{title}]")
        if song_info.get('album', {}).get('name'):
            lrc_lines.append(f"[al:{song_info['album']['name']}]")
        if song_info.get('duration_seconds'):
            duration_sec = song_info['duration_seconds']
            minutes = int(duration_sec // 60)
            seconds = duration_sec % 60
            lrc_lines.append(f"[length:{minutes:02d}:{seconds:05.2f}]")
        lrc_lines.append("")

        # Convert to LRC format if timestamps available
        if lyrics_data.get('hasTimestamps'):
            for line in lyrics_data['lyrics']:
                start_ms = line.start_time
                minutes = start_ms // 60000
                seconds = (start_ms % 60000) / 1000
                lrc_lines.append(f"[{minutes:02d}:{seconds:05.2f}]{line.text}")
            print(f"  [ytmusic] ✓ Found synced lyrics", file=sys.stderr)
        else:
            # Plain lyrics without timestamps
            for line in lyrics_data['lyrics'].split('\n'):
                lrc_lines.append(f"[00:00.00]{line}")
            print(f"  [ytmusic] ✓ Found plain lyrics (no timestamps)", file=sys.stderr)

        return "\n".join(lrc_lines)

    except Exception as e:
        print(f"  [ytmusic] Error: {e}", file=sys.stderr)
        return None


def fetch_lyrics_lyricsovh(artist: str, title: str) -> Optional[str]:
    """Fetch plain lyrics from lyrics.ovh (no sync timestamps)."""
    try:
        print(f"  [lyrics.ovh] Searching for: {artist} - {title}", file=sys.stderr)
        url = f"{LYRICSOVH_API}/{artist}/{title}"
        response = requests.get(url, timeout=10)

        if response.status_code == 200:
            data = response.json()
            lyrics_text = data.get("lyrics", "").strip()
            if lyrics_text:
                print(f"  [lyrics.ovh] ✓ Found plain lyrics (converting to LRC)", file=sys.stderr)
                # Build LRC with metadata headers
                lrc_lines = []
                lrc_lines.append(f"[ar:{artist}]")
                lrc_lines.append(f"[ti:{title}]")
                lrc_lines.append("")
                # Convert plain text to basic LRC format (no timestamps)
                for line in lyrics_text.split("\n"):
                    lrc_lines.append(f"[00:00.00]{line}")
                return "\n".join(lrc_lines)

        print(f"  [lyrics.ovh] No lyrics found", file=sys.stderr)
        return None

    except Exception as e:
        print(f"  [lyrics.ovh] Error: {e}", file=sys.stderr)
        return None


def fetch_lyrics(artist: str, title: str, album: str = "") -> Optional[str]:
    """
    Fetch lyrics using multiple sources with fallback.
    Order matches Lyrica's default synced sequence: SimpMusic, LRCLIB, YouTube Music
    (We skip SimpMusic since it's not in standard repos)

    Note: Unlike our old bash script, we do NOT strip parentheses or "Deluxe Edition"
    from titles/albums. Lyrica relies on lrclib's fuzzy search to handle variations.
    """
    # Source priority: lrclib -> YouTube Music -> lyrics.ovh
    sources = [
        ("lrclib", lambda a, t, alb: fetch_lyrics_lrclib(a, t, alb)),
        ("ytmusic", lambda a, t, alb: fetch_lyrics_youtube(a, t)),
        ("lyrics.ovh", lambda a, t, alb: fetch_lyrics_lyricsovh(a, t)),
    ]

    for source_name, fetcher in sources:
        lyrics = fetcher(artist, title, album)
        if lyrics:
            return lyrics

    return None


def process_audio_file(file_path: Path, artist_dir: str, album_dir: str, force: bool = False) -> bool:
    """Process a single audio file and fetch lyrics."""
    lrc_file = file_path.with_suffix('.lrc')

    if lrc_file.exists() and not force:
        print(f"– Skipping {file_path.name} (already have .lrc)")
        return True

    # Extract metadata
    metadata = get_audio_metadata(str(file_path))

    # Use metadata if available, fall back to directory/filename parsing
    artist = metadata["artist"] or artist_dir
    album = metadata["album"] or album_dir
    title = metadata["title"]

    if not title:
        # Fall back to filename
        title = file_path.stem
        # Strip track numbers
        title = re.sub(r'^[0-9]{1,3}[. -]+', '', title)

    print(f"→ Processing: {file_path.name}")
    print(f"  Title: {title}")
    print(f"  Artist: {artist}")
    print(f"  Album: {album}")

    lyrics = fetch_lyrics(artist, title, album)

    if not lyrics:
        print(f"✗ No lyrics found for: \"{title}\"")
        return False

    # Write LRC file
    with open(lrc_file, 'w', encoding='utf-8') as f:
        f.write(lyrics)

    print(f"✔ Saved lyrics: {lrc_file.name}")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Fetch synced lyrics for audio files using multiple sources"
    )
    parser.add_argument("album_dir", help="Path to album directory")
    parser.add_argument("-f", "--force", action="store_true",
                       help="Overwrite existing .lrc files")

    args = parser.parse_args()

    album_path = Path(args.album_dir)
    if not album_path.is_dir():
        print(f"Error: '{args.album_dir}' is not a directory", file=sys.stderr)
        sys.exit(1)

    artist = album_path.parent.name
    album = album_path.name

    print(f"▶ Fetching lyrics for all audio files in: {album_path}")
    print(f"  Artist: {artist}")
    print(f"  Album:  {album}")
    print()

    # Process audio files
    audio_extensions = ['.mp3', '.flac', '.m4a', '.ogg', '.opus']
    audio_files = []
    for ext in audio_extensions:
        audio_files.extend(album_path.glob(f'*{ext}'))

    audio_files.sort()

    if not audio_files:
        print("No audio files found")
        sys.exit(1)

    success_count = 0
    for audio_file in audio_files:
        if process_audio_file(audio_file, artist, album, args.force):
            success_count += 1
        print()

    print(f"Done. Successfully fetched lyrics for {success_count}/{len(audio_files)} files.")


if __name__ == "__main__":
    main()

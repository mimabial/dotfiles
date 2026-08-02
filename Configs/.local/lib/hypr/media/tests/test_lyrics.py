import contextlib
import io
import json
import sqlite3
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

import fetch_album_lyrics
import fetch_track_lyrics
import lyrics_provider_fetchers
from lyrics_provider_fetchers import fetch_lyrics_simpmusic, get_genius_token
from fetch_album_lyrics import (
    LrcState,
    ProcessResult,
    build_artist_candidates,
    build_title_candidates,
    directory_hints,
    get_audio_metadata,
    lrc_state,
    parse_filename,
    process_audio_file,
    should_fetch_lrc,
    track_identity,
)
from lyrics_cache import LyricsMissCache
from lyrics_provider import fetch_lyrics


class LyricsMetadataTests(unittest.TestCase):
    @patch("fetch_album_lyrics.MutagenFile")
    def test_reads_opus_style_stream_comments_directly(self, mutagen_file):
        mutagen_file.return_value = SimpleNamespace(
            tags={
                "TITLE": ["FATÚMATA"],
                "ARTIST": ["Didi B & Naira Marley"],
                "album_artist": ["Didi B"],
                "ALBUM": ["DIYILEM & BAZARHOFF : GENIUS"],
            },
            info=SimpleNamespace(length=174.93),
        )

        metadata = get_audio_metadata("/music/song.opus")

        self.assertEqual(metadata["title"], "FATÚMATA")
        self.assertEqual(metadata["artist"], "Didi B & Naira Marley")
        self.assertEqual(metadata["album_artist"], "Didi B")
        self.assertEqual(metadata["album"], "DIYILEM & BAZARHOFF : GENIUS")
        self.assertAlmostEqual(metadata["duration"], 174.93)

    def test_track_artist_is_tried_before_broader_fallbacks(self):
        self.assertEqual(
            build_artist_candidates(
                "Didi B & Naira Marley",
                "Didi B",
                "Directory Artist",
            ),
            ["Didi B & Naira Marley", "Didi B", "Directory Artist"],
        )

    def test_filename_fallback_separates_artist_and_title(self):
        path = Path("/music/03 - Didi B, Naira Marley - FATÚMATA.opus")
        self.assertEqual(
            parse_filename(path),
            ("Didi B, Naira Marley", "FATÚMATA"),
        )
        artist, candidates, title, album, _ = track_identity(
            path,
            {
                "title": "",
                "artist": "",
                "album_artist": "",
                "album": "",
                "duration": 175,
            },
            Path("/music"),
            recursive=True,
        )
        self.assertEqual(artist, "Didi B, Naira Marley")
        self.assertEqual(candidates, ["Didi B, Naira Marley"])
        self.assertEqual(title, "FATÚMATA")
        self.assertEqual(album, "")

    def test_title_candidates_are_shared_cleaned_and_ordered(self):
        self.assertEqual(
            build_title_candidates(
                "Ayra Starr & Lojay - Running (Visualizer)",
                "Running (Visualizer)",
                ["Ayra Starr"],
            ),
            ["Running", "Running (Visualizer)"],
        )
        self.assertEqual(
            build_title_candidates("Song (feat. Guest)", "", ["Artist"]),
            ["Song", "Song (feat. Guest)"],
        )

    def test_recursive_directory_hints_handle_album_and_genre_bucket(self):
        self.assertEqual(
            directory_hints(
                Path("/music/Didi B/Genius/song.opus"),
                Path("/music"),
                recursive=True,
            ),
            ("Didi B", "Genius"),
        )
        self.assertEqual(
            directory_hints(
                Path("/music/Rumba [G]/Artist/song.opus"),
                Path("/music"),
                recursive=True,
            ),
            ("Artist", ""),
        )

    def test_upgrade_plain_selects_only_existing_untimed_lyrics(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            missing = root / "missing.lrc"
            untimed = root / "untimed.lrc"
            synced = root / "synced.lrc"
            untimed.write_text("[00:00.00]First line\n[00:00.00]Second line\n")
            synced.write_text("[00:01.25]First line\n[00:04.00]Second line\n")

            self.assertEqual(lrc_state(missing), LrcState.MISSING)
            self.assertEqual(lrc_state(untimed), LrcState.UNTIMED)
            self.assertEqual(lrc_state(synced), LrcState.SYNCED)
            self.assertFalse(
                should_fetch_lrc(LrcState.MISSING, force=False, upgrade_plain=True)
            )
            self.assertTrue(
                should_fetch_lrc(LrcState.UNTIMED, force=False, upgrade_plain=True)
            )
            self.assertFalse(
                should_fetch_lrc(LrcState.SYNCED, force=False, upgrade_plain=True)
            )

    def test_synced_only_fetches_missing_file_and_rejects_plain_fallback(self):
        metadata = {
            "title": "Song",
            "artist": "Artist",
            "album_artist": "",
            "album": "Album",
            "duration": 180,
        }

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio_file = root / "Song.opus"
            lrc_file = root / "Song.lrc"
            with (
                patch("fetch_album_lyrics.lrc_path_for", return_value=lrc_file),
                patch("fetch_album_lyrics.fetch_lyrics", return_value=None) as fetch,
                patch("fetch_album_lyrics.save_lrc") as save_lrc,
            ):
                result = process_audio_file(
                    audio_file,
                    root,
                    recursive=False,
                    synced_only=True,
                    metadata=metadata,
                )

        self.assertIs(result, ProcessResult.FAILED)
        self.assertGreaterEqual(fetch.call_count, 1)
        self.assertTrue(
            all(call.kwargs["synced_only"] for call in fetch.call_args_list)
        )
        save_lrc.assert_not_called()

    def test_synced_only_with_upgrade_plain_selects_missing_and_untimed(self):
        self.assertTrue(
            should_fetch_lrc(
                LrcState.MISSING,
                force=False,
                upgrade_plain=True,
                synced_only=True,
            )
        )
        self.assertTrue(
            should_fetch_lrc(
                LrcState.UNTIMED,
                force=False,
                upgrade_plain=True,
                synced_only=True,
            )
        )
        self.assertFalse(
            should_fetch_lrc(
                LrcState.SYNCED,
                force=False,
                upgrade_plain=True,
                synced_only=True,
            )
        )

    def test_upgrade_plain_reports_untimed_file_kept_when_no_match_exists(self):
        metadata = {
            "title": "Song",
            "artist": "Artist",
            "album_artist": "",
            "album": "Album",
            "duration": 180,
        }

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio_file = root / "Song.opus"
            lrc_file = root / "Song.lrc"
            lrc_file.write_text("[00:00.00]Untimed line\n", encoding="utf-8")
            with (
                patch("fetch_album_lyrics.lrc_path_for", return_value=lrc_file),
                patch("fetch_album_lyrics.fetch_lyrics", return_value=None),
                patch("fetch_album_lyrics.save_lrc") as save_lrc,
            ):
                result = process_audio_file(
                    audio_file,
                    root,
                    recursive=False,
                    upgrade_plain=True,
                    metadata=metadata,
                )

        self.assertIs(result, ProcessResult.KEPT)
        save_lrc.assert_not_called()

    def test_existing_lyrics_are_reported_as_skipped(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio_file = root / "Song.opus"
            lrc_file = root / "Song.lrc"
            lrc_file.write_text("[00:00.00]Existing line\n", encoding="utf-8")
            with (
                patch("fetch_album_lyrics.lrc_path_for", return_value=lrc_file),
                patch("fetch_album_lyrics.fetch_lyrics") as fetch,
            ):
                result = process_audio_file(
                    audio_file,
                    root,
                    recursive=False,
                )

        self.assertIs(result, ProcessResult.SKIPPED)
        fetch.assert_not_called()

    def test_new_lyrics_are_reported_as_saved(self):
        metadata = {
            "title": "Song",
            "artist": "Artist",
            "album_artist": "",
            "album": "Album",
            "duration": 180,
        }

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio_file = root / "Song.opus"
            lrc_file = root / "Song.lrc"
            output = io.StringIO()
            with (
                patch("fetch_album_lyrics.lrc_path_for", return_value=lrc_file),
                patch(
                    "fetch_album_lyrics.fetch_lyrics",
                    return_value="[00:01.00]Timed line",
                ),
                patch("fetch_album_lyrics.save_lrc") as save_lrc,
                contextlib.redirect_stdout(output),
            ):
                result = process_audio_file(
                    audio_file,
                    root,
                    recursive=False,
                    synced_only=True,
                    metadata=metadata,
                    report_kind=True,
                )

        self.assertIs(result, ProcessResult.SAVED)
        self.assertIn("LYRICS_RESULT=synchronized lyrics", output.getvalue())
        save_lrc.assert_called_once()

    def test_summary_reports_each_process_result_separately(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio_files = [root / f"Song {index}.opus" for index in range(4)]
            output = io.StringIO()
            with (
                patch.object(sys, "argv", ["fetch_album_lyrics.py", str(root)]),
                patch(
                    "fetch_album_lyrics.collect_audio_files",
                    return_value=audio_files,
                ),
                patch(
                    "fetch_album_lyrics.process_audio_file",
                    side_effect=[
                        ProcessResult.SAVED,
                        ProcessResult.KEPT,
                        ProcessResult.SKIPPED,
                        ProcessResult.FAILED,
                    ],
                ),
                contextlib.redirect_stdout(output),
            ):
                return_code = fetch_album_lyrics.main()

        summary = output.getvalue()
        self.assertEqual(return_code, 1)
        self.assertIn("Saved:         1", summary)
        self.assertIn("Kept existing: 1", summary)
        self.assertIn("Skipped:       1", summary)
        self.assertIn("Failed:        1", summary)


class LyricsMissCacheTests(unittest.TestCase):
    def test_batches_miss_writes_until_flush(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "lyrics.sqlite3"
            cache = LyricsMissCache(path)
            cache.put("missing")

            with contextlib.closing(sqlite3.connect(path)) as observer:
                count_before = observer.execute(
                    "SELECT count(*) FROM misses"
                ).fetchone()[0]
            cache.flush()
            with contextlib.closing(sqlite3.connect(path)) as observer:
                count_after = observer.execute(
                    "SELECT count(*) FROM misses"
                ).fetchone()[0]
            cache.close()

        self.assertEqual(count_before, 0)
        self.assertEqual(count_after, 1)

    def test_provider_cooldown_persists_for_requested_ttl(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "lyrics.sqlite3"
            first_cache = LyricsMissCache(path)
            before = time.time()
            expires_at = first_cache.put_cooldown("provider", 60 * 60)
            first_cache.close()

            second_cache = LyricsMissCache(path)
            self.addCleanup(second_cache.close)
            persisted_expiry = second_cache.cooldown_until("provider")

        self.assertIsNotNone(persisted_expiry)
        self.assertEqual(persisted_expiry, expires_at)
        self.assertGreaterEqual(expires_at, before + 60 * 60)

    def test_recent_complete_miss_skips_provider_rounds(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = LyricsMissCache(Path(temporary) / "lyrics.sqlite3")
            self.addCleanup(cache.close)

            with (
                patch("lyrics_provider.lyrics_miss_cache", return_value=cache),
                patch(
                    "lyrics_provider._fetch_sequential",
                    return_value=(None, []),
                ) as fetch_sequential,
            ):
                first = fetch_lyrics(
                    "Missing Artist",
                    "Missing Song",
                    fast_mode=False,
                )
                second = fetch_lyrics(
                    "Missing Artist",
                    "Missing Song",
                    fast_mode=False,
                )

        self.assertIsNone(first)
        self.assertIsNone(second)
        self.assertEqual(fetch_sequential.call_count, 2)

    def test_synced_only_ignores_plain_results_and_plain_providers(self):
        plain_result = {
            "lyrics": "[00:00.00]Plain line",
            "source": "lrclib",
            "synced": False,
        }
        with (
            patch("lyrics_provider.lyrics_miss_cache", return_value=None),
            patch(
                "lyrics_provider._fetch_sequential",
                return_value=(None, [plain_result]),
            ) as fetch_sequential,
        ):
            result = fetch_lyrics(
                "Artist",
                "Song",
                fast_mode=False,
                synced_only=True,
            )

        self.assertIsNone(result)
        self.assertEqual(fetch_sequential.call_count, 1)


class SimpMusicCooldownTests(unittest.TestCase):
    def setUp(self):
        lyrics_provider_fetchers._SIMPMUSIC_COOLDOWN_UNTIL = 0.0
        lyrics_provider_fetchers._SIMPMUSIC_NOTICE_UNTIL = 0.0

    def tearDown(self):
        lyrics_provider_fetchers._SIMPMUSIC_COOLDOWN_UNTIL = 0.0
        lyrics_provider_fetchers._SIMPMUSIC_NOTICE_UNTIL = 0.0

    def test_first_search_429_starts_one_hour_cooldown(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = LyricsMissCache(Path(temporary) / "lyrics.sqlite3")
            self.addCleanup(cache.close)
            response = SimpleNamespace(status_code=429)

            with (
                patch(
                    "lyrics_provider_fetchers.lyrics_miss_cache",
                    return_value=cache,
                ),
                patch(
                    "lyrics_provider_fetchers.http_get",
                    return_value=response,
                ) as http_get,
            ):
                before = time.time()
                first = fetch_lyrics_simpmusic("Artist", "Song")
                second = fetch_lyrics_simpmusic("Artist", "Another Song")

            expires_at = cache.cooldown_until("simpmusic")

        self.assertIsNone(first)
        self.assertIsNone(second)
        self.assertEqual(http_get.call_count, 1)
        self.assertIsNotNone(expires_at)
        self.assertGreaterEqual(expires_at, before + 60 * 60)

    def test_details_429_also_starts_cooldown(self):
        search_response = SimpleNamespace(
            status_code=200,
            json=lambda: {
                "data": [
                    {
                        "videoId": "video-id",
                        "songTitle": "Song",
                        "artistName": "Artist",
                    }
                ]
            },
        )
        details_response = SimpleNamespace(status_code=429)

        with tempfile.TemporaryDirectory() as temporary:
            cache = LyricsMissCache(Path(temporary) / "lyrics.sqlite3")
            self.addCleanup(cache.close)
            with (
                patch(
                    "lyrics_provider_fetchers.lyrics_miss_cache",
                    return_value=cache,
                ),
                patch(
                    "lyrics_provider_fetchers.http_get",
                    side_effect=[search_response, details_response],
                ) as http_get,
            ):
                result = fetch_lyrics_simpmusic("Artist", "Song")
                skipped = fetch_lyrics_simpmusic("Artist", "Another Song")

            expires_at = cache.cooldown_until("simpmusic")

        self.assertIsNone(result)
        self.assertIsNone(skipped)
        self.assertEqual(http_get.call_count, 2)
        self.assertIsNotNone(expires_at)


class YTMusicLyricsTests(unittest.TestCase):
    def test_requests_and_returns_timed_lyrics(self):
        client = Mock()
        client.search.return_value = [
            {
                "title": "Song",
                "artists": [{"name": "Artist"}],
                "album": {"name": "Album"},
                "videoId": "video-id",
                "duration_seconds": 180,
            }
        ]
        client.get_watch_playlist.return_value = {"lyrics": "lyrics-browse-id"}
        client.get_lyrics.return_value = {
            "lyrics": [
                {"text": "First line", "start_time": 1200},
                {"text": "Second line", "start_time": 4500},
            ],
            "hasTimestamps": True,
        }

        with (
            patch("lyrics_provider_fetchers.HAS_YTMUSIC", True),
            patch(
                "lyrics_provider_fetchers.get_ytmusic_client",
                return_value=client,
            ),
        ):
            result = lyrics_provider_fetchers.fetch_lyrics_youtube(
                "Artist",
                "Song",
            )

        client.get_lyrics.assert_called_once_with(
            browseId="lyrics-browse-id",
            timestamps=True,
        )
        self.assertIsNotNone(result)
        self.assertTrue(result["synced"])
        self.assertIn("[00:01.20]First line", result["lyrics"])
        self.assertIn("[00:04.50]Second line", result["lyrics"])


class GeniusTokenTests(unittest.TestCase):
    @unittest.skipUnless(
        lyrics_provider_fetchers.HAS_GENIUS,
        "lyricsgenius is not installed",
    )
    def test_installed_genius_client_initializes(self):
        lyrics_provider_fetchers._GENIUS_CLIENT = None
        self.addCleanup(
            setattr,
            lyrics_provider_fetchers,
            "_GENIUS_CLIENT",
            None,
        )

        with patch(
            "lyrics_provider_fetchers.get_genius_token",
            return_value="test-token",
        ):
            client = lyrics_provider_fetchers.get_genius_client()

        self.assertIsInstance(client, lyrics_provider_fetchers.Genius)

    def test_reads_private_env_file_without_executing_shell_code(self):
        with tempfile.TemporaryDirectory() as temporary:
            config_home = Path(temporary)
            env_file = config_home / "genius" / "env"
            env_file.parent.mkdir()
            env_file.write_text(
                "# Local secret\n"
                "IGNORED=$(false)\n"
                'export GENIUS_TOKEN="file-token" # comment\n',
                encoding="utf-8",
            )
            env_file.chmod(0o600)

            with patch.dict(
                "os.environ",
                {"XDG_CONFIG_HOME": str(config_home)},
                clear=True,
            ):
                self.assertEqual(get_genius_token(), "file-token")

    def test_explicit_environment_token_overrides_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            config_home = Path(temporary)
            env_file = config_home / "genius" / "env"
            env_file.parent.mkdir()
            env_file.write_text("GENIUS_TOKEN=file-token\n", encoding="utf-8")
            env_file.chmod(0o600)

            with patch.dict(
                "os.environ",
                {
                    "XDG_CONFIG_HOME": str(config_home),
                    "GENIUS_ACCESS_TOKEN": "environment-token",
                },
                clear=True,
            ):
                self.assertEqual(get_genius_token(), "environment-token")

    def test_rejects_group_readable_env_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            config_home = Path(temporary)
            env_file = config_home / "genius" / "env"
            env_file.parent.mkdir()
            env_file.write_text("GENIUS_TOKEN=file-token\n", encoding="utf-8")
            env_file.chmod(0o640)

            with patch.dict(
                "os.environ",
                {"XDG_CONFIG_HOME": str(config_home)},
                clear=True,
            ):
                self.assertEqual(get_genius_token(), "")


class GeniusSplitTunnelTests(unittest.TestCase):
    def test_provider_runs_in_mullvad_excluded_worker(self):
        worker_result = {
            "lyrics": "[ar:Artist]\n[ti:Song]\n\n[00:00.00]Line",
            "source": "genius",
            "artist": "Artist",
            "title": "Song",
            "synced": False,
        }
        completed = SimpleNamespace(
            returncode=0,
            stdout=json.dumps(worker_result),
            stderr="",
        )

        with (
            patch(
                "lyrics_provider_fetchers.shutil.which",
                return_value="/usr/bin/mullvad-exclude",
            ),
            patch(
                "lyrics_provider_fetchers.subprocess.run",
                return_value=completed,
            ) as run,
            patch(
                "lyrics_provider_fetchers._fetch_lyrics_genius_direct"
            ) as direct_fetch,
        ):
            result = lyrics_provider_fetchers.fetch_lyrics_genius(
                "Artist",
                "Song",
            )

        self.assertEqual(result, worker_result)
        direct_fetch.assert_not_called()
        command = run.call_args.args[0]
        self.assertEqual(command[0], "/usr/bin/mullvad-exclude")
        self.assertEqual(command[1], sys.executable)
        self.assertEqual(command[-3:], ["--genius-worker", "Artist", "Song"])

    def test_provider_fetches_directly_without_mullvad(self):
        worker_result = {"lyrics": "lyrics"}
        with (
            patch("lyrics_provider_fetchers.shutil.which", return_value=None),
            patch(
                "lyrics_provider_fetchers._fetch_lyrics_genius_direct",
                return_value=worker_result,
            ) as direct_fetch,
        ):
            result = lyrics_provider_fetchers.fetch_lyrics_genius(
                "Artist",
                "Song",
            )

        self.assertEqual(result, worker_result)
        direct_fetch.assert_called_once_with("Artist", "Song")

    def test_worker_serializes_direct_result(self):
        worker_result = {
            "lyrics": "[ar:Artist]\n[ti:Song]\n\n[00:00.00]Line",
            "source": "genius",
        }
        output = io.StringIO()
        with (
            patch(
                "lyrics_provider_fetchers._fetch_lyrics_genius_direct",
                return_value=worker_result,
            ),
            contextlib.redirect_stdout(output),
        ):
            return_code = lyrics_provider_fetchers.main(
                ["--genius-worker", "Artist", "Song"]
            )

        self.assertEqual(return_code, 0)
        self.assertEqual(json.loads(output.getvalue()), worker_result)


class TrackLyricsWriterTests(unittest.TestCase):
    def test_lookup_fallback_does_not_replace_canonical_lrc_artist(self):
        full_artist = (
            "Ayetian, DJ MAC, Malik Tercien, Nathaneal Brown, Stephen Beckford"
        )
        lyrics = "[00:00.00] Balance"
        metadata = {
            "title": "Balance",
            "artist": full_artist,
            "album_artist": "Ayetian",
            "album": "Balance",
            "duration": 180,
        }

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio_file = root / "Ayetian - Balance.opus"
            lrc_file = root / "Balance.lrc"
            output = io.StringIO()

            def fetch(artist, *_args, **_kwargs):
                return lyrics if artist == "Ayetian" else None

            with (
                patch("fetch_album_lyrics.fetch_lyrics", side_effect=fetch),
                patch("fetch_album_lyrics.save_lrc") as save_lrc,
                contextlib.redirect_stdout(output),
            ):
                result = process_audio_file(
                    audio_file,
                    root,
                    recursive=True,
                    metadata=metadata,
                    lrc_file=lrc_file,
                    report_kind=True,
                )

        self.assertIs(result, ProcessResult.SAVED)
        self.assertIn("LYRICS_RESULT=untimed lyrics", output.getvalue())
        save_lrc.assert_called_once_with(
            lrc_file, lyrics, full_artist, "Balance", "Balance"
        )

    def test_single_track_cli_delegates_to_the_bulk_pipeline(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio_file = root / "Song.opus"
            lrc_file = root / "Song.lrc"
            audio_file.touch()
            argv = [
                "fetch_track_lyrics.py",
                "--audio-file",
                str(audio_file),
                "--scan-root",
                str(root),
                "--lrc-file",
                str(lrc_file),
            ]
            with (
                patch.object(sys, "argv", argv),
                patch(
                    "fetch_track_lyrics.process_audio_file",
                    return_value=ProcessResult.SAVED,
                ) as process,
            ):
                self.assertEqual(fetch_track_lyrics.main(), 0)

        process.assert_called_once_with(
            audio_file,
            root,
            recursive=True,
            lrc_file=lrc_file,
            report_kind=True,
        )


if __name__ == "__main__":
    unittest.main()

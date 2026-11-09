import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cliamp_ctl as cliamp


class CliampTests(unittest.TestCase):
    @patch.object(cliamp, "read_now_playing", return_value={"title": "Track", "artist": "Artist", "url": "", "pos": 12})
    @patch.object(cliamp, "sync_mirror")
    @patch.object(cliamp, "is_mpv_running", return_value=True)
    @patch.object(cliamp, "send_mpv_cmds")
    def test_status_batches_properties(self, send, _running, _sync, _playing):
        send.return_value = [{"data": value} for value in (12, 120, False, "Track", 80, 1, False, True, False, "inf")]

        status = cliamp.get_status()

        self.assertEqual((status["state"], status["shuffle"], status["repeat"]), ("playing", True, "all"))
        send.assert_called_once_with([["get_property", name] for name in
            ("time-pos", "duration", "pause", "media-title", "volume", "speed", "idle-active",
             "shuffle", "loop-file", "loop-playlist")])

    @patch.object(cliamp, "save_now_playing")
    def test_idle_sync_takes_current_from_last_started(self, remember):
        mirror = {"current": 2, "looping": False, "entries": [
            {"playlist_id": playlist_id, "url": title, "title": title, "artist": ""}
            for playlist_id, title in ((1, "One"), (2, "Two"), (3, "Three"))]}
        with TemporaryDirectory() as directory, patch.object(cliamp, "MIRROR_PATH", str(Path(directory) / "mirror.json")), \
                patch.object(cliamp, "MIRROR_LOCK", str(Path(directory) / "mirror.lock")), \
                patch.object(cliamp, "LAST_STARTED_PATH", str(Path(directory) / "last_started")), \
                patch.object(cliamp, "mpv_values", return_value=[None, None]):
            cliamp.save_mirror(mirror)
            self.assertEqual(cliamp.upcoming(cliamp.sync_mirror()), [mirror["entries"][2]])
            self.assertEqual(cliamp.read_mirror(), mirror)
            remember.assert_not_called()
            Path(cliamp.LAST_STARTED_PATH).write_text("3")
            self.assertEqual(cliamp.upcoming(cliamp.sync_mirror()), [])
            self.assertEqual(cliamp.read_mirror()["current"], 3)
        remember.assert_called_once_with("Three", "", "Three")

    @patch.object(cliamp, "play_next_in_queue", return_value={"success": True})
    @patch.object(cliamp, "sync_mirror", return_value={"current": None, "looping": False, "entries": [{"playlist_id": 4}]})
    @patch.object(cliamp, "send_mpv_cmd", side_effect=[{"data": False}, {"data": True}])
    @patch.object(cliamp, "start_mpv_daemon")
    def test_play_at_eof_uses_queue(self, _start, _send, _sync, play_next):
        self.assertEqual(cliamp.resume_playback(), {"success": True})
        play_next.assert_called_once_with()

    @patch.object(cliamp, "send_mpv_cmd")
    def test_title_is_file_local(self, send):
        cliamp.load_mpv("/music/next.opus", "append", "Next")

        send.assert_called_once_with([
            "loadfile", "/music/next.opus", "append", -1,
            {"force-media-title": "Next"},
        ])

    @patch.object(cliamp, "save_youtube_meta")
    @patch.object(cliamp, "resolve_youtube_stream_url")
    @patch.object(cliamp, "get_cached_stream_url")
    @patch.object(cliamp, "send_mpv_cmd")
    def test_youtube_load_uses_cache_without_resolving(self, send, cached_stream, resolve, _metadata):
        url = "https://www.youtube.com/watch?v=f9l5Z5Vu_c0"
        for cached in (None, "https://media.example/audio"):
            with self.subTest(cached=cached):
                cached_stream.return_value = cached
                cliamp.load_mpv(url, "append", "Next")
                send.assert_called_with([
                    "loadfile", cached or url, "append", -1,
                    {"force-media-title": "Next", "ytdl-format": "18/best"},
                ])
        resolve.assert_not_called()

    @patch.object(cliamp, "save_now_playing")
    @patch.object(cliamp, "save_mirror")
    @patch.object(cliamp, "read_mirror")
    @patch.object(cliamp, "mirror_lock")
    @patch.object(cliamp, "mpv_values")
    def test_sync_follows_mpv_back_to_played_entry(self, values, _lock, read, save, remember):
        read.return_value = {"current": 2, "looping": False, "entries": [
            {"playlist_id": 1, "url": "/music/one.opus", "title": "One", "artist": "A"},
            {"playlist_id": 2, "url": "/music/two.opus", "title": "Two", "artist": "B"},
        ]}
        values.return_value = [[{"id": 1, "current": True}, {"id": 2}, {"id": 5, "filename": "/music/added.opus"}], False]

        titles = [entry["title"] for entry in cliamp.upcoming(cliamp.sync_mirror())]

        self.assertEqual(titles, ["Two", "added"])
        self.assertEqual(save.call_args.args[0]["current"], 1)
        remember.assert_called_once_with("One", "A", "/music/one.opus")

    def test_looping_queue_wraps_to_played_entries(self):
        entries = [{"playlist_id": playlist_id} for playlist_id in (1, 2, 3)]
        self.assertEqual(cliamp.upcoming({"current": 2, "looping": True, "entries": entries}), [entries[2], entries[0]])

    def test_reorder_moves_reach_requested_order(self):
        queued, order, played = [4, 7, 5, 9, 6], [9, 4, 6, 7, 5], [1, 2]
        playlist = played + queued
        for _, source, target in cliamp.reorder_commands(queued, order, len(played)):
            playlist.insert(target - (source < target), playlist.pop(source))
        self.assertEqual(playlist, played + order)

    @patch.object(cliamp.subprocess, "run")
    def test_youtube_lookup_reports_extractor_failure(self, run):
        run.return_value = cliamp.subprocess.CompletedProcess([], 1, "", "Warning: unavailable\nERROR: Connection timed out\n")
        with self.assertRaisesRegex(RuntimeError, "ERROR: Connection timed out"):
            cliamp.youtube_tracks("https://www.youtube.com/playlist?list=PLtest")

    @patch.object(cliamp, "youtube_tracks")
    def test_youtube_queue_distinguishes_failure_from_empty_and_keeps_cache(self, tracks):
        url = "https://www.youtube.com/playlist?list=PLtest"
        cached = [{"id": "track", "title": "Cached", "backend": "youtube"}]
        with TemporaryDirectory() as directory, patch.object(cliamp, "EXTERNAL_QUEUE_CACHE_PATH", str(Path(directory) / "queue.json")):
            cache = Path(cliamp.EXTERNAL_QUEUE_CACHE_PATH)
            tracks.return_value = []
            self.assertEqual(cliamp.cached_youtube_queue(url), {"source": "youtube", "items": []})
            tracks.side_effect = RuntimeError("Connection timed out")
            for items in ([], cached):
                with self.subTest(cached=bool(items)):
                    cache.write_text(json.dumps({"key": "PLtest", "saved_at": 0, "items": items}))
                    self.assertEqual(cliamp.cached_youtube_queue(url),
                        {"source": "youtube", "items": items, "error": "Connection timed out"})
                    self.assertEqual(json.loads(cache.read_text())["items"], items)

    @patch.object(cliamp, "cached_youtube_queue", return_value={"source": "youtube", "items": [{"id": "one"}, {"id": "two"}]})
    def test_youtube_queue_marks_playing_video(self, _queue):
        items = cliamp.read_youtube_queue("https://www.youtube.com/watch?v=two&list=PLtest")["items"]
        self.assertEqual([item["current"] for item in items], [False, True])

    def test_local_history_filters_before_limit(self):
        with TemporaryDirectory() as directory:
            local = Path(directory) / "local.opus"
            local.touch()
            entries = [
                {"path": str(local), "title": "Local"},
                {"path": str(local.with_name("missing.opus")), "title": "Missing"},
                {"path": "https://www.youtube.com/watch?v=f9l5Z5Vu_c0", "title": "Online"},
                {"title": "Metadata only"},
            ]
            self.assertEqual(cliamp.unique_history(entries, 1, local_only=True), [entries[0]])
            self.assertEqual(cliamp.unique_history(entries, len(entries)), [entries[3], entries[2], entries[0]])

    def test_blank_artist_does_not_inherit_previous_artist(self):
        with TemporaryDirectory() as directory, patch.object(cliamp, "NOW_PLAYING_PATH", str(Path(directory) / "playing.json")):
            cliamp.save_now_playing("Previous", "Kaey", "/music/previous.opus")
            cliamp.save_now_playing("Sins For U", "", "https://www.youtube.com/watch?v=f9l5Z5Vu_c0")
            self.assertEqual(json.loads(Path(cliamp.NOW_PLAYING_PATH).read_text())["artist"], "")

    def test_cover_completion_keeps_success_and_reaps_timed_out_workers(self):
        launch_process = cliamp.subprocess.Popen
        workers = []
        extraction_deadline_seconds = 0.5

        def extract(command, **options):
            track = Path(command[command.index("-i") + 1]).stem
            destination = command[-1]
            program = "import signal; signal.pause()" if track == "blocked" else (
                "import sys; from pathlib import Path; Path(sys.argv[1]).write_bytes(b'cover'); "
                + ("sys.exit(1)" if track == "failed" else "sys.exit(0)"))
            worker = launch_process([sys.executable, "-c", program, destination], **options)
            workers.append(worker)
            return worker

        with TemporaryDirectory() as directory:
            tracks = [{"url": str(Path(directory) / (name + ".opus"))} for name in ("blocked", "finished", "failed")]
            for track in tracks:
                Path(track["url"]).touch()
            with patch.object(cliamp, "COVER_CACHE_DIR", str(Path(directory) / "covers")), \
                    patch.object(cliamp.shutil, "which", return_value="ffmpeg"), \
                    patch.object(cliamp.subprocess, "Popen", side_effect=extract), \
                    patch.object(cliamp.time, "sleep", side_effect=AssertionError("Cover extraction must wait for process exits")):
                self.assertIs(cliamp.attach_covers(tracks, budget_seconds=extraction_deadline_seconds), tracks)
                self.assertEqual(tracks[0]["thumb"], "")
                self.assertTrue(Path(tracks[1]["thumb"]).is_file())
                self.assertEqual(tracks[2]["thumb"], "")
                self.assertFalse(Path(cliamp.embedded_cover_cache_path(tracks[2]["url"])).exists())
            self.assertTrue(all(worker.returncode is not None for worker in workers))
            self.assertLess(workers[0].returncode, 0)

    def test_cached_covers_do_not_launch_extractors(self):
        with TemporaryDirectory() as directory, patch.object(cliamp, "COVER_CACHE_DIR", directory):
            track = {"url": str(Path(directory) / "track.opus")}
            Path(track["url"]).touch()
            cover = Path(cliamp.embedded_cover_cache_path(track["url"]))
            cover.write_bytes(b"cover")
            with patch.object(cliamp.shutil, "which", return_value="ffmpeg"), patch.object(cliamp.subprocess, "Popen") as launch:
                cliamp.attach_covers([track])
            self.assertEqual(track["thumb"], str(cover))
            launch.assert_not_called()

    def test_queue_art_finds_thumbnail_cached_after_queueing(self):
        video_id = "f9l5Z5Vu_c0"
        with TemporaryDirectory() as directory, patch.object(cliamp, "AUDIO_CACHE_DIR", directory):
            entry = cliamp.queue_entry(f"https://www.youtube.com/watch?v={video_id}", "Track", "")
            Path(cliamp.youtube_thumb_path(video_id)).write_bytes(b"thumb")
            self.assertEqual(cliamp.attach_track_art([entry])[0]["thumb"], cliamp.youtube_thumb_path(video_id))


if __name__ == "__main__":
    unittest.main()

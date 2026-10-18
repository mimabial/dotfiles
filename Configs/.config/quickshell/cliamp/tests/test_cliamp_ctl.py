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
    @patch.object(cliamp, "reconcile_queue", return_value=[])
    @patch.object(cliamp, "is_mpv_running", return_value=True)
    @patch.object(cliamp, "send_mpv_cmds")
    def test_status_batches_properties(self, send, _running, _queue, _playing):
        send.return_value = [{"data": value} for value in (12, 120, False, "Track", 80, 1, False)]

        status = cliamp.get_status()

        self.assertEqual(status["state"], "playing")
        send.assert_called_once_with([["get_property", name] for name in
            ("time-pos", "duration", "pause", "media-title", "volume", "speed", "idle-active")])

    @patch.object(cliamp, "read_now_playing", return_value={})
    @patch.object(cliamp, "play_item")
    @patch.object(cliamp, "is_mpv_running", return_value=True)
    @patch.object(cliamp, "send_mpv_cmd", return_value={"data": []})
    @patch.object(cliamp, "send_mpv_cmds")
    def test_idle_status_preserves_queue(self, send_properties, _send, _running, play, _playing):
        send_properties.side_effect = [[{"data": value} for value in
            (None, None, False, "", cliamp.DEFAULT_VOLUME, 1, idle)] for idle in (True, False)]
        queue = [{"url": "/music/next.opus"}]
        with TemporaryDirectory() as directory, patch.object(cliamp, "QUEUE_PATH", str(Path(directory) / "queue.json")):
            cliamp.save_queue(queue)
            self.assertEqual(cliamp.get_status()["state"], "stopped")
            self.assertEqual(cliamp.read_queue(), queue)
        play.assert_not_called()

    @patch.object(cliamp, "play_next_in_queue", return_value={"success": True})
    @patch.object(cliamp, "reconcile_queue", return_value=[{"url": "/music/next.opus"}])
    @patch.object(cliamp, "send_mpv_cmd", side_effect=[{"data": False}, {"data": True}])
    @patch.object(cliamp, "start_mpv_daemon")
    def test_play_at_eof_uses_queue(self, _start, _send, queue, play_next):
        self.assertEqual(cliamp.resume_playback(), {"success": True})
        play_next.assert_called_once_with(queue.return_value)

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
    @patch.object(cliamp, "save_queue")
    @patch.object(cliamp, "send_mpv_cmd", return_value={"data": [{"id": 2, "current": True}]})
    @patch.object(cliamp, "read_queue")
    def test_reconcile_updates_current_metadata(self, read, _send, save, remember):
        read.return_value = [
            {"playlist_id": 1, "url": "/music/one.opus", "title": "One", "artist": "A"},
            {"playlist_id": 2, "url": "/music/two.opus", "title": "Two", "artist": "B"},
            {"playlist_id": 3, "url": "/music/three.opus", "title": "Three", "artist": "C"},
        ]

        remaining = cliamp.reconcile_queue()

        self.assertEqual(remaining, [read.return_value[2]])
        save.assert_called_once_with(remaining)
        remember.assert_called_once_with("Two", "B", "/music/two.opus")

    @patch.object(cliamp, "save_queue")
    @patch.object(cliamp, "send_mpv_cmd", return_value={"data": [{"id": 1, "current": True}]})
    @patch.object(cliamp, "read_queue", return_value=[{"playlist_id": 2, "url": "/music/repeated.opus"}])
    def test_current_song_does_not_consume_queued_repeat(self, read, _send, save):
        self.assertEqual(cliamp.reconcile_queue(), read.return_value)
        save.assert_not_called()

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


if __name__ == "__main__":
    unittest.main()

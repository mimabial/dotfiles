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

    def test_blank_artist_does_not_inherit_previous_artist(self):
        with TemporaryDirectory() as directory, patch.object(cliamp, "NOW_PLAYING_PATH", str(Path(directory) / "playing.json")):
            cliamp.save_now_playing("Previous", "Kaey", "/music/previous.opus")
            cliamp.save_now_playing("Sins For U", "", "https://www.youtube.com/watch?v=f9l5Z5Vu_c0")
            self.assertEqual(json.loads(Path(cliamp.NOW_PLAYING_PATH).read_text())["artist"], "")


if __name__ == "__main__":
    unittest.main()

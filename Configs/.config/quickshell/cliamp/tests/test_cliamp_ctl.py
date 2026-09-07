import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cliamp_ctl as cliamp


class QueueMetadataTests(unittest.TestCase):
    @patch.object(cliamp, "send_mpv_cmd")
    def test_title_is_file_local(self, send):
        cliamp.load_mpv("/music/next.opus", "append", "Next")

        send.assert_called_once_with([
            "loadfile", "/music/next.opus", "append", -1,
            {"force-media-title": "Next"},
        ])

    @patch.object(cliamp, "save_now_playing")
    @patch.object(cliamp, "save_queue")
    @patch.object(cliamp, "send_mpv_cmd", return_value={"data": "/music/two.opus"})
    @patch.object(cliamp, "read_queue")
    def test_reconcile_updates_current_metadata(self, read, _send, save, remember):
        read.return_value = [
            {"url": "/music/one.opus", "title": "One", "artist": "A"},
            {"url": "/music/two.opus", "title": "Two", "artist": "B"},
            {"url": "/music/three.opus", "title": "Three", "artist": "C"},
        ]

        remaining = cliamp.reconcile_queue()

        self.assertEqual(remaining, [read.return_value[2]])
        save.assert_called_once_with(remaining)
        remember.assert_called_once_with("Two", "B", "/music/two.opus")


if __name__ == "__main__":
    unittest.main()

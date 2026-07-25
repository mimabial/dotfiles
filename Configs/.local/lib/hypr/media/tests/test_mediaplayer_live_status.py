import json
import sys
import unittest
from pathlib import Path

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

from mediaplayer_browser import (
    _parse_youtube_watch_page_media_info,
    _parse_ytdlp_media_info,
)
from mediaplayer_policy import MediaMetadata


def watch_page(player_response: dict) -> str:
    return (
        "<html><script>var ytInitialPlayerResponse = "
        f"{json.dumps(player_response)};"
        "</script></html>"
    )


class YouTubeLiveStatusTests(unittest.TestCase):
    def test_live_in_recorded_title_does_not_mark_video_live(self):
        info = _parse_youtube_watch_page_media_info(
            watch_page(
                {
                    "videoDetails": {
                        "title": "Didi B : Live Session",
                        "lengthSeconds": "1182",
                        "isLiveContent": False,
                    }
                }
            )
        )

        self.assertEqual(info.live_status, "not_live")
        self.assertEqual(info.duration_seconds, 1182)

    def test_explicit_is_live_now_marks_stream_live(self):
        info = _parse_youtube_watch_page_media_info(
            watch_page(
                {
                    "videoDetails": {"isLiveContent": True},
                    "microformat": {
                        "playerMicroformatRenderer": {
                            "liveBroadcastDetails": {"isLiveNow": True}
                        }
                    },
                }
            )
        )

        self.assertTrue(info.is_live)
        self.assertIsNone(info.duration_seconds)

    def test_archived_live_stream_is_not_live_now(self):
        info = _parse_youtube_watch_page_media_info(
            watch_page(
                {
                    "videoDetails": {
                        "lengthSeconds": "3600",
                        "isLiveContent": True,
                    },
                    "microformat": {
                        "playerMicroformatRenderer": {
                            "liveBroadcastDetails": {"isLiveNow": False}
                        }
                    },
                }
            )
        )

        self.assertEqual(info.live_status, "not_live")
        self.assertEqual(info.duration_seconds, 3600)

    def test_ambiguous_live_content_waits_for_ytdlp(self):
        info = _parse_youtube_watch_page_media_info(
            watch_page({"videoDetails": {"isLiveContent": True}})
        )

        self.assertEqual(info.live_status, "")
        self.assertIsNone(info.duration_seconds)

    def test_title_marker_without_player_metadata_is_not_evidence(self):
        info = _parse_youtube_watch_page_media_info(
            "<html><title>🔴 Example [LIVE]</title></html>"
        )

        self.assertEqual(info.live_status, "")
        self.assertIsNone(info.duration_seconds)

    def test_only_ytdlp_is_live_status_is_live(self):
        for status in ("not_live", "was_live", "post_live"):
            with self.subTest(status=status):
                info = _parse_ytdlp_media_info(f"{status}\n1182")
                metadata = MediaMetadata(ytdlp_live_status=status)
                self.assertFalse(info.is_live)
                self.assertFalse(metadata.is_live_stream)

        info = _parse_ytdlp_media_info("is_live\n")
        metadata = MediaMetadata(ytdlp_live_status="is_live")
        self.assertTrue(info.is_live)
        self.assertTrue(metadata.is_live_stream)


if __name__ == "__main__":
    unittest.main()

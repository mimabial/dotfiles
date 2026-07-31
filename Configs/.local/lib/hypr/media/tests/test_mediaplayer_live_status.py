import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

from mediaplayer_actions import player_name_matches
from mediaplayer_browser import (
    _build_ytdlp_probe_command,
    _parse_youtube_watch_page_media_info,
    _parse_ytdlp_media_info,
    _reuse_last_media_info,
)
from mediaplayer_policy import (
    MediaMetadata,
    PlaybackSnapshot,
    PlaybackState,
    resolve_playback,
)
from mediaplayer_ui import (
    MediaPlayerUiConfig,
    create_tooltip_text,
    format_artist_track,
)


def watch_page(player_response: dict) -> str:
    return (
        "<html><script>var ytInitialPlayerResponse = "
        f"{json.dumps(player_response)};"
        "</script></html>"
    )


def ui_config() -> MediaPlayerUiConfig:
    return MediaPlayerUiConfig(
        max_length_module=70,
        prefix_playing="",
        prefix_paused="",
        standby_text=" MPlayer",
        artist_track_separator="  ",
        artist_color="#ffffff",
        track_color="#ffffff",
        progress_color="#ffffff",
        empty_color="#000000",
        time_color="#ffffff",
    )


class YouTubeLiveStatusTests(unittest.TestCase):
    @patch(
        "mediaplayer_browser.ytdlp_auth_args",
        return_value=["--cookies-from-browser", "firefox"],
    )
    @patch("mediaplayer_browser.shutil.which", return_value="/usr/bin/yt-dlp")
    def test_ytdlp_probe_reuses_configured_authentication(self, _which, _auth_args):
        command = _build_ytdlp_probe_command(
            "https://www.youtube.com/watch?v=video-id"
        )

        self.assertIn("--ignore-config", command)
        self.assertIn("--cookies-from-browser", command)
        self.assertIn("firefox", command)

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


class PlaybackStateTests(unittest.TestCase):
    def test_recent_seek_reconciles_reported_position(self):
        state = PlaybackState()
        state.record_seek(42.0, 100.0)
        snapshot = PlaybackSnapshot(
            player_name="mpd",
            status="Playing",
            reported_position_seconds=5.0,
            metadata=MediaMetadata(
                track="Track",
                artist="Artist",
                duration_seconds=120.0,
            ),
            observed_at=101.0,
        )

        playback = resolve_playback(snapshot, state)

        self.assertEqual(playback.position_seconds, 42.0)
        self.assertEqual(state.position_seconds, 42.0)
        self.assertEqual(state.metadata.track, "Track")

    def test_stale_title_is_suppressed_until_browser_updates_it(self):
        def snapshot(track, url, at):
            return PlaybackSnapshot(
                player_name="fftab_t13",
                status="Playing",
                reported_position_seconds=0.0 if at > 100.0 else 200.0,
                metadata=MediaMetadata(
                    track=track,
                    artist="www.youtube.com",
                    track_id="/org/mpris/MediaPlayer2/fftab/t13",
                    media_url=url,
                    duration_seconds=234.0 if at <= 100.0 else 147.9,
                ),
                observed_at=at,
            )

        old = "https://www.youtube.com/watch?v=j_JH_zYoFEg"
        new = "https://www.youtube.com/watch?v=2_id9xzpx2Y"
        state = PlaybackState()

        first = resolve_playback(snapshot("Pressure", old, 100.0), state)
        self.assertEqual(first.metadata.track, "Pressure")

        for tick in (101.0, 102.0, 103.0):
            during = resolve_playback(snapshot("Pressure", new, tick), state)
            self.assertEqual(during.metadata.track, "")
            self.assertEqual(during.metadata.artist, "")

        after = resolve_playback(snapshot("Njerae - OTD", new, 104.0), state)
        self.assertEqual(after.metadata.track, "Njerae - OTD")

    def test_reset_clears_all_playback_tracking(self):
        state = PlaybackState(
            metadata=MediaMetadata(track="Track"),
            track_key="mpd|track",
            position_seconds=42.0,
            seek_at=100.0,
            seek_position=42.0,
        )

        state.reset()

        self.assertEqual(state, PlaybackState())


class MediaPlayerRegressionTests(unittest.TestCase):
    def test_last_media_info_reuse_has_one_policy(self):
        live = _reuse_last_media_info(True, 0.0, "is_live")
        recorded = _reuse_last_media_info(True, 1182.0, "")

        self.assertTrue(live.is_live)
        self.assertEqual(recorded.duration_seconds, 1182.0)
        self.assertEqual(recorded.live_status, "not_live")
        self.assertIsNone(_reuse_last_media_info(False, 1182.0, "is_live"))

    def test_player_filter_matches_mpris_instance_suffix(self):
        self.assertTrue(player_name_matches("firefox.instance_1234", "firefox"))
        self.assertTrue(player_name_matches("firefox", "firefox"))
        self.assertFalse(player_name_matches("firefox-beta", "firefox"))

    def test_pango_text_is_escaped_without_escaping_markup(self):
        module_text = format_artist_track(
            "",
            "Rock & Roll <Live>",
            True,
            ui_config(),
        )
        tooltip = create_tooltip_text(
            "Artist <One>",
            "Rock & Roll <Live>",
            10.0,
            120.0,
            "player<one>",
            ui_config(),
        )

        self.assertIn("<b>Rock &amp; Roll &lt;Live&gt;</b>", module_text)
        self.assertIn("<b>Rock &amp; Roll &lt;Live&gt;</b>", tooltip)
        self.assertIn("<i>Artist &lt;One&gt;</i>", tooltip)
        self.assertIn("<span>player&lt;one&gt;</span>", tooltip)
        self.assertNotIn("&amp;amp;", module_text + tooltip)


if __name__ == "__main__":
    unittest.main()

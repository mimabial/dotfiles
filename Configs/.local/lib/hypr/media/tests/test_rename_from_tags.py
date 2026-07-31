import contextlib
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

import rename_from_tags
from rename_from_tags import credit_loss_for_rename, default_pattern_for, fields_for


class RenameCreditSafetyTests(unittest.TestCase):
    path = Path("/music/Didi B, Zlatan, Chley - Je m'appelle.opus")

    def test_detects_credits_removed_from_complete_target(self):
        self.assertEqual(
            credit_loss_for_rename(
                self.path,
                {"artist": "Didi B", "title": "Je m'appelle"},
            ),
            ["Zlatan", "Chley"],
        )

    def test_guest_moved_into_title_is_not_lost(self):
        path = Path("/music/Main, Guest - Song.opus")
        self.assertEqual(
            credit_loss_for_rename(
                path,
                {"artist": "Main", "title": "Song (feat. Guest)"},
            ),
            [],
        )

    def test_multi_track_release_uses_numbered_album_pattern(self):
        tags = {
            "album": ["Papercut"],
            "tracknumber": ["1/11"],
        }

        self.assertEqual(
            default_pattern_for(Path("/music/Artist/song.opus"), tags),
            "{tracknumber}. {title}",
        )

    def test_matching_album_folder_uses_numbered_album_pattern(self):
        tags = {
            "album": ["Papercut"],
            "tracknumber": ["1"],
        }

        self.assertEqual(
            default_pattern_for(Path("/music/Artist/Papercut/song.opus"), tags),
            "{tracknumber}. {title}",
        )

    def test_one_track_single_keeps_artist_title_pattern(self):
        tags = {
            "album": ["Stars Misaligned"],
            "tracknumber": ["1/1"],
        }

        self.assertEqual(
            default_pattern_for(Path("/music/Artist/song.opus"), tags),
            "{artist} - {title}",
        )

    def test_track_position_is_extracted_before_filename_sanitizing(self):
        values = fields_for(
            {
                "artist": ["Imani Imani"],
                "title": ["Chasing"],
                "album": ["Papercut"],
                "tracknumber": ["8/11"],
            }
        )

        self.assertEqual(values["tracknumber"], "08")

    def test_default_preview_blocks_credit_erasing_rename(self):
        tags = {"artist": ["Didi B"], "title": ["Je m'appelle"]}
        output = io.StringIO()
        with (
            patch.object(sys, "argv", ["rename_from_tags.py", "/music"]),
            patch("rename_from_tags.collect", return_value=[self.path]),
            patch("rename_from_tags.read_tags", return_value=tags),
            patch("rename_from_tags.build_move_plan") as build_move_plan,
            contextlib.redirect_stderr(output),
        ):
            return_code = rename_from_tags.main()

        self.assertEqual(return_code, 1)
        self.assertIn("would remove credit(s): Zlatan, Chley", output.getvalue())
        build_move_plan.assert_not_called()

    @patch(
        "rename_from_tags.music_library_dir",
        return_value=Path("/configured/music"),
    )
    def test_cli_defaults_to_configured_music_library(self, _music_library_dir):
        output = io.StringIO()
        with (
            patch.object(sys, "argv", ["rename_from_tags.py"]),
            patch("rename_from_tags.collect", return_value=[]) as collect,
            contextlib.redirect_stderr(output),
        ):
            return_code = rename_from_tags.main()

        self.assertEqual(return_code, 0)
        collect.assert_called_once_with(
            ["/configured/music"],
            set(rename_from_tags.SUPPORTED),
        )

if __name__ == "__main__":
    unittest.main()

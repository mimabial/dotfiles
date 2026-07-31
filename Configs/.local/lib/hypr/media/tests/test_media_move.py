import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

import rename_from_tags
from media_move import MoveError, apply_move_plan, build_move_plan


class MusicMoveTests(unittest.TestCase):
    def test_moves_audio_file_and_mirrored_lrc_together(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Old" / "Song.opus"
            target = root / "New" / "Song.opus"
            source.parent.mkdir()
            source.write_text("audio")
            source_lrc = root / ".lyrics" / "Old" / "Song.lrc"
            source_lrc.parent.mkdir(parents=True)
            source_lrc.write_text("[00:01.00]Line")

            with patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}):
                plan = build_move_plan(source, target, require_music_root=True)
                apply_move_plan(plan)

            self.assertFalse(source.exists())
            self.assertFalse(source_lrc.exists())
            self.assertEqual(target.read_text(), "audio")
            self.assertEqual(
                (root / ".lyrics" / "New" / "Song.lrc").read_text(),
                "[00:01.00]Line",
            )

    def test_moves_directory_and_its_mirrored_lyrics_tree(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Artist" / "Album"
            target = root / "Moved" / "Album"
            source.mkdir(parents=True)
            (source / "Song.opus").write_text("audio")
            source_lyrics = root / ".lyrics" / "Artist" / "Album"
            source_lyrics.mkdir(parents=True)
            (source_lyrics / "Song.lrc").write_text("[00:01.00]Line")

            with patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}):
                plan = build_move_plan(source, target, require_music_root=True)
                apply_move_plan(plan)

            self.assertTrue((target / "Song.opus").is_file())
            self.assertTrue(
                (root / ".lyrics" / "Moved" / "Album" / "Song.lrc").is_file()
            )
            self.assertFalse(source.exists())
            self.assertFalse(source_lyrics.exists())

    def test_refuses_lyrics_collision_before_moving_audio(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Old" / "Song.opus"
            target = root / "New" / "Song.opus"
            source.parent.mkdir()
            source.write_text("audio")
            source_lrc = root / ".lyrics" / "Old" / "Song.lrc"
            target_lrc = root / ".lyrics" / "New" / "Song.lrc"
            source_lrc.parent.mkdir(parents=True)
            target_lrc.parent.mkdir(parents=True)
            source_lrc.write_text("old")
            target_lrc.write_text("collision")

            with (
                patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}),
                self.assertRaises(MoveError),
            ):
                build_move_plan(source, target, require_music_root=True)

            self.assertTrue(source.is_file())
            self.assertFalse(target.exists())

    def test_rename_from_tags_moves_lrc_and_updates_mpd_once(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Old Name.opus"
            source.write_text("audio")
            source_lrc = root / ".lyrics" / "Old Name.lrc"
            source_lrc.parent.mkdir()
            source_lrc.write_text("[00:01.00]Line")
            values = {
                "artist": "Artist",
                "albumartist": "",
                "title": "Title",
                "album": "",
                "tracknumber": "",
                "date": "",
                "genre": "",
            }
            argv = ["rename_from_tags.py", "--apply", str(source)]

            with (
                patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}),
                patch.object(sys, "argv", argv),
                patch("rename_from_tags.read_tags", return_value={}),
                patch("rename_from_tags.fields_for", return_value=values),
                patch("rename_from_tags.update_mpd") as update_mpd,
            ):
                self.assertEqual(rename_from_tags.main(), 0)

            self.assertTrue((root / "Artist - Title.opus").is_file())
            self.assertTrue((root / ".lyrics" / "Artist - Title.lrc").is_file())
            self.assertFalse(source.exists())
            self.assertFalse(source_lrc.exists())
            update_mpd.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()

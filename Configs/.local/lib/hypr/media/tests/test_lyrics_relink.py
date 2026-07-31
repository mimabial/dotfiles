import contextlib
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

from lyrics_relink import relink_directory

EXTENSIONS = {".opus"}


class LyricsRelinkTests(unittest.TestCase):
    def test_moves_orphaned_same_name_lyrics_to_current_audio_location(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio = root / "New" / "Song.opus"
            audio.parent.mkdir()
            audio.write_text("audio")
            orphan = root / ".lyrics" / "Old" / "Song.lrc"
            orphan.parent.mkdir(parents=True)
            orphan.write_text("[ar:Artist]\n[ti:Song]\n[00:01.00]Line\n")

            with (
                patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}),
                patch(
                    "lyrics_relink.get_audio_metadata",
                    return_value={"artist": "Artist", "title": "Song", "album": ""},
                ),
            ):
                result = relink_directory(
                    audio.parent,
                    recursive=False,
                    dry_run=False,
                    extensions=EXTENSIONS,
                )

            self.assertEqual(result, 0)
            self.assertFalse(orphan.exists())
            self.assertTrue((root / ".lyrics" / "New" / "Song.lrc").is_file())

    def test_finds_renamed_lyrics_by_exact_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio = root / "New" / "Renamed.opus"
            audio.parent.mkdir()
            audio.write_text("audio")
            orphan = root / ".lyrics" / "Old" / "Original Name.lrc"
            orphan.parent.mkdir(parents=True)
            orphan.write_text(
                "[ar:Artist]\n[ti:Canonical Title]\n[al:Album]\n[00:01.00]Line\n"
            )

            with (
                patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}),
                patch(
                    "lyrics_relink.get_audio_metadata",
                    return_value={
                        "artist": "Artist",
                        "title": "Canonical Title",
                        "album": "Album",
                    },
                ),
            ):
                result = relink_directory(
                    audio.parent,
                    recursive=False,
                    dry_run=False,
                    extensions=EXTENSIONS,
                )

            self.assertEqual(result, 0)
            self.assertFalse(orphan.exists())
            self.assertTrue((root / ".lyrics" / "New" / "Renamed.lrc").is_file())

    def test_does_not_steal_lyrics_from_an_existing_audio_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            old_audio = root / "Old" / "Song.opus"
            new_audio = root / "New" / "Song.opus"
            old_audio.parent.mkdir()
            new_audio.parent.mkdir()
            old_audio.write_text("old audio")
            new_audio.write_text("new audio")
            owned_lrc = root / ".lyrics" / "Old" / "Song.lrc"
            owned_lrc.parent.mkdir(parents=True)
            owned_lrc.write_text("[ar:Artist]\n[ti:Song]\n[00:01.00]Line\n")
            output = io.StringIO()

            with (
                patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}),
                patch(
                    "lyrics_relink.get_audio_metadata",
                    return_value={"artist": "Artist", "title": "Song", "album": ""},
                ),
                contextlib.redirect_stdout(output),
            ):
                result = relink_directory(
                    new_audio.parent,
                    recursive=False,
                    dry_run=False,
                    extensions=EXTENSIONS,
                )

            self.assertEqual(result, 1)
            self.assertTrue(owned_lrc.is_file())
            self.assertIn("no lyrics found", output.getvalue())

    def test_reports_each_file_without_lyrics(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio = root / "Album" / "Missing.opus"
            audio.parent.mkdir()
            audio.write_text("audio")
            output = io.StringIO()

            with (
                patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}),
                patch(
                    "lyrics_relink.get_audio_metadata",
                    return_value={"artist": "Artist", "title": "Missing", "album": ""},
                ),
                contextlib.redirect_stdout(output),
            ):
                result = relink_directory(
                    audio.parent,
                    recursive=False,
                    dry_run=False,
                    extensions=EXTENSIONS,
                )

            self.assertEqual(result, 1)
            self.assertIn("Missing.opus: no lyrics found", output.getvalue())


if __name__ == "__main__":
    unittest.main()

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

from lyrics_relink import LyricsMirrorTidy, relink_directory, tidy_lyrics_mirror

EXTENSIONS = {".opus"}


class LyricsMirrorTidyTests(unittest.TestCase):
    def library(self, root: Path) -> dict[str, Path]:
        files = {
            "renamed": root / "Album" / "01 - Song.opus",
            "kept": root / "Album" / "02 - Other.opus",
            "twice": root / "Album" / "03 - Twice.opus",
            "orphan": root / ".lyrics" / "Album" / "Song.lrc",
            "owned": root / ".lyrics" / "Album" / "02 - Other.lrc",
            "gone": root / ".lyrics" / "Deleted Album" / "Gone.lrc",
            "twice_a": root / ".lyrics" / "Old" / "Twice.lrc",
            "twice_b": root / ".lyrics" / "Older" / "Twice.lrc",
            "unplugged": root / ".lyrics" / "External" / "Away.lrc",
        }
        for name, path in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            title = "Twice" if name.startswith("twice") else path.stem
            path.write_text(f"[ar:Artist]\n[ti:{title}]\n[00:01.00]Line\n")
        (root / "External").symlink_to(root / "unplugged-drive")
        return files

    def tidy(self, root: Path, dry_run: bool) -> LyricsMirrorTidy:
        titles = {"01 - Song": "Song", "02 - Other": "02 - Other", "03 - Twice": "Twice"}
        with (
            patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}),
            patch(
                "lyrics_relink.get_audio_metadata",
                side_effect=lambda path: {"artist": "Artist", "title": titles[Path(path).stem], "album": ""},
            ),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            return tidy_lyrics_mirror(root, True, EXTENSIONS, dry_run)

    def test_relinks_before_deleting_only_lyrics_of_removed_songs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = self.library(root)

            self.assertEqual(self.tidy(root, dry_run=False), LyricsMirrorTidy(relinked=1, deleted=1))
            self.assertTrue((root / ".lyrics" / "Album" / "01 - Song.lrc").is_file())
            self.assertFalse(files["orphan"].exists())
            self.assertFalse(files["gone"].exists())
            self.assertFalse(files["gone"].parent.exists())
            for kept in ("owned", "twice_a", "twice_b", "unplugged"):
                self.assertTrue(files[kept].is_file(), kept)

    def test_dry_run_reports_the_same_work_without_touching_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = self.library(root)

            self.assertEqual(self.tidy(root, dry_run=True), LyricsMirrorTidy(relinked=1, deleted=1))
            self.assertTrue(all(path.exists() for path in files.values()))


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

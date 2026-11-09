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

from lyrics_mirror import LyricsMirrorTidy, tidy_lyrics_mirror

EXTENSIONS = {".opus"}


def write_lyrics(path: Path, title: str, album: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"[ar:Artist]\n[ti:{title}]\n[al:{album}]\n[00:01.00]Line\n")


def tidy(root: Path, directory: Path, recursive: bool, dry_run: bool, titles: dict[str, str]) -> LyricsMirrorTidy:
    with (
        patch.dict(os.environ, {"XDG_MUSIC_DIR": str(root)}),
        patch(
            "lyrics_mirror.get_audio_metadata",
            side_effect=lambda path: {"artist": "Artist", "title": titles[Path(path).stem], "album": "Album"},
        ),
        contextlib.redirect_stdout(io.StringIO()),
    ):
        return tidy_lyrics_mirror(directory, recursive, EXTENSIONS, dry_run)


def counts(result: LyricsMirrorTidy) -> tuple[int, int]:
    return len(result.relinked), result.deleted


class LyricsRelinkTests(unittest.TestCase):
    def test_moves_orphaned_same_name_lyrics_to_current_audio_location(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio = root / "New" / "Song.opus"
            audio.parent.mkdir()
            audio.write_text("audio")
            orphan = root / ".lyrics" / "Old" / "Song.lrc"
            write_lyrics(orphan, "Other Title")

            self.assertEqual(counts(tidy(root, audio.parent, False, False, {"Song": "Song"})), (1, 0))
            self.assertFalse(orphan.exists())
            self.assertTrue((root / ".lyrics" / "New" / "Song.lrc").is_file())

    def test_finds_renamed_lyrics_by_exact_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            audio = root / "New" / "Renamed.opus"
            audio.parent.mkdir()
            audio.write_text("audio")
            orphan = root / ".lyrics" / "Old" / "Original Name.lrc"
            write_lyrics(orphan, "Canonical Title", "Album")

            self.assertEqual(counts(tidy(root, audio.parent, False, False, {"Renamed": "Canonical Title"})), (1, 0))
            self.assertFalse(orphan.exists())
            self.assertTrue((root / ".lyrics" / "New" / "Renamed.lrc").is_file())

    def test_does_not_take_lyrics_from_an_existing_audio_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for folder in ("Old", "New"):
                (root / folder).mkdir()
                (root / folder / "Song.opus").write_text("audio")
            owned = root / ".lyrics" / "Old" / "Song.lrc"
            write_lyrics(owned, "Song")

            self.assertEqual(counts(tidy(root, root / "New", False, False, {"Song": "Song"})), (0, 0))
            self.assertTrue(owned.is_file())


class LyricsMirrorTidyTests(unittest.TestCase):
    titles = {"01 - Song": "Song", "02 - Other": "02 - Other", "03 - Twice": "Twice"}

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
            write_lyrics(path, "Twice" if name.startswith("twice") else path.stem)
        (root / "External").symlink_to(root / "unplugged-drive")
        return files

    def test_relinks_before_deleting_only_lyrics_of_removed_songs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = self.library(root)

            self.assertEqual(counts(tidy(root, root, True, False, self.titles)), (1, 1))
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

            result = tidy(root, root, True, True, self.titles)
            self.assertEqual(result, LyricsMirrorTidy({files["renamed"]: files["orphan"]}, 1))
            self.assertTrue(all(path.exists() for path in files.values()))


if __name__ == "__main__":
    unittest.main()

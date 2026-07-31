import sys
import tempfile
import unittest
from pathlib import Path

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

from ytdlp_config import ytdlp_auth_args


class YtDlpConfigTests(unittest.TestCase):
    def test_reads_only_cookie_authentication_options(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = Path(temporary_directory) / "config"
            config.write_text(
                "--cookies-from-browser firefox\n"
                "--embed-metadata\n"
                "--cookies=/tmp/youtube-cookies.txt\n"
                "-o '%(title)s.%(ext)s'\n",
                encoding="utf-8",
            )

            self.assertEqual(
                ytdlp_auth_args(config),
                [
                    "--cookies-from-browser",
                    "firefox",
                    "--cookies=/tmp/youtube-cookies.txt",
                ],
            )

    def test_missing_config_has_no_authentication_options(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            missing = Path(temporary_directory) / "missing"
            self.assertEqual(ytdlp_auth_args(missing), [])


if __name__ == "__main__":
    unittest.main()

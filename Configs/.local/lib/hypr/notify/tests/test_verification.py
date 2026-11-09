import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

NOTIFY = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("verification", NOTIFY / "verification.py")
verification = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verification)
TEST_LEASE_SECONDS = 0.1


class VerificationTest(unittest.TestCase):
    def test_codes_follow_explicit_verification_labels(self):
        cases = {
            "Your verification code is 482913": ["482913"],
            "482913 is your verification code": ["482913"],
            "Votre code de vérification est 482 913": ["482913"],
            "Your code is G-482913": ["482913"],
            "Your verification code is <b>&#52;82913</b>": ["482913"],
            "Your code is &lt;b&gt;482913&lt;/b&gt;": ["482913"],
            "Your verification code is A9F3K2": ["A9F3K2"],
            "Your code is 2000": ["2000"],
            "OTP: 482913; PIN: 482913": ["482913"],
            "Claude Code build 482913 finished": [],
            "Your order 482913 shipped": [],
            "Wallpaper /pink/482913.png": [],
            "Your code is 48291300extra": [],
            "Your code is SECRET": [],
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(verification.verification_codes("", text), expected)

    def test_archive_redacts_sender_metadata_and_never_copies_its_image(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "archive.jsonl"
            script = f"""
source {shlex.quote(str(NOTIFY / 'lib/archive-commands.bash'))}
notification_is_excluded() {{ return 1; }}
ensure_notification_archive() {{ :; }}
archive_timestamp_ms_into() {{ printf -v "$1" 1000; }}
with_archive_lock() {{ "$@"; }}
prune_archive_locked() {{ :; }}
python3() {{ printf true; }}
store_notification_image() {{ exit 9; }}
ARCHIVE_FILE={shlex.quote(str(archive))}
archive_add
"""
            environment = dict(os.environ, DUNST_APP_NAME="Sender 482913", DUNST_ID="5",
                               DUNST_SUMMARY="Your verification code", DUNST_BODY="482913",
                               DUNST_DESKTOP_ENTRY="secret-482913", DUNST_ICON_PATH="/secret-482913",
                               DUNST_CATEGORY="secret-482913")
            subprocess.run(["bash", "-eu", "-c", script], env=environment, check=True)
            stored = archive.read_text()
            self.assertNotIn("482913", stored)
            self.assertEqual(json.loads(stored)["body"], "[redacted]")

    def exercise_clipboard_lease(self, replace_clipboard):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            clipboard = root / "clipboard"

            def run_clipboard(command, **options):
                output = b""
                if command[0] == "wl-copy":
                    clipboard.write_bytes(b"" if "--clear" in command else options["input"].encode())
                elif command[0] == "wl-paste":
                    output = clipboard.read_bytes()
                return subprocess.CompletedProcess(command, 0, stdout=output)

            with patch.object(verification, "SECRET_LIFETIME_SECONDS", TEST_LEASE_SECONDS), \
                    patch.object(verification, "ensure_runtime_root_dir", return_value=root), \
                    patch.object(verification.child_process, "run", side_effect=run_clipboard):
                pid = verification.publish_codes("1000-5", ["482913"])
                result = verification.request("1000-5", "copy")
                self.assertEqual(result["copied"], 0)
                self.assertEqual(clipboard.read_bytes(), b"482913")
                if replace_clipboard:
                    clipboard.write_bytes(b"New clipboard content")
                os.waitpid(pid, 0)
                self.assertFalse(verification.socket_path("1000-5").exists())
                self.assertEqual(clipboard.read_bytes(), b"New clipboard content" if replace_clipboard else b"")

    def test_copied_code_expires(self):
        self.exercise_clipboard_lease(False)

    def test_newer_clipboard_content_survives_code_expiry(self):
        self.exercise_clipboard_lease(True)


if __name__ == "__main__":
    unittest.main()

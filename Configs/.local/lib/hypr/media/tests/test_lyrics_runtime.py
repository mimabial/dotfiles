import os
import subprocess
import tempfile
import unittest
from pathlib import Path

MEDIA_DIR = Path(__file__).resolve().parents[1]
LYRICS_RUNTIME = MEDIA_DIR / "lyrics_runtime.sh"


class LyricsRuntimeTests(unittest.TestCase):
    def resolve_python_result(self, environment):
        return subprocess.run(
            [
                "sh",
                "-c",
                '. "$1"; resolve_lyrics_python',
                "sh",
                str(LYRICS_RUNTIME),
            ],
            capture_output=True,
            text=True,
            env=environment,
        )

    def resolve_python(self, environment):
        result = self.resolve_python_result(environment)
        result.check_returncode()
        return result.stdout

    @staticmethod
    def make_executable(path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        path.chmod(0o700)

    def test_explicit_interpreter_overrides_managed_venv(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            explicit_python = root / "explicit-python"
            managed_python = root / "state" / "hypr" / "pip_env" / "bin" / "python"
            self.make_executable(explicit_python)
            self.make_executable(managed_python)
            environment = os.environ.copy()
            environment.update(
                {
                    "LYRICS_PYTHON": str(explicit_python),
                    "XDG_STATE_HOME": str(root / "state"),
                }
            )

            self.assertEqual(self.resolve_python(environment), str(explicit_python))

    def test_managed_venv_is_used_by_default(self):
        with tempfile.TemporaryDirectory() as temporary:
            state_home = Path(temporary) / "state"
            managed_python = state_home / "hypr" / "pip_env" / "bin" / "python"
            self.make_executable(managed_python)
            environment = os.environ.copy()
            environment.pop("LYRICS_PYTHON", None)
            environment["XDG_STATE_HOME"] = str(state_home)

            self.assertEqual(self.resolve_python(environment), str(managed_python))

    def test_system_python_is_not_used_when_managed_venv_is_missing(self):
        with tempfile.TemporaryDirectory() as temporary:
            environment = os.environ.copy()
            environment.pop("LYRICS_PYTHON", None)
            environment["XDG_STATE_HOME"] = str(Path(temporary) / "missing-state")

            result = self.resolve_python_result(environment)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()

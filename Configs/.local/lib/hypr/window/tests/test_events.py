import os
import signal
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from settings.events import SettingsEvents


class SettingsEventsTest(unittest.TestCase):
    def setUp(self):
        self.events = SettingsEvents()
        self.addCleanup(self.events.close)

    def test_atomic_replacement_wakes_file_watcher(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "staterc"
            changes = []
            self.events.watch_files((path,), lambda: changes.append(path.read_text()))
            temporary = path.with_suffix(".new")
            temporary.write_text("new theme")
            os.replace(temporary, path)
            self.events.wait()
            self.assertEqual(changes, ["new theme"])

    def test_process_completion_captures_large_output_without_pipe_deadlock(self):
        output_bytes = 256 * 1024
        results = []
        self.events.start([sys.executable, "-c", f"print('x' * {output_bytes}, end='')"],
                          on_complete=lambda code, text: results.append((code, text)),
                          capture_output=True)
        self.events.wait()
        self.assertEqual(results, [(0, "x" * output_bytes)])

    def test_resize_signal_wakes_selector(self):
        resized = []
        self.events.watch_resize(lambda: resized.append(True))
        os.kill(os.getpid(), signal.SIGWINCH)
        self.events.wait()
        self.assertEqual(resized, [True])

    def test_input_wakes_selector(self):
        read_fd, write_fd = os.pipe()
        self.addCleanup(os.close, read_fd)
        self.addCleanup(os.close, write_fd)
        self.events.watch_input(read_fd)
        os.write(write_fd, b"q")
        self.events.wait()
        self.assertEqual(os.read(read_fd, 1), b"q")


if __name__ == "__main__":
    unittest.main()

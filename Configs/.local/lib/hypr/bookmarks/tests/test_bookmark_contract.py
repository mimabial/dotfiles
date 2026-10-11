import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from lib.bounded_io import BoundedOutputError, read_limited_bytes, run_bounded_process
from lib.page_metadata import fetch_page_metadata_in_worker
from pyutils import child_process

ROOT = Path(__file__).resolve().parents[1]
HELPER_TIMEOUT_SECONDS = 5


class BookmarkContractTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="bookmarks-test-")
        self.addCleanup(self.directory.cleanup)
        self.fixture = Path(self.directory.name)
        self.store = self.fixture / "bookmarks.json"
        self.settings = self.fixture / "settings.json"

    def command(self, action, *arguments, data=None, env=None):
        result = child_process.run([sys.executable, str(ROOT / "bookmark_helper.py"),
                                    action, *map(str, arguments)],
                                   input=data, capture_output=True, text=True,
                                   timeout=HELPER_TIMEOUT_SECONDS, env=env, check=False)
        return result.returncode, json.loads(result.stdout)

    def test_html_import_deduplicates_urls_and_preserves_unicode(self):
        source = self.fixture / "bookmarks.html"
        source.write_text('<DL><A HREF="https://example.com/" TAGS="Work">Été</A>'
                          '<A HREF="https://EXAMPLE.com:443/" TAGS="New">Duplicate</A></DL>')
        code, result = self.command("import", source, self.store)
        self.assertEqual(code, 0)
        self.assertEqual(len(result["items"]), 1)
        self.assertEqual(result["items"][0]["title"], "Été")
        self.assertEqual(result["items"][0]["tags"], ["Work", "New"])
        self.assertEqual(result["stats"]["duplicatesInFile"], 1)

    def test_store_save_preserves_input_bytes_and_load_reports_invalid_entries(self):
        data = '{"version":3,"bookmarks":[{"id":"local-id","url":"https://example.com","title":"Été"},{"id":"bad","url":"file:///tmp"}]}\n'
        code, result = self.command("store-save", self.store, data=data)
        self.assertEqual((code, result), (0, {"ok": True}))
        self.assertEqual(self.store.read_text(), data)
        self.assertEqual(self.store.stat().st_mode & 0o777, 0o600)
        code, result = self.command("store-load", self.store)
        self.assertEqual(code, 0)
        self.assertEqual(result["invalid"], 1)
        self.assertEqual(result["data"]["bookmarks"][0]["title"], "Été")

    def test_firefox_sync_preserves_local_entries_and_is_stable_on_repeat(self):
        database_path = self.fixture / "places.sqlite"
        with sqlite3.connect(database_path) as database:
            database.executescript('CREATE TABLE moz_places(id INTEGER, url TEXT, hidden INTEGER);'
                                   'CREATE TABLE moz_bookmarks(title TEXT, fk INTEGER, type INTEGER, parent INTEGER, position INTEGER);'
                                   'INSERT INTO moz_places VALUES (1, "https://firefox.example/", 0);'
                                   'INSERT INTO moz_bookmarks VALUES ("Firefox", 1, 1, 0, 0);')
        self.store.write_text('{"version":3,"bookmarks":[{"id":"local-id","url":"https://local.example/","title":"Local"}]}')
        code, result = self.command("firefox-import", database_path, self.store)
        self.assertEqual(code, 0)
        self.assertTrue(Path(result["backup"]).is_file())
        records = json.loads(self.store.read_text())["bookmarks"]
        self.assertEqual([record["source"] for record in records], ["", "firefox"])
        self.assertEqual(records[0]["id"], "local-id")
        original = self.store.read_bytes()
        code, result = self.command("firefox-import", database_path, self.store)
        self.assertEqual((code, result["stats"]["changed"], result["backup"]), (0, 0, ""))
        self.assertEqual(self.store.read_bytes(), original)

    def test_clipboard_commands_use_the_existing_protocol(self):
        helpers = self.fixture / "bin"
        helpers.mkdir()
        for name, code in {"wl-paste": 'print("https://example.com/", end="")',
                           "wl-copy": 'import sys; sys.stdin.buffer.read()'}.items():
            path = helpers / name
            path.write_text("#!" + sys.executable + "\n" + code + "\n")
            path.chmod(0o755)
        environment = {**os.environ, "PATH": str(helpers)}
        code, result = self.command("clipboard", self.store, env=environment)
        self.assertEqual(code, 0)
        self.assertFalse(result["duplicate"])
        self.assertEqual(result["item"]["url"], "https://example.com/")
        code, result = self.command("copy", "https://example.com/", env=environment)
        self.assertEqual((code, result), (0, {"ok": True, "url": "https://example.com/"}))

    def test_metadata_worker_reenters_dispatcher(self):
        self.settings.write_text('{"version":1,"networkEnrichment":true}')
        result = fetch_page_metadata_in_worker("http://127.0.0.1/example", str(self.settings))
        self.assertEqual(result, ("127.0.0.1", ""))

    def test_settings_command_loads_only_its_own_dependencies(self):
        source = ('import sys,json;sys.path.insert(0,sys.argv[1]);import commands;'
                  'commands.dispatch(["network-enrichment","status",sys.argv[2]]);'
                  'print(json.dumps(sorted(name for name in sys.modules if name.startswith("lib."))))')
        result = subprocess.run([sys.executable, "-c", source, str(ROOT), str(self.settings)],
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), ["lib.bounded_io", "lib.network_settings"])

    def test_process_output_limit_and_deadline_are_enforced(self):
        with self.assertRaises(BoundedOutputError):
            run_bounded_process([sys.executable, "-c", "print('x' * 256)"],
                                max_output_bytes=128, timeout_seconds=1)
        with self.assertRaises(subprocess.TimeoutExpired):
            run_bounded_process([sys.executable, "-c", "import signal; signal.pause()"],
                                max_output_bytes=128, timeout_seconds=0.25)

    def test_special_file_is_rejected_without_waiting_for_input(self):
        fifo = self.fixture / "input.pipe"
        os.mkfifo(fifo)
        with self.assertRaisesRegex(ValueError, "not a regular file"):
            read_limited_bytes(fifo, 128, "Bookmark input")


if __name__ == "__main__":
    unittest.main()

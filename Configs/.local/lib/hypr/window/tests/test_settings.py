import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

import settings_tui


class SettingsTest(unittest.TestCase):
    def setUp(self):
        self.app = settings_tui.Settings()

    def test_visual_sections_share_the_settings_catalogue(self):
        titles = [section["title"] for section in self.app.sections]
        self.assertIn("Theme", titles)
        self.assertIn("Blur", titles)
        self.assertIn("Workspaces", titles)
        self.app.search = "blur"
        labels = [row["label"] for row in self.app.sections[0]["rows"]]
        self.assertTrue(any(label.startswith("Blur ·") for label in labels))

    def test_setters_use_local_helpers(self):
        rows = {row["id"]: row for page in self.app.pages for row in page["rows"]}
        self.app.values.update(color_source="theme", color_mode="dark")
        self.assertEqual(self.app.command(rows["theme"], "Tokyo Night", 1),
                         settings_tui.helper("theme/theme.switch.sh", "-s", "Tokyo Night"))
        self.assertEqual(self.app.command(rows["bar_layout"], "top", 1),
                         settings_tui.helper("quickshell/layout.sh", "set", "top"))
        self.assertEqual(self.app.command(rows["color_mode"], "light", 1),
                         settings_tui.helper("theme/color-mode.sh", "-q", "--set", "theme", "light"))

    def test_compose_edit_keeps_other_sequences_and_system_include(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".XCompose"
            path.write_text('<Multi_key> <a> <b> : "old"\n<Multi_key> <c> <d> : "keep"\n')
            with patch.object(settings_tui, "COMPOSE", path):
                self.app.write_compose("<Multi_key> <a> <b>", "new")
                text = path.read_text()
                self.assertIn('include "%L"', text)
                self.assertIn('<Multi_key> <c> <d> : "keep"', text)
                self.assertEqual(text.count("<Multi_key> <a> <b>"), 1)
                self.app.write_compose("<Multi_key> <a> <b>", None)
                self.assertNotIn("<Multi_key> <a> <b>", path.read_text())

    def test_theme_change_reloads_visual_overrides_once(self):
        self.app.visual_theme_key = "previous.dark"
        def refresh_marker():
            self.app.visual_theme_key = self.app.theme_key
        with patch.object(settings_tui.visual.Looknfeel, "tick", return_value=True), \
             patch.object(self.app, "refresh", side_effect=refresh_marker) as refresh:
            self.app.tick()
            self.app.tick()
        refresh.assert_called_once()


if __name__ == "__main__":
    unittest.main()

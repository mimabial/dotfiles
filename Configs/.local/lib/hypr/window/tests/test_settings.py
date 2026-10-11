import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from settings import desktop as desktop
from settings.paths import library_command


class SettingsTest(unittest.TestCase):
    def setUp(self):
        self.app = desktop.DesktopSettings()

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
        self.assertEqual(self.app.build_setting_command(rows["theme"], "Tokyo Night", 1),
                         library_command("theme/theme.switch.sh", "-s", "Tokyo Night"))
        self.assertEqual(self.app.build_setting_command(rows["bar_layout"], "top", 1),
                         library_command("quickshell/layout.sh", "set", "top"))
        self.assertEqual(self.app.build_setting_command(rows["color_mode"], "light", 1),
                         library_command("theme/color-mode.sh", "-q", "--set", "theme", "light"))

    def test_compose_edit_keeps_other_sequences_and_system_include(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".XCompose"
            path.write_text('<Multi_key> <a> <b> : "old"\n<Multi_key> <c> <d> : "keep"\n')
            with patch.object(desktop.compose, "COMPOSE", path):
                self.app.save_compose_sequence("<Multi_key> <a> <b>", "new")
                text = path.read_text()
                self.assertIn('include "%L"', text)
                self.assertIn('<Multi_key> <c> <d> : "keep"', text)
                self.assertEqual(text.count("<Multi_key> <a> <b>"), 1)
                self.app.save_compose_sequence("<Multi_key> <a> <b>", None)
                self.assertNotIn("<Multi_key> <a> <b>", path.read_text())

    def test_theme_change_reloads_visual_overrides_once(self):
        def read_theme():
            self.app.theme_name = "replacement"
        with patch.object(self.app, "read_state_files", side_effect=read_theme), \
             patch.object(self.app, "refresh") as refresh:
            self.app.handle_state_change()
            self.app.handle_state_change()
        refresh.assert_called_once()

    def test_compose_write_failure_stays_in_error_state(self):
        with patch.object(desktop, "write_compose_sequence", side_effect=OSError("unwritable")), \
             patch.object(self.app, "load_page") as load_page:
            self.app.save_compose_sequence("<Multi_key> <a> <b>", "new")
        self.assertEqual(self.app.error_text, "unwritable")
        load_page.assert_not_called()

    def test_preset_change_reloads_animation_baseline(self):
        self.app.pipeline_current["animation_preset"] = "old"
        def read_preset():
            self.app.pipeline_current["animation_preset"] = "new"
        with patch.object(self.app, "read_state_files", side_effect=read_preset), \
             patch.object(self.app, "read_animation_baseline") as read_baseline, \
             patch.object(self.app, "read_saved_overrides") as read_overrides:
            self.app.handle_state_change()
        read_baseline.assert_called_once()
        read_overrides.assert_called_once()

    def test_failed_save_prevents_reset_reload(self):
        self.app.save_pending = self.app.reload_after_save = True
        with patch.object(self.app, "save_overrides"), \
             patch.object(self.app, "start_command") as start:
            self.app.save_pending_changes()
        start.assert_not_called()
        self.assertTrue(self.app.reload_after_save)

    def test_cursor_changes_sync_once_after_running_sync_finishes(self):
        callbacks = []
        def start(command, on_exit):
            callbacks.append(on_exit)
        with patch.object(self.app, "start_command", side_effect=start):
            self.app.cursor_sync_pending = True
            self.app.start_cursor_sync()
            self.app.cursor_sync_pending = True
            self.app.start_cursor_sync()
            self.assertEqual(len(callbacks), 1)
            callbacks[0](0)
            self.assertEqual(len(callbacks), 2)
            callbacks[1](0)
            self.assertFalse(self.app.cursor_sync_running)

    def test_unsaved_cursor_changes_wait_for_successful_save(self):
        self.app.cursor_sync_running = self.app.cursor_sync_pending = self.app.save_pending = True
        with patch.object(self.app, "start_command") as start:
            self.app.cursor_sync_done(0)
        start.assert_not_called()
        self.assertTrue(self.app.cursor_sync_pending)


if __name__ == "__main__":
    unittest.main()

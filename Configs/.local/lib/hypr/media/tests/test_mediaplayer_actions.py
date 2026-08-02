import sys
import unittest
from pathlib import Path
from unittest.mock import patch

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

import mediaplayer_actions
from mediaplayer_actions import cycle_player, dynamic_menu_entries, run_action, run_menu
from mediaplayer_presenter import (
    focus_empty_workspace,
    focus_window,
    launch_on_empty_workspace,
    launch_spec,
    show_player,
    window_aliases,
)


class MediaPlayerMenuTests(unittest.TestCase):
    def test_menu_clamps_using_every_action_without_hiding_rows(self):
        menu_script = mediaplayer_actions.ROFI_MENU_SCRIPT

        self.assertNotIn("menu_lines > 8", menu_script)
        self.assertIn("menu_lines * 13 + 4", menu_script)
        self.assertIn('media_window_theme="window { width:', menu_script)

    @patch("mediaplayer_actions.player_status", return_value="Playing")
    @patch(
        "mediaplayer_actions.fetch_player_properties",
        return_value={
            "PlaybackStatus": {"data": "Playing"},
            "CanPlay": {"data": True},
            "CanPause": {"data": True},
            "CanGoNext": {"data": False},
            "CanGoPrevious": {"data": False},
        },
    )
    def test_menu_puts_show_player_first(self, _properties, _status):
        self.assertEqual(
            ("Show Player", "show-player"),
            dynamic_menu_entries("mpd")[0],
        )

    @patch("mediaplayer_actions.run_resolved_action", return_value=0)
    @patch("mediaplayer_actions.rofi_menu_index", return_value=0)
    @patch(
        "mediaplayer_actions.dynamic_menu_entries",
        return_value=[("Show Player", "show-player")],
    )
    @patch("mediaplayer_actions.fetch_player_properties", return_value={})
    @patch("mediaplayer_actions.resolve_player", return_value="mpd")
    def test_menu_reuses_resolved_player_properties(
        self,
        _resolve,
        fetch_properties,
        menu_entries,
        _menu_index,
        run_resolved,
    ):
        self.assertEqual(run_menu(), 0)
        fetch_properties.assert_called_once_with("mpd")
        menu_entries.assert_called_once_with("mpd", {})
        run_resolved.assert_called_once_with("show-player", "mpd", {})

    @patch("mediaplayer_actions.resolve_player")
    @patch("mediaplayer_actions.write_active_player_state")
    @patch("mediaplayer_actions.read_active_player_state", return_value="")
    @patch(
        "mediaplayer_actions.player_status",
        side_effect=lambda player: {
            "elisa": "Stopped",
            "mpd": "Playing",
            "fftab_t98": "Paused",
        }[player],
    )
    @patch(
        "mediaplayer_actions.available_players",
        return_value=["elisa", "mpd", "fftab_t98"],
    )
    def test_cycle_reuses_collected_players_and_statuses(
        self,
        _available,
        _status,
        _saved,
        write_state,
        resolve,
    ):
        self.assertEqual(cycle_player(1), 0)
        write_state.assert_called_once_with("fftab_t98")
        resolve.assert_not_called()

    @patch("mediaplayer_actions.show_player", return_value=0)
    @patch(
        "mediaplayer_actions.fetch_root_properties",
        return_value={
            "DesktopEntry": {"data": "org.kde.elisa"},
            "CanRaise": {"data": True},
        },
    )
    @patch(
        "mediaplayer_actions.fetch_player_properties",
        return_value={
            "Metadata": {
                "data": {
                    "xesam:url": {"data": "file:///music/song.opus"},
                }
            }
        },
    )
    @patch("mediaplayer_actions.resolve_player", return_value="elisa")
    def test_show_action_passes_player_presentation_metadata(
        self,
        _resolve,
        _player_properties,
        _root_properties,
        show,
    ):
        self.assertEqual(run_action("show-player"), 0)
        show.assert_called_once_with(
            "elisa",
            desktop_entry="org.kde.elisa",
            can_raise=True,
            media_url="file:///music/song.opus",
        )


class MediaPlayerPresenterTests(unittest.TestCase):
    def test_known_frontends_have_window_aliases(self):
        self.assertEqual(window_aliases("mpd"), ("org.tui.Rmpc",))
        self.assertEqual(window_aliases("fftab_t98"), ("firefox",))

    @patch("mediaplayer_presenter.command")
    def test_focus_actions_dispatch_hypr_lua(self, command):
        command.return_value.returncode = 0

        self.assertTrue(focus_window("0xplayer"))
        self.assertTrue(focus_empty_workspace())
        self.assertEqual(
            command.call_args_list[0].args[0],
            [
                "hyprctl",
                "dispatch",
                'hl.dsp.focus({window="address:0xplayer"})',
            ],
        )
        self.assertEqual(
            command.call_args_list[1].args[0],
            ["hyprctl", "dispatch", 'hl.dsp.focus({workspace="empty"})'],
        )

    @patch("mediaplayer_presenter.focus_empty_workspace")
    @patch("mediaplayer_presenter.focus_window", return_value=True)
    @patch(
        "mediaplayer_presenter.matching_window",
        return_value={"address": "0xplayer"},
    )
    def test_existing_window_is_focused_in_place(
        self,
        _matching_window,
        focus_window,
        focus_empty_workspace,
    ):
        self.assertEqual(show_player("mpd"), 0)
        focus_window.assert_called_once_with("0xplayer")
        focus_empty_workspace.assert_not_called()

    @patch("mediaplayer_presenter.launch_on_empty_workspace", return_value=True)
    @patch("mediaplayer_presenter.focus_empty_workspace", return_value=True)
    @patch("mediaplayer_presenter.matching_window", return_value=None)
    def test_missing_window_is_launched_on_empty_workspace(
        self,
        _matching_window,
        focus_empty_workspace,
        launch,
    ):
        self.assertEqual(show_player("mpd"), 0)
        focus_empty_workspace.assert_not_called()
        launch.assert_called_once_with("mpd", "", "")

    @patch("mediaplayer_presenter.time.sleep")
    @patch("mediaplayer_presenter.focus_window", return_value=True)
    @patch(
        "mediaplayer_presenter.matching_window",
        return_value={"address": "0xfirefox"},
    )
    @patch("mediaplayer_presenter.raise_mpris_player", return_value=True)
    def test_firefox_tab_is_activated_before_its_window_is_focused(
        self,
        raise_player,
        _matching_window,
        focus_window,
        _sleep,
    ):
        self.assertEqual(show_player("fftab_t98"), 0)
        raise_player.assert_called_once_with("fftab_t98")
        focus_window.assert_called_once_with("0xfirefox")

    @patch("mediaplayer_presenter.shutil.which", return_value="/usr/bin/hyprshell")
    def test_mpd_launches_the_configured_rmpc_frontend(self, _which):
        pattern, launch = launch_spec("mpd", "mpd-mpris", "")

        self.assertEqual(pattern, "class:org.tui.Rmpc")
        self.assertIn("launch/tui.sh", launch)
        self.assertIn("org.tui.Rmpc", launch)

    @patch("mediaplayer_presenter.command")
    @patch("mediaplayer_presenter.shutil.which", return_value="/usr/bin/hyprshell")
    def test_mpd_summon_overrides_the_general_tui_float_rule(self, _which, command):
        command.return_value.returncode = 0

        self.assertTrue(launch_on_empty_workspace("mpd", "", ""))

        summon = command.call_args.args[0]
        self.assertEqual(
            summon[:5],
            [
                "/usr/bin/hyprshell",
                "launch/summon.sh",
                "--empty-workspace-if-occupied",
                "--tile",
                "class:org.tui.Rmpc",
            ],
        )


if __name__ == "__main__":
    unittest.main()

import importlib.util
import shutil
import subprocess
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

MEDIA_DIR = Path(__file__).resolve().parents[1]
BRIDGE_DIR = MEDIA_DIR / "fftab-bridge"
HOST_PATH = BRIDGE_DIR / "host" / "fftab_host.py"
NAVIGATION_PATH = BRIDGE_DIR / "extension" / "playlist_navigation.js"

spec = importlib.util.spec_from_file_location("fftab_host_tested", HOST_PATH)
fftab_host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fftab_host)


def bare_player():
    player = fftab_host.TabPlayer.__new__(fftab_host.TabPlayer)
    player.tab_id = 98
    player.state = {
        "title": "Baby - YouTube",
        "url": "https://www.youtube.com/watch?v=id&list=playlist&index=13",
        "site": "www.youtube.com",
        "status": "Playing",
        "duration": 165.0,
        "rate": 1.0,
        "can_go_next": False,
        "can_go_previous": False,
    }
    player.anchor_pos = 10.0
    player.anchor_ts = time.monotonic()
    player.conn = Mock()
    return player


class FfTabHostCapabilityTests(unittest.TestCase):
    def test_state_update_publishes_navigation_capabilities(self):
        player = bare_player()
        message = {
            "title": player.state["title"],
            "url": player.state["url"],
            "site": player.state["site"],
            "status": player.state["status"],
            "duration": player.state["duration"],
            "rate": player.state["rate"],
            "position": 10.0,
            "canGoNext": True,
            "canGoPrevious": True,
        }

        with patch.object(player, "position_seconds", return_value=10.0):
            player.update(message)

        self.assertTrue(player.state["can_go_next"])
        self.assertTrue(player.state["can_go_previous"])
        changed = player.conn.emit_signal.call_args.args[4].unpack()[1]
        self.assertTrue(changed["CanGoNext"])
        self.assertTrue(changed["CanGoPrevious"])

    def test_next_is_forwarded_only_when_reported_available(self):
        player = bare_player()
        invocation = Mock()
        with patch.object(fftab_host, "send_to_extension") as send:
            player._on_method_call(None, None, None, None, "Next", None, invocation)
            send.assert_not_called()

            player.state["can_go_next"] = True
            player._on_method_call(None, None, None, None, "Next", None, invocation)
            send.assert_called_once_with(
                {"type": "command", "tabId": 98, "command": "next"}
            )

    def test_mpris_properties_reflect_reported_capabilities(self):
        player = bare_player()
        player.state["can_go_next"] = True

        can_go_next = player._on_get_property(
            None,
            None,
            None,
            fftab_host.PLAYER_IFACE,
            "CanGoNext",
        )
        can_go_previous = player._on_get_property(
            None,
            None,
            None,
            fftab_host.PLAYER_IFACE,
            "CanGoPrevious",
        )

        self.assertTrue(can_go_next.unpack())
        self.assertFalse(can_go_previous.unpack())

    def test_raise_is_forwarded_to_the_browser_extension(self):
        player = bare_player()
        invocation = Mock()
        with patch.object(fftab_host, "send_to_extension") as send:
            player._on_method_call(
                None,
                None,
                None,
                fftab_host.ROOT_IFACE,
                "Raise",
                None,
                invocation,
            )

        send.assert_called_once_with(
            {"type": "command", "tabId": 98, "command": "raise"}
        )


class PlaylistNavigationTests(unittest.TestCase):
    def test_youtube_playlist_navigation(self):
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is unavailable")
        script = r"""
const assert = require("assert");
const navigation = require(process.argv[1]);

const makeItem = (selected = false) => {
  const link = {
    clicked: false,
    click() { this.clicked = true; },
    getAttribute() { return null; },
    classList: { contains() { return false; } },
  };
  return {
    link,
    hasAttribute(name) { return selected && name === "selected"; },
    getAttribute() { return null; },
    querySelector(selector) {
      return selector.includes("wc-endpoint") ? link : null;
    },
  };
};

const items = [makeItem(), makeItem(true), makeItem()];
const document = {
  querySelectorAll() { return items; },
  querySelector() { return null; },
  getElementById() { return null; },
};
const url = "https://www.youtube.com/watch?v=id&list=playlist&index=2";

assert.deepStrictEqual(navigation.capabilities(document, url), {
  canGoNext: true,
  canGoPrevious: true,
});
assert.strictEqual(navigation.navigate("next", document, url), true);
assert.strictEqual(items[2].link.clicked, true);
assert.deepStrictEqual(
  navigation.capabilities(document, "https://www.youtube.com/watch?v=id"),
  { canGoNext: false, canGoPrevious: false }
);
"""
        subprocess.run(
            [node, "-e", script, str(NAVIGATION_PATH)],
            check=True,
            text=True,
            capture_output=True,
        )


if __name__ == "__main__":
    unittest.main()

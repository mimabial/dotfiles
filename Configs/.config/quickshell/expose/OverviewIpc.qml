import Quickshell
import Quickshell.Io

Scope {
  id: root
  required property var controller

  IpcHandler {
    id: ipc
    target: "expose"
    function open(): string {
        // Must not call toggle(): that makes "open" a duplicate of
        // "toggle", so calling open on an already-open overview closes it.
        // Mirrors close(), which correctly calls dismiss().
        root.controller.open("{}");
        return "ok";
    }
    function close(): string {
        root.controller.dismiss();
        return "ok";
    }
    function toggle(): string {
        root.controller.toggle();
        return "ok";
    }
    function status(): string {
        return JSON.stringify(root.controller.pluginEntry || {});
    }
    function previewPlacement(mode: string): string {
        if (mode !== "in-place" && mode !== "centered")
            return "expected in-place or centered";
        root.controller.setPreviewPlacement(mode);
        return mode;
    }
    function windowFooterStyle(style: string): string {
        if (root.controller.windowFooterStyles.indexOf(style) === -1)
            return "expected floating, integrated, overlay, or centered";
        root.controller.setWindowFooterStyle(style);
        return style;
    }
    function animationStyle(style: string): string {
        if (root.controller.animationStyles.indexOf(style) === -1)
            return "expected original, fade, zoom, or slide";
        return root.controller.setAnimationStyle(style);
    }
    function animationDuration(style: string, value: real): string {
        if (root.controller.animationStyles.indexOf(style) === -1)
            return "expected original, fade, zoom, or slide";
        return String(root.controller.setAnimationDuration(style, value));
    }
    function animationDurationIn(style: string, value: real): string {
        if (root.controller.animationStyles.indexOf(style) === -1)
            return "expected original, fade, zoom, or slide";
        return String(root.controller.setAnimationDurationIn(style, value));
    }
    function animationDurationOut(style: string, value: real): string {
        if (root.controller.animationStyles.indexOf(style) === -1)
            return "expected original, fade, zoom, or slide";
        return String(root.controller.setAnimationDurationOut(style, value));
    }
    function slideDirection(direction: string): string {
        if (!root.controller.isSlideDirection(direction))
            return "expected left, right, up, or down";
        return root.controller.setSlideDirection(direction);
    }
    function slideDirectionIn(direction: string): string {
        if (!root.controller.isSlideDirection(direction))
            return "expected left, right, up, or down";
        return root.controller.setSlideDirectionIn(direction);
    }
    function slideDirectionOut(direction: string): string {
        if (!root.controller.isSlideDirection(direction))
            return "expected left, right, up, or down";
        return root.controller.setSlideDirectionOut(direction);
    }
    function backgroundBlur(value: real): string {
        return String(root.controller.setBackgroundBlur(value));
    }
    function backgroundDim(value: real): string {
        return String(root.controller.setBackgroundDim(value));
    }
    function settings(mode: string): string {
        if (mode === "open")
            root.controller.openSettings();
        else if (mode === "close")
            root.controller.closeSettings();
        else if (mode === "toggle")
            root.controller.settingsOpen ? root.controller.closeSettings() : root.controller.openSettings();
        else
            return "expected open, close, or toggle";
        return mode;
    }
    function hotCorner(mode: string): string {
        if (mode !== "on" && mode !== "off")
            return "expected on or off";
        root.controller.setHotCornerEnabled(mode === "on");
        return mode;
    }
    function hotCornerPosition(position: string): string {
        if (["top-left", "top-right", "bottom-left", "bottom-right"].indexOf(position) === -1)
            return "expected top-left, top-right, bottom-left, or bottom-right";
        root.controller.setHotCornerPosition(position);
        return position;
    }
    function moveCursorToWindow(mode: string): string {
        if (mode !== "on" && mode !== "off")
            return "expected on or off";
        root.controller.setMoveCursorToWindow(mode === "on");
        return mode;
    }
    function multiMonitorMode(mode: string): string {
        if (mode !== "mirrored" && mode !== "per-monitor")
            return "expected mirrored or per-monitor";
        root.controller.setMultiMonitorMode(mode);
        return mode;
    }
    function showFooter(mode: string): string {
        if (mode !== "on" && mode !== "off")
            return "expected on or off";
        root.controller.updatePluginSetting("showFooter", mode === "on");
        return mode;
    }
  }
}

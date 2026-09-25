import json
import os
import sys
import time


FILE_ICONS = {
    "image-x-generic": {".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif"},
    "video-x-generic": {".mp4", ".mkv", ".webm", ".mov", ".avi"},
    "audio-x-generic": {".mp3", ".flac", ".wav", ".ogg", ".m4a"},
    "package-x-generic": {".zip", ".tar", ".gz", ".xz", ".7z", ".rar"},
    "application-pdf": {".pdf"},
    "text-x-generic": {".txt", ".md", ".json", ".qml", ".py", ".cpp", ".js", ".lua", ".rs", ".go", ".html", ".css"},
}
EXTENSION_ICONS = {extension: icon for icon, extensions in FILE_ICONS.items() for extension in extensions}


def size_label(size):
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size} B" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024


def age_label(seconds):
    if seconds < 60:
        return "Just now"
    for limit, divisor, suffix in ((3600, 60, "m"), (86400, 3600, "h")):
        if seconds < limit:
            return f"{int(seconds // divisor)}{suffix} ago"
    return f"{int(seconds // 86400)}d ago"


def scan_folder(folder):
    folder = os.path.expanduser(folder)
    entries = []
    now = time.time()
    try:
        with os.scandir(folder) as files:
            for file in files:
                if file.name.startswith("."):
                    continue
                try:
                    stat = file.stat()
                    is_dir = file.is_dir()
                except OSError:
                    continue
                extension = os.path.splitext(file.name)[1].lower()
                icon = "folder" if is_dir else EXTENSION_ICONS.get(extension, "application-x-executable")
                entries.append({
                    "name": file.name, "path": file.path, "isDir": is_dir,
                    "isImage": extension in FILE_ICONS["image-x-generic"],
                    "size": size_label(0 if is_dir else stat.st_size),
                    "time": age_label(now - stat.st_mtime),
                    "mtime": stat.st_mtime, "icon": icon,
                })
    except OSError:
        pass
    entries.sort(key=lambda entry: entry["mtime"], reverse=True)
    return {"count": len(entries), "items": entries[:16], "folder": folder}


def pick_folder():
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk

    dialog = Gtk.FileChooserDialog(
        title="Select Folder to Pin to Dock", action=Gtk.FileChooserAction.SELECT_FOLDER
    )
    dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
    try:
        if dialog.run() == Gtk.ResponseType.OK:
            print(dialog.get_filename())
    finally:
        dialog.destroy()


if __name__ == "__main__":
    if sys.argv[1] == "scan":
        print(json.dumps(scan_folder(sys.argv[2])))
    elif sys.argv[1] == "pick":
        pick_folder()

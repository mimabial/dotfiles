import json
import sqlite3
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree


RECENT_LIMIT = 10
items = []
if sys.argv[1:] == ["folders"]:
    history = Path.home() / ".local/share/kactivitymanagerd/resources/database"
    if history.exists():
        database = sqlite3.connect("file:" + str(history) + "?mode=ro", uri=True)
        rows = database.execute("SELECT targettedResource FROM ResourceScoreCache GROUP BY targettedResource ORDER BY MAX(lastUpdate) DESC")
        for (resource,) in rows:
            path = Path(resource)
            if path.is_dir():
                items.append({"text": path.name, "uri": path.as_uri()})
                if len(items) == RECENT_LIMIT:
                    break
else:
    app_name = sys.argv[2].casefold() if len(sys.argv) == 3 and sys.argv[1] == "app" else ""
    history = Path.home() / ".local/share/recently-used.xbel"
    if history.exists():
        if len(sys.argv) == 3 and sys.argv[1] == "remove":
            from gi.repository import GLib

            bookmark_file = GLib.BookmarkFile()
            bookmark_file.load_from_file(str(history))
            if bookmark_file.has_item(sys.argv[2]):
                bookmark_file.remove_item(sys.argv[2])
                bookmark_file.to_file(str(history))
        bookmarks = ElementTree.parse(history).getroot().findall("bookmark")
        for bookmark in sorted(bookmarks, key=lambda entry: entry.get("modified", ""), reverse=True):
            if app_name and not any(application.get("name", "").casefold() == app_name for application in bookmark.findall(".//{http://www.freedesktop.org/standards/desktop-bookmarks}application")):
                continue
            uri = bookmark.get("href", "")
            parsed = urlsplit(uri)
            if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
                continue
            path = Path(unquote(parsed.path))
            if path.is_file():
                items.append({"text": path.name, "uri": uri})
                if len(items) == RECENT_LIMIT:
                    break
print(json.dumps(items))

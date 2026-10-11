import json
import sqlite3
import sys
from contextlib import closing
from pathlib import Path
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils.xdg_base_dirs import xdg_data_home


RECENT_LIMIT = 10
DATA_HOME = xdg_data_home()
FOLDER_HISTORY_FILE = DATA_HOME / "kactivitymanagerd/resources/database"
RECENT_BOOKMARKS_FILE = DATA_HOME / "recently-used.xbel"
BOOKMARK_APPLICATION_TAG = ".//{http://www.freedesktop.org/standards/desktop-bookmarks}application"


def recent_folders():
    items = []
    if FOLDER_HISTORY_FILE.exists():
        with closing(sqlite3.connect("file:" + str(FOLDER_HISTORY_FILE) + "?mode=ro", uri=True)) as database:
            rows = database.execute("SELECT targettedResource FROM ResourceScoreCache GROUP BY targettedResource ORDER BY MAX(lastUpdate) DESC")
            for (resource,) in rows:
                path = Path(resource)
                if path.is_dir():
                    items.append({"text": path.name, "uri": path.as_uri()})
                    if len(items) == RECENT_LIMIT:
                        break
    return items


def remove_recent_bookmark(uri):
    if not RECENT_BOOKMARKS_FILE.exists():
        return
    from gi.repository import GLib

    bookmarks = GLib.BookmarkFile()
    bookmarks.load_from_file(str(RECENT_BOOKMARKS_FILE))
    if bookmarks.has_item(uri):
        bookmarks.remove_item(uri)
        bookmarks.to_file(str(RECENT_BOOKMARKS_FILE))


def recent_files(app_name=""):
    items = []
    if RECENT_BOOKMARKS_FILE.exists():
        bookmarks = ElementTree.parse(RECENT_BOOKMARKS_FILE).getroot().findall("bookmark")
        for bookmark in sorted(bookmarks, key=lambda entry: entry.get("modified", ""), reverse=True):
            if app_name and not any(application.get("name", "").casefold() == app_name for application in bookmark.findall(BOOKMARK_APPLICATION_TAG)):
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
    return items


def main(arguments):
    if arguments == ["folders"]:
        items = recent_folders()
    else:
        app_name = arguments[1].casefold() if len(arguments) == 2 and arguments[0] == "app" else ""
        if len(arguments) == 2 and arguments[0] == "remove":
            remove_recent_bookmark(arguments[1])
        items = recent_files(app_name)
    print(json.dumps(items))


if __name__ == "__main__":
    main(sys.argv[1:])

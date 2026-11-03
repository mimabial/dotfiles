import sys


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
    if sys.argv[1] == "pick":
        pick_folder()

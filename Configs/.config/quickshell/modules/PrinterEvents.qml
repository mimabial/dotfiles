pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property int consumers: 0
    property int revision: 0
    Process {
        command: ["bash", Quickshell.env("HOME") + "/.local/lib/hypr/system/printers.sh", "--watch"]
        running: root.consumers > 0
        stdout: SplitParser { onRead: line => { if (line.indexOf("org.cups.cupsd.Notifier") >= 0) root.revision++ } }
    }
}

import QtQuick
import qs as Bar
import Quickshell
ShellRoot {
Window {
    id: window
    width: 80; height: 42; visible: true; color: "black"
    property bool captured: false
    Bar.SymbolicIcon { id: integerIcon; x: 10; y: 10; name: "devices/media-memory"; color: "white"; size: 16; directory: "/home/rifle/.local/share/icons/MacTahoe-dark/{context}/symbolic" }
    Bar.SymbolicIcon { id: fractionalIcon; x: 40.75; y: 10; name: integerIcon.name; color: integerIcon.color; size: integerIcon.size; directory: integerIcon.directory }
    onFrameSwapped: {
        if (captured || !integerIcon.loaded || !fractionalIcon.loaded || integerIcon.children[0].status !== Image.Ready || fractionalIcon.children[0].status !== Image.Ready) return
        captured = true
        console.log(JSON.stringify({integer: {width: integerIcon.width, imageWidth: integerIcon.children[0].width, sourceSize: integerIcon.children[0].sourceSize, ink: integerIcon.ink}, fractional: {width: fractionalIcon.width, imageWidth: fractionalIcon.children[0].width, ink: fractionalIcon.ink}}))
        contentItem.grabToImage(function(result) { result.saveToFile("/tmp/systats-right-edge.png"); Qt.quit() })
    }
}
}
